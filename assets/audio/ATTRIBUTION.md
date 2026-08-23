# Audio Asset Attribution

All audio assets below were sourced from freely-licensed catalogs. Every asset here is
CC0 (public domain) — no attribution legally required for any of it, including the
theme — credited anyway for completeness/provenance, same as everything else below.

## theme.mp3
- **Track:** "Calm Ambient 2 (Synthwave 15k)"
- **Source:** https://opengameart.org/content/calm-ambient-2-synthwave-15k (direct file: https://opengameart.org/sites/default/files/002_Synthwave_15k.mp3)
- **Author:** The Cynic Project (cynicmusic.com)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Note:** Replaced the previous theme, "Cheap Speed, Think Fast" (also cynicmusic, CC0) — AJ found the upbeat rock theme annoying and asked for something chill/ambient instead. Picked this one specifically because it's CC0 like its predecessor (AJ explicitly chose a zero-attribution track once already, swapping away from a CC-BY Kevin MacLeod theme for that exact reason — kept that property rather than reintroducing an attribution requirement) and its synthwave/calm-pad character tonally matches this game's "Neon Downs" cyan/magenta broadcast-HUD visual identity (see UITheme.gd) better than a generic nature-ambience track would.

## bet_click.ogg
- **File:** click_001.ogg from the "Interface Sounds" pack
- **Source:** https://kenney.nl/assets/interface-sounds
- **Author:** Kenney (kenney.nl)
- **License:** CC0 1.0 (Public Domain) — no attribution required.

## race_start_bell.ogg
- **File:** impactBell_heavy_000.ogg from the "Impact Sounds" pack
- **Source:** https://kenney.nl/assets/impact-sounds
- **Author:** Kenney (kenney.nl)
- **License:** CC0 1.0 (Public Domain) — no attribution required.

## finish_fanfare.mp3
- **Track:** "Success Fanfare Trumpets"
- **Source:** https://freesound.org/people/FunWithSound/sounds/456966/ (direct file: https://cdn.freesound.org/previews/456/456966_6456158-hq.mp3)
- **Author:** FunWithSound (freesound.org)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Note:** Replaced the original "Hyper-Ultra-Fanfare" (Zane Little Music, CC0) — AJ found the original grating at the finish line.

## win_jingle.wav
- **Track:** "Win sound effect"
- **Source:** https://opengameart.org/content/win-sound-effect (direct file: https://opengameart.org/sites/default/files/Win%20sound.wav)
- **Author:** (uncredited on OpenGameArt, released CC0)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Note:** Replaced the original "Victory Fanfare Short" (cynicmusic, CC0) — same reason as finish_fanfare above.

## lose_sting.ogg
- **Track:** "Game Over"
- **Source:** https://opengameart.org/content/game-over (direct file: https://opengameart.org/sites/default/files/Game%20Over_1.ogg)
- **Author:** Kistol
- **License:** CC0 1.0 (Public Domain) — creator notes credit is not required, though attribution is welcome.

## horse_neigh.mp3
- **Track:** "G38-15-Perfect Horse Whinny.wav" — a single classic horse whinny/neigh, from a digitized collection of vintage Hollywood optical/mag sound effects (1930s-60s)
- **Source:** https://freesound.org/people/craigsmith/sounds/437110/ (direct file: https://cdn.freesound.org/previews/437/437110_2524442-hq.mp3)
- **Author:** craigsmith (freesound.org)
- **License:** CC0 1.0 (Public Domain) — no attribution required.

## hoofbeats_loop.mp3
- **Track:** "R23-56-Horse Galloping.wav" — horse galloping on hard ground, close up, constant gallop, from the same digitized vintage Hollywood sound effects collection
- **Source:** https://freesound.org/people/craigsmith/sounds/479799/ (direct file: https://cdn.freesound.org/previews/479/479799_2524442-hq.mp3)
- **Author:** craigsmith (freesound.org)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Note:** This is a continuous close-up gallop recording rather than a purpose-built seamless loop, so there may be a faint transient at the loop point when `AudioManager` plays it with `loop = true`; it was chosen over shorter purpose-cut "loop" files from the same archive because it is an actual gallop (not a trot) and has no extraneous events mixed in. No longer used in-game as of the "arcade excess" pass (the ambient hoofbeats channel was removed for feeling like a second competing music track) — kept in case a future ambient-audio pass wants it back.

## whoosh.mp3
- **Track:** "Whoosh" — a bamboo stick swung to produce a wind-swish sound
- **Source:** https://freesound.org/people/qubodup/sounds/60013/ (direct file: https://cdn.freesound.org/previews/60/60013_71257-hq.mp3)
- **Author:** qubodup (freesound.org)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Usage:** was played on a horse's big mid-race surge alongside the camera punch/speed lines/particle trail, part of the "arcade excess" pass — removed per AJ's feedback ("lose the swoosh noise thing"), the camera punch/speed-line/particle-trail effects still fire on their own. Kept in case a future pass wants a whoosh sound back.

## post_time_bugle.mp3
- **Track:** "G39-16-Bugle Call.wav" — a bugle playing the classic cavalry-charge call, twice, from the same digitized vintage Hollywood optical/mag sound effects collection as horse_neigh.mp3/hoofbeats_loop.mp3
- **Source:** https://freesound.org/people/craigsmith/sounds/438633/ (direct file: https://cdn.freesound.org/previews/438/438633_2524442-hq.mp3)
- **Author:** craigsmith (freesound.org)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Usage:** AJ: "its definitely missing the classic post time announcing horn blast" — this isn't the exact historic "First Call"/"Call to the Post" bugle tune specifically (a clean isolated CC0 recording of that exact melody wasn't found), but a real, high-quality vintage bugle recording rather than a synth fanfare, close enough in spirit to read as the classic pre-race horn. Played once, right as the post-time "riders up" beat begins (see RaceTrack3D.play_with_post_time) — well before the separate race_start_bell cue at the actual gate.

## crowd_cheer.mp3
- **Track:** "Short Crowd Cheer" — a small crowd (~40 people) applauding at a concert
- **Source:** https://freesound.org/people/qubodup/sounds/182571/ (direct file: https://cdn.freesound.org/previews/182/182571_71257-hq.mp3)
- **Author:** qubodup (freesound.org)
- **License:** CC0 1.0 (Public Domain) — no attribution required.
- **Usage:** layered into the finish-line celebration alongside the existing finish_fanfare/win_jingle for extra "arcade excess" spectacle.
