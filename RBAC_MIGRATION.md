# FixNow RBAC migration

Task 1 introduces these persisted roles:

- `superAdmin`
- `branchAdmin`
- `technician`
- `customer`

The old `admin` value is parsed as `branchAdmin` in both Flutter and the
tracking service, which prevents legacy accounts from receiving global access
before migration.

## Safe rollout

1. Back up Firestore and deploy the updated rules.
2. Configure Application Default Credentials for the tracking server.
3. Run the migration in dry-run mode from `tracking-server`:

   ```powershell
   $env:SUPER_ADMIN_UIDS='uid-of-owner'
   $env:DEFAULT_BRANCH_ID='existing-branch-id'
   npm run migrate:rbac
   ```

4. Resolve every item in `blocked`. The migration never invents or deletes a
   relationship.
5. Apply the reviewed plan:

   ```powershell
   npm run migrate:rbac -- --apply
   ```

The migration updates legacy roles and backfills missing `branchId` fields on
existing bills, attendance records, and technician locations. Writes are
batched and no document is deleted.
