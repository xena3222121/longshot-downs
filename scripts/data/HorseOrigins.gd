class_name HorseOrigins
extends RefCounted

## Career-mode horse marketplace tiers — AJ wanted buyable horses with real
## breeding/origin flavor ("some gray horse, some Spanish horse, a horse
## from the UK, a horse straight from Kentucky sired with good genetics"),
## not a full breeding simulation. Each origin is a price + a genetics-
## driven attribute ceiling (potential_cap, out of CareerStable.MAX_LEVEL) —
## a cheap horse can still be trained, it just plateaus lower, so the
## marketplace choice is a real long-term-vs-cheap-now tradeoff, not just a
## bigger number. coat_color overrides HorseMarker3D's usual random natural
## coat roll for origins with a genuinely breed-distinctive look (a gray is
## instantly recognizable on a real track); origins without one keep a
## normal random natural coat.

const ORIGINS: Array[Dictionary] = [
	{
		"id": "starter", "label": "Starter Prospect",
		"description": "Your very first horse — picked, not bought. Solid bones, real upside.",
		"price": 0, "potential_cap": 3,
	},
	{
		"id": "local_bred", "label": "Local-Bred",
		"description": "A solid claiming-bred prospect from a nearby farm. Nothing fancy, but honest.",
		"price": 25000, "potential_cap": 2,
	},
	{
		"id": "kentucky_bred", "label": "Kentucky-Bred",
		"description": "Bluegrass pedigree — a real step up in raw talent over a local-bred horse.",
		"price": 60000, "potential_cap": 3,
	},
	{
		"id": "andalusian_gray", "label": "Andalusian Gray",
		"description": "A striking Spanish gray with real natural trainability.",
		"price": 80000, "potential_cap": 3,
		"coat_color": Color(0.74, 0.75, 0.78),
	},
	{
		"id": "irish_import", "label": "Irish Import",
		"description": "European bloodstock, prized for stamina over the long haul.",
		"price": 95000, "potential_cap": 4,
	},
	{
		"id": "british_classic", "label": "British Classic Line",
		"description": "Old-money English pedigree with a long stakes-winning family tree.",
		"price": 130000, "potential_cap": 4,
	},
	{
		"id": "blue_blood", "label": "Blue-Blood Sire Line",
		"description": "Elite genetics, straight from a champion sire. As good as they come.",
		"price": 250000, "potential_cap": 5,
	},
]

static func get_origin(id: String) -> Dictionary:
	for origin in ORIGINS:
		if origin.id == id:
			return origin
	return ORIGINS[0]
