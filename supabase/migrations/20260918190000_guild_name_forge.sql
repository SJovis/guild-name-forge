create table public.guild_names (
  id bigint generated always as identity primary key,
  display_name text not null check (char_length(display_name) between 1 and 60),
  normalized_name text not null unique check (char_length(normalized_name) > 0),
  votes integer not null default 0 check (votes >= 0),
  created_at timestamptz not null default now()
);

create table public.guild_votes (
  guild_name_id bigint not null references public.guild_names(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (guild_name_id, user_id)
);

alter table public.guild_names enable row level security;
alter table public.guild_votes enable row level security;
create policy "Anyone can read rankings" on public.guild_names for select to anon, authenticated using (true);
revoke all on public.guild_names, public.guild_votes from anon, authenticated;
grant select on public.guild_names to anon, authenticated;

create or replace function public.suggest_guild_name(p_display_name text)
returns table(guild_name_id bigint, display_name text, votes integer, outcome text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_display_name text := btrim(p_display_name);
  v_normalized_name text;
  v_name public.guild_names%rowtype;
  v_created boolean;
  v_vote_added boolean;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Sign in is required to vote' using errcode = '28000'; end if;
  if v_display_name is null or char_length(v_display_name) = 0 or char_length(v_display_name) > 60 then
    raise exception 'A guild name must contain 1 to 60 characters' using errcode = '22023';
  end if;
  v_normalized_name := regexp_replace(lower(v_display_name), '\s+', '', 'g');
  if char_length(v_normalized_name) = 0 then raise exception 'A guild name cannot be whitespace' using errcode = '22023'; end if;

  insert into public.guild_names (display_name, normalized_name)
  values (v_display_name, v_normalized_name)
  on conflict (normalized_name) do update set normalized_name = excluded.normalized_name
  returning *, (xmax = 0) into v_name, v_created;
  insert into public.guild_votes (guild_name_id, user_id) values (v_name.id, v_user_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then
    update public.guild_names set votes = votes + 1 where id = v_name.id returning * into v_name;
  end if;
  return query select v_name.id, v_name.display_name, v_name.votes,
    case when not coalesce(v_vote_added, false) then 'already_voted' when v_created then 'created' else 'voted' end;
end;
$$;

create or replace function public.vote_for_guild_name(p_guild_name_id bigint)
returns table(guild_name_id bigint, display_name text, votes integer, outcome text)
language plpgsql security definer set search_path = ''
as $$
declare v_name public.guild_names%rowtype; v_vote_added boolean; v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Sign in is required to vote' using errcode = '28000'; end if;
  select * into v_name from public.guild_names where id = p_guild_name_id for update;
  if not found then return query select p_guild_name_id, ''::text, 0, 'not_found'::text; return; end if;
  insert into public.guild_votes (guild_name_id, user_id) values (v_name.id, v_user_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then update public.guild_names set votes = votes + 1 where id = v_name.id returning * into v_name; end if;
  return query select v_name.id, v_name.display_name, v_name.votes, case when coalesce(v_vote_added, false) then 'voted' else 'already_voted' end;
end;
$$;

create or replace function public.get_my_vote_ids()
returns table(guild_name_id bigint)
language sql security definer set search_path = ''
as $$ select v.guild_name_id from public.guild_votes v where v.user_id = auth.uid(); $$;

revoke all on function public.suggest_guild_name(text), public.vote_for_guild_name(bigint), public.get_my_vote_ids() from public, anon, authenticated;
grant execute on function public.suggest_guild_name(text), public.vote_for_guild_name(bigint), public.get_my_vote_ids() to authenticated;
