# StoreOS | Hamyana

Production-oriented bilingual POS for one store and one sales terminal. It uses Next.js 16, Supabase, an IndexedDB offline queue, and additive PostgreSQL migrations.

## Local setup

1. Copy `.env.example` to `.env.local` and fill the Supabase publishable and server secret keys.
2. Generate separate random values of at least 24 characters for `PIN_PEPPER` and `SETUP_KEY`.
3. Apply `supabase/migrations/202611220001_storeos_initial.sql` to an empty project.
4. Run `npm run dev`, open `/login`, and complete the one-time administrator setup.

Never reuse production values in preview or development. Variables beginning with `NEXT_PUBLIC_` are visible in the browser; `SUPABASE_SECRET_KEY`, `PIN_PEPPER`, and `SETUP_KEY` must remain server-only secrets.

## Safe releases

Run `npm run lint`, `npm run typecheck`, `npm test`, and `npm run build`. Stage a Vercel production deployment with `vercel --prod --skip-domain`, smoke-test its generated URL, then promote that exact build.

Database migrations are forward-only and additive. Never seed, reset, wipe, or run destructive down migrations against production. Take a Supabase backup before migrations and retain the prior Vercel deployment for application rollback.

## Offline recovery

The active catalog, shift, receipts, and operation queue are stored in IndexedDB. Offline sales use stable operation IDs and replay in order. A locally closed shift remains pending until all earlier sales synchronize. Do not clear browser site data while the queue badge is nonzero. If synchronization needs intervention, keep the browser profile intact and export its recovery data before troubleshooting.

Browser storage cannot survive device loss or deliberate site-data deletion. Close and synchronize the shift before replacing or resetting the store PC.

## Staging data

After applying the migration to an isolated staging project, run `ALLOW_STAGING_SEED=true node scripts/seed-staging.mjs` with staging environment variables loaded. The script refuses to run without the explicit staging flag. Demo PINs are Admin `0000` and Cashier `1234`; never run this seed against production.
