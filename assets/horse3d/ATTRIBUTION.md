# Horse 3D Model Attribution

## horse.glb (primary model — use this one)

- **Model name:** "Horse" (bay/brown horse)
- **Author / Creator:** Quaternius (https://quaternius.com/, https://twitter.com/quaternius)
- **Source page:** https://poly.pizza/m/qvTrSG9pZF
- **Direct asset origin:** Poly Pizza CDN mirror of Quaternius's CC0 low-poly animal packs
  (same model appears in Quaternius's "Ultimate Animated Animal Pack" / "Animated Animal Pack")
- **License:** CC0 1.0 Universal (Public Domain) — https://creativecommons.org/publicdomain/zero/1.0/
  No attribution legally required; this file exists for project record-keeping and courtesy credit.
- **Triangle count:** 1,874 tris (low-poly, no decimation needed)
- **Format as downloaded:** glTF 2.0 binary (`.glb`), originally exported from Blender/FBX via
  `FBX2glTF v0.9.7` (per the file's `asset.generator` field)
- **Rig:** Single skinned mesh named "Horse", one skeleton/skin ("AnimalArmature") with 68 nodes
  (head, neck, ears, tail, 4 legs with IK pole targets, etc.)
- **Materials:** Main, Hair, Main_Dark, Muzzle, Hooves, Main_Light, Eye_Black, Eye_White
  (flat-shaded, no textures/images embedded — fits a PS1/N64 low-poly look well). No saddle,
  bridle, reins, or rider geometry/materials are present — bare horse only, as required.
- **Animation clips embedded in the file** (26 total, listed twice under two naming schemes —
  plain names and `AnimalArmature|`-prefixed originals from the Blender action names; both
  point to the same underlying animation data so either can be used from Godot):
  - `Idle`, `Idle_2`, `Idle_Headlow`, `Idle_HitReact_Left`, `Idle_HitReact_Right`
  - `Walk`
  - **`Gallop`** ← use this as the run/gallop cycle for racing
  - `Gallop_Jump`, `Jump_toIdle`
  - `Eating`
  - `Attack_Headbutt`, `Attack_Kick`
  - `Death`
  - (each of the above also exists again prefixed `AnimalArmature|...`)

## horse_white_variant.glb (optional bonus — not required, kept for reference)

- **Model name:** "White Horse" — same rig/animations/mesh topology as `horse.glb`, different
  coat-color material values only (1,934 tris)
- **Author:** Quaternius
- **Source page:** https://poly.pizza/m/bEdE4rmZy9
- **License:** CC0 1.0 Universal (Public Domain)
- Useful if the game wants a second horse coat color (e.g. a distinct player/rival horse) without
  sourcing a whole new rig.

## How these were obtained

Poly Pizza (poly.pizza) hosts direct CDN mirrors of Quaternius's CC0 asset packs and allows
downloading individual models with no login/account required. The site confirms
"No login required" on its horse search results page. Files were fetched directly from
Poly Pizza's static asset CDN (`static.poly.pizza/<resource-id>.glb`) via the model's public
resource ID, which is the same file the site's in-browser "Download" button serves.

Original pack pages for reference (same models, distributed as fuller packs with more animals):
- https://quaternius.com/packs/ultimateanimatedanimals.html
- https://poly.pizza/bundle/Animated-Animal-Pack-ILAPXeUYiS
