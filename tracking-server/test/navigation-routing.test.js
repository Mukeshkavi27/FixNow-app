import assert from 'node:assert/strict';
import test from 'node:test';

import {
  canReuseNavigationRoute,
  navigationMetersBetween,
  safeNavigationRoute,
} from '../src/navigation-routing.js';

const existing = {
  origin: { lat: 13.0827, lng: 80.2707 },
  destination: { lat: 13.10, lng: 80.25 },
  route: {
    points: [
      { lat: 13.0827, lng: 80.2707 },
      { lat: 13.0830, lng: 80.2704 },
      { lat: 13.10, lng: 80.25 },
    ],
  },
};

test('small on-route GPS movement reuses the current route', () => {
  assert.equal(canReuseNavigationRoute(existing, {
    latitude: 13.0830,
    longitude: 80.2704,
    destinationLatitude: 13.10,
    destinationLongitude: 80.25,
  }), true);
});

test('route recalculates after meaningful movement or route deviation', () => {
  assert.equal(canReuseNavigationRoute(existing, {
    latitude: 13.0860,
    longitude: 80.2670,
    destinationLatitude: 13.10,
    destinationLongitude: 80.25,
  }), false);
  assert.ok(navigationMetersBetween(existing.origin, {
    lat: 13.0860,
    lng: 80.2670,
  }) > 120);
});

test('navigation provider failures do not interrupt live GPS updates', async () => {
  let reported;
  const route = await safeNavigationRoute(
    async () => { throw new Error('provider unavailable'); },
    (error) => { reported = error.message; },
  );
  assert.equal(route, null);
  assert.equal(reported, 'provider unavailable');
});
