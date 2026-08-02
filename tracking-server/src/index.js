import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import { Client as GoogleMapsClient } from '@googlemaps/google-maps-services-js';
import { FieldValue } from 'firebase-admin/firestore';
import {
  authenticateRequest,
  authenticateSocket,
  firebaseAuth,
  firebaseMessaging,
  firestore,
} from './firebase-auth.js';
import { registerSuperAdminRoutes } from './admin-api.js';
import {
  normalizeGpsPayload,
  persistGpsUpdate,
} from './tracking-persistence.js';
import {
  closeOvertimeUpdate,
  persistOvertimeUpdate,
} from './overtime.js';
import {
  canReuseNavigationRoute,
  safeNavigationRoute,
} from './navigation-routing.js';
import { allowedOriginsFor, httpCorsOptions } from './server-config.js';
import {
  canPublishTracking,
  canViewBookingTracking,
  hasPermission,
  permissions,
  roles,
} from './rbac.js';
import {
  socketSyncFor,
  startRealtimeEventBridge,
} from './realtime-events.js';
import { startAttendanceAutomation } from './attendance-automation.js';

const app = express();
const allowedCorsOrigins = allowedOriginsFor();
app.use(cors(httpCorsOptions(allowedCorsOrigins)));
app.use(express.json());

const httpServer = http.createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: allowedCorsOrigins,
    methods: ['GET', 'POST'],
  },
});

const googleMaps = new GoogleMapsClient({});
const latestByTechnician = new Map();
const routeByJob = new Map();
const firedEventsByJob = new Map();

const routeCacheMeters = Number(process.env.ROUTE_CACHE_METERS ?? 120);
const routeDeviationMeters = Number(process.env.ROUTE_DEVIATION_METERS ?? 90);
const nearbyTwoKmMeters = 2000;
const nearbyFiveHundredMeters = 500;
const arrivedMeters = 150;

app.get('/health', (_, res) => {
  res.json({ ok: true, service: 'fixnow-tracking-server' });
});

app.use('/api', authenticateRequest);
app.get('/api/session', (req, res) => {
  res.json({
    ok: true,
    user: {
      uid: req.principal.uid,
      role: req.principal.role,
      branchId: req.principal.branchId,
    },
  });
});
registerSuperAdminRoutes(app, { auth: firebaseAuth, firestore });

io.use(authenticateSocket);

io.on('connection', (socket) => {
  const principal = socket.data.principal;
  socket.join(`user:${principal.uid}`);
  if (principal.role === roles.superAdmin) socket.join('admin:global');
  if (principal.role === roles.branchAdmin && principal.branchId) {
    socket.join(`admin:branch:${principal.branchId}`);
  }
  // Reconnect recovery: send canonical Firestore state before subsequent
  // deltas, so events missed during a network outage cannot leave stale UI.
  socketSyncFor(principal, firestore)
    .then((snapshot) => socket.emit('syncSnapshot', snapshot))
    .catch((error) => socket.emit('syncError', { message: error.message }));

  socket.on('tracking:join-job', async ({ jobId }, ack) => {
    try {
      const booking = await bookingById(jobId);
      if (!canViewBookingTracking(principal, booking)) {
        throw new Error('You do not have access to this booking');
      }
      socket.join(jobRoom(jobId));
      ack?.({ ok: true });
    } catch (error) {
      ack?.({ ok: false, error: error.message });
    }
  });

  socket.on('tracking:join-admin', (_, ack) => {
    const canMonitorAll = hasPermission(
      principal,
      permissions.monitorAllTracking,
    );
    const canMonitorBranch = hasPermission(
      principal,
      permissions.monitorBranchTracking,
    );
    if (!canMonitorAll && !canMonitorBranch) {
      ack?.({ ok: false, error: 'Admin tracking permission is required' });
      return;
    }
    const room = adminRoom(principal);
    socket.join(room);
    const snapshot = [...latestByTechnician.values()].filter(
      (item) => canMonitorAll || item.adminBranchId === principal.branchId,
    );
    socket.emit('tracking:admin-snapshot', snapshot);
    ack?.({ ok: true });
  });

  socket.on('tracking:leave-job', ({ jobId }) => {
    if (!jobId) return;
    socket.leave(jobRoom(jobId));
  });

  socket.on('tracking:gps', async (payload, ack) => {
    try {
      const booking = await bookingById(payload?.jobId);
      if (!canPublishTracking(principal, booking, payload?.technicianId)) {
        throw new Error('Technician is not assigned to this booking');
      }
      const update = normalizeGpsPayload({
        ...payload,
        technicianId: principal.uid,
        customerId: booking.customerId,
        adminBranchId: booking.branchId,
      });
      latestByTechnician.set(update.technicianId, update);
      await persistGpsUpdate(update, firestore);
      const overtime = await persistOvertimeUpdate(update, firestore);

      const route = await routeForUpdate(update);
      const eventNames = geofenceEvents(update, route);
      const eventNotifications = eventNames.map((name) =>
        oncePerJob(update.jobId, name) ? toNotification(name, update) : null,
      ).filter(Boolean);

      const broadcast = {
        ...update,
        route,
        notifications: eventNotifications,
        overtime,
      };

      io.to(jobRoom(update.jobId)).emit('tracking:update', broadcast);
      io.to('admin:global').emit('tracking:admin-update', broadcast);
      io.to(`admin:branch:${update.adminBranchId}`)
        .emit('tracking:admin-update', broadcast);
      ack?.({ ok: true, routeVersion: route?.version ?? null });
    } catch (error) {
      ack?.({ ok: false, error: error.message });
    }
  });

  socket.on('tracking:stop', async ({ technicianId, jobId }, ack) => {
    const booking = await bookingById(jobId).catch(() => null);
    if (!canPublishTracking(principal, booking, technicianId)) {
      ack?.({ ok: false, error: 'Technician is not assigned to this booking' });
      return;
    }
    if (technicianId) {
      const current = latestByTechnician.get(technicianId);
      if (current) {
        await closeOvertimeUpdate(current, firestore);
        latestByTechnician.set(technicianId, {
          ...current,
          isOnline: false,
          updatedAt: new Date().toISOString(),
        });
      }
      await firestore.collection('technician_locations')
        .doc(String(technicianId)).set({
          isOnline: false,
          speed: 0,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    if (jobId) {
      io.to(jobRoom(jobId)).emit('tracking:stopped', { technicianId, jobId });
      io.to('admin:global').emit('tracking:stopped', { technicianId, jobId });
      io.to(`admin:branch:${principal.branchId}`)
        .emit('tracking:stopped', { technicianId, jobId });
    }
    ack?.({ ok: true });
  });
});

startRealtimeEventBridge({ firestore, io });
startAttendanceAutomation(firestore, console, firebaseMessaging);

async function bookingById(jobId) {
  if (!jobId) throw new Error('Booking ID is required');
  const snapshot = await firestore.collection('bookings').doc(String(jobId)).get();
  if (!snapshot.exists) throw new Error('Booking was not found');
  return { id: snapshot.id, ...snapshot.data() };
}

function adminRoom(principal) {
  return principal.role === roles.superAdmin
    ? 'admin:global'
    : `admin:branch:${principal.branchId}`;
}

async function routeForUpdate(update) {
  if (!Number.isFinite(update.destinationLatitude) ||
      !Number.isFinite(update.destinationLongitude)) {
    return null;
  }
  const existing = routeByJob.get(update.jobId);
  if (existing && canReuseNavigationRoute(existing, update, {
    cacheMeters: routeCacheMeters,
    deviationMeters: routeDeviationMeters,
  })) return existing.route;

  const route = await safeNavigationRoute(
    () => fetchGoogleRoute(update),
    (error) => console.warn('Navigation provider failed:', error.message),
  );
  if (!route) return null;
  const cached = {
    origin: { lat: update.latitude, lng: update.longitude },
    destination: {
      lat: update.destinationLatitude,
      lng: update.destinationLongitude,
    },
    route,
  };
  routeByJob.set(update.jobId, cached);
  return route;
}

async function fetchGoogleRoute(update) {
  if (!process.env.GOOGLE_MAPS_API_KEY) return null;
  const response = await googleMaps.directions({
    params: {
      key: process.env.GOOGLE_MAPS_API_KEY,
      origin: { lat: update.latitude, lng: update.longitude },
      destination: {
        lat: update.destinationLatitude,
        lng: update.destinationLongitude,
      },
      mode: 'driving',
    },
    timeout: 8000,
  });
  const route = response.data.routes?.[0];
  const leg = route?.legs?.[0];
  if (!route?.overview_polyline?.points || !leg) return null;
  return {
    provider: 'google',
    version: Date.now(),
    encodedPolyline: route.overview_polyline.points,
    points: decodePolyline(route.overview_polyline.points),
    distanceMeters: leg.distance?.value ?? 0,
    durationSeconds: leg.duration?.value ?? 0,
  };
}

function geofenceEvents(update, route) {
  if (!route) return [];
  const events = [];
  if (route.distanceMeters <= nearbyTwoKmMeters) events.push('within_2km');
  if (route.distanceMeters <= nearbyFiveHundredMeters) events.push('within_500m');
  if (route.distanceMeters <= arrivedMeters) events.push('arrived');
  return events;
}

function oncePerJob(jobId, eventName) {
  const fired = firedEventsByJob.get(jobId) ?? new Set();
  if (fired.has(eventName)) return false;
  fired.add(eventName);
  firedEventsByJob.set(jobId, fired);
  return true;
}

function toNotification(eventName, update) {
  const customerTitleByEvent = {
    within_2km: 'Technician is nearby',
    within_500m: 'Technician is almost there',
    arrived: 'Technician has arrived',
  };
  return {
    eventName,
    jobId: update.jobId,
    customerId: update.customerId,
    title: customerTitleByEvent[eventName] ?? 'Technician update',
    createdAt: new Date().toISOString(),
  };
}

function decodePolyline(encoded) {
  const points = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += result & 1 ? ~(result >> 1) : result >> 1;

    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lng += result & 1 ? ~(result >> 1) : result >> 1;

    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

function jobRoom(jobId) {
  return `job:${jobId}`;
}

app.use((error, _req, res, next) => {
  if (error?.code === 'CORS_ORIGIN_DENIED') {
    res.status(403).json({ ok: false, error: error.message });
    return;
  }
  next(error);
});

const port = Number(process.env.PORT ?? 8088);
httpServer.listen(port, () => {
  console.log(`FixNow tracking server listening on ${port}`);
});
