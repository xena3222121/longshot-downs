class_name Venues
extends RefCounted

## Per-venue track identity for the multi-track scheduler (RaceScheduler) —
## geometry AND theme, unlike TrackThemes alone (which only ever varied
## color/light on ONE fixed track shape, by the player's own cosmetic
## choice). Each real-world-inspired venue gets its own straight/turn
## proportions (still the same 4-segment stadium math RaceTrack3D already
## has — a fresh curve TOPOLOGY per venue would be unverified 3D geometry
## work with no way to visually confirm it isn't broken, whereas a different
## aspect ratio on proven math is a safe, still-genuinely-different-feeling
## track) paired with a theme_id that fits its real counterpart's mood.

const DEFAULT_VENUE_ID: String = "longshot_downs"
const VENUE_IDS: Array[String] = [
	"longshot_downs", "barton_bay", "el_cid", "silverspring_downs", "bluegrass_downs",
	"kingsgate_crown", "tradewind_shores", "sierra_alta_peak", "limestone_ridge", "timberline_north",
	"harborcrest_downs", "cedar_meadow", "cresthaven_shore", "prairiefield_reach",
]

const VENUES: Dictionary = {
	"longshot_downs": {
		"label": "Longshot Downs",
		"straight_len": 140.0,
		"inner_radius": 26.0,
		"theme_id": "neon_downs",
	},
	## Tampa Bay Downs-inspired — a long, stretched-out oval with tighter
	## turns (longer straights relative to turn radius than Longshot Downs),
	## paired with the warm golden-hour Florida-evening theme.
	"barton_bay": {
		"label": "Barton Bay",
		"straight_len": 170.0,
		"inner_radius": 20.0,
		"theme_id": "desert_dusk",
	},
	## Del Mar-inspired — a rounder, more compact oval (shorter straights,
	## wider turns) than either of the other two, paired with the cool
	## moonlit-seaside theme for a distinct night-by-the-ocean mood.
	"el_cid": {
		"label": "El Cid",
		"straight_len": 110.0,
		"inner_radius": 34.0,
		"theme_id": "storm_coast",
	},
	## Saratoga-inspired — America's oldest track, an upstate NY spa town
	## famously nicknamed "The Spa" for its mineral springs. Named for that
	## nickname rather than the real track's own name (the real name is used
	## verbatim nowhere in this file, unlike the previous "Saratoga" id this
	## venue replaces). A wide, sweeping oval with generously wide turns,
	## paired with the old-school amber theme for a classic, traditional feel.
	"silverspring_downs": {
		"label": "Silverspring Downs",
		"straight_len": 155.0,
		"inner_radius": 30.0,
		"theme_id": "classic_amber",
	},
	## Churchill Downs-inspired — a tighter, more compact oval than any of the
	## other four, paired with the emerald "Bluegrass Night" theme.
	"bluegrass_downs": {
		"label": "Bluegrass Downs",
		"straight_len": 130.0,
		"inner_radius": 24.0,
		"theme_id": "bluegrass_night",
	},
	## Belmont Park-inspired — the biggest oval of the bunch, long sweeping
	## straights (Belmont is famous for being the largest dirt track around).
	## "Kingsgate" stands in for the real name entirely (this venue previously
	## used "Belmont" verbatim, which this replaces).
	"kingsgate_crown": {
		"label": "Kingsgate Crown",
		"straight_len": 190.0,
		"inner_radius": 22.0,
		"theme_id": "neon_downs",
	},
	## Gulfstream Park-inspired — a Florida coast venue alongside Barton Bay,
	## deliberately different proportions so the two don't feel
	## interchangeable despite sharing that region and theme. Named for the
	## actual Gulf Stream ocean current instead of the real park's own name
	## (previously used "Gulfstream" verbatim, which this replaces).
	"tradewind_shores": {
		"label": "Tradewind Shores",
		"straight_len": 145.0,
		"inner_radius": 28.0,
		"theme_id": "desert_dusk",
	},
	## Santa Anita-inspired — Southern California like El Cid, but a rounder,
	## more compact shape and the cooler storm-coast mood instead. "Sierra
	## Alta" (Spanish for "high sierra") stands in for the San Gabriel
	## Mountains backdrop instead of using the real park's own name (previously
	## "Santa Anita" verbatim, which this replaces).
	"sierra_alta_peak": {
		"label": "Sierra Alta Peak",
		"straight_len": 120.0,
		"inner_radius": 32.0,
		"theme_id": "storm_coast",
	},
	## Keeneland-inspired — another Kentucky venue alongside Bluegrass Downs,
	## paired with the old-school amber theme instead for its own identity.
	## "Limestone" stands in for the real name, referencing the actual
	## limestone-rich soil the Bluegrass region's horse farms are known for
	## (previously "Keeneland" verbatim, which this replaces).
	"limestone_ridge": {
		"label": "Limestone Ridge",
		"straight_len": 135.0,
		"inner_radius": 27.0,
		"theme_id": "classic_amber",
	},
	## Woodbine-inspired — the track this whole broadcast HUD's look was
	## originally modeled on (a real Woodbine harness-racing screenshot).
	## "Timberline" stands in for the real name (previously "Woodbine"
	## verbatim, which this replaces) while keeping the same wooded-north
	## flavor.
	"timberline_north": {
		"label": "Timberline North",
		"straight_len": 160.0,
		"inner_radius": 25.0,
		"theme_id": "bluegrass_night",
	},
	## Pimlico-inspired — Baltimore's harbor city, home of the Preakness
	## (Triple Crown's 2nd leg). A mid-sized oval with the widest turns of
	## any venue, paired with the warm Florida-evening theme reused for a
	## different regional mood.
	"harborcrest_downs": {
		"label": "Harborcrest Downs",
		"straight_len": 150.0,
		"inner_radius": 36.0,
		"theme_id": "desert_dusk",
	},
	## Oaklawn Park-inspired — the real park's own name ("Oak" + "lawn") is
	## swapped word-for-word for near-synonyms of the same category (oak ->
	## cedar, lawn -> meadow) rather than reused. Compact, tight-turned oval,
	## paired with the classic amber theme for a Southern small-town feel.
	"cedar_meadow": {
		"label": "Cedar Meadow",
		"straight_len": 125.0,
		"inner_radius": 23.0,
		"theme_id": "classic_amber",
	},
	## Monmouth Park-inspired — Jersey Shore boardwalk track, "by the sea."
	## Rounder and more compact than Tradewind Shores' Gulf-coast stretch, for
	## a distinct Atlantic-coast feel, paired with the cool moonlit theme.
	"cresthaven_shore": {
		"label": "Cresthaven Shore",
		"straight_len": 115.0,
		"inner_radius": 33.0,
		"theme_id": "storm_coast",
	},
	## Arlington Park-inspired — flat Midwest prairie country, home of the
	## Arlington Million. The widest, most stretched-out oval of any venue,
	## paired with the emerald night theme for its own identity apart from
	## the other Bluegrass-region tracks.
	"prairiefield_reach": {
		"label": "Prairiefield Reach",
		"straight_len": 200.0,
		"inner_radius": 21.0,
		"theme_id": "bluegrass_night",
	},
}

static func get_venue(venue_id: String) -> Dictionary:
	return VENUES.get(venue_id, VENUES[DEFAULT_VENUE_ID])

static func label_for(venue_id: String) -> String:
	return String(get_venue(venue_id).get("label", venue_id))
