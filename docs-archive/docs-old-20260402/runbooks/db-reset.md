# Database Reset

## Reset Local Supabase (safe — local only)
```bash
supabase stop
supabase start        # Wipes local DB and re-applies all migrations from supabase/migrations/
```

## Apply New Migrations Locally
```bash
supabase db push      # Applies pending migrations to local instance
```

## Apply Migrations to Cloud (production)
```bash
supabase db push --linked   # BLOCKED by no-raw-sql guard in autopilot — requires human approval
```

## Seed Local DB
```bash
psql $(supabase status | grep 'DB URL' | awk '{print $3}') -f supabase/seed.sql
```

## Check Migration Status
```bash
supabase migration list   # Shows applied vs pending migrations
```

## NEVER
- Run `supabase db reset --linked` — drops all cloud data
- Copy-paste SQL into Supabase dashboard — bypasses migration tracking
- Edit migration files after they've been applied — create a new migration instead
