#!/usr/bin/env python3
"""One-time batch generator for the race announcer's ElevenLabs voice clips.

Reads the commentary templates straight out of RaceAnnouncerDirector.gd and
the horse roster straight out of HorseRoster.gd (so this never drifts from
the actual game text), renders every template x horse-name (or, for the
filler banks, x post-position-number permutation) combination that's worth
pre-caching, and calls the ElevenLabs TTS API once per unique line. Output
goes to assets/audio/announcer/<hash>.mp3 plus a manifest.json mapping exact
line text -> filename, which Announcer.gd reads at runtime.

FILLER_CALLS_2 / FILLER_CALLS_3 use post-position NUMBERS (%d), not horse
names, specifically so they ARE cacheable: which of up to 60 horse names ends
up running 1-2-3 isn't a boundable space, but post position is always capped
at FIELD_SIZE regardless of which horses got drawn, so it's just permutations
of 1..FIELD_SIZE. These two banks are the ONLY mechanism that fills dead air
between real events, so leaving them uncached (the original design) meant
the announcer went completely silent, every race, whenever nothing dramatic
was happening — Announcer.gd has no OS-TTS fallback (removed on purpose, see
its own header comment), so an uncached line is caption-only, no voice.

Usage:
    set ELEVENLABS_API_KEY=...
    set ELEVENLABS_VOICE_ID=...      (grab this from the ElevenLabs voice library)
    python tools/generate_announcer_audio.py --dry-run     # see cost estimate first
    python tools/generate_announcer_audio.py --max-credits 9000

Safe to re-run: already-generated lines (present in manifest.json AND still on
disk) are skipped, so a free-tier monthly credit cap can be spread over
several runs/months by just re-running this until the manifest is complete.
"""

import argparse
import hashlib
import itertools
import json
import os
import re
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DIRECTOR_GD = PROJECT_ROOT / "scripts" / "RaceAnnouncerDirector.gd"
ROSTER_GD = PROJECT_ROOT / "scripts" / "data" / "HorseRoster.gd"
OUT_DIR = PROJECT_ROOT / "assets" / "audio" / "announcer"
MANIFEST_PATH = OUT_DIR / "manifest.json"

API_URL = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"

# Post positions are always 1..FIELD_SIZE regardless of which of the 60
# roster horses got drawn (see HorseRoster.generate/assign_race_colors and
# RaceScheduler's field draw) — this bounds FILLER_CALLS_2/3's permutation
# space so they're cacheable at all. Keep in sync with the actual per-race
# field size if that ever changes.
FIELD_SIZE = 8

# Which banks to pre-render, and whether that bank is spoken "excited" (bumps
# ElevenLabs' speed setting) — mirrors the excited flag each call site passes
# to Announcer.say() in RaceAnnouncerDirector.gd.
#
# Order here is generation PRIORITY under a monthly credit cap, not the order
# banks appear in RaceAnnouncerDirector.gd.
#
# FILLER_CALLS_2/3 (numeric, permutation-based) REMOVED 2026-08-23 after AJ
# actually heard them: "announcer says number 3 number 7 instead of horses
# name kinda annoying." A full monthly credit run had already been spent
# generating FILLER_CALLS_3 — that audio is still on disk, just unreferenced,
# per this project's convention of not deleting shipped/generated assets.
# Replaced with FILLER_LEADER_CALLS/FILLER_CHASER_CALLS, which mention ONE
# real horse name per line instead of 2-3 post-position numbers — same flat
# per-name cost shape as LEADER_CALLS/MOVE_CALLS below (cheap), not a
# permutation blowup.
BANKS = {
    "RACE_START_CALLS": True,
    "TURN_CALLS": False,
    "STRETCH_CALLS": False,
    "DUEL_CALLS": True,
    "WIN_CALLS": True,
    "PHOTO_WIN_CALLS": True,
    "BLOWOUT_WIN_CALLS": True,
    "FILLER_LEADER_CALLS": False,
    "FILLER_CHASER_CALLS": False,
    "LEADER_CALLS": False,
    "MOVE_CALLS": False,
}

CONST_ARRAY_RE = re.compile(r'const\s+(\w+)\s*:\s*Array\[String\]\s*=\s*\[(.*?)\]', re.DOTALL)
STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


# Manual, non-lossy escape handling for the few GDScript string escapes these
# templates could plausibly use. Deliberately NOT `s.encode().decode("unicode_escape")`
# (the original approach): that round-trips through bytes assuming each byte
# is its own Latin-1 code point, which mangles any real non-ASCII character
# (e.g. the em dash in PHOTO_WIN_CALLS's "%s just gets there first — what a
# finish!" became three garbage codepoints — a real bug caught 2026-08-23
# mid-generation-run after already corrupting some manifest entries: the
# corrupted text was sent to ElevenLabs as the TTS input AND doesn't match
# what Announcer.gd looks up at runtime, since that reads the actual GDScript
# string with the real em dash — those lines would never have played).
_ESCAPES = {'\\n': '\n', '\\t': '\t', '\\"': '"', "\\'": "'", '\\\\': '\\'}


def _unescape(s: str) -> str:
    for escaped, literal in _ESCAPES.items():
        s = s.replace(escaped, literal)
    return s


def parse_string_arrays(gd_path: Path) -> dict:
    text = gd_path.read_text(encoding="utf-8")
    out = {}
    for name, body in CONST_ARRAY_RE.findall(text):
        out[name] = [_unescape(s) for s in STRING_RE.findall(body)]
    return out


def render_template(template: str, names: list) -> list:
    """Expand one template into every line worth caching for it."""
    placeholders = template.count("%d")
    if placeholders > 0:
        # Numeric (post-position) template: bounded permutations of
        # 1..FIELD_SIZE, order matters (1st/2nd/3rd are different slots).
        return [
            template % combo
            for combo in itertools.permutations(range(1, FIELD_SIZE + 1), placeholders)
        ]
    if "%s" in template:
        return [template % n for n in names]
    return [template]


def build_jobs(templates: dict, names: list) -> list:
    jobs = []  # list of (text, excited)
    seen = set()
    for bank, excited in BANKS.items():
        for template in templates.get(bank, []):
            for text in render_template(template, names):
                if text in seen:
                    continue
                seen.add(text)
                jobs.append((text, excited))
    return jobs


def clip_filename(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:20] + ".mp3"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api-key", default=os.environ.get("ELEVENLABS_API_KEY"))
    parser.add_argument("--voice-id", default=os.environ.get("ELEVENLABS_VOICE_ID"))
    parser.add_argument("--model", default="eleven_flash_v2_5", help="eleven_flash_v2_5 costs ~0.5 credit/char vs 1/char for multilingual_v2")
    parser.add_argument("--max-credits", type=float, default=9000.0, help="stop once estimated spend would exceed this (free tier is 10k/month)")
    parser.add_argument("--sleep", type=float, default=0.3, help="seconds between API calls")
    parser.add_argument("--dry-run", action="store_true", help="print the job list and credit estimate, make no API calls")
    parser.add_argument("--test", action="store_true", help="generate exactly one sample line per bank (mixed excited/normal, ~9 lines) to preview a voice cheaply instead of the full job list")
    args = parser.parse_args()

    templates = parse_string_arrays(DIRECTOR_GD)
    roster = parse_string_arrays(ROSTER_GD)
    names = roster.get("NAMES", [])
    if not names:
        print(f"error: couldn't parse NAMES out of {ROSTER_GD}", file=sys.stderr)
        return 1

    if args.test:
        jobs = []
        seen = set()
        for bank, excited in BANKS.items():
            bank_templates = templates.get(bank, [])
            if not bank_templates:
                continue
            template = bank_templates[0]
            text = render_template(template, names)[0]
            if text not in seen:
                seen.add(text)
                jobs.append((text, excited))
    else:
        jobs = build_jobs(templates, names)
    credit_per_char = 0.5 if "flash" in args.model or "turbo" in args.model else 1.0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = {}
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    pending = []
    already_done = 0
    for text, excited in jobs:
        fname = manifest.get(text)
        if fname and (OUT_DIR / fname).exists():
            already_done += 1
            continue
        pending.append((text, excited))

    total_chars = sum(len(t) for t, _ in pending)
    est_credits = total_chars * credit_per_char
    print(f"{len(jobs)} total lines, {already_done} already cached, {len(pending)} pending")
    print(f"pending: {total_chars} chars ~= {est_credits:.0f} credits at {credit_per_char}/char ({args.model})")

    if args.dry_run:
        for text, excited in pending[:20]:
            print(f"  [{'excited' if excited else 'normal '}] {text}")
        if len(pending) > 20:
            print(f"  ... and {len(pending) - 20} more")
        return 0

    if not args.api_key or not args.voice_id:
        print("error: --api-key/--voice-id (or ELEVENLABS_API_KEY/ELEVENLABS_VOICE_ID) required to actually generate", file=sys.stderr)
        return 1

    import requests  # deferred so --dry-run works without the dependency installed

    spent = 0.0
    generated = 0
    for text, excited in pending:
        cost = len(text) * credit_per_char
        if spent + cost > args.max_credits:
            print(f"stopping: next line would exceed --max-credits budget ({args.max_credits}); re-run later to continue")
            break

        resp = requests.post(
            API_URL.format(voice_id=args.voice_id),
            headers={"xi-api-key": args.api_key, "Content-Type": "application/json"},
            json={
                "text": text,
                "model_id": args.model,
                "voice_settings": {
                    "stability": 0.5,
                    "similarity_boost": 0.75,
                    "speed": 1.15 if excited else 1.0,
                },
            },
            timeout=30,
        )
        if resp.status_code != 200:
            print(f"error {resp.status_code} on {text!r}: {resp.text[:200]}", file=sys.stderr)
            break

        fname = clip_filename(text)
        (OUT_DIR / fname).write_bytes(resp.content)
        manifest[text] = fname
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

        spent += cost
        generated += 1
        print(f"[{generated}/{len(pending)}] {text!r} -> {fname} ({spent:.0f}/{args.max_credits:.0f} credits used)")
        time.sleep(args.sleep)

    print(f"done: generated {generated} clips this run, {len(manifest)} total in manifest")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
