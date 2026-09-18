# Guild Name Forge

A no-login, shared guild-name ballot built as a static Next.js export for GitHub Pages. Suggestions and totals are stored in Supabase; GitHub Pages serves only the generated files.

## Setup

1. Create a Supabase project and run `supabase/migrations/20260918190000_guild_name_forge.sql` in its SQL Editor (or apply it with the Supabase CLI).
2. Copy `.env.example` to `.env.local` and add the project's **public** URL and publishable (or legacy anon) key.
3. Run `npm install`, then `npm run dev`. Run `npm test`, `npm run lint`, and `npm run build` before publishing.

The SQL migration enables RLS, permits public reads of leaderboard rows only, denies direct table writes, and grants anonymous visitors access only to the three narrowly scoped RPCs. It intentionally does not expose vote records for general reading.

## GitHub Pages

Commit `package-lock.json` after installing dependencies. In GitHub, add repository **Actions variables** named `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, then select **Settings → Pages → Build and deployment → Source → GitHub Actions**. The included workflow builds `out/` with the repository base path and deploys it using current Pages actions.

`NEXT_PUBLIC_*` values are embedded in the static JavaScript and visible to site visitors; they are identifiers, not secrets. Never add a service-role key, database password, or other secret to these variables. For a `USERNAME.github.io` root repository or a custom domain, set `BASE_PATH` to an empty string in the workflow.

## Vote limitation and data migration

Each browser receives a random ID stored with its voted entry IDs in `localStorage`. It prevents repeat votes per browser/name, including concurrent requests through a database uniqueness constraint, but is not authentication: clearing browser storage or changing devices allows another vote. The app does not fingerprint visitors.

This repository had no prior source or data to migrate. If live names or votes exist in D1, export and import them into `guild_names` and `guild_votes` before switching traffic; do not run an unreviewed import that rewrites existing Supabase vote totals.
