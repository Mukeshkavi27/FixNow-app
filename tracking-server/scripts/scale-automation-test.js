import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';

const CONFIG = Object.freeze({
  projectId: 'demo-fixnow-scale-test',
  runId: `scale_${Date.now()}`,
  branchCount: 5,
  techniciansPerBranch: 40,
  customersPerBranch: 200,
  bookingsPerCustomer: 1,
  authConcurrency: 25,
  firestoreBatchSize: 400,
  querySamples: 50,
  p95QueryLimitMs: 1000,
  trackingConcurrency: 25,
  trackingRounds: 5,
  keepData: process.argv.includes('--keep-data'),
});

function requireEmulators() {
  const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (!firestoreHost || !authHost) {
    throw new Error(
      'Refusing to run outside emulators. Set FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST.',
    );
  }
  if (process.env.GCLOUD_PROJECT && process.env.GCLOUD_PROJECT !== CONFIG.projectId) {
    throw new Error(`GCLOUD_PROJECT must be ${CONFIG.projectId}.`);
  }
}

function percentile(values, percentileValue) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * percentileValue) - 1)];
}

async function mapConcurrent(items, concurrency, operation) {
  let cursor = 0;
  const workers = Array.from({ length: concurrency }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      await operation(items[index], index);
    }
  });
  await Promise.all(workers);
}

async function commitInBatches(db, writes) {
  for (let offset = 0; offset < writes.length; offset += CONFIG.firestoreBatchSize) {
    const batch = db.batch();
    for (const write of writes.slice(offset, offset + CONFIG.firestoreBatchSize)) {
      batch.set(write.ref, write.data);
    }
    await batch.commit();
  }
}

function buildFixture(db) {
  const branches = [];
  const technicians = [];
  const customers = [];
  const bookings = [];
  const now = Date.now();

  for (let branchIndex = 0; branchIndex < CONFIG.branchCount; branchIndex += 1) {
    const branchId = `${CONFIG.runId}_branch_${branchIndex.toString().padStart(2, '0')}`;
    const branchName = `Scale Branch ${branchIndex + 1}`;
    branches.push({
      id: branchId,
      ref: db.collection('branches').doc(branchId),
      data: { name: branchName, isActive: true, scaleRunId: CONFIG.runId },
    });

    for (let i = 0; i < CONFIG.techniciansPerBranch; i += 1) {
      const sequence = branchIndex * CONFIG.techniciansPerBranch + i;
      const uid = `${CONFIG.runId}_tech_${sequence.toString().padStart(3, '0')}`;
      technicians.push({
        uid,
        branchId,
        branchName,
        email: `${uid}@example.test`,
        password: 'ScaleTest!234',
        data: {
          uid,
          name: `Scale Technician ${sequence + 1}`,
          email: `${uid}@example.test`,
          phone: `910${sequence.toString().padStart(7, '0')}`,
          role: 'technician',
          branchId,
          branchName,
          isActive: true,
          accountStatus: 'approved',
          scaleRunId: CONFIG.runId,
          createdAt: Timestamp.fromMillis(now + sequence),
        },
      });
    }

    for (let i = 0; i < CONFIG.customersPerBranch; i += 1) {
      const sequence = branchIndex * CONFIG.customersPerBranch + i;
      const uid = `${CONFIG.runId}_customer_${sequence.toString().padStart(4, '0')}`;
      customers.push({
        uid,
        branchId,
        branchName,
        email: `${uid}@example.test`,
        password: 'ScaleTest!234',
        data: {
          uid,
          name: `Scale Customer ${sequence + 1}`,
          email: `${uid}@example.test`,
          phone: `920${sequence.toString().padStart(7, '0')}`,
          role: 'customer',
          branchId,
          branchName,
          isActive: true,
          accountStatus: 'approved',
          scaleRunId: CONFIG.runId,
          createdAt: Timestamp.fromMillis(now + sequence),
        },
      });

      const bookingId = `${CONFIG.runId}_booking_${sequence.toString().padStart(4, '0')}`;
      const assignedTechnician = i < CONFIG.techniciansPerBranch
        ? technicians[branchIndex * CONFIG.techniciansPerBranch + i]
        : null;
      bookings.push({
        id: bookingId,
        customerId: uid,
        branchId,
        technicianId: assignedTechnician?.uid ?? null,
        data: {
          customerId: uid,
          customerName: `Scale Customer ${sequence + 1}`,
          phone: `920${sequence.toString().padStart(7, '0')}`,
          address: `${i + 1}, Automation Test Street`,
          applianceType: ['AC', 'Refrigerator', 'Washing Machine', 'Television'][sequence % 4],
          problemDescription: `Automated scale booking ${sequence + 1}`,
          preferredDate: Timestamp.fromMillis(now + 86400000),
          preferredTime: 'Immediately',
          status: assignedTechnician ? 'technicianAssigned' : 'booked',
          createdAt: Timestamp.fromMillis(now + sequence),
          updatedAt: Timestamp.fromMillis(now + sequence),
          imageUrl: `https://res.cloudinary.com/mxdofr6e/image/upload/${CONFIG.runId}/${bookingId}.jpg`,
          servicePhotos: [],
          branchId,
          branchName,
          technicianId: assignedTechnician?.uid ?? null,
          technicianName: assignedTechnician?.data.name ?? null,
          scaleRunId: CONFIG.runId,
        },
      });
    }
  }
  return { branches, technicians, customers, bookings };
}

async function seed(auth, db, fixture, timings) {
  const users = [...fixture.technicians, ...fixture.customers];
  let started = performance.now();
  await mapConcurrent(users, CONFIG.authConcurrency, async (user) => {
    await auth.createUser({ uid: user.uid, email: user.email, password: user.password });
  });
  timings.authSeedMs = performance.now() - started;

  const writes = [
    ...fixture.branches.map((branch) => ({ ref: branch.ref, data: branch.data })),
    ...users.map((user) => ({ ref: db.collection('users').doc(user.uid), data: user.data })),
    ...fixture.bookings.map((booking) => ({
      ref: db.collection('bookings').doc(booking.id), data: booking.data,
    })),
    ...fixture.bookings.filter((booking) => booking.technicianId).map((booking) => ({
      ref: db.collection('technician_active_jobs').doc(booking.technicianId),
      data: {
        technicianId: booking.technicianId,
        bookingId: booking.id,
        branchId: booking.branchId,
        scaleRunId: CONFIG.runId,
        updatedAt: FieldValue.serverTimestamp(),
      },
    })),
  ];
  started = performance.now();
  await commitInBatches(db, writes);
  timings.firestoreSeedMs = performance.now() - started;
}

async function validate(auth, db, fixture, timings) {
  const authUsers = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    authUsers.push(...page.users.filter((user) => user.uid.startsWith(CONFIG.runId)));
    pageToken = page.pageToken;
  } while (pageToken);
  assert.equal(authUsers.filter((user) => user.uid.includes('_tech_')).length, 200);
  assert.equal(authUsers.filter((user) => user.uid.includes('_customer_')).length, 1000);

  const [users, bookings, activeJobs] = await Promise.all([
    db.collection('users').where('scaleRunId', '==', CONFIG.runId).get(),
    db.collection('bookings').where('scaleRunId', '==', CONFIG.runId).get(),
    db.collection('technician_active_jobs').where('scaleRunId', '==', CONFIG.runId).get(),
  ]);
  assert.equal(users.docs.filter((doc) => doc.data().role === 'technician').length, 200);
  assert.equal(users.docs.filter((doc) => doc.data().role === 'customer').length, 1000);
  assert.equal(bookings.size, 1000);
  assert.equal(activeJobs.size, 200);

  const lockByTechnician = new Map(activeJobs.docs.map((doc) => [doc.id, doc.data()]));
  for (const doc of bookings.docs) {
    const booking = doc.data();
    assert.match(booking.imageUrl, /^https:\/\/res\.cloudinary\.com\/mxdofr6e\//);
    if (booking.technicianId) {
      assert.equal(booking.status, 'technicianAssigned');
      assert.equal(lockByTechnician.get(booking.technicianId)?.bookingId, doc.id);
      const technician = users.docs.find((candidate) => candidate.id === booking.technicianId)?.data();
      assert.equal(technician?.branchId, booking.branchId);
    }
  }

  const assigned = fixture.bookings.filter((booking) => booking.technicianId);
  const transitionWrites = assigned.map((booking) => ({
    ref: db.collection('bookings').doc(booking.id),
    data: { ...booking.data, status: 'accepted', updatedAt: FieldValue.serverTimestamp() },
  }));
  const started = performance.now();
  await commitInBatches(db, transitionWrites);
  timings.transition200Ms = performance.now() - started;

  const latencies = [];
  for (let i = 0; i < CONFIG.querySamples; i += 1) {
    const technician = fixture.technicians[i % fixture.technicians.length];
    const queryStarted = performance.now();
    const result = await db.collection('bookings')
      .where('technicianId', '==', technician.uid).get();
    latencies.push(performance.now() - queryStarted);
    assert.equal(result.size, 1);
    assert.equal(result.docs[0].data().imageUrl.length > 0, true);
  }
  timings.technicianQueryP50Ms = percentile(latencies, 0.50);
  timings.technicianQueryP95Ms = percentile(latencies, 0.95);
  assert.ok(
    timings.technicianQueryP95Ms <= CONFIG.p95QueryLimitMs,
    `Technician query p95 ${timings.technicianQueryP95Ms.toFixed(2)}ms exceeded ${CONFIG.p95QueryLimitMs}ms`,
  );
}

async function exerciseTrackingLoad(db, fixture) {
  const stages = [10, 50, 100, 150, 200];
  const report = [];
  for (const technicianCount of stages) {
    const technicians = fixture.technicians.slice(0, technicianCount);
    const latencies = [];
    let errors = 0;
    const stageStarted = performance.now();
    for (let round = 0; round < CONFIG.trackingRounds; round += 1) {
      await mapConcurrent(technicians, CONFIG.trackingConcurrency, async (technician, index) => {
        const requestStarted = performance.now();
        try {
          const locationRef = db.collection('technician_locations').doc(technician.uid);
          const historyRef = locationRef.collection('history')
            .doc(`${CONFIG.runId}_${technicianCount}_${round}_${index}`);
          const batch = db.batch();
          const data = {
            technicianId: technician.uid,
            branchId: technician.branchId,
            latitude: 11.0168 + index / 100000,
            longitude: 76.9558 + round / 100000,
            accuracy: 10,
            isMocked: false,
            capturedAt: Timestamp.now(),
            updatedAt: FieldValue.serverTimestamp(),
            isOnline: true,
            scaleRunId: CONFIG.runId,
          };
          batch.set(locationRef, data, { merge: true });
          batch.set(historyRef, data);
          await batch.commit();
        } catch (_) {
          errors += 1;
        } finally {
          latencies.push(performance.now() - requestStarted);
        }
      });
    }
    const elapsedMs = performance.now() - stageStarted;
    const requests = technicianCount * CONFIG.trackingRounds;
    report.push({
      technicians: technicianCount,
      rounds: CONFIG.trackingRounds,
      requests,
      writes: requests * 2,
      requestsPerSecond: Number((requests / (elapsedMs / 1000)).toFixed(2)),
      p50Ms: Number(percentile(latencies, 0.50).toFixed(2)),
      p95Ms: Number(percentile(latencies, 0.95).toFixed(2)),
      p99Ms: Number(percentile(latencies, 0.99).toFixed(2)),
      errors,
      errorRate: Number((errors / requests).toFixed(4)),
    });
  }
  assert.equal(report.at(-1).technicians, 200);
  assert.equal(report.reduce((sum, stage) => sum + stage.errors, 0), 0);
  return report;
}

async function cleanup(auth, db, fixture, timings) {
  const started = performance.now();
  const refs = [
    ...fixture.branches.map((item) => item.ref),
    ...fixture.technicians.map((item) => db.collection('users').doc(item.uid)),
    ...fixture.customers.map((item) => db.collection('users').doc(item.uid)),
    ...fixture.bookings.map((item) => db.collection('bookings').doc(item.id)),
    ...fixture.technicians.map((item) => db.collection('technician_active_jobs').doc(item.uid)),
  ];
  for (let offset = 0; offset < refs.length; offset += CONFIG.firestoreBatchSize) {
    const batch = db.batch();
    refs.slice(offset, offset + CONFIG.firestoreBatchSize).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
  for (const technician of fixture.technicians) {
    const locationRef = db.collection('technician_locations').doc(technician.uid);
    const history = await locationRef.collection('history').get();
    for (let offset = 0; offset < history.docs.length; offset += CONFIG.firestoreBatchSize) {
      const batch = db.batch();
      history.docs.slice(offset, offset + CONFIG.firestoreBatchSize)
        .forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
    await locationRef.delete();
  }
  await mapConcurrent(
    [...fixture.technicians, ...fixture.customers],
    CONFIG.authConcurrency,
    async (user) => {
      try {
        await auth.deleteUser(user.uid);
      } catch (error) {
        if (error?.code !== 'auth/user-not-found') throw error;
      }
    },
  );
  timings.cleanupMs = performance.now() - started;
}

async function main() {
  requireEmulators();
  process.env.GCLOUD_PROJECT = CONFIG.projectId;
  const app = initializeApp({ projectId: CONFIG.projectId });
  const auth = getAuth(app);
  const db = getFirestore(app);
  const fixture = buildFixture(db);
  const timings = {};
  let trackingLoad = [];
  const totalStarted = performance.now();
  let passed = false;
  try {
    await seed(auth, db, fixture, timings);
    await validate(auth, db, fixture, timings);
    trackingLoad = await exerciseTrackingLoad(db, fixture);
    passed = true;
  } finally {
    if (!CONFIG.keepData) await cleanup(auth, db, fixture, timings);
  }
  timings.totalMs = performance.now() - totalStarted;
  const report = {
    passed,
    runId: CONFIG.runId,
    topology: {
      branches: CONFIG.branchCount,
      technicians: fixture.technicians.length,
      customers: fixture.customers.length,
      bookings: fixture.bookings.length,
      assignedBookings: fixture.bookings.filter((item) => item.technicianId).length,
    },
    assertions: {
      oneActiveBookingPerTechnician: true,
      sameBranchAssignment: true,
      customerImageUrlPresent: true,
      assignedBookingQueryReturnsImage: true,
      workflowTransitionsTested: 200,
    },
    timings: Object.fromEntries(
      Object.entries(timings).map(([key, value]) => [key, Number(value.toFixed(2))]),
    ),
    trackingLoad,
    dataRetained: CONFIG.keepData,
  };
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(JSON.stringify({ passed: false, error: error.stack ?? String(error) }, null, 2));
  process.exitCode = 1;
});
