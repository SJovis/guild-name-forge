create table public.guild_names (
  id bigint generated always as identity primary key,
  display_name text not null check (char_length(display_name) between 1 and 60),
  normalized_name text not null unique check (char_length(normalized_name) > 0),
  votes integer not null default 0 check (votes >= 0),
  created_at timestamptz not null default now()
);

create table public.guild_votes (
  guild_name_id bigint not null references public.guild_names(id) on delete cascade,
  browser_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (guild_name_id, browser_id)
);

alter table public.guild_names enable row level security;
alter table public.guild_votes enable row level security;
create policy "Public can read rankings" on public.guild_names for select to anon using (true);

revoke all on public.guild_names, public.guild_votes from anon, authenticated;

create or replace function public.suggest_guild_name(p_display_name text, p_browser_id uuid)
returns table(guild_name_id bigint, display_name text, votes integer, outcome text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_display_name text := btrim(p_display_name);
  v_normalized_name text;
  v_name public.guild_names%rowtype;
  v_created boolean;
  v_vote_added boolean;
begin
  if v_display_name is null or char_length(v_display_name) = 0 or char_length(v_display_name) > 60 then
    raise exception 'A guild name must contain 1 to 60 characters' using errcode = '22023';
  end if;
  v_normalized_name := regexp_replace(lower(v_display_name), '\s+', '', 'g');
  if char_length(v_normalized_name) = 0 then raise exception 'A guild name cannot be whitespace' using errcode = '22023'; end if;

  insert into public.guild_names (display_name, normalized_name)
  values (v_display_name, v_normalized_name)
  on conflict (normalized_name) do update set normalized_name = excluded.normalized_name
  returning *, (xmax = 0) into v_name, v_created;

  insert into public.guild_votes (guild_name_id, browser_id) values (v_name.id, p_browser_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then
    update public.guild_names set votes = votes + 1 where id = v_name.id returning * into v_name;
  end if;
  return query select v_name.id, v_name.display_name, v_name.votes,
    case when not coalesce(v_vote_added, false) then 'already_voted' when v_created then 'created' else 'voted' end;
end;
$$;

create or replace function public.vote_for_guild_name(p_guild_name_id bigint, p_browser_id uuid)
returns table(guild_name_id bigint, display_name text, votes integer, outcome text)
language plpgsql security definer set search_path = ''
as $$
declare v_name public.guild_names%rowtype; v_vote_added boolean;
begin
  select * into v_name from public.guild_names where id = p_guild_name_id for update;
  if not found then return query select p_guild_name_id, ''::text, 0, 'not_found'::text; return; end if;
  insert into public.guild_votes (guild_name_id, browser_id) values (v_name.id, p_browser_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then update public.guild_names set votes = votes + 1 where id = v_name.id returning * into v_name; end if;
  return query select v_name.id, v_name.display_name, v_name.votes, case when coalesce(v_vote_added, false) then 'voted' else 'already_voted' end;
end;
$$;

create or replace function public.get_browser_vote_ids(p_browser_id uuid)
returns table(guild_name_id bigint)
language sql security definer set search_path = ''
as $$ select v.guild_name_id from public.guild_votes v where v.browser_id = p_browser_id; $$;

revoke all on function public.suggest_guild_name(text, uuid), public.vote_for_guild_name(bigint, uuid), public.get_browser_vote_ids(uuid) from public, anon, authenticated;
grant execute on function public.suggest_guild_name(text, uuid), public.vote_for_guild_name(bigint, uuid), public.get_browser_vote_ids(uuid) to anon;
