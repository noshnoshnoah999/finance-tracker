# Claude Code prompt — push the fail-closed AI caps

Work in `~/Claude/finance-tracker`.

One commit is waiting to be pushed. It changes `supabase/functions/analyze-passbook/index.ts`,
`supabase/functions/limit-advisor/index.ts`, and adds `SECURITY.md`.

What it does: both AI edge functions now share a fail-closed daily cap. `analyze-passbook`'s old
cap was fail-open (any error let requests straight through), and `limit-advisor` had no cap at
all. The counter now increments atomically in Postgres and refuses the request if it can't be
read.

Steps:

1. **Clear stale locks first.** Check `ps aux | grep -i git` shows no real git process, then
   remove any `.git/*.lock`, `.git/refs/**/*.lock` and `.git/objects/**/tmp_obj_*`. Delete the
   `_to_delete/` folder at the repo root if it has reappeared.
2. `git status` and `git log --oneline -3` — show me the state first.
3. `git push origin main` (check the branch name, don't assume). No Xcode build needed — this
   commit contains no Swift.
4. Confirm the push landed and give me the SHA.
5. **Clean up afterwards so next time is smoother:** remove any lock files git left behind
   (`.git/index.lock`, `.git/HEAD.lock`, `.git/objects/maintenance.lock`, any
   `.git/objects/**/tmp_obj_*`, `.git/refs/**/*.lock`) and confirm `git status` runs clean.

## Then, and this order matters

Pushing does **not** deploy edge functions — they deploy separately, and if you deploy them
before the SQL exists both AI features will refuse every request.

1. **First**, run the SQL block from `SECURITY.md` (the `fn_usage_daily` table plus the
   `bump_fn_usage` function and its grants) in Supabase → SQL Editor.
2. **Then** deploy: `supabase functions deploy analyze-passbook` and
   `supabase functions deploy limit-advisor`.
3. **Then** check it: use an AI feature in the app once, then run
   `select * from fn_usage_daily;` in the SQL editor. You should see today's row at count 1.
   If the feature returns an error instead, the SQL didn't run — check step 1 before touching
   the function code.

Tell Noah when each of those three is done, and paste the `select * from fn_usage_daily;` output.
