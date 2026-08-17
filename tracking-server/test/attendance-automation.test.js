import test from 'node:test';
import assert from 'node:assert/strict';
import {
  attendanceActionAt,
  runAttendanceAutomation,
} from '../src/attendance-automation.js';

test('attendance reminders run every ten minutes from 09:00 through 09:40 IST', () => {
  for (const minute of [0, 10, 20, 30, 40]) {
    const utc = new Date(Date.UTC(2026, 6, 26, 3, 30 + minute));
    assert.equal(attendanceActionAt(utc).action, 'reminder');
  }
});

test('attendance remains available as late after 09:45 IST', () => {
  const result = attendanceActionAt(new Date(Date.UTC(2026, 6, 26, 4, 15)));
  assert.deepEqual(result, { action: null, dayKey: '2026-07-26' });
});

test('attendance scheduler is idle before 09:00 IST', () => {
  assert.equal(attendanceActionAt(new Date(Date.UTC(2026, 6, 26, 3, 29))).action, null);
});

test('attendance reminder is delivered to the registered FCM token', async () => {
  const stored = new Map([
    ['device_tokens/tech-1', { token: 'device-token-1' }],
  ]);
  const technician = {
    id: 'tech-1',
    data: () => ({
      role: 'technician',
      isActive: true,
      accountStatus: 'approved',
      branchId: 'branch-1',
    }),
  };
  const doc = (path) => ({
    async get() {
      const value = stored.get(path);
      return { exists: value != null, data: () => value };
    },
    async set(value) { stored.set(path, value); },
    async update(value) {
      stored.set(path, { ...stored.get(path), ...value });
    },
  });
  const firestore = {
    collection(name) {
      if (name === 'users') {
        const query = {
          where() { return query; },
          async get() { return { docs: [technician] }; },
        };
        return query;
      }
      return { doc: (id) => doc(`${name}/${id}`) };
    },
  };
  const sent = [];
  const messaging = {
    async send(message) {
      sent.push(message);
      return 'projects/fixnow/messages/reminder-1';
    },
  };

  const result = await runAttendanceAutomation(
    firestore,
    new Date(Date.UTC(2026, 6, 26, 3, 30)),
    messaging,
  );

  assert.equal(result.processed, 1);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].token, 'device-token-1');
  assert.equal(sent[0].data.type, 'attendanceReminder');
  const notification = stored.get(
    'notifications/attendance_reminder_tech-1_2026-07-26_0900',
  );
  assert.equal(notification.pushMessageId, 'projects/fixnow/messages/reminder-1');
});
