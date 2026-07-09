# FixNow Live Tracking Server

Socket.IO service for road-based live technician tracking.

## Run

```bash
npm install
GOOGLE_MAPS_API_KEY=your_key npm start
```

Optional environment variables:

```bash
PORT=8088
CORS_ORIGIN=http://localhost:5200,https://your-app.web.app
ROUTE_CACHE_METERS=120
ROUTE_DEVIATION_METERS=90
```

## Socket Rooms

- `tracking:join-job` with `{ jobId }` joins one booking room.
- `tracking:join-admin` joins the global admin room.
- `tracking:gps` accepts technician telemetry and broadcasts `tracking:update`.
- `tracking:stop` marks the technician offline for that active job.

The server keeps only the latest technician location in memory and broadcasts
route, ETA, distance, speed, online state, timestamp, and one-time proximity
events.
