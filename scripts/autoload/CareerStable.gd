extends Node

## Phase 1 of the Career/"owner mode" system AJ asked for: buy a horse from
## a small marketplace of origin/pedigree tiers (see HorseOrigins.gd), train
## it daily (hire a trainer for automatic passive gains, or self-train by
## buying a one-off drill for a bigger but rng'd gain), and see those gains
## actually change how the horse runs (see RaceSim.gd's attribute_overrides
## param). Deliberately curtailed to a real, complete loop rather than the
## full Madden-Owner-Mode-scale vision AJ described (breeding, a big rotating
## marketplace, multi-horse empire management) — every list here (origins,
## trainer tiers) is meant to grow later without a data-format change, not a
## final scope.
##
## Its own save file / autoload, separate from Career.gd (wild-roster
## win/loss stats + achievements) and Bankroll.gd (spendable balance) — this
## only tracks WHICH horses you own and how trained they are; actual money
## still flows through the one shared Bankroll.

signal horse_purchased(stable_horse_id: int)
signal horse_trained(stable_horse_id: int, attribute_id: String, points_gained: int)
signal race_purse_paid(stable_horse_id: int, amount: int)

const SAVE_FILENAME: String = "career_stable.save"
var SAVE_PATH: String

const ATTRIBUTE_IDS: Array[String] = ["acceleration", "stamina", "closing_kick"]
const ATTRIBUTE_LABELS: Dictionary = {
	"acceleration": "Acceleration",
	"stamina": "Stamina",
	"closing_kick": "Closing Kick",
}
## A horse needs roughly 3 level-ups spread across these 3 stats (not 3 in
## one stat) before it's genuinely competitive against a fresh-rolled wild
## field — see RaceSim's per-level bonus consts for why: each individual
## level is a real but modest edge, not a power spike.
const POINTS_PER_LEVEL: int = 20
const MAX_LEVEL: int = 5

## "elite" tier's name is a wink at a real, very famous (and very
## controversial) trainer — AJ asked for something "similar-ish" to play on,
## deliberately NOT his actual name for obvious legal reasons. Close enough
## to land the joke, different enough to be clearly its own fictional
## character, same as this game already does for its wild-roster horse names.
const TRAINER_TIERS: Array[Dictionary] = [
	{"id": "none", "label": "No Trainer (self-train only)", "daily_cost": 0, "gain": 0},
	{"id": "local", "label": "Local Trainer", "daily_cost": 100, "gain": 4},
	{"id": "regional", "label": "Regional Trainer", "daily_cost": 300, "gain": 7},
	{"id": "elite", "label": "Bob Baffleton (Elite)", "daily_cost": 800, "gain": 11},
]
## Self-training is the cheaper-per-point path IF you show up every day and
## buy the drill yourself; hiring a trainer costs more per point but needs
## zero attention once set — a real convenience-vs-cost choice, not a
## strictly-better option either way.
const SELF_TRAIN_ITEM_COST: int = 400
const SELF_TRAIN_GAIN_MIN: int = 8
const SELF_TRAIN_GAIN_MAX: int = 16

## Owned-horse ids start well past HorseRoster's 60 wild-roster ids (0-59)
## so a bought horse never collides with a wild horse's coat-color lookup
## (HorseMarker3D keys natural coat off horse_id) or Career.gd's own
## horse_stats dict (also keyed by id).
const ID_START: int = 1000

## Pokemon-style "pick your starter" opening — AJ: three horses, each visibly
## leaning into one attribute, pick one and go, no purchase/price gate on
## the very first horse (the marketplace/origin-price system above is still
## real, it's just how you buy your SECOND+ horse once you've actually
## earned money racing). STARTER_SPECIALTY_POINTS (40 = level 2 of up to the
## "starter" origin's potential_cap of 3, see HorseOrigins.ORIGINS) gives an
## immediately legible identity to each choice without pre-deciding the
## whole game for the player — there's still real training ahead.
const STARTER_SPECIALTY_POINTS: int = 40
const STARTER_HORSES: Array[Dictionary] = [
	{"horse_name": "Steady Gallop", "specialty": "stamina", "flavor": "Built to go the distance — never fades late."},
	{"horse_name": "Quick Break", "specialty": "acceleration", "flavor": "Explosive out of the gate — sets the pace early."},
	{"horse_name": "Late Charge", "specialty": "closing_kick", "flavor": "Saves it all for the stretch — a real closer."},
]
var _has_picked_starter: bool = false

## Per-horse race-class ladder, gated on THIS horse's own career_races (not
## Career.gd's RACE_CLASSES, which gates a global purse-bonus MULTIPLIER off
## total races run across every wild-field bet regardless of whose horse ran
## — a career-mode horse making its stable debut shouldn't already be racing
## for allowance money just because the player has bet on 40 unrelated wild
## races). Same shape as Career.RACE_CLASSES on purpose (min_races gates,
## cosmetic name, escalating reward) but a flat purse per rung rather than a
## bonus multiplier, since a career race has no separate "base purse" to
## apply a bonus on top of. Deliberately doesn't touch RaceSim/OddsTable — a
## Grade 1 field is still drawn and paced exactly like a Maiden field, same
## as Career.gd's own class ladder leaves race math alone.
const STABLE_RACE_CLASSES: Array[Dictionary] = [
	{"id": "maiden", "name": "Maiden Special Weight", "min_races": 0, "purse": 20000},
	{"id": "claiming", "name": "Claiming", "min_races": 4, "purse": 32000},
	{"id": "allowance", "name": "Allowance", "min_races": 10, "purse": 50000},
	{"id": "stakes", "name": "Stakes", "min_races": 20, "purse": 85000},
	{"id": "grade1", "name": "Grade 1 Stakes", "min_races": 35, "purse": 150000},
]

func get_horse_class(stable_horse_id: int) -> Dictionary:
	var races: int = int(get_owned_horse(stable_horse_id).get("career_races", 0))
	var current: Dictionary = STABLE_RACE_CLASSES[0]
	for race_class in STABLE_RACE_CLASSES:
		if races >= int(race_class.min_races):
			current = race_class
	return current

## No free-text input anywhere in this game (see docs/STEAM_DECK_REVIEW.md —
## zero LineEdit/TextEdit usage is a real, already-banked Deck-compatibility
## point) — a purchased horse's name is picked from this pool instead of
## typed, same "pick, don't type" shape as the starter horses above.
const PURCHASABLE_NAME_POOL: Array[String] = [
	"Harbor Verdict", "Iron Ledger", "Wildfire Reach", "Stonebrook Miracle",
	"Cobalt Promise", "Marlow's Gambit", "Rustwood Charger", "Evening Accord",
	"Granite Wager", "Silver Covenant", "Ashgrove Legacy", "Windmill Fortune",
]

## String(id) -> Dictionary: horse_name, jockey_name, origin_id,
## attributes ({attribute_id: {"points": int}}), trainer_tier_id,
## training_focus, last_trained_date ("" if never), career_wins,
## career_races, purchase_price. Level is derived from points (see
## get_attribute_level), never stored directly, so POINTS_PER_LEVEL can be
## retuned later without a save migration.
var owned_horses: Dictionary = {}
var _next_id: int = ID_START

## Dev tools that drive this through fake trials set this false first, same
## pattern as Bankroll.autosave_enabled — so a headless test run never
## overwrites the player's real save file on disk.
var autosave_enabled: bool = true

func _ready() -> void:
	SAVE_PATH = SavePaths.resolve(SAVE_FILENAME)
	_load()

func has_picked_starter() -> bool:
	return _has_picked_starter

## Free, one-time only (see has_picked_starter) — the marketplace's
## purchase_horse below is for every acquisition after this one.
func pick_starter_horse(starter_index: int) -> int:
	if _has_picked_starter or starter_index < 0 or starter_index >= STARTER_HORSES.size():
		return -1
	var starter: Dictionary = STARTER_HORSES[starter_index]
	var attributes: Dictionary = {}
	for attr in ATTRIBUTE_IDS:
		attributes[attr] = {"points": STARTER_SPECIALTY_POINTS if attr == starter.specialty else 0}
	var id: int = _next_id
	_next_id += 1
	owned_horses[str(id)] = {
		"horse_name": starter.horse_name,
		"jockey_name": HorseRoster.JOCKEY_NAMES[randi() % HorseRoster.JOCKEY_NAMES.size()],
		"origin_id": "starter",
		"attributes": attributes,
		"trainer_tier_id": "none",
		"training_focus": starter.specialty,
		"last_trained_date": "",
		"career_wins": 0,
		"career_races": 0,
		"purchase_price": 0,
	}
	_has_picked_starter = true
	_save()
	horse_purchased.emit(id)
	return id

func purchase_horse(origin_id: String, horse_name: String) -> int:
	var origin: Dictionary = HorseOrigins.get_origin(origin_id)
	var price: int = int(origin.price)
	if not Bankroll.can_afford(price):
		return -1
	Bankroll.place_bet(price) # reuses the existing balance-deduction path (place_bet just subtracts and persists; the "bet" framing doesn't leak anywhere Career-mode-visible)
	var id: int = _next_id
	_next_id += 1
	var attributes: Dictionary = {}
	for attr in ATTRIBUTE_IDS:
		attributes[attr] = {"points": 0}
	owned_horses[str(id)] = {
		"horse_name": horse_name,
		"jockey_name": HorseRoster.JOCKEY_NAMES[randi() % HorseRoster.JOCKEY_NAMES.size()],
		"origin_id": origin.id,
		"attributes": attributes,
		"trainer_tier_id": "none",
		"training_focus": ATTRIBUTE_IDS[0],
		"last_trained_date": "",
		"career_wins": 0,
		"career_races": 0,
		"purchase_price": price,
	}
	_save()
	horse_purchased.emit(id)
	return id

func get_owned_horse_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in owned_horses.keys():
		ids.append(int(key))
	return ids

func get_owned_horse(stable_horse_id: int) -> Dictionary:
	return owned_horses.get(str(stable_horse_id), {})

func get_attribute_points(stable_horse_id: int, attribute_id: String) -> int:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	return int(horse.get("attributes", {}).get(attribute_id, {}).get("points", 0))

func get_attribute_level(stable_horse_id: int, attribute_id: String) -> int:
	var cap: int = get_potential_cap(stable_horse_id)
	return min(get_attribute_points(stable_horse_id, attribute_id) / POINTS_PER_LEVEL, cap)

func get_potential_cap(stable_horse_id: int) -> int:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	return int(HorseOrigins.get_origin(horse.get("origin_id", "")).get("potential_cap", MAX_LEVEL))

func _today() -> String:
	return Time.get_date_string_from_system()

func can_train_today(stable_horse_id: int) -> bool:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	return not horse.is_empty() and String(horse.get("last_trained_date", "")) != _today()

## Player-directed self-training — costs SELF_TRAIN_ITEM_COST regardless of
## outcome (a real drill session bought for the horse), rng gain, available
## whether or not a trainer is hired (skipping the trainer's automatic
## session that day in favor of self-training instead is a legitimate,
## if slightly wasteful, choice — see process_daily_trainer_upkeep).
func self_train(stable_horse_id: int, attribute_id: String) -> bool:
	if not can_train_today(stable_horse_id) or not ATTRIBUTE_IDS.has(attribute_id):
		return false
	if not Bankroll.can_afford(SELF_TRAIN_ITEM_COST):
		return false
	Bankroll.place_bet(SELF_TRAIN_ITEM_COST)
	_apply_training(stable_horse_id, attribute_id, randi_range(SELF_TRAIN_GAIN_MIN, SELF_TRAIN_GAIN_MAX))
	return true

func hire_trainer(stable_horse_id: int, trainer_tier_id: String) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty():
		return
	horse.trainer_tier_id = trainer_tier_id
	owned_horses[str(stable_horse_id)] = horse
	_save()

func set_training_focus(stable_horse_id: int, attribute_id: String) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty() or not ATTRIBUTE_IDS.has(attribute_id):
		return
	horse.training_focus = attribute_id
	owned_horses[str(stable_horse_id)] = horse
	_save()

## Passive daily trainer upkeep — call once per session (TrackLobby's own
## _ready is the natural hook, matching how Bankroll.ensure_minimum is
## already called at the start of every session) so a hired trainer trains
## automatically without the player needing to remember to log in and do it
## manually. Silently skips (does NOT queue up/backdate) a horse whose
## trainer couldn't be paid that day — matches a real trainer just not
## showing up if the bill isn't covered, no debt mechanic.
func process_daily_trainer_upkeep() -> void:
	for key in owned_horses.keys():
		var id: int = int(key)
		var horse: Dictionary = owned_horses[key]
		var tier_id: String = String(horse.get("trainer_tier_id", "none"))
		if tier_id == "none" or not can_train_today(id):
			continue
		var tier: Dictionary = get_trainer_tier(tier_id)
		var cost: int = int(tier.get("daily_cost", 0))
		if not Bankroll.can_afford(cost) and cost > 0:
			continue
		if cost > 0:
			Bankroll.place_bet(cost)
		_apply_training(id, String(horse.get("training_focus", ATTRIBUTE_IDS[0])), int(tier.get("gain", 0)))

func _apply_training(stable_horse_id: int, attribute_id: String, gain: int) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty():
		return
	var attributes: Dictionary = horse.get("attributes", {})
	var attr: Dictionary = attributes.get(attribute_id, {"points": 0})
	var cap_points: int = get_potential_cap(stable_horse_id) * POINTS_PER_LEVEL
	attr.points = min(int(attr.get("points", 0)) + gain, cap_points)
	attributes[attribute_id] = attr
	horse.attributes = attributes
	horse.last_trained_date = _today()
	owned_horses[str(stable_horse_id)] = horse
	_save()
	horse_trained.emit(stable_horse_id, attribute_id, gain)

func get_trainer_tier(id: String) -> Dictionary:
	for tier in TRAINER_TIERS:
		if tier.id == id:
			return tier
	return TRAINER_TIERS[0]

## Builds the attribute_overrides dict RaceSim.simulate expects, for a
## Career race where `field_index` in that race's field array is this owned
## horse (see RaceTrack3D/RaceSim.gd — Phase 2 wires an actual Career race
## flow that calls this).
func build_attribute_overrides(stable_horse_id: int, field_index: int) -> Dictionary:
	return {
		field_index: {
			"acceleration_level": get_attribute_level(stable_horse_id, "acceleration"),
			"stamina_level": get_attribute_level(stable_horse_id, "stamina"),
			"closing_kick_level": get_attribute_level(stable_horse_id, "closing_kick"),
		},
	}

## Purse cut paid to the owner on top of Bankroll's normal betting payouts —
## called by whatever drives a Career race's finish (Phase 2). placement is
## 1-based finish position; anything outside win/place/show pays nothing.
const PURSE_WIN_SHARE: float = 1.0
const PURSE_PLACE_SHARE: float = 0.4
const PURSE_SHOW_SHARE: float = 0.2

func pay_purse(stable_horse_id: int, placement: int, class_purse: int) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty():
		return
	horse.career_races = int(horse.get("career_races", 0)) + 1
	var share: float = 0.0
	if placement == 1:
		share = PURSE_WIN_SHARE
		horse.career_wins = int(horse.get("career_wins", 0)) + 1
	elif placement == 2:
		share = PURSE_PLACE_SHARE
	elif placement == 3:
		share = PURSE_SHOW_SHARE
	owned_horses[str(stable_horse_id)] = horse
	_save()
	var amount: int = int(class_purse * share)
	if amount > 0:
		Bankroll.pay(amount)
		race_purse_paid.emit(stable_horse_id, amount)

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	owned_horses = data.get("owned_horses", {})
	_next_id = int(data.get("next_id", ID_START))
	_has_picked_starter = bool(data.get("has_picked_starter", false))

func _save() -> void:
	if not autosave_enabled:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"owned_horses": owned_horses,
		"next_id": _next_id,
		"has_picked_starter": _has_picked_starter,
	}))
