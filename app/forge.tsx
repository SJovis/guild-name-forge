"use client";

import { createClient, type User } from "@supabase/supabase-js";
import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";

type GuildName = { id: number; display_name: string; votes: number; created_at: string };
type Mutation = { guild_name_id: number; display_name: string; votes: number; outcome: "created" | "voted" | "already_voted" | "not_found" };

function clearOAuthCallback() {
  const parameters = new URLSearchParams(window.location.search);
  const hasOAuthCallback = window.location.hash.includes("access_token") || parameters.has("code");
  if (!hasOAuthCallback) return;
  parameters.delete("code");
  const query = parameters.toString();
  window.history.replaceState(null, "", `${window.location.pathname}${query ? `?${query}` : ""}`);
}

function Swords() {
  return <svg aria-hidden="true" viewBox="0 0 64 64" fill="none" stroke="currentColor" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round"><path d="m18 14 32 32M46 14 14 46M16 12l8 2-4 8M48 12l-8 2 4-8M16 52l8-2-4-8M48 52l-8-2 4-8" /></svg>;
}

export function Forge() {
  const [names, setNames] = useState<GuildName[]>([]);
  const [votedIds, setVotedIds] = useState<Set<number>>(new Set());
  const [name, setName] = useState("");
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [message, setMessage] = useState("");
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const [now, setNow] = useState(0);
  const [pending, setPending] = useState<"suggest" | number | null>(null);
  const [bumpedId, setBumpedId] = useState<number | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [authReady, setAuthReady] = useState(true);

  const supabase = useMemo(() => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    return url && key ? createClient(url, key, { auth: { detectSessionInUrl: true, flowType: "pkce" } }) : null;
  }, []);

  const refresh = useCallback(async () => {
    if (!supabase) {
      setStatus("error");
      setMessage("The forge is not configured yet. Add the public Supabase environment values.");
      return;
    }
    setStatus("loading");
    const [namesResult, votesResult] = await Promise.all([
      supabase.from("guild_names").select("id, display_name, votes, created_at").order("votes", { ascending: false }).order("created_at", { ascending: true }).order("id", { ascending: true }),
      user ? supabase.rpc("get_my_vote_ids") : Promise.resolve({ data: [], error: null }),
    ]);
    if (namesResult.error || votesResult.error) {
      setStatus("error");
      setMessage("The leaderboard could not be reached. Check your connection and try again.");
      return;
    }
    setVotedIds(new Set<number>((votesResult.data ?? []).map((row: { guild_name_id: number }) => row.guild_name_id)));
    setNames(namesResult.data as GuildName[]);
    const fetchedAt = Date.now();
    setUpdatedAt(new Date(fetchedAt));
    setNow(fetchedAt);
    setStatus("ready");
    setMessage("");
  }, [supabase, user]);

  useEffect(() => {
    const initialRefresh = window.setTimeout(() => void refresh(), 0);
    return () => {
      window.clearTimeout(initialRefresh);
    };
  }, [refresh]);

  useEffect(() => {
    if (!supabase) return;
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      setAuthReady(true);
      if (session) clearOAuthCallback();
    });
    void supabase.auth.getSession().then(({ data }) => {
      setUser(data.session?.user ?? null);
      setAuthReady(true);
      if (data.session) clearOAuthCallback();
    });
    return () => listener.subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 5_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (bumpedId === null) return;
    const timer = window.setTimeout(() => setBumpedId(null), 700);
    return () => window.clearTimeout(timer);
  }, [bumpedId]);

  const applyMutation = (result: Mutation, completedAt: number) => {
    if (result.outcome === "already_voted") {
      setMessage("You already voted for this name.");
      return false;
    }
    if (result.outcome === "not_found") {
      setMessage("That contender has left the board. Refresh and try again.");
      return false;
    }
    setVotedIds((current) => new Set(current).add(result.guild_name_id));
    setNames((current) => {
      const found = current.some((entry) => entry.id === result.guild_name_id);
      const updated = found
        ? current.map((entry) => entry.id === result.guild_name_id ? { ...entry, votes: result.votes } : entry)
        : [...current, { id: result.guild_name_id, display_name: result.display_name, votes: result.votes, created_at: new Date().toISOString() }];
      return updated.sort((a, b) => b.votes - a.votes || a.created_at.localeCompare(b.created_at) || a.id - b.id);
    });
    setBumpedId(result.guild_name_id);
    setUpdatedAt(new Date(completedAt));
    setNow(completedAt);
    setMessage(result.outcome === "created" ? "Name forged and your first vote is in." : "Your vote has been added.");
    return true;
  };

  const suggest = async (event: FormEvent) => {
    event.preventDefault();
    const displayName = name.trim();
    if (!displayName) return setMessage("Enter a guild name before throwing it into the fire.");
    if (displayName.length > 60) return setMessage("Guild names must be 60 characters or fewer.");
    if (!supabase) return setMessage("The forge is not configured yet. Add the public Supabase environment values.");
    if (!user) return setMessage("Sign in with Discord to suggest a name.");
    setPending("suggest");
    setMessage("");
    const { data, error } = await supabase.rpc("suggest_guild_name", { p_display_name: displayName });
    setPending(null);
    if (error || !data?.[0]) return setMessage("The name could not be saved. Your suggestion is still in the anvil—please retry.");
    if (applyMutation(data[0] as Mutation, now || updatedAt?.getTime() || 0)) setName("");
  };

  const vote = async (id: number) => {
    if (votedIds.has(id) || pending !== null || !supabase || !user) return;
    setPending(id);
    setMessage("");
    const { data, error } = await supabase.rpc("vote_for_guild_name", { p_guild_name_id: id });
    setPending(null);
    if (error || !data?.[0]) return setMessage("The vote could not be recorded. Please retry.");
    applyMutation(data[0] as Mutation, now || updatedAt?.getTime() || 0);
  };

  const totalVotes = names.reduce((total, entry) => total + entry.votes, 0);
  const elapsedSeconds = updatedAt ? Math.max(0, Math.floor((now - updatedAt.getTime()) / 1000)) : 0;
  const updatedLabel = !updatedAt ? "Waiting for the forge" : elapsedSeconds < 5 ? "Updated just now" : `Updated ${elapsedSeconds}s ago`;
  const signIn = async () => {
    if (!supabase) return setMessage("The forge is not configured yet. Add the public Supabase environment values.");
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "discord",
      options: { redirectTo: `${window.location.origin}${window.location.pathname}` },
    });
    if (error) setMessage("Discord sign-in could not start. Please try again.");
  };
  const signOut = async () => {
    if (!supabase) return;
    const { error } = await supabase.auth.signOut();
    if (error) setMessage("Could not sign out. Please try again.");
  };

  return <main className="page-shell">
    <header className="hero">
      <div className="logo"><Swords /></div>
      <div>
        <p className="eyebrow">✣ Community naming ritual</p>
        <h1>Guild Name Forge</h1>
        <p className="subtitle">Suggest a name. Vote for your favorites. May the least terrible name win.</p>
      </div>
      <div className="auth-control">
        {!authReady ? <span>Checking sign-in...</span> : user ? <><span>{user.user_metadata.full_name || user.user_metadata.name || "Discord member"}</span><button className="refresh" onClick={signOut}>Sign out</button></> : <button className="primary discord" onClick={signIn}>Sign in with Discord</button>}
      </div>
    </header>

    <section className="panel suggestion-panel" aria-labelledby="anvil-title">
      <p className="eyebrow">The anvil</p>
      <h2 id="anvil-title">Throw a name into the fire</h2>
      <form onSubmit={suggest}>
        <label className="sr-only" htmlFor="guild-name">Guild name</label>
        <input id="guild-name" value={name} onChange={(event) => setName(event.target.value)} maxLength={60} placeholder="Enter a guild name..." disabled={pending === "suggest" || !user} />
        <button className="primary" type="submit" disabled={pending === "suggest" || !user}>{pending === "suggest" ? "Forging..." : user ? "Suggest name" : "Sign in to suggest"}</button>
      </form>
      <p className="helper">Same name, different spacing or capitalization? It becomes a vote for the existing entry. Discord sign-in is required to vote.</p>
      {message && <p className="notice" role="status">{message}</p>}
    </section>

    <section className="panel rankings" aria-labelledby="rankings-title" aria-busy={status === "loading"}>
      <div className="panel-heading">
        <div><p className="eyebrow">Live leaderboard</p><h2 id="rankings-title">Guild name rankings</h2></div>
        <button className="refresh" onClick={refresh} disabled={status === "loading"} aria-label="Refresh guild name rankings">↻ <span>Refresh</span></button>
      </div>
      <div className="list">
        {status === "loading" && Array.from({ length: 4 }, (_, index) => <div className="skeleton" key={index} />)}
        {status === "error" && <div className="state"><strong>The board is unavailable</strong><span>{message}</span><button className="refresh" onClick={refresh}>Try again</button></div>}
        {status === "ready" && names.length === 0 && <div className="state"><strong>The board is gloriously empty</strong><span>Be brave. Submit the first questionable idea.</span></div>}
        {status === "ready" && names.map((entry, index) => <article className={`name-row ${bumpedId === entry.id ? "bump" : ""}`} key={entry.id}>
          <span className="rank">{String(index + 1).padStart(2, "0")}</span>
          <strong>{entry.display_name}</strong>
          <span className="vote-count"><b>{entry.votes}</b> {entry.votes === 1 ? "vote" : "votes"}</span>
          <button className={`vote ${votedIds.has(entry.id) ? "voted" : ""}`} onClick={() => vote(entry.id)} disabled={votedIds.has(entry.id) || pending !== null || !user} title={!user ? "Sign in with Discord to vote" : undefined}>
            {pending === entry.id ? "Voting..." : votedIds.has(entry.id) ? "Voted ✓" : user ? "↑ Vote" : "Sign in to vote"}
          </button>
        </article>)}
      </div>
      <footer><span>{names.length} {names.length === 1 ? "contender" : "contenders"} · {totalVotes} total votes</span><span>{updatedLabel}</span></footer>
    </section>
    <p className="footer-note">One vote per Discord account, per name. No loot council.</p>
  </main>;
}
