# Steamworks setup checklist

Reference for the one-time Steamworks admin-panel setup this game's code
already assumes. Nothing here can be done from inside the codebase — this is
what to fill in on Valve's side once the Steamworks Direct application
(one-time $100 fee, refunded after $1,000 in sales) is approved and a real
App ID exists.

## 1. Replace the dev App ID

`scripts/autoload/SteamManager.gd` currently hardcodes
`DEV_APP_ID = 480` — Valve's public "Spacewar" test app, used so achievements/
leaderboards are exercisable during development without a real App ID yet.
Once Steamworks issues a real App ID for Longshot Downs, swap that one
constant. Nothing else in the codebase needs to change.

## 2. Achievements — create these exact API names

Steamworks achievements are matched by a string "API Name" that must be
**byte-for-byte identical** (case-sensitive) to what `Career.gd` passes to
`SteamManager.unlock_achievement()`. The game already unlocks these — they
just don't persist anywhere until they exist server-side.

| API Name (enter exactly) | Display Name | Description |
|---|---|---|
| `first_blood` | First Blood | Win your very first bet. |
| `hot_streak` | Hot Streak | Win 3 bets in a row. |
| `on_fire` | On Fire | Win 5 bets in a row. |
| `giant_killer` | Giant Killer | Win a Win bet on a 20/1-or-longer shot. |
| `high_roller` | High Roller | Place a single bet of $100,000 or more. |
| `photo_finish_fan` | Photo Finish Fan | Watch a race decided by a photo finish. |
| `millionaire` | Millionaire | Grow your bankroll to $2,000,000. |
| `century_club` | Century Club | Run 100 races. |

Icon art (unlocked + locked versions) already exists for all 8, generated to
match this game's own accent-ring badge style — see
`assets/icons/achievements/<id>.png` and `<id>_locked.png` (256x256). Just
upload these in the admin panel next to each achievement above.

(Source of truth if this list ever drifts: `Career.ACHIEVEMENTS` in
`scripts/autoload/Career.gd`.)

## 3. Leaderboards — create these exact names

`SteamManager.gd` calls `findLeaderboard()`/`uploadLeaderboardScore()` against
these two names. If a leaderboard with that exact name doesn't already exist
on Steamworks, the find silently fails and nothing uploads — the game can't
create these itself.

| Leaderboard Name (enter exactly) | What it tracks | Sort order | Display type |
|---|---|---|---|
| `Biggest_Bankroll` | Peak bankroll ever reached | Descending (higher is better) | Numeric |
| `Best_Win_Streak` | Longest consecutive winning-bet streak | Descending (higher is better) | Numeric |

(Source of truth: `SteamManager.LEADERBOARD_BANKROLL` /
`LEADERBOARD_WIN_STREAK`.)

## 4. Content survey

This game simulates wagering with an in-game-only currency — no real money
can be deposited, wagered, or withdrawn (see the in-game Credits screen,
which now says this explicitly). Steam's content survey should be answered
accordingly under simulated gambling; it does not involve real-money
gambling, loot boxes, or in-app purchases of any kind.

## 5. Store page assets still needed (none of these exist yet)

- Header capsule, small capsule, main capsule, vertical capsule, library
  assets (exact required pixel sizes are listed in Steamworks' own
  documentation and change occasionally — check there at upload time rather
  than trusting a number pinned here).
- At least 5 screenshots.
- A trailer (not strictly mandated, but close to it in practice for
  discoverability).
- Store page copy (short description, full description, tags — Simulation /
  Sports / Casual / Betting / Singleplayer / Controller Support all apply).

## 6. Build upload

The existing Windows Desktop export preset (`export_presets.cfg`) produces
`builds/windows/LongshotDowns.exe`. That build needs to go up via
SteamPipe/`steamcmd` into a depot once the App ID and a build branch exist in
Steamworks — this is a Steamworks-admin-panel + `steamcmd` step, not
something `export_presets.cfg` itself needs changed for.
