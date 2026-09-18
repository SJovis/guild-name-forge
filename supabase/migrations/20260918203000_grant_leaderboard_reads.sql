-- Applies the least-privilege leaderboard grant to projects using an earlier migration.
grant select on public.guild_names to anon, authenticated;
