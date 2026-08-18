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
## Every venue with NO screen assigned, ticking down in the background
## regardless of what's on screen, resolves silently and instantly when its
## countdown hits zero: WIN/PLACE/SHOW bets only for now (v1 — the full
## Exacta/Trifecta/Daily-Double matrix stays exclusive to an on-screen venue;
## extending background resolution to every bet type is a reasonable
## fast-follow, not done here to keep this landable).

signal race_ready(venue_id: String, screen: int, result: RaceResult, bet_context: Dictionary)
signal background_result(venue_id: String, description: String, won: bool, payout: int)
signal countdown_reset(venue_id: String) # field/tiers redrawn — UI showing odds should refresh
signal screen_assignment_changed(screen: int, venue_id: String)

const POST_INTERVAL: float = 240.0 # 4 minutes between races per venue — TVG-plausible pacing
const SCREEN_COUNT: int = 4 # how many venues can get the full visual treatment AT ONCE — see TrackLobby's split-screen view

class VenueState:
	var venue_id: String
	var countdown: float = POST_INTERVAL
	var field: Array[Horse] = []
	var tiers: Array[Dictionary] = []
	var bet: Dictionary = {} # {} = no bet placed for the UPCOMING race at this venue
	var is_racing: bool = false # true while a screen's visual flow is playing this venue's race out — pauses ticking

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
			continue
		state.countdown -= delta
		if state.countdown <= 0.0:
			_on_post_time(state)

func get_countdown(venue_id: String) -> float:
	return max(0.0, _venues[venue_id].countdown)

func get_field(venue_id: String) -> Array[Horse]:
	return _venues[venue_id].field

func get_tiers(venue_id: String) -> Array[Dictionary]:
	return _venues[venue_id].tiers

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
## tracked one in-flight bet at a time.
func place_bet(venue_id: String, horse_index: int, bet_type: OddsTable.BetType, amount: int) -> bool:
	var state: VenueState = _venues[venue_id]
	if not state.bet.is_empty():
		Bankroll.pay(state.bet.amount) # refund the previous bet on THIS venue's upcoming race before replacing it — changing your pick shouldn't double-charge you
	if not Bankroll.place_bet(amount):
		if not state.bet.is_empty():
			Bankroll.place_bet(state.bet.amount) # couldn't afford the new amount — restore the old bet rather than leaving the player with neither
		return false
	state.bet = {"horse_index": horse_index, "bet_type": bet_type, "amount": amount}
	return true

func _on_post_time(state: VenueState) -> void:
	var result: RaceResult = RaceSim.simulate(state.field, state.tiers)
	var screen: int = screen_venue_ids.find(state.venue_id)
	if screen != -1:
		state.is_racing = true
		var bet_context: Dictionary = {}
		if not state.bet.is_empty():
			bet_context = {
				"bet_type": state.bet.bet_type, "horse_index": state.bet.horse_index, "second_index": -1,
				"picks": [state.bet.horse_index], "amount": state.bet.amount, "dd_leg": 0,
			}
		race_ready.emit(state.venue_id, screen, result, bet_context)
	else:
		_resolve_background(state, result)
		_reset_venue(state)

## Only reached for a venue with no screen assigned — no playback at all,
## just an instant win/loss check + payout + a notification the lobby can
## surface (see background_result). A no-op if there was no bet either
## (nothing to resolve, nothing to notify about).
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
	_draw_field(state)
	state.countdown = POST_INTERVAL
	countdown_reset.emit(state.venue_id)

func _draw_field(state: VenueState) -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	state.field = roster.slice(0, 8)
	HorseRoster.assign_race_colors(state.field)
	state.tiers = OddsTable.assign_to_field(state.field.size())
