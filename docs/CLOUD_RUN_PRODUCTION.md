# Cloud Run production setup

This is FixNow's production server option when the Firebase project is on the
Blaze plan. It replaces Render; do not run both production servers.

Cloud Run automatically adds instances when requests grow. The deployment
pipeline has a safety cap of 10 instances and 40 concurrent requests per
instance. The Firestore lease in the server allows only one instance to run
background automation at a time.

## One-time company-account setup

1. In Google Cloud for `fixnow-2933a`, enable Cloud Run, Cloud Build, Artifact
   Registry, Secret Manager, Cloud Scheduler, Monitoring, and Logging APIs.
2. Create a runtime service account, for example
   `fixnow-runtime@fixnow-2933a.iam.gserviceaccount.com`. Grant only the Firebase
   Admin/Firestore, Firebase Auth Admin, Firebase Cloud Messaging Admin, and
   Storage Object Admin permissions that the server needs.
3. In Secret Manager, create `fixnow-firebase-web-api-key` and add the current
   Firebase Web API key as its first version. Do not put a service-account JSON
   key in GitHub, Cloud Run, or the repository. Cloud Run uses its runtime
   service account automatically.
4. Configure GitHub Workload Identity Federation and a deployer service account.
   Grant the deployer Cloud Run Admin, Cloud Build Editor, Artifact Registry
   Writer, Service Account User (for the runtime account), and Secret Manager
   Secret Accessor roles.
5. In GitHub's **production** environment add these variables:
   - `FIXNOW_FIREBASE_PROJECT_ID=fixnow-2933a`
   - `CLOUD_RUN_REGION=asia-south1`
   - `CLOUD_RUN_RUNTIME_SERVICE_ACCOUNT=fixnow-runtime@fixnow-2933a.iam.gserviceaccount.com`
   - `GCP_WORKLOAD_IDENTITY_PROVIDER` (the provider resource name)
   - `GCP_DEPLOYER_SERVICE_ACCOUNT` (the GitHub deployer identity)

The workflow `.github/workflows/cloud-run-deploy.yml` then deploys only server
changes merged to `main`, verifies `/health`, and stops if the health check is
not healthy. The output URL is the value for both `FIXNOW_AUTH_API_URL` and
`FIXNOW_ADMIN_API_URL` in GitHub's production environment before building an
Android release.

## Performance and cost guardrails

- Start with `min-instances=0` to use Cloud Run's request-based scaling and
  minimize cost. This is not an always-on worker; active sockets keep an
  instance active, but idle instances can stop.
- Cloud Monitoring must alert on 5xx errors, p95 request latency, instance
  count, container CPU, container memory, and Cloud Run bill/forecast.
- Configure a Cloud Scheduler authenticated job for recurring background checks
  before relying on unattended tracking-gap alerts. This is required because an
  idle Cloud Run instance is deliberately allowed to stop.
- Do not raise `max-instances` above 10 without a live load test and an agreed
  monthly budget.
- Use the existing emulator scale test and HTTP smoke test before a capacity
  change. Automated tests prove behavior; Cloud Monitoring verifies real use.

## Security and rollback

- Rotate any Firebase service-account key that was exposed or copied into a
  third-party dashboard. Prefer Cloud Run runtime identity going forward.
- Require GitHub production-environment approval before deploys.
- To roll back, redeploy the prior Git commit, then verify `/health` and a
  technician login. Do not roll back Firestore rules or data blindly.
