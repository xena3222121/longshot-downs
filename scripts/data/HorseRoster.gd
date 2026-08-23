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
	"Pit Stop Preacher", "Quick Excuse", "Rowdy Receipt", "Devin Is A Tool",
	"Tumbleweed Tony", "Undertow", "Vapor Trail", "Devin's Flat Footed",
]

## Ordinary human names, deliberately plain next to NAMES' pun-heavy horse
## names — real racing broadcasts always pair a jockey name with the horse,
## and the contrast reads better than jokey names on both sides. Fixed 1:1
## with NAMES by index (this horse's regular rider), not randomized per race
## — matches Horse.gd's own "persistent identity" framing (see its header
## comment) rather than introducing a second layer of per-race randomness.
const JOCKEY_NAMES: Array[String] = [
	"J. Alvarez", "M. Delgado", "R. Whitfield", "T. Okafor", "S. Marchetti",
	"L. Beaumont", "K. Nakamura", "D. Fairweather", "P. Sokolov", "A. Kowalski",
	"C. Vasquez", "E. Lindqvist", "N. Abernathy", "G. Petrov", "H. Duarte",
	"W. Castellano", "B. Odom", "F. Nakashima", "V. Torrance", "Q. Reyes",
	"O. Brennan", "I. Marsh", "U. Kimura", "Y. Solano", "Z. Whitcombe",
	"J. Bellamy", "M. Ferraro", "R. Achebe", "T. Lindgren", "S. Okonkwo",
	"L. Vance", "K. Delacroix", "D. Mbeki", "P. Harrow", "A. Ferreira",
	"C. Nakagawa", "E. Whitlock", "N. Barros", "G. Sandoval", "H. Kessler",
	"W. Adeyemi", "B. Larkspur", "F. Moreno", "V. Sundberg", "Q. Ashworth",
	"O. Pemberton", "I. Yamada", "U. Castellanos", "Y. Marlowe", "Z. Odell",
	"J. Kowalczyk", "M. Fontaine", "R. Osei", "T. Bramwell", "S. Iturbide",
	"L. Ngata", "K. Ashford", "D. Villanueva", "P. Lindholm", "A. Okafor",
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
		horse.jockey_name = JOCKEY_NAMES[i]
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
