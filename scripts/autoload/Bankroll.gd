extends Node

## Autoload singleton (registered in project.godot) — the player's fake-money
## balance, persisted to disk so it survives app restarts. Deliberately no
## class_name: autoloads are referenced by their registered global name, and
## giving this one a matching class_name risks a duplicate-identifier
## collision with that.

signal balance_changed(new_balance: int)
## Fired the instant balance actually hits 0 from a bet/payout mutation (NOT
## from ensure_minimum, which is the fix for this, not the problem) — see
## TrackLobby's connection to this for the "you suck at betting, try again?"
## prompt. Bankroll itself only reports the state change; it doesn't own any
## UI/dialog, same separation as balance_changed.
signal went_broke

const STARTING_BALANCE: int = 1000000

## Resolved once in _ready() (SavePaths reads OS.get_environment, which isn't
## a compile-time constant) rather than being a const.
var SAVE_PATH: String

## Floor the player can never stay below going into a new bet — a busted
## player always has enough to keep playing instead of getting stuck at $0.
const MIN_BALANCE: int = 100

var balance: int = STARTING_BALANCE

## Dev tools (see scripts/tools/) that drive Bankroll through hundreds of
## fake trials set this false first, so their throwaway wins/losses never
## overwrite the player's real save file on disk.
var autosave_enabled: bool = true

func _ready() -> void:
	SAVE_PATH = SavePaths.resolve("bankroll.save")
	_load()
	ensure_minimum()

## Called at the start of every new race setup (see Main.gd) so a player who
## just lost their last few dollars is topped back up before betting again,
## not just once at game launch.
func ensure_minimum() -> void:
	if balance < MIN_BALANCE:
		balance = MIN_BALANCE
		balance_changed.emit(balance)
		_save()

func can_afford(amount: int) -> bool:
	return amount > 0 and amount <= balance

## Real bug fixed: this used to fire went_broke itself whenever a bet spent
## the last of the balance (e.g. "All In") — meaning the busted dialog could
## pop up the INSTANT a bet was placed, before the race even played, even on
## a bet that was about to win. Going broke is only real once a bet actually
## RESOLVES with nothing left — every resolution path (FinishPodium,
## TrackLobby._show_compact_result, RaceScheduler._resolve_background) now
## calls pay() unconditionally (0 on a loss), so went_broke's own check
## inside pay() below fires at the correct moment instead.
func place_bet(amount: int) -> bool:
	if not can_afford(amount):
		return false
	balance -= amount
	balance_changed.emit(balance)
	_save()
	return true

func pay(amount: int) -> void:
	balance += amount
	balance_changed.emit(balance)
	_save()
	if balance <= 0:
		went_broke.emit()

## Sets the balance directly to `amount` (not an add-on-top like pay()) —
## used by the "you suck at betting, try again?" prompt to top a busted
## player back up to a fixed fresh-start amount regardless of exactly how
## negative-adjacent their balance was.
func refill(amount: int) -> void:
	balance = amount
	balance_changed.emit(balance)
	_save()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) == TYPE_DICTIONARY and data.has("balance"):
		balance = int(data["balance"])

func _save() -> void:
	if not autosave_enabled:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"balance": balance}))
