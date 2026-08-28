# Steam content survey — self-check

Went through what's actually in the game against Steam's content-survey
categories, so filling out the real survey at upload time is a quick
confirm rather than a from-scratch audit.

## Simulated gambling — yes, flag this one

The whole game is pari-mutuel betting on simulated horse races using an
in-game-only currency. No real money can ever be deposited, wagered, or
withdrawn — the Credits screen says this explicitly (added specifically for
this reason, see `docs/STEAMWORKS_SETUP.md` §4). Answer Steam's gambling
question as **simulated gambling with in-game currency only**, not real-money
gambling.

## Everything else — reviewed, nothing to flag

- **Violence**: none. No combat, no death depicted (horses don't get
  injured/die in any race outcome).
- **Sexual content / nudity**: none.
- **Profanity / strong language**: none in any UI text, horse names, jockey
  names, venue names, or announcer lines. The horse roster (`HorseRoster.
  NAMES`, all 60 reviewed) leans into crude/toilet humor by design (e.g.
  "Fartin' Martin," "Sir Poops-a-Lot," "Buttcrack Bandit," "Hoof Hearted")
  and a couple of drink-name puns ("Whiskey Business," "Tequila
  Mockinghorse") — none of it is profanity, slurs, or anything depicting
  actual substance use. Reads as PG/family-humor crude, not Mature.
- **Drug or alcohol use**: not depicted — the two drink-adjacent horse names
  above are wordplay, not scenes of use.
- **In-app purchases**: none. Single $0.99 purchase, no IAP of any kind.
- **User-generated content / online interaction**: none — single-player,
  local save only, no chat/multiplayer/UGC surface.

## Net recommendation

Answer the survey as: general-audience, simulated (not real-money) gambling
theme, no other mature content flags needed. Nothing here should push this
toward a Mature rating or trigger extra review scrutiny beyond the standard
simulated-gambling question.
