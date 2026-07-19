# Firestore Schema

## users

`uid`, `name`, `email`, `phone`, `role`, `profilePhoto`, `createdAt`, `isActive`, `accountStatus`, `branchId`, `branchName`, `approvedAt`, `approvedBy`, `rejectionReason`, `rejectedAt`, `rejectedBy`, `inactivatedAt`, `inactivatedBy`, `inactivationReason`, `reactivatedAt`, `reactivatedBy`, `transferredAt`, `transferredBy`

Technician registration starts with `accountStatus = pendingApproval` and
`isActive = false`. Branch Admin approval sets `approvedAt`/`approvedBy` and
activates the account. Rejection keeps the account inactive and records a
mandatory `rejectionReason`, `rejectedAt`, and `rejectedBy`.

Approved technicians are never deleted. Branch Admin inactivation sets
`isActive = false` and records a mandatory reason, timestamp, and actor. This
blocks login and assignment while retaining bookings, bills/revenue, reviews,
ratings, attendance, and location history. Reactivation restores assignment
eligibility and records `reactivatedAt`/`reactivatedBy`.

Roles: `superAdmin`, `branchAdmin`, `technician`, `customer`.

## branches

`id`, `name`, `city`, `latitude`, `longitude`, `aliases`, `radiusMeters`, `isActive`, `branchAdminIds`, `createdAt`, `updatedAt`

## bookings

`customerId`, `customerName`, `phone`, `address`, `applianceType`, `problemDescription`, `preferredDate`, `preferredTime`, `status`, `createdAt`, `imageUrl`, `technicianId`, `technicianName`, `branchId`, `branchName`, `latitude`, `longitude`

Branch Admin queries and writes are scoped to the authenticated administrator's
`branchId`. Technician assignment additionally requires an active, approved
technician whose `branchId` matches the booking.

Every new booking must have both `branchId` and `branchName`. The branch ID is
immutable after creation, including for Super Admin updates. Legacy unassigned
bookings can be inspected with `npm run migrate:booking-branches` from
`tracking-server`; the command is dry-run by default and stops on ambiguous
relationships before any data is changed.

Branch Admin transfers update the user's `branchId`/`branchName`, remove their
UID from the previous branch's `branchAdminIds`, add it to the destination
branch, and record `transferredAt`/`transferredBy` plus an audit log. Transfers
are only allowed to active branches.

Status flow:

`booked`, `technicianAssigned`, `accepted`, `onTheWay`, `arrived`, `estimateSent`, `estimateApproved`, `serviceStarted`, `serviceCompleted`, `billGenerated`, `closed`

## attendance

`technicianId`, `selfieUrl`, `latitude`, `longitude`, `timestamp`

## estimates

`bookingId`, `technicianId`, `labourCharge`, `partsCharge`, `notes`, `isApproved`, `createdAt`

## bills

`bookingId`, `customerId`, `technicianId`, `branchId`, `amount`, `createdAt`,
`isPaid`, `paidAt`, `paymentMode`, `paymentConfirmedAt`, `paymentApprovedAt`

Revenue is recognized from confirmed paid bills using `paidAt`. Older paid
bills without that field remain compatible and fall back to approval,
confirmation, then bill-creation time. Revenue dashboards calculate daily,
weekly, monthly, yearly, branch, technician, and service totals from the live
bill and booking relationships; no destructive aggregation migration is
required.

## reviews

`bookingId`, `technicianId`, `customerId`, `branchId`, `rating`, `text`, `createdAt`

New reviews copy the immutable booking branch inside the same transaction so
Branch Admin rating queries remain branch-scoped. Legacy reviews can be planned
with `npm run migrate:review-branches` in `tracking-server`; it is a dry run by
default and only derives the branch from the linked booking.

## notifications

`userId`, `recipientRole`, `title`, `body`, `type`, `bookingId`, `technicianId`, `branchId`, `createdAt`, `isRead`, `readAt`

Technician registration creates a deterministic
`technician_registration_{technicianId}` notification for the requested branch.
Approval and rejection create a corresponding technician decision notification.
The first verified GPS point after 10:00 PM creates three deterministic
`technicianOvertimeStarted` notifications: one for the technician, one for the
assigned Branch Admin scope, and one for Super Admin.

## technician_locations

Document ID is technician UID.

`technicianId`, `latitude`, `longitude`, `updatedAt`, `activeBookingId`, `speed`, `accuracy`, `heading`, `bearing`, `isOnline`, `branchId`

The latest point remains on the technician document. Immutable travel points
are appended to `technician_locations/{technicianId}/history/{pointId}` from
9:20 AM until midnight and retain latitude, longitude, server timestamp,
captured timestamp, speed, accuracy, booking ID, technician ID, and branch ID.
Branch Admin reads are branch-scoped; technicians cannot edit or delete history.

The standard working-hours journey ends at 10:00 PM. Points after 10:00 PM are
retained so overtime can be verified and audited.

Navigation treats a latest point older than 90 seconds as stale. The technician
client requests a fresh high-accuracy fix and restarts its position stream when
the watchdog cannot recover. Route recalculation is based on meaningful
movement/time thresholds; immutable GPS history remains unchanged.

## technician_overtime

Document ID is `{technicianId}_{yyyy-MM-dd}`.

`technicianId`, `branchId`, `dateKey`, `startedAt`, `lastDetectedAt`, `isActive`, `extraBookingIds`

The first post-10:00 PM GPS point creates the daily record. Later points update
its duration and append active booking IDs without deleting history. Extra
revenue is calculated from paid bills attached to those bookings. Super Admin
can read all records, Branch Admin is branch-scoped, and technicians can only
create/update/read their own records.

## analytics

Recommended documents:

`daily/{yyyy-MM-dd}`, `weekly/{yyyy-WW}`, `monthly/{yyyy-MM}` with revenue, booking counts, technician revenue map, and company revenue.

## audit_logs

Append-only Super Admin and branch-scoped Branch Admin activity records.
Branch Admin records are write-only from the branch console and can only carry
the authenticated administrator's `branchId`; Super Admin retains global read
access:

`actorId`, `actorRole`, `action`, `targetType`, `targetId`, `branchId`, `summary`, `createdAt`.
