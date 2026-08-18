class_name HorseRoster
extends RefCounted

const NAMES: Array[String] = [
	"Midnight Runner", "Copper Comet", "Velvet Thunder", "Iron Whisper",
	"Solar Flare", "Rusty Nickel", "Lucky Strike", "Silver Bullet",
	"Windy Ridge", "Blazing Saddles", "Northern Fable", "Quiet Storm",
	"Prairie Ghost", "Amber Rebellion", "Cinder Cloak", "Diesel Dream",
	"Echo Canyon", "Frostbite Folly", "Golden Ratio", "Honest Gamble",
	"Ironclad Alibi", "Jubilee Jazz", "Kettle Corn Kid", "Loose Change",
	"Midwest Mirage", "Neon Nightfall", "Overtime Outlaw", "Paper Tiger",
	"Quarter Moon", "Reckless Rumor", "Salty Comeback", "Thunder Tax",
	"Umber Uproar", "Velcro Villain", "Wildcard Willow", "Xtra Mile",
	"Yonder Bound", "Zero Hour", "Backfire Betty", "Crooked Odds",
	"Dusty Verdict", "Emberline", "Fickle Fortune", "Gravel Road Glory",
	"Hollow Point Hank", "Ill-Advised", "Jackrabbit Jubilee", "Kite String",
	"Long Shot Larry", "Muddy Waters", "No Refunds", "Overdraft",
	"Pit Stop Preacher", "Quick Excuse", "Rowdy Receipt", "Static Cling",
	"Tumbleweed Tony", "Undertow", "Vapor Trail", "Wager's Regret",
]

## Full persistent roster of 60 horses (name/id only). Silk colors aren't
## assigned here — see assign_race_colors below — spreading them evenly
## across all 60 names couldn't guarantee any given race's random 8-horse
## draw ends up well-separated (two adjacent-hue horses, only a few degrees
## apart, could easily land in the same field by chance).
static func generate() -> Array[Horse]:
	var horses: Array[Horse] = []
	for i in range(NAMES.size()):
		var horse := Horse.new()
		horse.id = i
		horse.horse_name = NAMES[i]
		horses.append(horse)
	return horses

## Spreads silk colors evenly around the hue wheel across exactly this
## race's field (not the full roster), so every horse actually running
## today is guaranteed visually distinct regardless of which random subset
## got drawn. Call once right after slicing a roster down to a race field.
static func assign_race_colors(field: Array[Horse]) -> void:
	for i in range(field.size()):
		var hue := float(i) / field.size()
		field[i].silk_primary = Color.from_hsv(hue, 0.75, 0.9)
		field[i].silk_secondary = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.6, 0.95)
