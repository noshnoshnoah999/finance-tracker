# Security notes — finance-tracker

Audited 2026-08-28.

## The underlying problem

`github.com/noshnoshnoah999/finance-tracker` is a **public** repo, and `app.html` is served
publicly by GitHub Pages. Both contain the Supabase URL, the **anon key**, and a hardcoded
`USER_KEY`. Anyone who views the live site's source has everything the app has.

Supabase's default `verify_jwt` on Edge Functions accepts the anon key, so for every endpoint
"has the anon key" currently means "is authorised". That is the root cause of everything below.

## Done

### 1. `import-bank-emails` deleted (2026-08-28)

It had no caller check and returned Sony Bank transactions pulled live from Gmail via a stored
refresh token — to anyone who POSTed to it. The function was deleted from the Supabase dashboard
and the Gmail OAuth grant was revoked. **The source is still in this repo. Do not redeploy it
without auth in front of it.** The app's "import bank emails" button no longer works; that is
expected.

### 2. Fail-closed daily caps on the AI functions (2026-08-28)

`analyze-passbook` had a cap that was explicitly fail-open — any error (including the counter
table not existing) let the request straight through, so in practice there was probably no cap at
all. `limit-advisor` had no cap whatsoever: unlimited Claude calls on Noah's `ANTHROPIC_API_KEY`.

Both now share the same fail-closed `underDailyCap()`:

- If the counter can't be reached or read, the request is **refused**, not allowed.
- The counter increments atomically in Postgres (`INSERT .. ON CONFLICT DO UPDATE .. RETURNING`),
  so concurrent hammering can't slip past the limit the way a read-then-write check could.
- Caps: `analyze-passbook` 15/day, `limit-advisor` 40/day.

The helper is duplicated in both function files rather than shared from `_shared/`, on purpose —
each file must stay self-contained so it can be pasted straight into the Supabase dashboard
editor, which is how these have been deployed before.

#### Required one-time SQL — run this BEFORE deploying the functions

If you deploy first, both AI features will refuse every request until this exists. Paste into
Supabase → SQL Editor and run:

```sql
create table if not exists fn_usage_daily (
  day   date not null,
  fn    text not null,
  count int  not null default 0,
  primary key (day, fn)
);

-- No policies are created, so anon and authenticated cannot touch this table at all.
-- service_role bypasses RLS, which is how the edge functions reach it.
alter table fn_usage_daily enable row level security;

create or replace function bump_fn_usage(p_fn text, p_cap int)
returns boolean
language plpgsql
as $$
declare n int;
begin
  insert into fn_usage_daily (day, fn, count)
  values (current_date, p_fn, 1)
  on conflict (day, fn) do update set count = fn_usage_daily.count + 1
  returning count into n;
  return n <= p_cap;
end;
$$;

-- Only the edge functions (service_role) may bump the counter. Without this, anyone
-- holding the public anon key could call the RPC directly and burn the daily quota.
revoke all on function bump_fn_usage(text, int) from public, anon, authenticated;
grant execute on function bump_fn_usage(text, int) to service_role;
```

Then deploy: `supabase functions deploy analyze-passbook` and
`supabase functions deploy limit-advisor` (or paste each file into the dashboard editor).

To check it works: use an AI feature once, then in the SQL editor run
`select * from fn_usage_daily;` — you should see today's row at count 1.

## Still open

### 3. `finance_data` has no real access control

**Not directly verified** — no network route from the dev sandbox to `supabase.co`, and there is
no `supabase/migrations/` in this repo, so the policies aren't in source. But `app.html` has no
login and identifies itself only by the public `USER_KEY`, so the anon role must be permitted to
read and write that table for the app to work at all. Treat the budget data as publicly readable
and writable until proven otherwise. Check at
Supabase → Authentication → Policies → `finance_data`.

The fix is real auth. **Note the caps above do not help here** — they only protect the AI spend.

#### What an auth migration has to touch

Listed because it is easy to miss one and silently break sync or lock yourself out:

| Surface | What reads/writes with the anon key today |
|---|---|
| `app.html` / `index.html` | `sb.from('finance_data').select(...)`, `.upsert(...)`, and the realtime `sb.channel(...)` subscription |
| `ios/Budget/Budget/BudgetStore.swift` | `refresh()` and the persist call — raw REST with `anon` + `userKey`; plus 4 edge-function calls |
| `ios/Budget/BudgetWidgets/BudgetWidgets.swift` | **its own independent network read** with the anon key — needs the token shared via the app group, or it goes blank |
| `scripts/send-push.js` (GitHub Action) | reads `finance_data` with `ANON`. Enabling RLS **silently kills the daily reminder push** unless this gets the service_role key as a GitHub secret |

**Ordering matters.** Turning RLS on before every one of those sends a real token locks you out of
your own data, and a client mid-edit could fail its save. Get every client sending a token first,
verify, then tighten the policy.

### 4. The anon key is public and cannot be un-published

Making the repo private does **not** fix this — `app.html` is served publicly by Pages, so the key
is readable from the live site regardless. Rotating it is possible (Supabase → Settings → API)
but rotates `service_role` too and would need every client and secret updated. Rotation is only
worth doing *after* auth is in place; before that, the new key would be just as public as the old.
