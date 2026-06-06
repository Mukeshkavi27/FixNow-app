# Firestore Schema

## users

`uid`, `name`, `email`, `phone`, `role`, `profilePhoto`, `createdAt`, `isActive`

## bookings

`customerId`, `customerName`, `phone`, `address`, `applianceType`, `problemDescription`, `preferredDate`, `preferredTime`, `status`, `createdAt`, `imageUrl`, `technicianId`, `technicianName`, `latitude`, `longitude`

Status flow:

`booked`, `technicianAssigned`, `accepted`, `onTheWay`, `arrived`, `estimateSent`, `estimateApproved`, `serviceStarted`, `serviceCompleted`, `billGenerated`, `closed`

## attendance

`technicianId`, `selfieUrl`, `latitude`, `longitude`, `timestamp`

## estimates

`bookingId`, `technicianId`, `labourCharge`, `partsCharge`, `notes`, `isApproved`, `createdAt`

## bills

`bookingId`, `customerId`, `technicianId`, `amount`, `createdAt`, `isPaid`

## reviews

`bookingId`, `technicianId`, `customerId`, `rating`, `text`, `createdAt`

## notifications

`userId`, `role`, `title`, `body`, `bookingId`, `createdAt`, `isRead`

## technician_locations

Document ID is technician UID.

`technicianId`, `latitude`, `longitude`, `updatedAt`, `activeBookingId`

## analytics

Recommended documents:

`daily/{yyyy-MM-dd}`, `weekly/{yyyy-WW}`, `monthly/{yyyy-MM}` with revenue, booking counts, technician revenue map, and company revenue.
