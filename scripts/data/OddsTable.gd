class_name OddsTable
extends RefCounted

## Fractional-odds ladder, favorite -> longshot. Each race field draws a
## spread from this ladder; true race performance is rolled independently
## (see HorseRoster / race sim), so a longshot's displayed odds are not a
## reliable predictor of its actual finish. That gap is the point.
const TIERS: Array[Dictionary] = [
	{"num": 3, "den": 2, "label": "3/2"},
	{"num": 2, "den": 1, "label": "2/1"},
	{"num": 3, "den": 1, "label": "3/1"},
	{"num": 5, "den": 1, "label": "5/1"},
	{"num": 8, "den": 1, "label": "8/1"},
	{"num": 12, "den": 1, "label": "12/1"},
	{"num": 20, "den": 1, "label": "20/1"},
	{"num": 33, "den": 1, "label": "33/1"},
	{"num": 50, "den": 1, "label": "50/1"},
]

enum BetType { WIN, PLACE, SHOW, EXACTA, DAILY_DOUBLE, QUINELLA, TRIFECTA, SUPERFECTA }

## Finer real-style fractional odds ladder used ONLY for live tote-board
## display once RaceScheduler starts drifting a horse's odds pre-race (see
## RaceScheduler._drift_odds) — TIERS above stays exactly as-is and untouched
## for RaceSim's own favorite-vs-longshot performance correlation (RaceSim
## only ever reads a tier's "index" key, never num/den/label — drifting the
## displayed/paid odds has zero effect on how a horse actually runs). Every
## exact TIERS value is included here too, so a horse's odds at zero drift
## still render identically to today.
const LIVE_ODDS_LADDER: Array[Dictionary] = [
	{"num": 1, "den": 9}, {"num": 1, "den": 5}, {"num": 2, "den": 5}, {"num": 1, "den": 2},
	{"num": 3, "den": 5}, {"num": 4, "den": 5}, {"num": 1, "den": 1}, {"num": 6, "den": 5},
	{"num": 7, "den": 5}, {"num": 3, "den": 2}, {"num": 8, "den": 5}, {"num": 9, "den": 5},
	{"num": 2, "den": 1}, {"num": 5, "den": 2}, {"num": 3, "den": 1}, {"num": 7, "den": 2},
	{"num": 4, "den": 1}, {"num": 9, "den": 2}, {"num": 5, "den": 1}, {"num": 6, "den": 1},
	{"num": 8, "den": 1}, {"num": 10, "den": 1}, {"num": 12, "den": 1}, {"num": 15, "den": 1},
	{"num": 20, "den": 1}, {"num": 30, "den": 1}, {"num": 33, "den": 1}, {"num": 50, "den": 1},
]

## Snaps a live win-multiplier to the nearest real-style fractional odds
## label (e.g. a drifted 6.2x -> "5/1") — keeps the tote-board LABEL text
## consistent with whatever live decimal it's actually paying on, at a much
## finer granularity than the base TIERS ladder (which stays reserved for
## RaceSim's own performance correlation, never shown as a label directly
## once drift is active).
static func live_odds_label(win_multiplier: float) -> String:
	var target_profit: float = win_multiplier - 1.0
	var best: Dictionary = LIVE_ODDS_LADDER[0]
	var best_diff: float = INF
	for entry in LIVE_ODDS_LADDER:
		var diff: float = absf(float(entry.num) / float(entry.den) - target_profit)
		if diff < best_diff:
			best_diff = diff
			best = entry
	return "%d/%d" % [int(best.num), int(best.den)]

## Win pays the full tier odds. Place/Show are easier to hit (top 2 / top 3)
## so they pay a smaller slice of the win profit — real tracks do the same
## thing via separate pari-mutuel pools; here it's just a flat discount on
## the win multiplier's profit portion since there's no real pool to balance.
const PLACE_PROFIT_FACTOR: float = 0.5
const SHOW_PROFIT_FACTOR: float = 0.3

## Exacta (exact 1st+2nd) and Daily Double (win both of two races) multiply
## the two picks' win odds together — much harder to hit than a single Win
## bet, so it pays out like it. DAMPENING pulls the raw product down a bit
## so pairing two longshots doesn't produce an ridiculous payout, while
## still leaving room for a big, exciting jackpot-style win.
const EXACTA_DAMPENING: float = 0.6
const DAILY_DOUBLE_DAMPENING: float = 0.6

## Total return per 1 unit staked, including the stake itself.
## Prefers a live-drifted win multiplier (set by RaceScheduler._drift_odds
## on the SAME tier dict reference every UI/payout call site already reads)
## over the tier's own fixed num/den whenever one's been set — every existing
## caller/test that never goes through RaceScheduler simply never sees this
## key, so behavior is byte-identical to before for them.
static func decimal_multiplier(tier: Dictionary, bet_type: BetType = BetType.WIN) -> float:
	var win_multiplier: float = float(tier.get("live_win_multiplier", float(tier.num) / float(tier.den) + 1.0))
	var profit: float = win_multiplier - 1.0
	match bet_type:
		BetType.PLACE:
			return profit * PLACE_PROFIT_FACTOR + 1.0
		BetType.SHOW:
			return profit * SHOW_PROFIT_FACTOR + 1.0
		_:
			return win_multiplier

static func payout(bet_amount: int, tier: Dictionary, bet_type: BetType = BetType.WIN) -> int:
	return int(round(bet_amount * decimal_multiplier(tier, bet_type)))

## How many finishing positions count as a hit for this bet type.
static func positions_required(bet_type: BetType) -> int:
	match bet_type:
		BetType.PLACE:
			return 2
		BetType.SHOW:
			return 3
		_:
			return 1

## True if `horse_index` finished within the positions this bet type pays on.
static func is_winning_bet(finish_order: Array[int], horse_index: int, bet_type: BetType) -> bool:
	var needed: int = min(positions_required(bet_type), finish_order.size())
	return finish_order.slice(0, needed).has(horse_index)

static func bet_type_label(bet_type: BetType) -> String:
	match bet_type:
		BetType.PLACE:
			return "Place (top 2)"
		BetType.SHOW:
			return "Show (top 3)"
		BetType.EXACTA:
			return "Exacta (exact 1st+2nd)"
		BetType.DAILY_DOUBLE:
			return "Daily Double (win both races)"
		BetType.QUINELLA:
			return "Quinella (top 2, either order)"
		BetType.TRIFECTA:
			return "Trifecta (exact 1st+2nd+3rd)"
		BetType.SUPERFECTA:
			return "Superfecta (exact 1st-4th)"
		_:
			return "Win"

## How many horses the player must pick for this bet type — drives BettingUI's
## generalized N-slot picker (see BettingUI.picks/OddsTable.picks_required).
## WIN/PLACE/SHOW/DAILY_DOUBLE's race-1 leg only ever need a single pick.
static func picks_required(bet_type: BetType) -> int:
	match bet_type:
		BetType.EXACTA, BetType.QUINELLA:
			return 2
		BetType.TRIFECTA:
			return 3
		BetType.SUPERFECTA:
			return 4
		_:
			return 1

## Total return per 1 unit staked on an Exacta: both picks' win multipliers
## multiplied together (much harder to hit than either alone) then dampened
## so two longshots don't produce an ridiculous number.
static func exacta_multiplier(tier_first: Dictionary, tier_second: Dictionary) -> float:
	var combined: float = decimal_multiplier(tier_first, BetType.WIN) * decimal_multiplier(tier_second, BetType.WIN)
	return 1.0 + (combined - 1.0) * EXACTA_DAMPENING

static func exacta_payout(bet_amount: int, tier_first: Dictionary, tier_second: Dictionary) -> int:
	return int(round(bet_amount * exacta_multiplier(tier_first, tier_second)))

## True if `first_idx` won and `second_idx` finished exactly 2nd.
static func is_winning_exacta(finish_order: Array[int], first_idx: int, second_idx: int) -> bool:
	return finish_order.size() >= 2 and finish_order[0] == first_idx and finish_order[1] == second_idx

## Same combined-odds shape as an Exacta, but across two separate races'
## win picks instead of one race's 1st+2nd.
static func daily_double_multiplier(tier_race1: Dictionary, tier_race2: Dictionary) -> float:
	var combined: float = decimal_multiplier(tier_race1, BetType.WIN) * decimal_multiplier(tier_race2, BetType.WIN)
	return 1.0 + (combined - 1.0) * DAILY_DOUBLE_DAMPENING

static func daily_double_payout(bet_amount: int, tier_race1: Dictionary, tier_race2: Dictionary) -> int:
	return int(round(bet_amount * daily_double_multiplier(tier_race1, tier_race2)))

## Same "multiply the picks' win multipliers together, then dampen" shape as
## exacta_multiplier/daily_double_multiplier above, generalized to any pick
## count (Quinella/Trifecta/Superfecta all resolve through this one). The
## dampening factor drops further as the pick count grows — a 4-horse
## Superfecta's raw product of four win multipliers would otherwise spiral
## into an ridiculous number; a steeper per-count dampening keeps every pick
## count's payout feeling like "a big, exciting jackpot" rather than either
## a rounding error or an ridiculous number.
const MULTI_DAMPENING_BY_PICK_COUNT: Dictionary = {2: 0.6, 3: 0.4, 4: 0.28}

static func multi_multiplier(tiers: Array[Dictionary]) -> float:
	var combined: float = 1.0
	for tier in tiers:
		combined *= decimal_multiplier(tier, BetType.WIN)
	var dampening: float = MULTI_DAMPENING_BY_PICK_COUNT.get(tiers.size(), 0.6)
	return 1.0 + (combined - 1.0) * dampening

static func multi_payout(bet_amount: int, tiers: Array[Dictionary]) -> int:
	return int(round(bet_amount * multi_multiplier(tiers)))

## Trifecta/Superfecta: `picks` must match the top `picks.size()` finishers
## in EXACT order (1st, then 2nd, then 3rd, ...).
static func is_winning_exact_order(finish_order: Array[int], picks: Array[int]) -> bool:
	if finish_order.size() < picks.size() or picks.is_empty():
		return false
	for i in range(picks.size()):
		if finish_order[i] != picks[i]:
			return false
	return true

## Quinella: the top 2 finishers are exactly `picks`, in EITHER order — easier
## to hit than an Exacta (no order requirement) so it pays less for the same
## two picks; multi_multiplier's dampening table already reflects that.
static func is_winning_quinella(finish_order: Array[int], picks: Array[int]) -> bool:
	if finish_order.size() < 2 or picks.size() != 2 or picks[0] == picks[1]:
		return false
	var top2: Array[int] = [finish_order[0], finish_order[1]]
	return picks[0] in top2 and picks[1] in top2

## Returns `field_size` tiers (favorite -> longshot spread), shuffled so the
## assignment to horses in the field is random each race.
static func assign_to_field(field_size: int) -> Array[Dictionary]:
	var count: int = min(field_size, TIERS.size())
	var chosen: Array[Dictionary] = []
	for i in range(count):
		var tier: Dictionary = TIERS[i].duplicate()
		tier["index"] = i # favorite = 0, longshot = highest index; used by RaceSim
		chosen.append(tier)
	chosen.shuffle()
	return chosen

## Thousands-separated money string, e.g. 1250000 -> "$1,250,000".
static func format_money(amount: int) -> String:
	var digits: String = str(abs(amount))
	var grouped: String = ""
	var count_from_right: int = 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count_from_right += 1
		if count_from_right % 3 == 0 and i != 0:
			grouped = "," + grouped
	return "%s$%s" % ["-" if amount < 0 else "", grouped]
