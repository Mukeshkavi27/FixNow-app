import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import http from 'http';
import { Server } from 'socket.io';
import { Client as GoogleMapsClient } from '@googlemaps/google-maps-services-js';

const app = express();
app.use(cors());
app.use(express.json());

const httpServer = http.createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: process.env.CORS_ORIGIN?.split(',') ?? '*',
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

io.on('connection', (socket) => {
  socket.on('tracking:join-job', ({ jobId }) => {
    if (!jobId) return;
    socket.join(jobRoom(jobId));
  });

  socket.on('tracking:join-admin', () => {
    socket.join('admins');
    socket.emit('tracking:admin-snapshot', [...latestByTechnician.values()]);
  });

  socket.on('tracking:leave-job', ({ jobId }) => {
    if (!jobId) return;
    socket.leave(jobRoom(jobId));
  });

  socket.on('tracking:gps', async (payload, ack) => {
    try {
      const update = normalizeGpsPayload(payload);
      latestByTechnician.set(update.technicianId, update);

      const route = await routeForUpdate(update);
      const eventNames = geofenceEvents(update, route);
      const eventNotifications = eventNames.map((name) =>
        oncePerJob(update.jobId, name) ? toNotification(name, update) : null,
      ).filter(Boolean);

      const broadcast = {
        ...update,
        route,
        notifications: eventNotifications,
      };

      io.to(jobRoom(update.jobId)).emit('tracking:update', broadcast);
      io.to('admins').emit('tracking:admin-update', broadcast);
      ack?.({ ok: true, routeVersion: route?.version ?? null });
    } catch (error) {
      ack?.({ ok: false, error: error.message });
    }
  });

  socket.on('tracking:stop', ({ technicianId, jobId }) => {
    if (technicianId) {
      const current = latestByTechnician.get(technicianId);
      if (current) {
        latestByTechnician.set(technicianId, {
          ...current,
          isOnline: false,
          updatedAt: new Date().toISOString(),
        });
      }
    }
    if (jobId) {
      io.to(jobRoom(jobId)).emit('tracking:stopped', { technicianId, jobId });
      io.to('admins').emit('tracking:stopped', { technicianId, jobId });
    }
  });
});

function normalizeGpsPayload(payload) {
  const required = ['technicianId', 'jobId', 'latitude', 'longitude'];
  for (const key of required) {
    if (payload?.[key] === undefined || payload?.[key] === null) {
      throw new Error(`Missing ${key}`);
    }
  }
  return {
    technicianId: String(payload.technicianId),
    jobId: String(payload.jobId),
    customerId: payload.customerId ? String(payload.customerId) : null,
    adminBranchId: payload.adminBranchId ? String(payload.adminBranchId) : null,
    latitude: Number(payload.latitude),
    longitude: Number(payload.longitude),
    destinationLatitude: Number(payload.destinationLatitude),
    destinationLongitude: Number(payload.destinationLongitude),
    heading: numberOrNull(payload.heading),
    bearing: numberOrNull(payload.bearing ?? payload.heading),
    speed: numberOrNull(payload.speed),
    accuracy: numberOrNull(payload.accuracy),
    isOnline: true,
    updatedAt: payload.timestamp ?? new Date().toISOString(),
  };
}

async function routeForUpdate(update) {
  if (!Number.isFinite(update.destinationLatitude) ||
      !Number.isFinite(update.destinationLongitude)) {
    return null;
  }
  const existing = routeByJob.get(update.jobId);
  if (existing && canReuseRoute(existing, update)) return existing.route;

  const route = await fetchGoogleRoute(update);
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

function canReuseRoute(existing, update) {
  const originMove = metersBetween(existing.origin, {
    lat: update.latitude,
    lng: update.longitude,
  });
  const destinationMove = metersBetween(existing.destination, {
    lat: update.destinationLatitude,
    lng: update.destinationLongitude,
  });
  if (originMove > routeCacheMeters || destinationMove > routeCacheMeters) {
    return false;
  }
  const distanceToPolyline = minDistanceToPolyline(
    { lat: update.latitude, lng: update.longitude },
    existing.route.points,
  );
  return distanceToPolyline <= routeDeviationMeters;
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

function minDistanceToPolyline(point, polyline) {
  if (!polyline?.length) return Infinity;
  return Math.min(...polyline.map((item) => metersBetween(point, item)));
}

function metersBetween(a, b) {
  const earthRadius = 6371000;
  const lat1 = toRadians(a.lat);
  const lat2 = toRadians(b.lat);
  const deltaLat = toRadians(b.lat - a.lat);
  const deltaLng = toRadians(b.lng - a.lng);
  const value = Math.sin(deltaLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(deltaLng / 2) ** 2;
  return earthRadius * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
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

function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function toRadians(value) {
  return value * Math.PI / 180;
}

function jobRoom(jobId) {
  return `job:${jobId}`;
}

const port = Number(process.env.PORT ?? 8088);
httpServer.listen(port, () => {
  console.log(`FixNow tracking server listening on ${port}`);
});
