# FixNow Capacity Test Report

Tested on 10 September 2026 using isolated Firebase Auth and Firestore
emulators. No production data was read or written.

## Verified dataset

- 5 branches
- 200 technicians
- 10,000 customers
- 10,000 bookings
- 200 assigned bookings and matching active-job locks
- 200 booking-query samples
- 4,000 tracking writes at the largest stage

## Result

- Overall result: PASS
- Invalid cross-branch assignments: 0
- Duplicate active technician jobs: 0
- Tracking errors: 0
- Booking-query p50: 87.59 ms
- Booking-query p95: 118.10 ms
- 200-technician tracking p50: 24.73 ms
- 200-technician tracking p95: 39.92 ms
- 200-technician tracking p99: 47.19 ms
- Largest-stage throughput: 983.66 update batches/second
- Total test duration including seed, validation, and cleanup: 62.44 seconds

The local Render server HTTP smoke gate also completed 5,000 health requests at
100 concurrent requests with zero errors. Throughput was 2,512.07 requests per
second; p50 was 33.63 ms, p95 was 79.39 ms, and p99 was 118.58 ms.

## Release interpretation

This proves that the FixNow data model, booking constraints, and tracking write
path handle the target dataset in the local Firebase emulator. It is not an SLA
or proof of 10,000 simultaneous internet connections. The final release gate is
a controlled HTTP/WebSocket test against the deployed Render service, followed
by monitoring of CPU, memory, latency, error rate, and Firestore usage.
