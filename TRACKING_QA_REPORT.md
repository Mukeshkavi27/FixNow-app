# FixNow technician tracking QA report

Date: 2026-08-25 (Asia/Kolkata)

## Scope

This report covers automated validation of the Flutter tracking client,
Firestore persistence rules, and Node tracking server. It does not replace a
physical-device field test or a staging load test.

## Verified pass

- Current and history location writes remain limited to one per minute.
- Flutter rejects mocked GPS samples, invalid coordinates, and accuracy worse
  than 250 metres.
- Node rejects mocked, stale, future-dated, inaccurate, and invalid GPS input.
- Node uses server receipt time for the canonical update timestamp.
- Firestore writes now use `FieldValue.serverTimestamp()` for canonical order.
- Firestore rules require a recent valid attendance record, matching technician
  identity and branch, assigned booking ownership, physical GPS flag, valid
  coordinate bounds, acceptable accuracy, and a server timestamp.
- Immutable history remains limited to one point per technician per minute.
- Completed Socket.IO jobs release route/geofence cache entries to prevent
  unbounded memory growth.
- Technician impersonation and cross-branch monitoring tests pass.
- Full Flutter regression suite: 90 passed, 0 failed.
- Full Node regression suite: 41 passed, 0 failed.
- Targeted Dart static analysis: no issues.

## Emulator scale result

`tracking-server/scripts/scale-automation-test.js` now runs progressive GPS
stages for 10, 50, 100, 150, and 200 technicians. Each stage records requests,
writes, requests/second, P50, P95, P99, errors, and error rate. It refuses to run
unless both Firebase Auth and Firestore emulators are configured.

The disposable emulator run passed on 2026-08-25. It created 5 branches, 200
technicians, 1,000 customers, 1,000 bookings, and 200 assigned bookings. All
test data was removed and both emulators shut down after the run.

| Technicians | Requests | Writes | Requests/sec | P50 | P95 | P99 | Errors |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 50 | 100 | 95.32 | 75.92 ms | 209.17 ms | 210.42 ms | 0 |
| 50 | 250 | 500 | 149.51 | 155.24 ms | 252.20 ms | 279.17 ms | 0 |
| 100 | 500 | 1,000 | 145.09 | 160.37 ms | 312.48 ms | 384.63 ms | 0 |
| 150 | 750 | 1,500 | 175.51 | 136.50 ms | 238.77 ms | 297.05 ms | 0 |
| 200 | 1,000 | 2,000 | 181.27 | 125.54 ms | 238.01 ms | 338.60 ms | 0 |

Additional measured results: technician booking query P50 54.23 ms, P95
73.10 ms; 200 workflow transitions completed in 280.95 ms. Total run time was
81.63 seconds. Firestore rules loaded without a compilation failure.

## Not verified

- Real Render CPU, memory, latency, cold-start, and multi-instance behaviour.
- Tracking on physical Android hardware with screen locked, app backgrounded,
  app killed, phone rebooted, battery saver, GPS disabled, and network loss.
- Durable delivery after the operating system force-stops or uninstalls the app.
- Play Integrity/App Check attestation. Client-side mock detection raises the
  effort required to cheat but cannot defeat a modified APK or rooted device.

## Release position

Tracking is safer at code level, but 200-technician scalability and Android
background reliability remain **NOT VERIFIED** until the emulator/staging and
physical-device matrices are completed.
