extends Node2D

## Orchestrates one full loop: draw a field -> player bets via BettingUI ->
## simulate -> play back via RaceTrack3D -> resolve payout against Bankroll
## -> offer to do it again. Owns the bet's horse/amount/type; BettingUI and
## RaceTrack3D stay ignorant of each other and of the betting outcome.
## RaceTrack3D/HorseMarker3D are Node3D and FinishPodium/BettingUI are
## Control — both mix fine as children of this Node2D root, since neither
## needs to inherit a 2D transform from it.
##
## Daily Double is the one bet type that spans two races: race 1 uses the
## normal `field`/`tiers`, and betting_ui lazily requests a second field
## (dd_field_2/dd_tiers_2) only if the player actually selects it. Race 1's
## FinishPodium then defers resolution (dd_leg=1) instead of paying out,
## race 2 runs automatically afterward, and its FinishPodium (dd_leg=2)
## resolves the combined bet against both results.

var field: Array[Horse] = []
var tiers: Array[Dictionary] = []
var bet_picks: Array[int] = [] # every horse the player picked, in click order — see BettingUI.picks
var bet_horse_index: int = -1 # alias for bet_picks[0] — kept for the single-pick (Win/Place/Show) bet types
var bet_second_index: int = -1 # alias for bet_picks[1] — Exacta/Quinella's 2nd pick, or Daily Double's race-2 pick
var bet_amount: int = 0
var bet_type: OddsTable.BetType = OddsTable.BetType.WIN

var dd_field_2: Array[Horse] = []
var dd_tiers_2: Array[Dictionary] = []
var dd_result_1: RaceResult

var betting_ui: BettingUI
var race_track: RaceTrack3D

func _ready() -> void:
	ScreenFade.fade_in() # reveals from the black TitleScreen left behind after its own fade_out — see
	# TitleScreen._on_play_pressed's comment for why the fade-in has to happen from here, not there
	AudioManager.play_music("theme")
	_start_new_race_setup()

func _start_new_race_setup() -> void:
	for child in get_children():
		child.queue_free()

	Bankroll.ensure_minimum()

	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	field = roster.slice(0, 8)
	HorseRoster.assign_race_colors(field)
	tiers = OddsTable.assign_to_field(field.size())
	bet_picks = []
	bet_horse_index = -1
	bet_second_index = -1
	bet_amount = 0
	bet_type = OddsTable.BetType.WIN
	dd_field_2 = []
	dd_tiers_2 = []
	dd_result_1 = null

	betting_ui = BettingUI.new()
	betting_ui.position = Vector2(20.0, 20.0)
	add_child(betting_ui)
	betting_ui.setup(field, tiers)
	betting_ui.bet_placed.connect(_on_bet_placed)
	betting_ui.daily_double_second_race_needed.connect(_on_daily_double_second_race_needed)

func _on_daily_double_second_race_needed() -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	dd_field_2 = roster.slice(0, 8)
	HorseRoster.assign_race_colors(dd_field_2)
	dd_tiers_2 = OddsTable.assign_to_field(dd_field_2.size())
	betting_ui.provide_second_race(dd_field_2, dd_tiers_2)

func _on_bet_placed(picks: Array[int], amount: int, p_bet_type: OddsTable.BetType) -> void:
	if not Bankroll.place_bet(amount):
		return

	bet_picks = picks
	bet_horse_index = picks[0]
	bet_second_index = picks[1] if picks.size() > 1 else -1
	bet_amount = amount
	bet_type = p_bet_type
	betting_ui.lock()
	betting_ui.status_label.text = "Bet placed: %s on %s (%s). Racing..." % [
		OddsTable.format_money(amount), field[bet_horse_index].horse_name, OddsTable.bet_type_label(bet_type),
	]

	betting_ui.visible = false # stop covering the broadcast HUD's header/leaderboard once the race is actually on screen

	var result: RaceResult = RaceSim.simulate(field, tiers)
	# Daily Double leg 1 only shows THIS race's own relevant pick (bet_picks[0],
	# the race-1 winner call) — bet_picks[1] is the race-2 pick, into a
	# different field entirely, and would be meaningless (or out of bounds)
	# looked up against this race's field.
	var leg1_picks: Array[int] = [bet_picks[0]] if bet_type == OddsTable.BetType.DAILY_DOUBLE else bet_picks
	_play_race(field, tiers, result, {
		"bet_type": bet_type, "picks": leg1_picks, "amount": bet_amount,
		"dd_leg": 1 if bet_type == OddsTable.BetType.DAILY_DOUBLE else 0,
	})

	var handler: Callable = _on_daily_double_leg1_finished if bet_type == OddsTable.BetType.DAILY_DOUBLE else _on_race_finished
	race_track.playback_finished.connect(handler.bind(result))

func _play_race(p_field: Array[Horse], p_tiers: Array[Dictionary], result: RaceResult, bet_context: Dictionary = {}) -> void:
	race_track = RaceTrack3D.new()
	add_child(race_track)
	race_track.setup(p_field, result, bet_context)
	race_track.play_with_post_time() # gate SFX + announcer's opening call fire after the countdown, not here

func _on_race_finished(result: RaceResult) -> void:
	await race_track.play_replay() # TVG-style "here's the stretch run again" slow-mo replay before the podium
	race_track.queue_free() # otherwise its BroadcastHUD (a separate CanvasLayer, drawn/input-routed above
	# the podium's own Control layer) lingers on screen and steals clicks meant for the podium's buttons
	var podium := FinishPodium.new()
	add_child(podium)
	podium.setup(field, result, {
		"bet_type": bet_type, "horse_index": bet_horse_index, "second_index": bet_second_index,
		"picks": bet_picks, "amount": bet_amount, "dd_leg": 0,
	})
	podium.race_again_pressed.connect(_on_race_again_pressed)

func _on_daily_double_leg1_finished(result: RaceResult) -> void:
	dd_result_1 = result
	race_track.queue_free() # see _on_race_finished's comment
	var podium := FinishPodium.new()
	add_child(podium)
	podium.setup(field, result, {"dd_leg": 1})
	podium.continue_to_next_race.connect(_on_continue_to_leg2_pressed)

## Fades to black, resets for the next race underneath the cover, fades back
## in — a soft transition instead of the podium popping straight into the
## next betting screen.
func _on_race_again_pressed() -> void:
	await ScreenFade.fade_out()
	_start_new_race_setup()
	ScreenFade.fade_in()

func _on_continue_to_leg2_pressed() -> void:
	await ScreenFade.fade_out()
	_start_daily_double_leg2()
	ScreenFade.fade_in()

func _start_daily_double_leg2() -> void:
	for child in get_children():
		child.queue_free()

	var result2: RaceResult = RaceSim.simulate(dd_field_2, dd_tiers_2)
	_play_race(dd_field_2, dd_tiers_2, result2, {
		"bet_type": OddsTable.BetType.DAILY_DOUBLE, "picks": [bet_second_index], "amount": bet_amount, "dd_leg": 2,
	})
	race_track.playback_finished.connect(_on_daily_double_leg2_finished.bind(result2))

func _on_daily_double_leg2_finished(result2: RaceResult) -> void:
	await race_track.play_replay() # see _on_race_finished's comment
	race_track.queue_free() # see _on_race_finished's comment
	var podium := FinishPodium.new()
	add_child(podium)
	podium.setup(dd_field_2, result2, {
		"bet_type": OddsTable.BetType.DAILY_DOUBLE, "horse_index": bet_horse_index, "second_index": bet_second_index,
		"picks": bet_picks, "amount": bet_amount, "dd_leg": 2, "dd_leg1_result": dd_result_1,
	})
	podium.race_again_pressed.connect(_on_race_again_pressed)
