extends SceneTree

## Dev tool, not part of the game: run with
##   godot --headless --path . --script res://scripts/tools/generate_achievement_icons.gd
## Generates Steamworks achievement icon PNGs (unlocked + locked variant per
## achievement, 256x256) matching this game's own dark-panel/accent-ring
## visual language instead of generic clip art — Steamworks requires icon
## uploads per achievement and none existed at all before this (see
## docs/STEAMWORKS_SETUP.md's own note on the gap). Ids are hardcoded here
## rather than read from Career.ACHIEVEMENTS/CareerStable.MILESTONES since
## those are autoloads only available in a real scene tree (--path . alone,
## without a .tscn, doesn't instantiate autoloads) — keep this list in sync
## with BOTH by hand if achievements ever change on either side.
##
## Pure Image pixel drawing, not a rendered Control/SubViewport — avoids any
## dependency on font/theme rendering actually working correctly in a
## brand-new headless SubViewport (unverified, and this environment can't
## visually confirm text rendered correctly anyway), so a simple accent-ring
## badge is the reliable choice over a lettered monogram.

const ICON_SIZE: int = 256
const OUT_DIR: String = "res://assets/icons/achievements/"

## One thematic accent color per achievement id — distinct enough to tell
## apart at a glance in Steamworks' achievement list. Loosely matched to each
## achievement's own flavor (fire/streak = warm orange-red, money = gold,
## upset = violet, camera = cyan, endurance = green) rather than one flat
## palette reused for all eight.
const ACCENTS: Dictionary = {
	"first_blood": Color(0.85, 0.2, 0.25),
	"hot_streak": Color(1.0, 0.55, 0.1),
	"on_fire": Color(1.0, 0.35, 0.05),
	"giant_killer": Color(0.6, 0.3, 0.9),
	"high_roller": Color(0.85, 0.68, 0.15),
	"photo_finish_fan": Color(0.2, 0.7, 0.95),
	"millionaire": Color(1.0, 0.84, 0.2),
	"century_club": Color(0.3, 0.85, 0.45),
	# CareerStable.MILESTONES (owner-mode career achievements) — added same
	# session as the career mode overhaul, kept in this same generator/style
	# rather than a separate tool so every Steam achievement icon in the game
	# looks like one consistent set.
	"first_win": Color(0.85, 0.25, 0.55),
	"three_horses": Color(0.35, 0.65, 0.9),
	"allowance_class": Color(0.55, 0.75, 0.25),
	"stakes_class": Color(0.2, 0.55, 0.35),
	"grade1_win": Color(0.95, 0.75, 0.1),
	"maxed_category": Color(0.75, 0.4, 0.15),
	"maxed_all_three": Color(0.9, 0.15, 0.15),
	"blue_blood_owner": Color(0.45, 0.4, 0.85),
	"five_wins": Color(0.15, 0.75, 0.75),
	"big_spender": Color(0.85, 0.8, 0.2),
}

const BG_COLOR: Color = Color(0.043, 0.067, 0.106, 1.0)
const LOCKED_ACCENT: Color = Color(0.4, 0.42, 0.46)

func _init() -> void:
	var out_dir_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir_abs)

	for id in ACCENTS.keys():
		_write_icon(id, ACCENTS[id], false, out_dir_abs)
		_write_icon(id, LOCKED_ACCENT, true, out_dir_abs)

	print("generate_achievement_icons: wrote %d icon pairs to %s" % [ACCENTS.size(), out_dir_abs])
	quit()

## Concentric-ring badge: solid background disc, a bright accent ring near
## the edge, a dimmer accent-tinted fill inside it — reads as a medal/coin at
## a glance regardless of which achievement it's for. The locked variant uses
## one flat gray accent instead of the achievement's own color and a lower
## fill alpha, so locked/unlocked are distinguishable even before Steamworks'
## own grayscale-locked-icon treatment (if it applies one) kicks in.
func _write_icon(id: String, accent: Color, locked: bool, out_dir_abs: String) -> void:
	var image := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(ICON_SIZE, ICON_SIZE) * 0.5
	var outer_radius: float = ICON_SIZE * 0.48
	var ring_inner_radius: float = outer_radius - ICON_SIZE * 0.07
	var fill_alpha: float = 0.85 if not locked else 0.35

	for y in range(ICON_SIZE):
		for x in range(ICON_SIZE):
			var d: float = Vector2(x, y).distance_to(center)
			var pixel := Color(0.0, 0.0, 0.0, 0.0)
			if d <= outer_radius:
				if d >= ring_inner_radius:
					pixel = accent
				else:
					pixel = BG_COLOR.lerp(accent, fill_alpha)
			image.set_pixel(x, y, pixel)

	var suffix: String = "_locked" if locked else ""
	image.save_png(out_dir_abs.path_join(id + suffix + ".png"))
