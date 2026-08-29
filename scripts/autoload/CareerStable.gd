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
## Its own save file(s) / autoload, separate from Career.gd (wild-roster
## win/loss stats + achievements) and Bankroll.gd (spendable balance) — this
## only tracks WHICH horses you own and how trained they are; actual money
## still flows through the one shared Bankroll.

signal horse_purchased(stable_horse_id: int)
signal horse_trained(stable_horse_id: int, attribute_id: String, points_gained: int)
signal race_purse_paid(stable_horse_id: int, amount: int)

## Multiple independent career slots — AJ: every starter pick/stable he'd
## ever tried was piling up in ONE shared save, reading as "all just
## commingled in one cluster" with no way to separate a fresh attempt from an
## old one. Each slot is its own save file with its own owned_horses/
## next_id/has_picked_starter; CareerHub gates on current_slot == -1 to show
## a slot-select screen before anything else. Slot files use the OLD
## unslotted SAVE_FILENAME's naming scheme with a slot number suffix, not the
## original bare filename — the original single career_stable.save is left
## untouched on disk (not auto-migrated into slot 0): AJ's complaint was that
## everything was already tangled together, so silently moving that same
## tangle into "slot 1" would just recreate the exact problem this exists to
## fix. That old file is simply orphaned/unused now, not deleted.
const SLOT_COUNT: int = 4
var current_slot: int = -1

func slot_save_path(slot: int) -> String:
	return SavePaths.resolve("career_stable_slot%d.save" % slot)

## Lightweight peek at a slot's summary (horse count / lead horse / total
## wins) WITHOUT touching the live owned_horses/current_slot state — used by
## the slot-picker screen to show what's in each slot before committing to
## loading it.
func peek_slot_summary(slot: int) -> Dictionary:
	var path: String = slot_save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var owned: Dictionary = data.get("owned_horses", {})
	var lead_name: String = ""
	var total_wins: int = 0
	for key in owned.keys():
		var h: Dictionary = owned[key]
		total_wins += int(h.get("career_wins", 0))
		if lead_name == "":
			lead_name = String(h.get("horse_name", ""))
	return {"horse_count": owned.size(), "lead_name": lead_name, "total_wins": total_wins}

func load_slot(slot: int) -> void:
	current_slot = slot
	_load()

## Starts a brand-new career in this slot — resets in-memory state; nothing
## is written to disk until the first real mutation (starter pick, etc.),
## same as a fresh single-save game always worked before slots existed.
func start_new_career(slot: int) -> void:
	current_slot = slot
	owned_horses = {}
	_next_id = ID_START
	_has_picked_starter = false
	milestones_unlocked = {}

## Permanently deletes a slot's save file — destructive, only ever called
## from a confirmation dialog (see CareerHub._build_slot_picker).
func delete_slot(slot: int) -> void:
	var path: String = slot_save_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## Kept as 3 broad categories (these are the only 3 RaceSim actually reads —
## see build_attribute_overrides) but each is now trained through a set of
## more specific SUB_ATTRIBUTE_IDS instead of directly — AJ wanted "more than
## three stat lines... maybe twenty five" instead of one flat number per
## category. A sub-attribute's points count toward its category's total
## (get_category_points sums them) using the exact same POINTS_PER_LEVEL/cap
## math as before, so RaceSim's own tuned per-level bonuses are completely
## unaffected — this only changes how a category's points get EARNED (spread
## across several specific drills instead of one), never what they're worth.
const CATEGORY_IDS: Array[String] = ["acceleration", "stamina", "closing_kick"]
const CATEGORY_LABELS: Dictionary = {
	"acceleration": "Acceleration",
	"stamina": "Stamina",
	"closing_kick": "Closing Kick",
}
## Which sub-attribute a starter horse's specialty bonus (STARTER_SPECIALTY_
## POINTS) lands on, and what a purchased horse's training_focus defaults
## toward when its origin doesn't specify one — one representative "primary"
## drill per category so a starting horse still opens at a legible Level 2 in
## its specialty category (40 points in ONE sub-attribute = the category's
## own sum reaches 40 = level 2, identical to the old single-attribute math).
const CATEGORY_PRIMARY_SUB: Dictionary = {
	"acceleration": "early_speed",
	"stamina": "endurance",
	"closing_kick": "late_speed",
}

const SUB_ATTRIBUTE_IDS: Array[String] = [
	# Acceleration (8)
	"gate_break", "early_speed", "burst_power", "reflexes",
	"track_grip", "sprint_mechanics", "warmup_focus", "pace_sense",
	# Stamina (9)
	"endurance", "lung_capacity", "heart_recovery", "distance_aptitude",
	"mental_toughness", "conditioning", "fitness_base", "pacing_discipline", "fatigue_resistance",
	# Closing Kick (8)
	"late_speed", "determination", "competitive_drive", "traffic_sense",
	"whip_response", "final_furlong_push", "rail_awareness", "closing_instinct",
]
const SUB_ATTRIBUTE_LABELS: Dictionary = {
	"gate_break": "Gate Break", "early_speed": "Early Speed", "burst_power": "Burst Power", "reflexes": "Reflexes",
	"track_grip": "Track Grip", "sprint_mechanics": "Sprint Mechanics", "warmup_focus": "Warm-Up Focus", "pace_sense": "Pace Sense",
	"endurance": "Endurance", "lung_capacity": "Lung Capacity", "heart_recovery": "Heart Recovery", "distance_aptitude": "Distance Aptitude",
	"mental_toughness": "Mental Toughness", "conditioning": "Conditioning", "fitness_base": "Fitness Base",
	"pacing_discipline": "Pacing Discipline", "fatigue_resistance": "Fatigue Resistance",
	"late_speed": "Late Speed", "determination": "Determination", "competitive_drive": "Competitive Drive", "traffic_sense": "Traffic Sense",
	"whip_response": "Whip Response", "final_furlong_push": "Final Furlong Push", "rail_awareness": "Rail Awareness", "closing_instinct": "Closing Instinct",
}
const SUB_ATTRIBUTE_CATEGORY: Dictionary = {
	"gate_break": "acceleration", "early_speed": "acceleration", "burst_power": "acceleration", "reflexes": "acceleration",
	"track_grip": "acceleration", "sprint_mechanics": "acceleration", "warmup_focus": "acceleration", "pace_sense": "acceleration",
	"endurance": "stamina", "lung_capacity": "stamina", "heart_recovery": "stamina", "distance_aptitude": "stamina",
	"mental_toughness": "stamina", "conditioning": "stamina", "fitness_base": "stamina",
	"pacing_discipline": "stamina", "fatigue_resistance": "stamina",
	"late_speed": "closing_kick", "determination": "closing_kick", "competitive_drive": "closing_kick", "traffic_sense": "closing_kick",
	"whip_response": "closing_kick", "final_furlong_push": "closing_kick", "rail_awareness": "closing_kick", "closing_instinct": "closing_kick",
}

## A horse needs roughly 3 level-ups spread across the 3 CATEGORIES (not 3 in
## one) before it's genuinely competitive against a fresh-rolled wild field —
## see RaceSim's per-level bonus consts for why: each individual level is a
## real but modest edge, not a power spike.
const POINTS_PER_LEVEL: int = 20
const MAX_LEVEL: int = 5

## "elite" tier's name is a wink at a real, very famous (and very
## controversial) trainer — AJ asked for something "similar-ish" to play on,
## deliberately NOT his actual name for obvious legal reasons. Close enough
## to land the joke, different enough to be clearly its own fictional
## character, same as this game already does for its wild-roster horse names.
## daily_cost ladder: AJ wanted a flatter, cheaper spread (100/200/300) than
## the original (100/300/800) — noted the earlier name-only change "didn't
## look like it changed" anything price-wise, which it hadn't; this is the
## actual rate change.
const TRAINER_TIERS: Array[Dictionary] = [
	{"id": "none", "label": "No Trainer (self-train only)", "daily_cost": 0, "gain": 0},
	{"id": "local", "label": "Local Trainer", "daily_cost": 100, "gain": 4},
	{"id": "regional", "label": "Regional Trainer", "daily_cost": 200, "gain": 7},
	{"id": "elite", "label": "Bob Baffleton (Elite)", "daily_cost": 300, "gain": 11},
]
## Self-training is the cheaper-per-point path IF you show up every day and
## buy the drill yourself; hiring a trainer costs more per point but needs
## zero attention once set — a real convenience-vs-cost choice, not a
## strictly-better option either way.
const SELF_TRAIN_ITEM_COST: int = 400
const SELF_TRAIN_GAIN_MIN: int = 8
const SELF_TRAIN_GAIN_MAX: int = 16
## AJ: "you can train... maybe one or two per day" — was a flat one-action-
## per-day gate; now a horse can take up to this many training ACTIONS
## (self-train and/or the hired trainer's own automatic session, whichever
## combination happens first) in the same day, matching a 25-sub-attribute
## spread taking meaningfully longer to flesh out than the old 3-attribute
## version did.
const DAILY_TRAINING_ACTIONS: int = 2

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
## whole game for the player — there's still real training ahead. specialty
## is a CATEGORY id (see CATEGORY_PRIMARY_SUB for which specific sub-
## attribute actually receives the bonus points).
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
## attributes ({sub_attribute_id: {"points": int}}, one entry per
## SUB_ATTRIBUTE_IDS), trainer_tier_id, training_focus (a sub-attribute id),
## last_trained_date ("" if never), trainings_today (int, resets whenever
## last_trained_date rolls to a new day), career_wins, career_races,
## purchase_price. Category levels are derived from summed sub-attribute
## points (see get_category_level), never stored directly, so POINTS_PER_
## LEVEL/the sub-attribute list can both keep growing without a save
## migration.
var owned_horses: Dictionary = {}
var _next_id: int = ID_START

## Dev tools that drive this through fake trials set this false first, same
## pattern as Bankroll.autosave_enabled — so a headless test run never
## overwrites the player's real save file on disk.
var autosave_enabled: bool = true

## Career-mode-specific milestones — separate from Career.gd's own
## achievement set (which only tracks WILD-FIELD betting stats, nothing
## about an owned stable at all). AJ asked to make career mode "deeper" —
## these are real goals to chase beyond just training/racing on repeat.
## Per-SLOT (part of this slot's own save data), same as everything else
## about a career — a fresh slot starts every milestone locked again.
const MILESTONES: Dictionary = {
	"first_win": {"name": "Winner's Circle", "description": "Win your first career race."},
	"three_horses": {"name": "Growing Stable", "description": "Own 3 horses at once."},
	"allowance_class": {"name": "Rising Star", "description": "Reach Allowance class with a horse."},
	"stakes_class": {"name": "Stakes Company", "description": "Reach Stakes class with a horse."},
	"grade1_win": {"name": "Grade 1 Champion", "description": "Win a Grade 1 Stakes race."},
	"maxed_category": {"name": "Specialist", "description": "Max out one category on a horse."},
	"maxed_all_three": {"name": "Complete Package", "description": "Max out all three categories on one horse."},
	"blue_blood_owner": {"name": "Blue Blood", "description": "Own a Blue-Blood Sire Line horse."},
	"five_wins": {"name": "Consistent Winner", "description": "Win 5 career races total, across your whole stable."},
	"big_spender": {"name": "Big Spender", "description": "Spend $500,000 total buying horses."},
}
var milestones_unlocked: Dictionary = {}

func milestone_name(id: String) -> String:
	return String(MILESTONES.get(id, {}).get("name", id))

## Scans current stable state for every scannable milestone condition (no
## redundant counters kept — everything here is derived from owned_horses,
## same "never store what you can compute" preference the rest of this file
## already follows for attribute levels). `just_won_race_class_id` covers the
## one milestone that ISN'T scannable from current state after the fact
## (class only ever goes up, so "currently Grade 1" doesn't prove a Grade 1
## race was ever actually WON) — pass the race's own class id when placement
## was 1st, "" otherwise. Returns newly-unlocked milestone ids for the caller
## to toast (see CareerHub._show_milestone_toasts).
func check_milestones(just_won_race_class_id: String = "") -> Array[String]:
	var newly_unlocked: Array[String] = []
	var ids: Array[int] = get_owned_horse_ids()

	if ids.size() >= 3:
		_try_unlock_milestone("three_horses", newly_unlocked)
	if just_won_race_class_id == "grade1":
		_try_unlock_milestone("grade1_win", newly_unlocked)

	var total_wins: int = 0
	var total_spent: int = 0
	var any_first_win: bool = false
	var any_allowance: bool = false
	var any_stakes: bool = false
	var any_blue_blood: bool = false
	var any_maxed_one: bool = false
	var any_maxed_all: bool = false
	for id in ids:
		var horse: Dictionary = get_owned_horse(id)
		total_wins += int(horse.get("career_wins", 0))
		total_spent += int(horse.get("purchase_price", 0))
		if int(horse.get("career_wins", 0)) >= 1:
			any_first_win = true
		if String(horse.get("origin_id", "")) == "blue_blood":
			any_blue_blood = true
		var horse_class_id: String = String(get_horse_class(id).id)
		if horse_class_id == "allowance" or horse_class_id == "stakes" or horse_class_id == "grade1":
			any_allowance = true
		if horse_class_id == "stakes" or horse_class_id == "grade1":
			any_stakes = true
		var cap: int = get_potential_cap(id)
		var maxed_count: int = 0
		for category_id in CATEGORY_IDS:
			if get_category_level(id, category_id) >= cap:
				maxed_count += 1
		if maxed_count >= 1:
			any_maxed_one = true
		if maxed_count >= CATEGORY_IDS.size():
			any_maxed_all = true

	if any_first_win:
		_try_unlock_milestone("first_win", newly_unlocked)
	if total_wins >= 5:
		_try_unlock_milestone("five_wins", newly_unlocked)
	if total_spent >= 500000:
		_try_unlock_milestone("big_spender", newly_unlocked)
	if any_allowance:
		_try_unlock_milestone("allowance_class", newly_unlocked)
	if any_stakes:
		_try_unlock_milestone("stakes_class", newly_unlocked)
	if any_blue_blood:
		_try_unlock_milestone("blue_blood_owner", newly_unlocked)
	if any_maxed_one:
		_try_unlock_milestone("maxed_category", newly_unlocked)
	if any_maxed_all:
		_try_unlock_milestone("maxed_all_three", newly_unlocked)

	return newly_unlocked

func _try_unlock_milestone(id: String, newly_unlocked: Array[String]) -> void:
	if milestones_unlocked.has(id):
		return
	milestones_unlocked[id] = true
	newly_unlocked.append(id)
	_save()

## No eager _load() here anymore — current_slot starts unset (-1) until
## CareerHub's slot-picker screen actually chooses or starts one (see
## load_slot/start_new_career above).
func _ready() -> void:
	pass

func has_picked_starter() -> bool:
	return _has_picked_starter

## Free, one-time only (see has_picked_starter) — the marketplace's
## purchase_horse below is for every acquisition after this one.
func pick_starter_horse(starter_index: int) -> int:
	if _has_picked_starter or starter_index < 0 or starter_index >= STARTER_HORSES.size():
		return -1
	var starter: Dictionary = STARTER_HORSES[starter_index]
	var attributes: Dictionary = {}
	for sub_id in SUB_ATTRIBUTE_IDS:
		attributes[sub_id] = {"points": 0}
	var primary_sub: String = String(CATEGORY_PRIMARY_SUB.get(starter.specialty, SUB_ATTRIBUTE_IDS[0]))
	attributes[primary_sub] = {"points": STARTER_SPECIALTY_POINTS}
	var id: int = _next_id
	_next_id += 1
	owned_horses[str(id)] = {
		"horse_name": starter.horse_name,
		"jockey_name": HorseRoster.JOCKEY_NAMES[randi() % HorseRoster.JOCKEY_NAMES.size()],
		"origin_id": "starter",
		"attributes": attributes,
		"trainer_tier_id": "none",
		"training_focus": primary_sub,
		"last_trained_date": "",
		"trainings_today": 0,
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
	for sub_id in SUB_ATTRIBUTE_IDS:
		attributes[sub_id] = {"points": 0}
	owned_horses[str(id)] = {
		"horse_name": horse_name,
		"jockey_name": HorseRoster.JOCKEY_NAMES[randi() % HorseRoster.JOCKEY_NAMES.size()],
		"origin_id": origin.id,
		"attributes": attributes,
		"trainer_tier_id": "none",
		"training_focus": SUB_ATTRIBUTE_IDS[0],
		"last_trained_date": "",
		"trainings_today": 0,
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

## Sum of every sub-attribute's points under one category — the category's
## own effective "points" for level/cap purposes (see get_category_level).
func get_category_points(stable_horse_id: int, category_id: String) -> int:
	var total: int = 0
	for sub_id in SUB_ATTRIBUTE_IDS:
		if String(SUB_ATTRIBUTE_CATEGORY.get(sub_id, "")) == category_id:
			total += get_attribute_points(stable_horse_id, sub_id)
	return total

func get_category_level(stable_horse_id: int, category_id: String) -> int:
	var cap: int = get_potential_cap(stable_horse_id)
	return min(get_category_points(stable_horse_id, category_id) / POINTS_PER_LEVEL, cap)

func get_potential_cap(stable_horse_id: int) -> int:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	return int(HorseOrigins.get_origin(horse.get("origin_id", "")).get("potential_cap", MAX_LEVEL))

func _today() -> String:
	return Time.get_date_string_from_system()

func can_train_today(stable_horse_id: int) -> bool:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty():
		return false
	if String(horse.get("last_trained_date", "")) != _today():
		return true
	return int(horse.get("trainings_today", 0)) < DAILY_TRAINING_ACTIONS

## Player-directed self-training — costs SELF_TRAIN_ITEM_COST regardless of
## outcome (a real drill session bought for the horse), rng gain, available
## whether or not a trainer is hired (skipping the trainer's automatic
## session that day in favor of self-training instead is a legitimate,
## if slightly wasteful, choice — see process_daily_trainer_upkeep). Up to
## DAILY_TRAINING_ACTIONS total actions/day, shared with the hired trainer's
## own automatic session (see can_train_today).
func self_train(stable_horse_id: int, sub_attribute_id: String) -> bool:
	if not can_train_today(stable_horse_id) or not SUB_ATTRIBUTE_IDS.has(sub_attribute_id):
		return false
	if not Bankroll.can_afford(SELF_TRAIN_ITEM_COST):
		return false
	Bankroll.place_bet(SELF_TRAIN_ITEM_COST)
	_apply_training(stable_horse_id, sub_attribute_id, randi_range(SELF_TRAIN_GAIN_MIN, SELF_TRAIN_GAIN_MAX))
	return true

func hire_trainer(stable_horse_id: int, trainer_tier_id: String) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty():
		return
	horse.trainer_tier_id = trainer_tier_id
	owned_horses[str(stable_horse_id)] = horse
	_save()

func set_training_focus(stable_horse_id: int, sub_attribute_id: String) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty() or not SUB_ATTRIBUTE_IDS.has(sub_attribute_id):
		return
	horse.training_focus = sub_attribute_id
	owned_horses[str(stable_horse_id)] = horse
	_save()

## Passive daily trainer upkeep — call once per session (TrackLobby's own
## _ready is the natural hook, matching how Bankroll.ensure_minimum is
## already called at the start of every session) so a hired trainer trains
## automatically without the player needing to remember to log in and do it
## manually. Silently skips (does NOT queue up/backdate) a horse whose
## trainer couldn't be paid that day — matches a real trainer just not
## showing up if the bill isn't covered, no debt mechanic.
## Guarded by its OWN trainer_last_upkeep_date, separate from the self-train
## trainings_today counter this shares via _apply_training below — this
## function gets called once per session load (CareerHub's slot-continue),
## and needs to stay a no-op on a second same-day call in the same session
## rather than double-charging/double-training. A hired trainer's session
## still counts as ONE of the day's shared DAILY_TRAINING_ACTIONS (see
## can_train_today) — hiring a trainer and self-training both eat from the
## same daily budget, same "pick one or the other, or both if the budget
## allows" relationship this project had before DAILY_TRAINING_ACTIONS was 1.
func process_daily_trainer_upkeep() -> void:
	for key in owned_horses.keys():
		var id: int = int(key)
		var horse: Dictionary = owned_horses[key]
		var tier_id: String = String(horse.get("trainer_tier_id", "none"))
		if tier_id == "none":
			continue
		if String(horse.get("trainer_last_upkeep_date", "")) == _today():
			continue
		if not can_train_today(id):
			continue
		var tier: Dictionary = get_trainer_tier(tier_id)
		var cost: int = int(tier.get("daily_cost", 0))
		if not Bankroll.can_afford(cost) and cost > 0:
			continue
		if cost > 0:
			Bankroll.place_bet(cost)
		_apply_training(id, String(horse.get("training_focus", SUB_ATTRIBUTE_IDS[0])), int(tier.get("gain", 0)))
		var updated_horse: Dictionary = get_owned_horse(id)
		updated_horse.trainer_last_upkeep_date = _today()
		owned_horses[str(id)] = updated_horse
		_save()

## Clamps the ACTUAL applied gain so the sub-attribute's own category never
## sums past its potential cap (cap * POINTS_PER_LEVEL) — capping each
## sub-attribute individually at that same threshold would be wrong now that
## a category sums ~8 of them (a fully-capped category would then read as
## 8x over cap). Still advances trainings_today/last_trained_date even when
## the applied gain clamps to 0 (a training session that didn't help still
## used up the day's action and the trainer's fee, same as before).
func _apply_training(stable_horse_id: int, sub_attribute_id: String, gain: int) -> void:
	var horse: Dictionary = get_owned_horse(stable_horse_id)
	if horse.is_empty():
		return
	var category_id: String = String(SUB_ATTRIBUTE_CATEGORY.get(sub_attribute_id, ""))
	var cap_points: int = get_potential_cap(stable_horse_id) * POINTS_PER_LEVEL
	var category_points_now: int = get_category_points(stable_horse_id, category_id)
	var allowed_gain: int = max(cap_points - category_points_now, 0)
	var applied_gain: int = min(gain, allowed_gain)

	var attributes: Dictionary = horse.get("attributes", {})
	var attr: Dictionary = attributes.get(sub_attribute_id, {"points": 0})
	attr.points = int(attr.get("points", 0)) + applied_gain
	attributes[sub_attribute_id] = attr
	horse.attributes = attributes

	var today: String = _today()
	if String(horse.get("last_trained_date", "")) != today:
		horse.trainings_today = 1
	else:
		horse.trainings_today = int(horse.get("trainings_today", 0)) + 1
	horse.last_trained_date = today

	owned_horses[str(stable_horse_id)] = horse
	_save()
	horse_trained.emit(stable_horse_id, sub_attribute_id, applied_gain)

func get_trainer_tier(id: String) -> Dictionary:
	for tier in TRAINER_TIERS:
		if tier.id == id:
			return tier
	return TRAINER_TIERS[0]

## Builds the attribute_overrides dict RaceSim.simulate expects, for a
## Career race where `field_index` in that race's field array is this owned
## horse (see RaceTrack3D/RaceSim.gd — Phase 2 wires an actual Career race
## flow that calls this). Still only 3 flat category levels — RaceSim itself
## has no idea sub-attributes exist at all.
func build_attribute_overrides(stable_horse_id: int, field_index: int) -> Dictionary:
	return {
		field_index: {
			"acceleration_level": get_category_level(stable_horse_id, "acceleration"),
			"stamina_level": get_category_level(stable_horse_id, "stamina"),
			"closing_kick_level": get_category_level(stable_horse_id, "closing_kick"),
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
	var path: String = slot_save_path(current_slot)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	owned_horses = data.get("owned_horses", {})
	_next_id = int(data.get("next_id", ID_START))
	_has_picked_starter = bool(data.get("has_picked_starter", false))
	milestones_unlocked = data.get("milestones_unlocked", {})

func _save() -> void:
	if not autosave_enabled or current_slot == -1:
		return
	var file := FileAccess.open(slot_save_path(current_slot), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"owned_horses": owned_horses,
		"next_id": _next_id,
		"has_picked_starter": _has_picked_starter,
		"milestones_unlocked": milestones_unlocked,
	}))
