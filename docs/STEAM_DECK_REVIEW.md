# Steam Deck compatibility review

A code-level review for obvious Deck blockers — not a substitute for actually
testing on real hardware (or Valve's own compatibility check after
submission), but nothing here needs a real Deck to catch or fix.

## No blockers found

- **No text input anywhere.** Grepped for `LineEdit`/`TextEdit` across every
  script — zero matches. Nothing in this game ever needs the on-screen
  keyboard, which is one of the most common "Unsupported" reasons for an
  otherwise-fine game. Every screen is already fully controller-navigable
  (see this session's/earlier sessions' gamepad work in `InputHints.gd`).
- **No Windows-only APIs.** Grepped for `OS.execute`/`OS.get_name`/other
  platform-specific calls — the only Windows-specific code left in the
  project is the commented-out SAPI/PowerShell TTS announcer path from an
  earlier, since-removed feature (never actually wired in). Nothing active
  touches the OS in a Windows-only way.
- **Resolution/aspect already adaptive.** `project.godot`'s
  `window/stretch/mode="canvas_items"` + `aspect="expand"` scales the UI to
  fill whatever window size it's actually given — should adapt fine to the
  Deck's 1280×800 (16:10) screen without a dedicated Deck resolution preset.
- **Controller glyphs**: `InputHints._is_playstation_pad()` only special-
  cases PlayStation pads; anything else (including Steam Deck's own
  controls, which Steam Input reports to games as a standard Xbox-layout
  XInput gamepad) falls through to the default Xbox-style glyphs — which is
  actually correct for the Deck's own face-button layout (A/B/X/Y), so no
  change needed there.

## Worth knowing, not blockers

- **No native Linux export preset** — only "Windows Desktop" exists in
  `export_presets.cfg`. Valve's Deck verification tests the Windows build
  running under Proton by default; a native Linux export isn't required for
  a "Playable" or even "Verified" badge, though it's sometimes worth adding
  later for best-case performance/compatibility. Not needed to submit for
  Deck review as-is.
- **`SavePaths.resolve()` syncs saves via a local OneDrive folder** (checks
  `OS.get_environment("OneDrive")`) for cross-PC progress sync — on Deck/
  Proton that env var won't exist, so it correctly falls back to the normal
  `user://` save path (already handled, not a bug), just means Deck saves
  won't ride along with the OneDrive sync the way a Windows PC's would. If
  cross-device save sync on Deck specifically ever matters, Steamworks'
  actual Steam Cloud API (already partially wired for achievements/
  leaderboards via `SteamManager.gd`) would be the more idiomatic fix — not
  needed for launch.

## Net recommendation

Nothing here blocks submitting for Steam Deck compatibility review once a
real build is up on Steamworks. Worth an actual hands-on test on real
hardware (or via Steam's own Proton compatibility testing) before or shortly
after launch to confirm in practice, but no code changes are needed first.
