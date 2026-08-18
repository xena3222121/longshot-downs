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
	"longshot_downs", "barton_bay", "el_cid", "saratoga", "bluegrass_downs",
	"belmont_crown", "gulfstream_shores", "santa_anita_peak", "keeneland_ridge", "woodbine_north",
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
	## Saratoga-inspired — a wide, sweeping oval with generously wide turns,
	## paired with the old-school amber theme for a classic, traditional feel.
	"saratoga": {
		"label": "Saratoga",
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
	## Belmont Park-inspired — the biggest oval of the ten, long sweeping
	## straights (Belmont is famous for being the largest dirt track around).
	"belmont_crown": {
		"label": "Belmont Crown",
		"straight_len": 190.0,
		"inner_radius": 22.0,
		"theme_id": "neon_downs",
	},
	## Gulfstream Park-inspired — another Florida coast venue alongside Barton
	## Bay, deliberately different proportions so the two don't feel
	## interchangeable despite sharing that region and theme.
	"gulfstream_shores": {
		"label": "Gulfstream Shores",
		"straight_len": 145.0,
		"inner_radius": 28.0,
		"theme_id": "desert_dusk",
	},
	## Santa Anita-inspired — Southern California like El Cid, but a rounder,
	## more compact shape and the cooler storm-coast mood instead.
	"santa_anita_peak": {
		"label": "Santa Anita Peak",
		"straight_len": 120.0,
		"inner_radius": 32.0,
		"theme_id": "storm_coast",
	},
	## Keeneland-inspired — another Kentucky venue alongside Bluegrass Downs,
	## paired with the old-school amber theme instead for its own identity.
	"keeneland_ridge": {
		"label": "Keeneland Ridge",
		"straight_len": 135.0,
		"inner_radius": 27.0,
		"theme_id": "classic_amber",
	},
	## Woodbine-inspired — the track this whole broadcast HUD's look was
	## originally modeled on (a real Woodbine harness-racing screenshot).
	"woodbine_north": {
		"label": "Woodbine North",
		"straight_len": 160.0,
		"inner_radius": 25.0,
		"theme_id": "bluegrass_night",
	},
}

static func get_venue(venue_id: String) -> Dictionary:
	return VENUES.get(venue_id, VENUES[DEFAULT_VENUE_ID])

static func label_for(venue_id: String) -> String:
	return String(get_venue(venue_id).get("label", venue_id))
