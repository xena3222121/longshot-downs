extends Node

## Persistent meta-progression layer, separate from Bankroll (which only
## tracks spendable fake money): a per-horse lifetime win/loss record (so the
## same 60-name HorseRoster reads as a recognizable recurring stable instead
## of disposable random extras), a race-count-gated class ladder (cosmetic
## flavor + a small purse bonus — deliberately NOT touching RaceSim's
## carefully-balanced speed/odds math, see RaceSim.gd's own tuning notes),
## and a small achievement set mirrored to Steam when available. Deliberately
## no class_name — see Bankroll.gd for why.

signal achievement_unlocked(id: String)

const SAVE_PATH: String = "user://career.save"

## Gated purely by races RUN (not bankroll, which swings wildly on its own
## from betting) so a losing streak never locks a player out of career
## progress. purse_bonus is a flat payout multiplier applied on top of a
## winning bet's normal payout (see FinishPodium._build_outcome_and_list) —
## small and additive, not a rebalance of any odds/speed constant.
const RACE_CLASSES: Array[Dictionary] = [
	{"id": "maiden", "name": "Maiden Special Weight", "min_races": 0, "purse_bonus": 0.0},
	{"id": "claiming", "name": "Claiming", "min_races": 6, "purse_bonus": 0.05},
	{"id": "allowance", "name": "Allowance", "min_races": 16, "purse_bonus": 0.10},
	{"id": "stakes", "name": "Stakes", "min_races": 31, "purse_bonus": 0.18},
	{"id": "grade1", "name": "Grade 1 Stakes", "min_races": 61, "purse_bonus": 0.30},
]

## A Win bet at these odds or longer counts as a genuine upset for the
## "Giant Killer" achievement.
const GIANT_KILLER_MIN_ODDS: float = 20.0
const HIGH_ROLLER_AMOUNT: int = 100000
const MILLIONAIRE_BALANCE: int = 2000000
const CENTURY_CLUB_RACES: int = 100
const HOT_STREAK_LENGTH: int = 3
const ON_FIRE_STREAK_LENGTH: int = 5

const ACHIEVEMENTS: Dictionary = {
	"first_blood": {"name": "First Blood", "description": "Win your very first bet."},
	"hot_streak": {"name": "Hot Streak", "description": "Win 3 bets in a row."},
	"on_fire": {"name": "On Fire", "description": "Win 5 bets in a row."},
	"giant_killer": {"name": "Giant Killer", "description": "Win a Win bet on a 20/1-or-longer shot."},
	"high_roller": {"name": "High Roller", "description": "Place a single bet of $100,000 or more."},
	"photo_finish_fan": {"name": "Photo Finish Fan", "description": "Watch a race decided by a photo finish."},
	"millionaire": {"name": "Millionaire", "description": "Grow your bankroll to $2,000,000."},
	"century_club": {"name": "Century Club", "description": "Run 100 races."},
}

## horse_stats keys are String(Horse.id) — JSON object keys are always
## strings, so storing/loading with int keys would silently stringify on the
## very first save/load round-trip anyway; using String from the start
## avoids a save-then-load mismatch.
var horse_stats: Dictionary = {}
var total_races: int = 0
var current_streak: int = 0
var best_streak: int = 0
var peak_bankroll: int = 0
var achievements_unlocked: Dictionary = {}

func _ready() -> void:
	_load()

func get_current_class() -> Dictionary:
	var current: Dictionary = RACE_CLASSES[0]
	for race_class in RACE_CLASSES:
		if total_races >= int(race_class.min_races):
			current = race_class
	return current

func get_purse_bonus() -> float:
	return float(get_current_class().purse_bonus)

## Empty string for a horse that's never raced yet (nothing worth showing);
## otherwise "(3W-8R) " with a trailing space so BettingUI can splice it
## straight into its label format string without a double-space when absent.
func get_horse_record_label(horse_id: int) -> String:
	var stats: Dictionary = horse_stats.get(str(horse_id), {})
	var races: int = int(stats.get("races", 0))
	if races == 0:
		return ""
	return "(%dW-%dR) " % [int(stats.get("wins", 0)), races]

## Called once per race actually run, regardless of whether a bet was placed
## on it (Daily Double leg 1 has no resolved bet yet, but the race still
## happened and its horses still earned a race credit) — increments every
## field horse's race count, the winner's win count, and checks the
## race-count/bankroll/photo-finish achievements. Returns newly unlocked
## achievement ids for the caller to toast. Reads horses straight off
## result.field[i].horse (RaceHorseState already carries the reference)
## rather than taking a separate field array — FinishPodium, the only
## caller, never stored its own field array either.
func record_finish(result: RaceResult) -> Array[String]:
	total_races += 1
	for state in result.field:
		var key: String = str(state.horse.id)
		var stats: Dictionary = horse_stats.get(key, {"races": 0, "wins": 0})
		stats.races = int(stats.get("races", 0)) + 1
		horse_stats[key] = stats
	if not result.finish_order.is_empty():
		var winner_key: String = str(result.field[result.finish_order[0]].horse.id)
		var winner_stats: Dictionary = horse_stats.get(winner_key, {"races": 0, "wins": 0})
		winner_stats.wins = int(winner_stats.get("wins", 0)) + 1
		horse_stats[winner_key] = winner_stats

	peak_bankroll = max(peak_bankroll, Bankroll.balance)
	SteamManager.upload_leaderboard_score(SteamManager.LEADERBOARD_BANKROLL, peak_bankroll)

	var unlocked: Array[String] = []
	if total_races >= CENTURY_CLUB_RACES:
		_try_unlock("century_club", unlocked)
	if peak_bankroll >= MILLIONAIRE_BALANCE:
		_try_unlock("millionaire", unlocked)
	if result.finish_order.size() >= 2:
		var margin: float = result.field[result.finish_order[1]].finish_time - result.field[result.finish_order[0]].finish_time
		if margin < FinishPodium.PHOTO_FINISH_MARGIN:
			_try_unlock("photo_finish_fan", unlocked)

	_save()
	return unlocked

## Called once a bet's win/loss is actually known (skipped on Daily Double
## leg 1, which defers resolution to leg 2) — `tier` is the tier of the horse
## actually bet to WIN (pass the null/empty default for multi-pick bets,
## where "the odds of the bet" isn't one single horse's tier and the Giant
## Killer check is skipped accordingly). `amount` is checked for High Roller
## regardless of outcome — the achievement is about the size of the stake,
## not whether it paid off.
func record_bet_outcome(won: bool, amount: int, win_tier: Dictionary = {}) -> Array[String]:
	var unlocked: Array[String] = []

	if amount >= HIGH_ROLLER_AMOUNT:
		_try_unlock("high_roller", unlocked)

	if won:
		current_streak += 1
		if current_streak > best_streak:
			best_streak = current_streak
			SteamManager.upload_leaderboard_score(SteamManager.LEADERBOARD_WIN_STREAK, best_streak)
		_try_unlock("first_blood", unlocked)
		if current_streak >= ON_FIRE_STREAK_LENGTH:
			_try_unlock("on_fire", unlocked)
		elif current_streak >= HOT_STREAK_LENGTH:
			_try_unlock("hot_streak", unlocked)
		if not win_tier.is_empty() and float(win_tier.num) / float(win_tier.den) >= GIANT_KILLER_MIN_ODDS:
			_try_unlock("giant_killer", unlocked)
	else:
		current_streak = 0

	_save()
	return unlocked

func _try_unlock(id: String, unlocked: Array[String]) -> void:
	if achievements_unlocked.has(id):
		return
	achievements_unlocked[id] = true
	unlocked.append(id)
	achievement_unlocked.emit(id)
	SteamManager.unlock_achievement(id)

func achievement_name(id: String) -> String:
	return String(ACHIEVEMENTS.get(id, {}).get("name", id))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	horse_stats = data.get("horse_stats", {})
	total_races = int(data.get("total_races", 0))
	current_streak = int(data.get("current_streak", 0))
	best_streak = int(data.get("best_streak", 0))
	peak_bankroll = int(data.get("peak_bankroll", 0))
	achievements_unlocked = data.get("achievements_unlocked", {})

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"horse_stats": horse_stats,
		"total_races": total_races,
		"current_streak": current_streak,
		"best_streak": best_streak,
		"peak_bankroll": peak_bankroll,
		"achievements_unlocked": achievements_unlocked,
	}))
