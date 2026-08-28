class_name TrackThemes
extends RefCounted

## Palette/lighting presets for RaceTrack3D — geometry (track shape, rail
## height, grandstand tier sizes, ...) never changes between themes, only
## color/light values do. Selected via Settings.track_theme_id (persisted,
## picked from TitleScreen's Settings dialog) and read once per race by
## RaceTrack3D._apply_theme(). Every theme carries the exact same key set so
## RaceTrack3D can pull from whichever theme is active without branching on
## which one it is.

const DEFAULT_THEME_ID: String = "neon_downs"

const THEME_IDS: Array[String] = ["neon_downs", "desert_dusk", "storm_coast", "bluegrass_night", "classic_amber", "golden_coast"]

## Every theme's track_surface_color (dirt) and infield_color (grass) were
## re-tuned toward genuinely brown/green — AJ asked for the racing SURFACE
## itself to look natural rather than continuing the neon-tinted look the
## broadcast-HUD re-skin gave it (the rail/floodlight/trim/flag colors below
## are untouched — those are deliberate broadcast-style accents, not
## "environment," and AJ didn't ask to lose those). Each theme keeps its own
## mood variance (desert_dusk stays sandier, storm_coast stays cooler/muted,
## etc.) rather than converging on one identical brown/green everywhere.

const THEMES: Dictionary = {
	## Default theme (id kept as "neon_downs" for save-file/Settings
	## compatibility — Settings.track_theme_id persists this exact string —
	## but re-themed entirely: AJ, after seeing an actual screenshot, "the
	## horses dont look like fucking horses this is a huge problem." Natural
	## coat colors (see HorseMarker3D.NATURAL_COAT_COLORS) still read as dark
	## indistinct blobs under EVERY theme's night-racing-under-floodlights
	## lighting (sun_energy 0.2-0.9, near-black sky) — no coat color fix could
	## ever fully solve that on its own. This is real daylight instead: bright
	## blue sky, sun_energy actually driving the scene instead of floodlights,
	## a traditional white-rail/green-grandstand look matching the
	## already-reverted "Racing Elegance" UI palette (brass/gold trim, deep
	## green roof) rather than a night-broadcast HUD feel. The other 4 themes
	## are left as deliberate atmospheric alternatives a player can still pick
	## (dusk/storm/night/amber) — this is the one the game actually opens on.
	"neon_downs": {
		"label": "Longshot Downs (Classic Day)",
		"rail_color": Color(0.93, 0.91, 0.85),
		"track_surface_color": Color(0.42, 0.27, 0.15),
		"infield_color": Color(0.16, 0.45, 0.14),
		"sky_top": Color(0.3, 0.52, 0.85),
		"sky_horizon": Color(0.78, 0.85, 0.92),
		"ground_bottom": Color(0.14, 0.17, 0.1),
		"ground_horizon": Color(0.42, 0.44, 0.32),
		# Real CC0 HDRI (Poly Haven, "Kloofendal 48d Partly Cloudy") for this
		# theme's bright midday look — see RaceTrack3D._build_lighting, which
		# falls back to the procedural sky_top/sky_horizon/etc. colors above if
		# this file is ever missing, so those stay authored and correct
		# regardless.
		"sky_hdri": "res://assets/env/sky_day.hdr",
		"ambient_color": Color(0.5, 0.53, 0.55),
		"sun_color": Color(1.0, 0.97, 0.88),
		"sun_energy": 1.35,
		"floodlight_color": Color(1.0, 0.97, 0.9),
		"floodlight_energy": 8.0,
		"grandstand_lower": Color(0.74, 0.71, 0.61),
		"grandstand_upper": Color(0.87, 0.84, 0.76),
		"grandstand_roof": Color(0.1, 0.32, 0.15),
		"trim_color": Color(0.75, 0.6, 0.24),
		"pylon_beacon_color": Color(0.8, 0.65, 0.3),
		"flag_colors": [Color(0.75, 0.6, 0.24), Color(0.58, 0.14, 0.15)],
	},
	## Warm golden-hour meet — sun still up but low, so warm halogen floodlights
	## are already kicking in alongside it. Amber/coral neon instead of
	## cyan/magenta so it reads as a distinct mood, not just a recolor.
	"desert_dusk": {
		"label": "Desert Dusk Circuit",
		"rail_color": Color(1.0, 0.75, 0.4),
		"track_surface_color": Color(0.44, 0.28, 0.16),
		"infield_color": Color(0.26, 0.32, 0.13),
		"sky_top": Color(0.25, 0.14, 0.28),
		"sky_horizon": Color(0.93, 0.5, 0.28),
		"ground_bottom": Color(0.16, 0.09, 0.08),
		"ground_horizon": Color(0.55, 0.32, 0.22),
		"sky_hdri": "", # no real HDRI matches this dusk gradient — stays procedural
		"ambient_color": Color(0.32, 0.2, 0.18),
		"sun_color": Color(1.0, 0.62, 0.35),
		"sun_energy": 0.9,
		"floodlight_color": Color(1.0, 0.78, 0.5),
		"floodlight_energy": 38.0,
		"grandstand_lower": Color(0.24, 0.15, 0.11),
		"grandstand_upper": Color(0.46, 0.3, 0.2),
		"grandstand_roof": Color(0.3, 0.15, 0.12),
		"trim_color": Color(1.0, 0.65, 0.2),
		"pylon_beacon_color": Color(1.0, 0.45, 0.3),
		"flag_colors": [Color(1.0, 0.65, 0.2), Color(0.87, 0.32, 0.42)],
	},
	## Re-themed from a pitch-black "storm-front NIGHT meet" to an overcast
	## storm-front DAY — AJ's own saved Settings.track_theme_id was actually
	## set to THIS theme (not the default) when he called the horses "hot
	## dogs" and said they "dont look like fucking horses," so fixing only
	## the default theme above wouldn't have touched what he was actually
	## looking at at all. Keeps the cool/stormy icy-white-and-gray mood
	## (still visibly its own place next to the bright warm default day) but
	## with real diffused daylight instead of near-black night — sun_energy
	## 0.2->0.85 and every sky/ground/ambient value brightened accordingly.
	"storm_coast": {
		"label": "Storm Coast Downs",
		"rail_color": Color(0.85, 0.9, 0.95),
		"track_surface_color": Color(0.3, 0.24, 0.19),
		"infield_color": Color(0.14, 0.32, 0.22),
		"sky_top": Color(0.35, 0.4, 0.48),
		"sky_horizon": Color(0.62, 0.65, 0.7),
		"ground_bottom": Color(0.16, 0.17, 0.16),
		"ground_horizon": Color(0.37, 0.38, 0.36),
		# Real CC0 HDRI (Poly Haven, "Kloofendal Overcast") — same location as
		# the default theme's HDRI, different weather, matching this theme's
		# own "overcast storm-front DAY" mood.
		"sky_hdri": "res://assets/env/sky_overcast.hdr",
		"ambient_color": Color(0.42, 0.45, 0.5),
		"sun_color": Color(0.85, 0.88, 0.92),
		"sun_energy": 0.85,
		"floodlight_color": Color(0.85, 0.9, 1.0),
		"floodlight_energy": 10.0,
		"grandstand_lower": Color(0.5, 0.52, 0.56),
		"grandstand_upper": Color(0.65, 0.67, 0.71),
		"grandstand_roof": Color(0.28, 0.3, 0.36),
		"trim_color": Color(0.6, 0.72, 0.85),
		"pylon_beacon_color": Color(0.55, 0.7, 0.85),
		"flag_colors": [Color(0.6, 0.72, 0.85), Color(0.8, 0.83, 0.88)],
	},
	## Deep emerald night meet — warm amber floodlights against a cool green
	## rail/infield instead of any of the other three's cyan/amber/icy-white
	## combinations, so it reads as its own place at a glance.
	"bluegrass_night": {
		"label": "Bluegrass Night",
		"rail_color": Color(0.45, 0.95, 0.55),
		"track_surface_color": Color(0.28, 0.2, 0.13),
		"infield_color": Color(0.09, 0.3, 0.14),
		"sky_top": Color(0.02, 0.05, 0.03),
		"sky_horizon": Color(0.06, 0.14, 0.09),
		"ground_bottom": Color(0.01, 0.02, 0.015),
		"ground_horizon": Color(0.05, 0.09, 0.06),
		"sky_hdri": "", # night meet — no daylight HDRI applies, stays procedural
		"ambient_color": Color(0.09, 0.16, 0.11),
		"sun_color": Color(0.55, 0.75, 0.6),
		"sun_energy": 0.22,
		"floodlight_color": Color(1.0, 0.88, 0.6),
		"floodlight_energy": 46.0,
		"grandstand_lower": Color(0.06, 0.09, 0.07),
		"grandstand_upper": Color(0.14, 0.22, 0.16),
		"grandstand_roof": Color(0.08, 0.12, 0.09),
		"trim_color": Color(0.5, 0.95, 0.6),
		"pylon_beacon_color": Color(0.6, 0.9, 0.5),
		"flag_colors": [Color(0.45, 0.95, 0.55), Color(1.0, 0.85, 0.4)],
	},
	## Old-school sodium-vapor warmth — deliberately LESS neon than every
	## other theme (muted brass rail instead of a glowing electric color) for
	## a "this is the old, traditional track" mood among otherwise-flashy
	## venues.
	"classic_amber": {
		"label": "Classic Amber",
		"rail_color": Color(0.85, 0.65, 0.25),
		"track_surface_color": Color(0.4, 0.26, 0.15),
		"infield_color": Color(0.18, 0.3, 0.11),
		"sky_top": Color(0.08, 0.05, 0.02),
		"sky_horizon": Color(0.28, 0.16, 0.06),
		"ground_bottom": Color(0.05, 0.035, 0.02),
		"ground_horizon": Color(0.2, 0.13, 0.07),
		"sky_hdri": "", # night meet — no daylight HDRI applies, stays procedural
		"ambient_color": Color(0.2, 0.15, 0.09),
		"sun_color": Color(0.95, 0.7, 0.4),
		"sun_energy": 0.4,
		"floodlight_color": Color(1.0, 0.82, 0.45),
		"floodlight_energy": 42.0,
		"grandstand_lower": Color(0.14, 0.1, 0.06),
		"grandstand_upper": Color(0.32, 0.24, 0.15),
		"grandstand_roof": Color(0.18, 0.12, 0.07),
		"trim_color": Color(0.85, 0.65, 0.25),
		"pylon_beacon_color": Color(0.9, 0.7, 0.3),
		"flag_colors": [Color(0.85, 0.65, 0.25), Color(0.6, 0.4, 0.2)],
	},
	## AJ: "make it look like Del Mar... kinda like Blender graphics, not over
	## the top, match the scale of the game." el_cid/mesa_fairgrounds are both
	## Del Mar-inspired (see Venues.gd) but were both riding storm_coast's
	## overcast/stormy mood, which is the opposite of Del Mar's real identity
	## ("where the surf meets the turf" — bright coastal Southern California
	## sun, not a gray storm front). storm_coast itself is left completely
	## untouched (several OTHER venues use it, see Venues.gd's theme_id list),
	## so this is a new theme rather than a re-tune of an existing one. Reuses
	## sky_day.hdr (same bright-midday HDRI as the default theme) since that
	## mood is exactly right here too. skyline_style/tree_style below are new
	## opt-in keys (default "skyscraper"/"round" for every other theme, see
	## RaceTrack3D._build_skyline/_make_tree) so only this theme swaps the
	## distant-city skyline for coastal hills and the round shade trees for
	## palms — every other theme's environment dressing is unaffected.
	"golden_coast": {
		"label": "Golden Coast Downs",
		"rail_color": Color(0.95, 0.93, 0.86),
		"track_surface_color": Color(0.46, 0.32, 0.19),
		"infield_color": Color(0.22, 0.5, 0.19),
		"sky_top": Color(0.25, 0.55, 0.85),
		"sky_horizon": Color(0.75, 0.86, 0.93),
		"ground_bottom": Color(0.16, 0.19, 0.13),
		"ground_horizon": Color(0.5, 0.47, 0.36),
		"sky_hdri": "res://assets/env/sky_day.hdr",
		"ambient_color": Color(0.52, 0.53, 0.5),
		"sun_color": Color(1.0, 0.97, 0.86),
		"sun_energy": 1.4,
		"floodlight_color": Color(1.0, 0.97, 0.9),
		"floodlight_energy": 8.0,
		# White Spanish-mission grandstand walls with a teal tower-roof
		# accent — Del Mar's own real, instantly-recognizable color pairing.
		"grandstand_lower": Color(0.88, 0.85, 0.76),
		"grandstand_upper": Color(0.96, 0.94, 0.88),
		"grandstand_roof": Color(0.08, 0.42, 0.44),
		"trim_color": Color(0.1, 0.5, 0.5),
		"pylon_beacon_color": Color(0.85, 0.42, 0.32),
		"flag_colors": [Color(0.1, 0.5, 0.5), Color(0.85, 0.42, 0.32)],
		"skyline_style": "coastal_hills",
		"tree_style": "palm",
	},
}

static func get_theme(theme_id: String) -> Dictionary:
	return THEMES.get(theme_id, THEMES[DEFAULT_THEME_ID])

static func label_for(theme_id: String) -> String:
	return String(get_theme(theme_id).get("label", theme_id))
