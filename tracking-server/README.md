# FixNow Live Tracking Server

Socket.IO service for road-based live technician tracking.

## Run

```bash
npm install
GOOGLE_MAPS_API_KEY=your_key npm start
```

The server requires Firebase Application Default Credentials. For local admin
actions such as branch-admin creation, download a Firebase service account JSON
for project `fixnow-a6515`, keep it outside git, and start the server with:

```bash
FIREBASE_PROJECT_ID=fixnow-a6515
GOOGLE_APPLICATION_CREDENTIALS=D:\Fixnow\FixNow-app\tracking-server\firebase-service-account.json
npm start
```

On Windows PowerShell:

```powershell
$env:FIREBASE_PROJECT_ID="fixnow-a6515"
$env:GOOGLE_APPLICATION_CREDENTIALS="D:\Fixnow\FixNow-app\tracking-server\firebase-service-account.json"
npm start
```

You can also place those values in `tracking-server/.env`. Do not commit the
service account JSON or `.env` file.

Every Socket.IO
connection must send a Firebase ID token as `auth.token`; protected HTTP APIs
use `Authorization: Bearer <id-token>`. Identity, active status, approval,
branch membership, and booking ownership are verified server-side.

Optional environment variables:

```bash
PORT=8088
CORS_ORIGIN=http://localhost:5200,https://your-app.web.app
ROUTE_CACHE_METERS=120
ROUTE_DEVIATION_METERS=90
```

The Flutter Super Admin console calls this service through
`FIXNOW_ADMIN_API_URL` (a Dart define). The following endpoints require a
verified Firebase ID token and the `superAdmin` role:

- `POST /api/admin/branch-admins`
- `PATCH /api/admin/branch-admins/:uid/status`
- `PATCH /api/admin/branch-admins/:uid/branch`
- `POST /api/admin/branch-admins/:uid/password-reset`

Account creation and status changes update Firebase Authentication, Firestore,
the assigned branch, and the immutable `audit_logs` collection.

## Socket Rooms

- `tracking:join-job` with `{ jobId }` joins one booking room.
- `tracking:join-admin` joins the global admin room.
- `tracking:gps` accepts technician telemetry and broadcasts `tracking:update`.
- `tracking:stop` marks the technician offline for that active job.

## RBAC migration

Legacy `admin` documents are migrated conservatively to `branchAdmin`. Select
Super Admin accounts explicitly with `SUPER_ADMIN_UIDS`. The command is a dry
run unless `--apply` is provided, and stops rather than guessing when a branch
relationship cannot be derived.

```bash
SUPER_ADMIN_UIDS=ownerUid DEFAULT_BRANCH_ID=branchId npm run migrate:rbac
SUPER_ADMIN_UIDS=ownerUid DEFAULT_BRANCH_ID=branchId npm run migrate:rbac -- --apply
```

## Booking branch migration

Legacy bookings without `branchId` can be assigned conservatively from a unique
legacy branch name or the customer's existing branch relationship. The command
prints a dry-run plan by default and stops on ambiguous records before applying
any writes. `DEFAULT_BRANCH_ID` is only used as an explicit final fallback.

```bash
npm run migrate:booking-branches
DEFAULT_BRANCH_ID=branchId npm run migrate:booking-branches -- --apply
```

Legacy reviews are branch-scoped from their linked booking. The migration is a
dry run unless `--apply` is provided and stops if customer, technician, or
booking branch relationships do not match.

```bash
npm run migrate:review-branches
npm run migrate:review-branches -- --apply
```

## Overtime detection

The 9:20 AM-10:00 PM window is the standard journey. Tracking remains active
until midnight so post-10:00 PM work can be verified. The server records that
activity transactionally in
`technician_overtime/{technicianId}_{yyyy-MM-dd}` and sends one idempotent
notification each to the technician, Branch Admin, and Super Admin.

## Navigation and route recalculation

Google Directions is used when `GOOGLE_MAPS_API_KEY` is configured. The server
reuses a cached route for small on-route GPS changes and recalculates after the
technician moves more than `ROUTE_CACHE_METERS` (120 m by default) or deviates
more than `ROUTE_DEVIATION_METERS` (90 m by default). Tracking updates include
route distance, duration/ETA, provider, polyline, and a route version.

The Flutter client independently suppresses GPS jitter, refreshes road routes
after meaningful movement or 60 seconds, and runs a 45-second GPS watchdog. A
point older than 90 seconds pauses navigation and exposes an immediate GPS
recovery action instead of presenting a misleading route.

The server keeps the latest technician location in memory for immediate
broadcasts and persists it to Firestore. Every accepted GPS event also appends
an immutable point under `technician_locations/{technicianId}/history` with
technician, booking and branch identifiers, latitude/longitude, captured and
server times, speed, accuracy, heading and online state. Flutter technicians
publish the same schema continuously during the 9:20 AM–10:00 PM window.
