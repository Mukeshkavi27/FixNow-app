import { FieldValue } from 'firebase-admin/firestore';

const androidChannelId = 'fixnow_technician_alerts';

/// Delivers new workflow notifications while the app is backgrounded. Existing
/// notifications are not re-sent when the server starts.
export function startNotificationPushBridge(firestore, messaging, logger = console) {
  const startedAt = Date.now();
  const inFlight = new Set();
  return firestore.collection('notifications').onSnapshot((snapshot) => {
    snapshot.docChanges().forEach((change) => {
      if (change.type !== 'added' && change.type !== 'modified') return;
      void deliverNotification(change.doc, { firestore, messaging, logger, startedAt, inFlight });
    });
  }, (error) => logger.error('Notification push bridge failed:', error));
}

async function deliverNotification(doc, { firestore, messaging, logger, startedAt, inFlight }) {
  const notification = doc.data();
  const createdAt = notification.createdAt?.toDate?.();
  if (!createdAt || createdAt.getTime() < startedAt || notification.isRead === true ||
      notification.pushSentAt || notification.pushFailedAt || inFlight.has(doc.id)) {
    return;
  }
  inFlight.add(doc.id);
  try {
    const tokens = await recipientTokens(notification, firestore);
    if (tokens.length === 0) return;
    const payload = {
      type: String(notification.type ?? 'general'),
      notificationId: doc.id,
      bookingId: String(notification.bookingId ?? ''),
    };
    const results = await Promise.allSettled(tokens.map((token) => messaging.send({
      token,
      notification: {
        title: String(notification.title ?? 'FixNow update'),
        body: String(notification.body ?? ''),
      },
      data: payload,
      android: {
        priority: 'high',
        notification: { channelId: androidChannelId },
      },
      apns: { payload: { aps: { sound: 'default' } } },
    })));
    const delivered = results.filter((result) => result.status === 'fulfilled').length;
    if (delivered > 0) {
      await doc.ref.update({
        pushSentAt: FieldValue.serverTimestamp(),
        pushRecipientCount: delivered,
      });
    } else {
      const failure = results.find((result) => result.status === 'rejected');
      throw failure?.reason ?? new Error('No device accepted the notification');
    }
  } catch (error) {
    logger.warn('Workflow push notification could not be delivered:', error?.message ?? error);
    await doc.ref.update({
      pushFailedAt: FieldValue.serverTimestamp(),
      pushError: String(error?.code ?? error?.message ?? error),
    }).catch(() => {});
  } finally {
    inFlight.delete(doc.id);
  }
}

async function recipientTokens(notification, firestore) {
  const userId = String(notification.userId ?? '');
  if (userId && !userId.startsWith('branch:') && userId !== 'admin') {
    const token = await firestore.collection('device_tokens').doc(userId).get();
    return token.data()?.token ? [token.data().token] : [];
  }

  let query = firestore.collection('device_tokens');
  if (userId === 'admin') {
    query = query.where('role', '==', 'superAdmin');
  } else if (userId.startsWith('branch:') && notification.branchId) {
    query = query.where('branchId', '==', notification.branchId);
  } else {
    return [];
  }
  const snapshot = await query.get();
  return snapshot.docs
    .map((item) => item.data())
    .filter((item) => userId === 'admin' || item.role === 'branchAdmin')
    .map((item) => item.token)
    .filter((token) => typeof token === 'string' && token.length > 0);
}
