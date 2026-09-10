# FixNow Play Console submission answers

Verified against the Android app source on 29 August 2026. Recheck this file whenever SDKs or data flows change.

## Store identity

- App name: FixNow
- Package: `com.fixnow.app`
- Category: Business
- Target audience: 18 and over
- Ads: No
- Government app: No
- News app: No
- Health app: No
- Privacy Policy: https://fixnow.live/privacy-policy
- Terms: https://fixnow.live/terms
- Account deletion: https://fixnow.live/account-deletion

All three URLs must load publicly without login, must not be PDFs, and must identify FixNow consistently with the Play developer/listing entity.

## Data Safety

### Security questions

- Does the app collect or share required user data types? **Yes**
- Is all collected data encrypted in transit? **Yes**
- Can users request deletion? **Yes** — inside `My profile > Delete account` and at the public deletion URL.
- Independent security review: **No**, unless a qualifying review is completed later.
- Ads or sale of personal data: **No**

“Shared” should be marked **No** only while Firebase, Google Maps/geocoding, OpenStreetMap tile infrastructure, Render and storage providers act solely as service providers processing data for FixNow. Reassess if any provider uses the data for its own advertising or independent purposes.

### Data types to declare as collected

| Play category | Data type | Required/optional | Purpose |
|---|---|---|---|
| Location | Precise location | Required for on-duty technicians; optional location picker for customers | App functionality, fraud prevention/security, operations |
| Location | Approximate location | Collected as part of device location/address selection | App functionality |
| Personal info | Name | Required | Account management, app functionality |
| Personal info | Email address | Required | Authentication, account management, support |
| Personal info | Phone number | Required | Authentication, booking communication, account management |
| Personal info | Physical address | Required when booking service | App functionality and technician dispatch |
| Personal info | User IDs | Required | Authentication, security and account management |
| Photos and videos | Photos | Optional for customer issue/payment evidence; required for technician attendance where configured | App functionality, fraud prevention/security |
| Financial info | Purchase history | Generated for estimates, bills and payment records | App functionality, accounting |
| Financial info | Other financial info | Payment mode, amount and optional uploaded payment proof | App functionality, fraud prevention/security |
| App activity | Other user-generated content | Problem descriptions, reviews, job updates and hold reasons | App functionality, customer support |
| Device or other IDs | Device or other IDs | Push-notification token | App functionality and security alerts |

Do **not** select contacts, browsing history, advertising data, health data, audio, calendar, SMS/call logs or installed apps; the current code does not collect them.

### Retention and deletion statement

Deleting a customer account removes Firebase Authentication, the customer profile, device tokens, personal notifications and stored profile/booking images. Personal fields in legally retained service, bill and rating records are anonymised. Non-identifying accounting totals may be retained for tax, fraud, disputes and legal compliance.

## Background location declaration

### One core feature

**On-duty technician journey monitoring**

### Copy-ready explanation

FixNow is a field-service and appliance-repair operations app. After a technician marks attendance and explicitly accepts the prominent disclosure, FixNow records the technician’s precise location during the workday, including while the app is closed or not in use. This allows authorised Branch Admins and Super Admins to monitor the technician’s journey, verify continuous attendance and field activity, and see whether the technician is travelling to or has reached an assigned customer. The feature cannot work using foreground-only location because technicians must lock or minimise their phones while travelling and repairing appliances. Tracking stops when the technician closes the workday or signs out. Location is not used for advertising or sold.

### Disclosure shown in the app

> FixNow collects precise location data to enable live technician monitoring, route progress, job arrival confirmation, and travel history even when the app is closed or not in use.

The disclosure appears before Android’s location permission request. Do not move it behind a settings or privacy-policy page.

### Required review video — 30 seconds or less

1. Open FixNow on an Android phone and sign in as a technician.
2. Show the full prominent location disclosure.
3. Tap **Agree & continue**.
4. Show Android’s location permission flow and select **Allow all the time**.
5. Complete attendance and show the green **LIVE** state plus ongoing FixNow notification.
6. Lock/minimise the app.
7. On the admin screen, show the technician location updating while the technician app is not visible.
8. Upload the video as an unlisted YouTube video or a publicly viewable Google Drive MP4 and paste its URL into the declaration.

Also record the rejection path once for internal evidence: tap **Not now**, confirm tracking does not start, then reopen the disclosure from the location status.

## Content rating (IARC)

- Questionnaire category: Utility, Productivity, Communication or Other
- App type: Utility/Business field-service application
- Violence: No
- Sexual content/nudity: No
- Profanity/crude humour: No
- Drugs/alcohol/tobacco: No
- Gambling: No
- Horror/fear: No
- Ads: No
- Unrestricted web browsing: No
- Location sharing: Yes, controlled on-duty technician location visible only to authorised operational users and the relevant workflow
- User-generated content: Limited booking photos, problem descriptions and reviews; no public feed or unrestricted chat

Answer the Console’s exact wording truthfully. If it asks broadly whether users exchange content, answer **Yes** and describe the restricted booking workflow.

## App access for reviewers

Play reviewers must receive working credentials and exact navigation steps for:

- Technician account: approved, assigned to a branch, able to mark attendance
- Branch Admin account: same branch, able to open Monitoring
- Customer account: able to create and inspect a booking

Never place production administrator passwords in this repository. Enter temporary reviewer credentials only inside Play Console and rotate them after approval.

## Target audience and app content

- Select **18 and over**.
- Select **not designed for children**.
- The app contains no advertising.
- The app is not primarily a social, dating, news, health, financial-services or government app.

## Testing requirement

If the developer account is a personal account created after 13 November 2023:

1. Create a closed-testing track.
2. Add at least 12 real testers.
3. Keep all 12 opted in continuously for at least 14 days.
4. Collect feedback covering login, booking, attendance, background tracking, billing, notifications and deletion.
5. Apply for production access after the testing requirement is satisfied.

This waiting period cannot be bypassed in code.

## Final submission evidence

- [ ] Privacy, Terms and deletion URLs open publicly without login
- [ ] Signed AAB uploaded and background-location permission detected
- [ ] Data Safety answers entered from this document
- [ ] Background-location explanation entered
- [ ] Review video URL added and accessible without requesting permission
- [ ] Reviewer credentials tested immediately before submission
- [ ] Content rating submitted
- [ ] Target audience submitted
- [ ] Ads declaration submitted
- [ ] App access instructions submitted
- [ ] Closed-testing requirement completed if applicable
- [ ] Store listing explicitly mentions on-duty background location monitoring
