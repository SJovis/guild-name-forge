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
  returning id, display_name, normalized_name, votes, created_at, (xmax = 0)
  into v_name.id, v_name.display_name, v_name.normalized_name, v_name.votes, v_name.created_at, v_created;
  insert into public.guild_votes (guild_name_id, user_id) values (v_name.id, v_user_id)
  on conflict do nothing returning true into v_vote_added;
  if coalesce(v_vote_added, false) then
    update public.guild_names set votes = votes + 1 where id = v_name.id returning * into v_name;
  end if;
  return query select v_name.id, v_name.display_name, v_name.votes,
    case when not coalesce(v_vote_added, false) then 'already_voted' when v_created then 'created' else 'voted' end;
end;
$$;
