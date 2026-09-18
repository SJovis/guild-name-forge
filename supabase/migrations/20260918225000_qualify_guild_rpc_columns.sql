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

  insert into public.guild_names as guild_name (display_name, normalized_name)
  values (v_display_name, v_normalized_name)
  on conflict (normalized_name) do update set normalized_name = excluded.normalized_name
  returning guild_name.id, guild_name.display_name, guild_name.normalized_name, guild_name.votes, guild_name.created_at, (guild_name.xmax = 0)
  into v_name.id, v_name.display_name, v_name.normalized_name, v_name.votes, v_name.created_at, v_created;
  insert into public.guild_votes (guild_name_id, user_id) values (v_name.id, v_user_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then
    update public.guild_names as guild_name set votes = guild_name.votes + 1 where guild_name.id = v_name.id returning * into v_name;
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
  select * into v_name from public.guild_names as guild_name where guild_name.id = p_guild_name_id for update;
  if not found then return query select p_guild_name_id, ''::text, 0, 'not_found'::text; return; end if;
  insert into public.guild_votes (guild_name_id, user_id) values (v_name.id, v_user_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then update public.guild_names as guild_name set votes = guild_name.votes + 1 where guild_name.id = v_name.id returning * into v_name; end if;
  return query select v_name.id, v_name.display_name, v_name.votes, case when coalesce(v_vote_added, false) then 'voted' else 'already_voted' end;
end;
$$;
