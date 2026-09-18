# Guild Name Forge

A Discord-authenticated, shared guild-name ballot built as a static Next.js export for GitHub Pages. Suggestions and totals are stored in Supabase; GitHub Pages serves only the generated files.

## Setup

1. Create a Supabase project and run `supabase/migrations/20260918190000_guild_name_forge.sql` in its SQL Editor (or apply it with the Supabase CLI).
2. Create a Discord application in the [Discord Developer Portal](https://discord.com/developers). In its OAuth2 redirects, add `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`.
3. In Supabase **Authentication → Sign In / Providers → Discord**, enable Discord and enter the Discord application's client ID and client secret. Keep the secret only in Supabase, never in this repository or browser configuration.
4. In Supabase **Authentication → URL Configuration**, set the Site URL and add redirect URLs for `http://localhost:3000/` and `https://SJovis.github.io/guild-name-forge/`.
5. Copy `.env.example` to `.env.local` and add the project's **public** URL and publishable (or legacy anon) key. Run `npm install`, then `npm run dev`.

The SQL migration enables RLS, permits public reads of leaderboard rows only, denies direct table writes, and grants authenticated visitors access only to three narrowly scoped RPCs. It intentionally does not expose vote records for general reading. Each database vote is uniquely constrained by guild-name ID and authenticated Supabase user ID.

## GitHub Pages

Commit `package-lock.json` after installing dependencies. In GitHub, add repository **Actions variables** named `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, then select **Settings → Pages → Build and deployment → Source → GitHub Actions**. The included workflow builds `out/` with the repository base path and deploys it using current Pages actions.

`NEXT_PUBLIC_*` values are embedded in the static JavaScript and visible to site visitors; they are identifiers, not secrets. Never add a service-role key, database password, or other secret to these variables. For a `USERNAME.github.io` root repository or a custom domain, set `BASE_PATH` to an empty string in the workflow.

## Identity and data migration

Visitors sign in through Discord before suggesting or voting. The database derives their Supabase user ID from the signed-in access token and permits only one vote per account per name, including across private windows, devices, tabs, and retries. This is account-based protection: someone with multiple Discord accounts can still vote once with each account. The app does not fingerprint visitors.

This repository had no prior source or data to migrate. If live names or votes exist in D1, export and import them into `guild_names` and `guild_votes` before switching traffic; do not run an unreviewed import that rewrites existing Supabase vote totals.
