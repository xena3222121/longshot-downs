extends Node

## Runs every venue in Venues.VENUE_IDS on independent, continuous post-time
## countdowns — the "you have to catch the countdown to post, just like real
## TVG" mechanic. An autoload so it keeps ticking across every scene change,
## the same way a real simulcast parlor's clocks don't stop just because
## you're looking at a different monitor.
##
## SCREEN_COUNT fixed viewing "screens" (TrackLobby renders each as its own
## SubViewport, side by side — real simultaneous multi-race viewing) can each
## have any venue assigned to them via set_screen_venue(). Whichever venue is
## CURRENTLY assigned to a screen when its countdown hits zero gets the full
## existing rich single-race experience (RaceTrack3D visual playback, slow-mo
## replay, FinishPodium with every bet type/achievement) — betting is
## optional for this, watching the spectacle doesn't require it. This script
## hands off to that flow via race_ready rather than duplicating it.
##
## Every venue actually RUNS its race the moment its countdown hits zero,
## whether or not a screen is watching — AJ: "make it start anyways, if im
## not watching it it still runs and remains live until the race is over, if
## i choose to tune in itll open at whatever part of the race its at." A
## venue with no screen assigned races silently for the same real-time
## duration a watched one takes (see `race_elapsed`/`VenueState.result`
## below) before resolving: WIN/PLACE/SHOW bets only for now (v1 — the full
## Exacta/Trifecta/Daily-Double matrix stays exclusive to an on-screen venue;
## extending background resolution to every bet type is a reasonable
## fast-follow, not done here to keep this landable). Assigning a screen to a
## venue that's already mid-race (see screen_assignment_changed) hands
## TrackLobby the SAME already-computed RaceResult plus how far into it the
## race already is, so it can build a RaceTrack3D seeked to that point
## instead of restarting from the gate — this game's actual "catch the race
## already in progress" moment.

signal race_ready(venue_id: String, screen: int, result: RaceResult, bet_context: Dictionary)
signal background_result(venue_id: String, description: String, won: bool, payout: int)
signal countdown_reset(venue_id: String) # field/tiers redrawn — UI showing odds should refresh
signal screen_assignment_changed(screen: int, venue_id: String)

const POST_INTERVAL: float = 240.0 # 4 minutes between races per venue — TVG-plausible pacing
const SCREEN_COUNT: int = 4 # how many venues can get the full visual treatment AT ONCE — see TrackLobby's split-screen view

## Cosmetic pre-race odds drift — AJ: "make the odds change before the race
## like in live betting but not drastically... realistic like late money
## comes on a certain horse." Real pari-mutuel odds move continuously as
## money comes in, and a bettor is paid whatever the board reads at ACTUAL
## post time, not whatever it read when they placed their bet — this needs
## zero extra plumbing to get that right, since `_on_post_time` below already
## passes `state.tiers` (the exact dicts this drift mutates in place) into
## `RaceSim.simulate`, which snapshots them onto RaceResult at that instant.
## Mean-reverting random walk (same Ornstein-Uhlenbeck shape as RaceSim's own
## `surge` mechanic) bounded to a "noticeable but not drastic" range, plus a
## rare one-time sharper tightening in the final quarter of the countdown on
## at most one horse per venue per race — the "late money" moment.
const ODDS_DRIFT_REVERSION: float = 0.22
const ODDS_DRIFT_VOLATILITY: float = 0.42
const ODDS_DRIFT_MAX_DEVIATION: float = 0.35 # odds can lengthen up to +35% over their base (money staying away)
const ODDS_DRIFT_MIN_DEVIATION: float = -0.3 # or tighten down to -30% from ordinary ambient drift alone
const LATE_MONEY_WINDOW_FRACTION: float = 0.25 # only eligible in the final quarter of the countdown
const LATE_MONEY_CHANCE_PER_SECOND: float = 0.006 # small — not every race gets a late-money moment
const LATE_MONEY_MIN_DEVIATION: float = -0.5
const LATE_MONEY_MAX_DEVIATION: float = -0.3 # a real, noticeable "the money's on this one" swing, still bounded so it can't produce a nonsensical near-1.0x payout

## AJ: "make it so they randomly race on turf or dirt." Purely cosmetic
## (RaceTrack3D's surface color/BroadcastHUD's header tag) — doesn't touch
## RaceSim's performance math at all, same "displayed conditions aren't a
## performance model" spirit as the odds drift above. Dirt is the more common
## surface in North American racing (this game's clear stylistic reference —
## TVG, post-time countdowns, etc.), so turf stays the minority surface.
const TURF_CHANCE: float = 0.35

class VenueState:
	var venue_id: String
	var countdown: float = POST_INTERVAL
	var field: Array[Horse] = []
	var tiers: Array[Dictionary] = []
	var bet: Dictionary = {} # {} = no bet placed for the UPCOMING race at this venue
	var is_racing: bool = false # true from post time until this race is fully resolved — REGARDLESS of whether a screen is watching; pauses countdown ticking
	var is_turf: bool = false # this race's track surface — see TURF_CHANCE
	var result: RaceResult # the CURRENT race's already-computed result, set at post time, cleared on resolution — lets a screen assigned later join wherever this actually is
	var race_elapsed: float = 0.0 # real seconds since this race's post time — same units RaceTrack3D.playback_time already runs in, so a join just seeds that field directly, no conversion
	var race_bet_context: Dictionary = {} # frozen at post time from `bet`, same shape race_ready already emits — real pari-mutuel rule: what airs/pays out reflects the bet AT POST TIME (see place_bet's new is_racing guard, which stops a NEW bet on a race already underway)

## screen_venue_ids[i] = which venue screen `i` is currently showing, or ""
## if that screen is unassigned. Screen 0 defaults to the flagship venue so
## there's always something to watch on first launch.
var screen_venue_ids: Array[String] = [Venues.DEFAULT_VENUE_ID, "", "", ""]
var _venues: Dictionary = {} # venue_id -> VenueState

## Screen-assigned venues always get exactly this long on the FIRST time the
## lobby ever opens — not "however much of the stagger fraction happened to
## be left" (which could read as almost no time at all) and definitely not
## already-live (see the bug this whole running/_seeded pair exists to fix).
const INITIAL_SCREEN_COUNTDOWN: float = 30.0

## Ticking only actually happens while `running` (see begin_watching/
## stop_watching, called from TrackLobby/InputHints) — this is an autoload,
## so without this gate it would start counting down from the moment the
## game BOOTS, including the whole time spent on the title screen before
## TrackLobby even exists to receive race_ready. AJ hit exactly that: leave
## the title screen up long enough and a venue's countdown would hit zero
## with nobody listening, permanently stuck showing "LIVE NOW" (is_racing
## set true, but no RaceTrack3D ever built and nothing left to ever clear
## it) once the lobby finally opened. Pausing here instead of trying to
## "catch up" a missed race_ready after the fact is the simpler, safer fix.
var running: bool = false
var _seeded: bool = false

func _ready() -> void:
	for venue_id in Venues.VENUE_IDS:
		var state := VenueState.new()
		state.venue_id = venue_id
		_draw_field(state)
		_venues[venue_id] = state

## Called by TrackLobby._ready() every time the lobby opens (idempotent for
## the actual countdown seeding — only applies once, ever, via _seeded; every
## call still resumes ticking). The very first time, screen-assigned venues
## get INITIAL_SCREEN_COUNTDOWN and everything else gets staggered evenly
## across one POST_INTERVAL window (240s / N venues apart) so they don't all
## post at the same moment either. After that first seed, a return visit
## just resumes ticking from wherever each venue's countdown was paused —
## no re-seeding, no skipping ahead.
func begin_watching() -> void:
	running = true
	if _seeded:
		return
	_seeded = true
	var venue_ids: Array[String] = Venues.VENUE_IDS
	for i in range(venue_ids.size()):
		var venue_id: String = venue_ids[i]
		var state: VenueState = _venues[venue_id]
		if screen_venue_ids.has(venue_id):
			state.countdown = INITIAL_SCREEN_COUNTDOWN
		else:
			state.countdown = POST_INTERVAL * (float(i + 1) / float(venue_ids.size()))

## Called from InputHints when leaving TrackLobby for the title screen —
## freezes every countdown exactly where it is rather than letting them
## silently resolve in the background with nobody around to see race_ready.
func stop_watching() -> void:
	running = false

func _process(delta: float) -> void:
	if not running:
		return
	for venue_id in Venues.VENUE_IDS:
		var state: VenueState = _venues[venue_id]
		if state.is_racing:
			# A venue currently on a screen is resolved by that screen's own
			# playback -> replay -> podium flow calling finish_watched_race
			# whenever IT decides the race is over (which can be well after
			# `result.duration`, e.g. during the replay/podium beats) — only
			# an UNWATCHED race times out here, against the same real-second
			# duration a watched one takes.
			if screen_venue_ids.find(venue_id) == -1:
				state.race_elapsed += delta
				if state.race_elapsed >= state.result.duration:
					_resolve_background(state, state.result)
					state.is_racing = false
					_reset_venue(state)
			continue
		state.countdown -= delta
		_drift_odds(state, delta)
		if state.countdown <= 0.0:
			_start_race(state)

## See this file's own const block above for the design rationale. Mutates
## each tier dict's `_drift_deviation` (internal state), `live_win_multiplier`,
## and `label` in place — every UI/payout call site already reads these same
## dict references via OddsTable.decimal_multiplier/payout, so nothing else
## needs to change to pick this up.
func _drift_odds(state: VenueState, delta: float) -> void:
	var late_window_start: float = POST_INTERVAL * LATE_MONEY_WINDOW_FRACTION
	var in_late_window: bool = state.countdown <= late_window_start

	for tier in state.tiers:
		var deviation: float = tier.get("_drift_deviation", 0.0)
		deviation += -ODDS_DRIFT_REVERSION * deviation * delta + randfn(0.0, ODDS_DRIFT_VOLATILITY * sqrt(delta))
		deviation = clamp(deviation, ODDS_DRIFT_MIN_DEVIATION, ODDS_DRIFT_MAX_DEVIATION)

		if in_late_window and not tier.get("_late_money_fired", false) and randf() < LATE_MONEY_CHANCE_PER_SECOND * delta:
			deviation = randf_range(LATE_MONEY_MIN_DEVIATION, LATE_MONEY_MAX_DEVIATION)
			tier["_late_money_fired"] = true

		tier["_drift_deviation"] = deviation
		var base_win_multiplier: float = float(tier.num) / float(tier.den) + 1.0
		var live_win_multiplier: float = max(1.05, base_win_multiplier * (1.0 + deviation))
		tier["live_win_multiplier"] = live_win_multiplier
		tier["label"] = OddsTable.live_odds_label(live_win_multiplier)

func get_countdown(venue_id: String) -> float:
	return max(0.0, _venues[venue_id].countdown)

func get_field(venue_id: String) -> Array[Horse]:
	return _venues[venue_id].field

func get_tiers(venue_id: String) -> Array[Dictionary]:
	return _venues[venue_id].tiers

func get_is_turf(venue_id: String) -> bool:
	return _venues[venue_id].is_turf

func has_bet(venue_id: String) -> bool:
	return not _venues[venue_id].bet.is_empty()

func is_racing(venue_id: String) -> bool:
	return _venues[venue_id].is_racing

func is_watched(venue_id: String) -> bool:
	return screen_venue_ids.has(venue_id)

func screen_for(venue_id: String) -> int:
	return screen_venue_ids.find(venue_id)

## Assigns `venue_id` to `screen`, unassigning it from any other screen it
## might already be on (a venue can only ever occupy one screen at a time).
## Pass "" to clear a screen. Refuses to move a screen that's currently
## mid-race out from under itself — finish or abandon that race first.
func set_screen_venue(screen: int, venue_id: String) -> bool:
	if screen < 0 or screen >= SCREEN_COUNT:
		return false
	var current: String = screen_venue_ids[screen]
	if current != "" and _venues[current].is_racing:
		return false
	if venue_id != "":
		var existing_screen: int = screen_venue_ids.find(venue_id)
		if existing_screen != -1:
			screen_venue_ids[existing_screen] = ""
			screen_assignment_changed.emit(existing_screen, "")
	screen_venue_ids[screen] = venue_id
	screen_assignment_changed.emit(screen, venue_id)
	return true

## Called by TrackLobby's bet popup — WIN/PLACE/SHOW only (single horse_index,
## see class comment). Overwrites any previous bet on this venue's upcoming
## race, matching how the original single-track BettingUI also only ever
## tracked one in-flight bet at a time. Refuses once this venue's race has
## actually gone off (is_racing) — real pari-mutuel wagering closes at post
## time, and this venue's race may already be running invisibly in the
## background by the time a player opens the bet dialog on it.
func place_bet(venue_id: String, horse_index: int, bet_type: OddsTable.BetType, amount: int) -> bool:
	var state: VenueState = _venues[venue_id]
	if state.is_racing:
		return false
	if not state.bet.is_empty():
		Bankroll.pay(state.bet.amount) # refund the previous bet on THIS venue's upcoming race before replacing it — changing your pick shouldn't double-charge you
	if not Bankroll.place_bet(amount):
		if not state.bet.is_empty():
			Bankroll.place_bet(state.bet.amount) # couldn't afford the new amount — restore the old bet rather than leaving the player with neither
		return false
	state.bet = {"horse_index": horse_index, "bet_type": bet_type, "amount": amount}
	return true

## Every venue's race actually starts here, screen or no screen — see this
## file's own class comment. `state.result`/`race_bet_context` are stored
## (not just passed through locally) specifically so a screen assigned
## AFTER this point can still join via get_live_race() below.
func _start_race(state: VenueState) -> void:
	state.result = RaceSim.simulate(state.field, state.tiers)
	state.race_elapsed = 0.0
	state.is_racing = true
	state.race_bet_context = {}
	if not state.bet.is_empty():
		state.race_bet_context = {
			"bet_type": state.bet.bet_type, "horse_index": state.bet.horse_index, "second_index": -1,
			"picks": [state.bet.horse_index], "amount": state.bet.amount, "dd_leg": 0,
		}
	var screen: int = screen_venue_ids.find(state.venue_id)
	if screen != -1:
		race_ready.emit(state.venue_id, screen, state.result, state.race_bet_context)

## Read by TrackLobby when a screen gets assigned to a venue that's already
## `is_racing` (see screen_assignment_changed) — hands back the SAME result
## computed at post time plus how many real seconds have elapsed, so the new
## screen can seek RaceTrack3D straight to "wherever this actually is" rather
## than restarting the race from the gate. Empty dictionary if this venue
## isn't actually racing right now (nothing to join).
func get_live_race(venue_id: String) -> Dictionary:
	var state: VenueState = _venues[venue_id]
	if not state.is_racing or state.result == null:
		return {}
	return {"result": state.result, "bet_context": state.race_bet_context, "elapsed": state.race_elapsed}

## Only reached for a venue with no screen assigned when its race's real
## duration has fully elapsed — no playback at all, just a win/loss check +
## payout + a notification the lobby can surface (see background_result). A
## no-op if there was no bet either (nothing to resolve, nothing to notify
## about).
func _resolve_background(state: VenueState, result: RaceResult) -> void:
	if state.bet.is_empty():
		return
	var horse_index: int = state.bet.horse_index
	var bet_type: OddsTable.BetType = state.bet.bet_type
	var amount: int = state.bet.amount
	var won: bool = OddsTable.is_winning_bet(result.finish_order, horse_index, bet_type)
	var payout: int = 0
	if won:
		payout = OddsTable.payout(amount, result.field[horse_index].tier, bet_type)
	# Unconditional (payout is 0 on a loss) — see Bankroll.gd's place_bet
	# comment for why this is also the correct place went_broke fires from.
	Bankroll.pay(payout)
	var horse_name: String = state.field[horse_index].horse_name if horse_index < state.field.size() else "?"
	var description: String = "%s — %s %s on %s" % [
		Venues.label_for(state.venue_id), OddsTable.format_money(amount), OddsTable.bet_type_label(bet_type), horse_name,
	]
	background_result.emit(state.venue_id, description, won, payout)

## Called by a screen's watched-race flow (RaceTrack3D playback -> replay ->
## FinishPodium) once it's fully done with this venue's race and that screen
## is free again — draws a fresh field and starts this venue's next
## countdown. The watched flow resolves ITS OWN bet through the normal
## FinishPodium pipeline (every bet type, achievements, etc.) before calling
## this, when there was one; RaceScheduler never touches bet resolution for
## an on-screen venue.
func finish_watched_race(venue_id: String) -> void:
	var state: VenueState = _venues[venue_id]
	state.is_racing = false
	_reset_venue(state)

## Safety escape for InputHints' "Circle returns to title" — if ANY screen's
## venue was actually mid-flight (visual playback/podium never reached
## finish_watched_race normally, e.g. the player bailed out to the title
## screen mid-race), this unsticks ALL of them: without this those venues
## would stay paused (is_racing=true) forever, never resuming their
## countdowns even after coming back to the lobby later. A no-op for any
## venue that wasn't actually racing.
func force_finish_all_races() -> void:
	for venue_id in _venues.keys():
		var state: VenueState = _venues[venue_id]
		if state.is_racing:
			finish_watched_race(venue_id)

func _reset_venue(state: VenueState) -> void:
	state.bet = {}
	state.result = null
	state.race_elapsed = 0.0
	state.race_bet_context = {}
	_draw_field(state)
	state.countdown = POST_INTERVAL
	countdown_reset.emit(state.venue_id)

func _draw_field(state: VenueState) -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	state.field = roster.slice(0, 8)
	HorseRoster.assign_race_colors(state.field)
	state.tiers = OddsTable.assign_to_field(state.field.size())
	state.is_turf = randf() < TURF_CHANCE
