# Supabase schema changes

`migrations/` is the authoritative source for database changes from version
1.5.1 onward. Apply migrations in filename order to a non-production Supabase
project first, run the authorization tests with separate users, and take a
verified backup before promoting them.

The two historical `supabase_schema.sql` files describe earlier snapshots and
must not be applied to a new or existing environment. They remain temporarily
for forensic comparison and will be removed only after the deployed schema has
been captured and reconciled.

No migration in this directory is executed automatically by the Flutter app.
