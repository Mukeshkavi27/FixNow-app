# FixNow Pilot User Manual

## Installing the application

1. Download the ARM64 APK supplied by the FixNow administrator.
2. On Android, allow **Install unknown apps** when prompted.
3. Install and open FixNow.
4. Allow location, camera, photo, and notification permissions when requested.

## Accounts and passwords

- Passwords are private and cannot be viewed or exported from Firebase.
- Customers create their own accounts from the registration screen.
- Technicians register and wait for branch-administrator approval.
- Branch administrators are created by the super administrator.
- Forgotten passwords must be reset; never ask users to share passwords in chat.
- The 1,200 scale-test accounts were temporary emulator records and were
  automatically deleted. They are not valid application logins.

## Customer workflow

1. Register or sign in using the registered email and password.
2. Select the appliance or service required.
3. Enter the problem, service address, preferred time, and an optional photo.
4. Confirm the location and submit the booking.
5. Wait for a technician assignment.
6. Follow the booking status and technician location in the app.
7. Review and approve or reject the estimate.
8. Confirm technician arrival when the technician is physically present.
9. Confirm that the work is complete.
10. Review the bill, confirm payment, and optionally leave a rating.

## Technician workflow

1. Register and wait until the branch administrator approves the account.
2. Sign in and complete attendance/check-in.
3. Allow precise Android location access. Background tracking also requires
   the applicable background-location permission on the device.
4. Open the assigned job.
5. Use **View customer photo** to inspect the appliance photo.
6. Accept the booking and follow the required job-status sequence.
7. Submit the estimate and wait for customer approval.
8. Start travel and keep GPS enabled so the customer and administrator receive
   Firestore location updates.
9. Record before, during, and after service photos where available.
10. Complete the work, generate the bill, and record payment information.

## Branch administrator workflow

1. Sign in with the branch-administrator account.
2. Review and approve pending technicians for the administrator's branch.
3. Review new bookings for that branch.
4. Assign an approved technician who does not already have an active job.
5. Monitor booking status, attendance, and technician location.
6. Handle held, reassigned, delayed, or disputed jobs.

## Super administrator workflow

1. Create and manage branches and branch-administrator accounts.
2. Monitor all branches, bookings, technicians, bills, and revenue reports.
3. Inactivate accounts when access must be removed; do not share administrator
   credentials.

## Pilot limitations

- This is a debug-signed testing APK, not a Play Store production release.
- The public web version is disabled.
- Firebase Storage is not enabled. Customer booking photos use Cloudinary, but
  Storage-dependent technician service photos may be unavailable.
- Email/password login works through Firebase. Mobile-number/password login
  requires the separate FixNow server to be publicly hosted.
- Core technician GPS updates use Firestore directly. GPS must be enabled,
  location permission granted, and attendance/check-in completed.
- Push automation and some server-side administration require the separate
  FixNow server to be hosted.
- Maps and address search require a configured Google Maps API key.

## Reporting pilot problems

For every problem, record:

1. User role: customer, technician, branch administrator, or super administrator.
2. Phone model and Android version.
3. Booking ID and approximate time of the problem.
4. Exact screen and action performed.
5. Screenshot or screen recording, excluding passwords and payment secrets.
6. Whether internet, GPS, camera, and required permissions were enabled.
