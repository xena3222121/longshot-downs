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

const THEME_IDS: Array[String] = ["neon_downs", "desert_dusk", "storm_coast", "bluegrass_night", "classic_amber"]

## Every theme's track_surface_color (dirt) and infield_color (grass) were
## re-tuned toward genuinely brown/green — AJ asked for the racing SURFACE
## itself to look natural rather than continuing the neon-tinted look the
## broadcast-HUD re-skin gave it (the rail/floodlight/trim/flag colors below
## are untouched — those are deliberate broadcast-style accents, not
## "environment," and AJ didn't ask to lose those). Each theme keeps its own
## mood variance (desert_dusk stays sandier, storm_coast stays cooler/muted,
## etc.) rather than converging on one identical brown/green everywhere.

const THEMES: Dictionary = {
	"neon_downs": {
		"label": "Neon Downs (Night)",
		"rail_color": Color(0.55, 0.92, 1.0),
		"track_surface_color": Color(0.32, 0.21, 0.14),
		"infield_color": Color(0.09, 0.28, 0.11),
		"sky_top": Color(0.015, 0.02, 0.05),
		"sky_horizon": Color(0.08, 0.12, 0.22),
		"ground_bottom": Color(0.01, 0.012, 0.02),
		"ground_horizon": Color(0.05, 0.07, 0.1),
		"ambient_color": Color(0.1, 0.13, 0.19),
		"sun_color": Color(0.55, 0.68, 0.95),
		"sun_energy": 0.25,
		"floodlight_color": Color(0.86, 0.92, 1.0),
		"floodlight_energy": 48.0,
		"grandstand_lower": Color(0.05, 0.065, 0.09),
		"grandstand_upper": Color(0.13, 0.16, 0.21),
		"grandstand_roof": Color(0.07, 0.09, 0.13),
		"trim_color": Color(0.184, 0.878, 0.976),
		"pylon_beacon_color": Color(0.667, 0.529, 0.976),
		"flag_colors": [Color(0.184, 0.878, 0.976), Color(0.847, 0.184, 0.616)],
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
	## Storm-front night meet — cold, low-visibility, electric-white rail like
	## lightning caught mid-flash. Floodlights pushed hardest of the three
	## themes to cut through the gloom instead of adding fog/haze (a real
	## Environment.fog pass swallowed the whole scene the first time this was
	## tried — see RaceTrack3D's own history — so mood here comes entirely
	## from color/light choices, not a fog volume).
	"storm_coast": {
		"label": "Storm Coast Downs",
		"rail_color": Color(0.82, 0.9, 1.0),
		"track_surface_color": Color(0.24, 0.19, 0.15),
		"infield_color": Color(0.07, 0.2, 0.13),
		"sky_top": Color(0.03, 0.035, 0.05),
		"sky_horizon": Color(0.13, 0.16, 0.2),
		"ground_bottom": Color(0.02, 0.022, 0.03),
		"ground_horizon": Color(0.1, 0.12, 0.15),
		"ambient_color": Color(0.12, 0.15, 0.19),
		"sun_color": Color(0.6, 0.68, 0.78),
		"sun_energy": 0.2,
		"floodlight_color": Color(0.75, 0.85, 1.0),
		"floodlight_energy": 58.0,
		"grandstand_lower": Color(0.07, 0.08, 0.1),
		"grandstand_upper": Color(0.18, 0.21, 0.25),
		"grandstand_roof": Color(0.09, 0.1, 0.13),
		"trim_color": Color(0.7, 0.85, 1.0),
		"pylon_beacon_color": Color(0.6, 0.8, 1.0),
		"flag_colors": [Color(0.7, 0.85, 1.0), Color(0.85, 0.9, 0.95)],
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
}

static func get_theme(theme_id: String) -> Dictionary:
	return THEMES.get(theme_id, THEMES[DEFAULT_THEME_ID])

static func label_for(theme_id: String) -> String:
	return String(get_theme(theme_id).get("label", theme_id))
