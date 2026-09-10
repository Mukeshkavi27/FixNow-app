import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import { FieldValue } from 'firebase-admin/firestore';
import {
  authenticateRequest,
  authenticateSocket,
  firebaseAuth,
  firebaseMessaging,
  firebaseStorage,
  firestore,
} from './firebase-auth.js';
import { registerSuperAdminRoutes } from './admin-api.js';
import { registerMobilePasswordAuth } from './mobile-password-auth.js';
import { registerAccountDeletionRoutes } from './account-deletion.js';
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
  navigationMetersBetween,
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
import { startNotificationPushBridge } from './notification-push-bridge.js';
import { startTrackingGapMonitor } from './tracking-gap-monitor.js';
import { createRateLimiter, securityHeaders } from './http-security.js';
import { startDistributedSingleton } from './distributed-singleton.js';

const app = express();
if (process.env.NODE_ENV === 'production') app.set('trust proxy', 1);
app.disable('x-powered-by');
const allowedCorsOrigins = allowedOriginsFor();
app.use(cors(httpCorsOptions(allowedCorsOrigins)));
app.use(securityHeaders);
app.use(express.json({ limit: '64kb', strict: true }));

const httpServer = http.createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: allowedCorsOrigins,
    methods: ['GET', 'POST'],
  },
});

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

// This endpoint is deliberately before /api authentication: it creates the
// Firebase session. It validates the password via Firebase Auth and is rate
// limited in the route itself.
app.use('/auth', createRateLimiter({
  windowMs: 15 * 60 * 1000,
  maximumRequests: 30,
  message: 'Too many sign-in requests from this device. Try again later.',
}));
registerMobilePasswordAuth(app, { auth: firebaseAuth, firestore });

app.use('/api', createRateLimiter({
  windowMs: 60 * 1000,
  maximumRequests: 300,
}));
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
registerAccountDeletionRoutes(app, {
  auth: firebaseAuth,
  firestore,
  storage: firebaseStorage,
});

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
      routeByJob.delete(String(jobId));
      firedEventsByJob.delete(String(jobId));
    }
    ack?.({ ok: true });
  });
});

const stopRealtimeEventBridge = startRealtimeEventBridge({ firestore, io });
const stopBackgroundAutomation = startDistributedSingleton({
  firestore,
  logger: console,
  start: () => {
    const stops = [
      startAttendanceAutomation(firestore, console, firebaseMessaging),
      startNotificationPushBridge(firestore, firebaseMessaging),
      startTrackingGapMonitor(firestore, console),
    ];
    return () => stops.forEach((stop) => stop());
  },
});

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

  const origin = { lat: update.latitude, lng: update.longitude };
  const destination = {
    lat: update.destinationLatitude,
    lng: update.destinationLongitude,
  };
  const distanceMeters = navigationMetersBetween(origin, destination);
  const route = {
    provider: 'direct',
    version: Date.now(),
    points: [origin, destination],
    distanceMeters,
    // This is deliberately labelled as an estimate by clients. It avoids an
    // external routing provider while keeping proximity alerts operational.
    durationSeconds: Math.round(distanceMeters / 8.33),
  };
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

function jobRoom(jobId) {
  return `job:${jobId}`;
}

app.use((error, _req, res, next) => {
  if (error?.code === 'CORS_ORIGIN_DENIED') {
    res.status(403).json({ ok: false, error: error.message });
    return;
  }
  if (error?.type === 'entity.too.large') {
    res.status(413).json({ ok: false, error: 'Request body is too large' });
    return;
  }
  if (error instanceof SyntaxError && 'body' in error) {
    res.status(400).json({ ok: false, error: 'Request body is not valid JSON' });
    return;
  }
  next(error);
});

const port = Number(process.env.PORT ?? 8088);
httpServer.listen(port, () => {
  console.log(`FixNow tracking server listening on ${port}`);
});

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`${signal} received; closing FixNow tracking server`);
  stopBackgroundAutomation();
  stopRealtimeEventBridge();
  io.close();
  const forceExit = setTimeout(() => process.exit(1), 10_000);
  forceExit.unref();
  httpServer.close(() => {
    clearTimeout(forceExit);
    process.exit(0);
  });
}

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
