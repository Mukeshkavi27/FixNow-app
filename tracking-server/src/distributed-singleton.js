import { randomUUID } from 'node:crypto';

export async function tryAcquireLease({
  firestore,
  leaseName,
  ownerId,
  now = new Date(),
  ttlMs = 60_000,
}) {
  const ref = firestore.collection('service_leases').doc(leaseName);
  return firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data() ?? {};
    const expiresAt = data.expiresAt?.toDate?.() ?? data.expiresAt;
    const expired = !(expiresAt instanceof Date) || expiresAt <= now;
    if (!expired && data.ownerId !== ownerId) return false;
    transaction.set(ref, {
      ownerId,
      renewedAt: now,
      expiresAt: new Date(now.getTime() + ttlMs),
    }, { merge: true });
    return true;
  });
}

/// Runs Firestore-triggered background bridges on one Render instance only.
/// If the leader disappears, another instance takes over after the lease TTL.
export function startDistributedSingleton({
  firestore,
  start,
  logger = console,
  leaseName = 'background-automation',
  ownerId = process.env.RENDER_INSTANCE_ID ?? randomUUID(),
  renewEveryMs = 20_000,
  ttlMs = 60_000,
}) {
  let stopped = false;
  let running = false;
  let stopWork = null;

  const tick = async () => {
    if (stopped || running) return;
    running = true;
    try {
      const leader = await tryAcquireLease({
        firestore, leaseName, ownerId, ttlMs,
      });
      if (leader && stopWork == null) stopWork = start();
      if (!leader && stopWork != null) {
        stopWork();
        stopWork = null;
      }
    } catch (error) {
      logger.error('Distributed singleton lease failed:', error);
    } finally {
      running = false;
    }
  };
  void tick();
  const timer = setInterval(tick, renewEveryMs);
  timer.unref?.();
  return () => {
    stopped = true;
    clearInterval(timer);
    stopWork?.();
    stopWork = null;
  };
}
