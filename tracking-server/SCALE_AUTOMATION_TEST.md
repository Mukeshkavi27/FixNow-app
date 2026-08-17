# FixNow 1,200-user automation test

This test is intentionally emulator-only. It refuses to start unless both
`FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` are present.

Prerequisites: Node.js 20+, Firebase CLI, and JDK 21+. Recent Firebase Tools
will not start the Firestore emulator on older Java versions.

## Exact topology

- 5 branches
- 40 approved, active technicians per branch (200 total)
- 200 active customers per branch (1,000 total)
- 1 booking per customer (1,000 total)
- 40 initially assigned bookings per branch (200 total)
- 1 active-job lock per technician
- 800 unassigned bookings
- Every booking contains a deterministic Cloudinary HTTPS customer-photo URL

## Run

From the repository root, with Firebase CLI available:

```powershell
firebase emulators:exec --project demo-fixnow-scale-test --only auth,firestore "npm --prefix tracking-server run test:scale"
```

To inspect the generated emulator records after the test, run the emulators
separately and retain the fixture:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:GCLOUD_PROJECT = 'demo-fixnow-scale-test'
npm --prefix tracking-server run test:scale -- --keep-data
```

## Pass criteria

The script exits with code `0` only when all of these are true:

1. Firebase Auth and Firestore each contain exactly 200 technicians and 1,000 customers.
2. Firestore contains exactly 1,000 test bookings.
3. Exactly 200 bookings are assigned, with 200 matching active-job locks.
4. No technician has more than one active booking.
5. Every assigned technician and booking belong to the same branch.
6. Every booking has a valid Cloudinary HTTPS image URL.
7. Fifty technician booking queries each return one booking carrying its customer image URL.
8. All 200 assigned bookings transition from `technicianAssigned` to `accepted`.
9. Technician booking-query p95 latency stays at or below 1,000 ms locally.

The final stdout entry is a JSON report containing topology, assertions,
latencies, total duration, pass/fail status, and whether test data was retained.
By default all Auth and Firestore fixture data is deleted in a `finally` block.
