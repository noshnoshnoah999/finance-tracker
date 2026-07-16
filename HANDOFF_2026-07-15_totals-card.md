# Handoff — One-off Total + Combined Totals Card

**Date:** 2026-07-15
**Commit:** `b1f69c3` — "Add One-off total + left-to-pay and combined Total Expenses card (web + iOS)"
**Status:** Committed on `main`. NOT pushed (stale git locks blocked sandbox; push delegated to Claude Code — see prompt below).

## What was requested
1. One-off Expenses card: add a total (like Fixed has) plus a "left to pay" figure.
2. New card under Free to Spend (every month) showing **Total left to pay** and **Total expenses**, combining Fixed + One-off.
3. Make that new card reorderable like the other cards.

## Decisions confirmed with Noah
- **Combined "Total Expenses" scope:** Fixed + One-off only. Excludes Send-to-Mum and Subscribe (Subscribe already feeds Fixed's Amazon line).
- **"Left to pay" calc:** unpaid/unticked items only (decreases as you tick paid), mirroring how Fixed already works.
- **One-off Mum-pays:** excluded from One-off total and left-to-pay (only items you pay count). Mum-pays still shown separately.
- **Silver bug fix:** web Fixed "Left to pay" pill was excluding Silver investment while iOS `leftToPay` included it. Noah chose **include Silver everywhere** (it's already in "Total Fixed" on both). Web Fixed pill updated to match.

## Changes made (web + iOS parity)

### Web — `app.html` AND `index.html` (identical edits)
- **One-off card:** after the add-row, added `Total One-off` line (`bdOY`, peach) + a "Left to pay" pill. Left = `bd.oneOffs.filter(o=>!o.mumPays && !bdPOO[o.id])` summed. Green "All paid ✓" when 0. Only shown when `bdOY>0`.
- **New `totals` card:** inserted after the `free` card's wrapper. Shows Fixed row (`bdFT`), One-off row (`bdOY`), `Total expenses` = `bdFT+bdOY`, and a "Total left to pay" pill = inline Fixed-unpaid (same IIFE logic as Fixed pill, **now including silver**) + one-off unticked.
- Added `"totals"` to `cardOrder` (line ~85) and `BUDGET_CARDS` (line ~103) in both files.
- **Fixed pill fix:** added `if(!bdPF["silverInvest"])unpaid+=bdSilver;` to the Fixed card's left-to-pay IIFE.
- No migration needed: existing `cardOrder` loader (line ~330) auto-appends any `BUDGET_CARDS` id missing from saved order.

### iOS/macOS — SwiftUI
- `Shared/Finance.swift`: added `oneOffTotal(_ mk)` (excludes Mum) and `oneOffLeft(_ mk)` (excludes Mum + paidOneOffs) to `Calc`. Existing `leftToPay` already includes silver — unchanged.
- `Budget/BudgetTabView.swift`: one-off card now shows `Total One-off` + Left-to-pay pill (uses `T.peachBg`). Added `totalsCard(_:)` (Fixed + One-off breakdown, total, and "Total left to pay" = `c.leftToPay(bm) + c.oneOffLeft(bm)`). Added `case "totals": totalsCard(c)` to `cardFor`.
- `Shared/Models.swift`: added `"totals"` to `BUDGET_CARDS` and `"totals": "Total Expenses"` to `BUDGET_CARD_NAMES` (reorder sheet label).
- `BudgetStore.cardOrder` already appends missing ids — no migration.

## Verification done
- Both html files: 10 `data-cardid` cards; card region byte-identical between app.html and index.html; paren/brace balance 0/0.
- iOS theme colors (`peachBg`, `lavBg`, `peachD`, `lavD`) confirmed to exist in `Theme.swift`.
- Silver now included in left-to-pay on web Fixed pill, web combined card, and iOS `leftToPay` — consistent.
- `git status`: 5 tracked files committed, working tree clean.

## NOT verified (do next session / on device)
- iOS project has NOT been compiled/built in Xcode — Swift edits are eyeballed only. Build before shipping.
- Web not rendered in a browser this session — logic-checked, not visually confirmed.

## Push instructions for Claude Code
Stale locks (`.git/HEAD.lock`, `.git/index.lock`, `.git/objects/maintenance.lock`) exist — sandbox lacked permission to delete them. CC must:
1. `rm -f .git/HEAD.lock .git/index.lock .git/objects/maintenance.lock` and any `.git/objects/**/tmp_obj_*`.
2. `git status` — confirm `b1f69c3` present, tracked tree clean (untracked `HANDOFF_*` files are fine).
3. `git push origin main`.
4. Confirm `git log origin/main -1` shows `b1f69c3`.
5. Remove the lock files again after pushing so next session is clean.
