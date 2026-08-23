class_name RaceAnnouncerDirector
extends RefCounted

## Turns raw per-tick race state (who's leading, who's surging, how far
## around the track the leader is) into broadcast-style play-by-play lines.
## Owned and driven by RaceTrack3D one call per frame, the same
## "RaceTrack3D delegates to a focused helper" shape it already uses for
## BroadcastHUD — this one owns commentary timing/phrasing instead of HUD
## layout. Every line goes to both Announcer.say (TTS, no-ops silently if
## unavailable) and BroadcastHUD.show_commentary (on-screen caption) so the
## call is always visible even with TTS off or muted.

const LEADER_CHANGE_COOLDOWN: float = 0.7
const LEADER_HOLD_TIME: float = 0.2 # a lead has to stick for a beat before it's worth calling — real
	# broadcasters don't call every hair's-width position swap in a bunched pack
const MOVE_COOLDOWN: float = 0.9
const MIN_LINE_GAP: float = 0.45 # floor between ANY two lines regardless of source — a real track
	# announcer is talking almost the entire race, not pausing between calls
const FILLER_INTERVAL: float = 1.2 # if nothing else has been said in this long, call the running order —
	# a real caller is never actually silent, even when nothing dramatic is happening

const TURNING_FOR_HOME_FRACTION: float = 0.80
const INTO_THE_STRETCH_FRACTION: float = 0.95
const DUEL_GAP_FRACTION: float = 0.012 # top two within this much of the lap = a real photo-finish duel

const LEADER_CALLS: Array[String] = [
	"%s takes over at the front!",
	"It's %s showing the way now!",
	"%s has the lead!",
	"%s pushes to the front of this field!",
	"%s finds room and grabs the lead!",
]
const MOVE_CALLS: Array[String] = [
	"%s is really turning it on!",
	"Look out, here comes %s!",
	"%s is flying on the outside!",
	"%s is asking for run and getting it!",
]
const TURN_CALLS: Array[String] = [
	"They're turning for home!",
	"Into the far turn they go!",
	"Around the final bend now!",
]
const STRETCH_CALLS: Array[String] = [
	"Down the stretch they come!",
	"It's the home stretch now!",
	"Into the final furlong!",
]
const DUEL_CALLS: Array[String] = [
	"This one's a blanket finish!",
	"Too close to call, folks!",
	"They're neck and neck to the wire!",
]
const WIN_CALLS: Array[String] = [
	"%s wins it!",
	"%s takes the race!",
	"And %s gets there first!",
]
const BLOWOUT_WIN_CALLS: Array[String] = [
	"%s wins it going away!",
	"%s runs away with this one!",
]
const PHOTO_WIN_CALLS: Array[String] = [
	"%s gets the nod in a photo finish!",
	"%s just gets there first — what a finish!",
]
const RACE_START_CALLS: Array[String] = [
	"And they're off!",
	"Here we go!",
	"They break from the gate!",
]
## Running-order filler, said whenever nothing else has come up in a while —
## keeps the call constant instead of going quiet between events. Needs at
## least 2 names; only the 3-name bank is used when a 3rd is available (see
## _update_filler_call).
const FILLER_CALLS_3: Array[String] = [
	"It's %s in front, %s and %s right there in behind.",
	"%s leads the way, tracked by %s and %s.",
	"%s sets the pace, with %s and %s chasing hard.",
	"Out front it's %s, %s close up, %s not far behind.",
]
const FILLER_CALLS_2: Array[String] = [
	"%s and %s battling up front.",
	"It's %s just ahead of %s.",
	"%s leads, %s right there with him.",
]

var _field: Array[Horse] = []
var _hud: BroadcastHUD

var _leader_index: int = -1
var _pending_leader_index: int = -1
var _leader_hold: float = 0.0
var _leader_cooldown: float = 0.0
var _move_cooldown: float = 0.0
var _line_gap: float = 0.0
var _filler_timer: float = 0.0
var _announced_turn: bool = false
var _announced_stretch: bool = false
var _announced_duel: bool = false

## Live-toggleable by RaceTrack3D/TrackLobby (not just set once in setup) —
## with several venues racing at once on separate screens, only the one
## screen the player has audio focus on should ever actually speak/play a
## crowd cue; the others still narrate their own on-screen caption via _say's
## hud.show_commentary call below, just silently.
var has_audio_focus: bool = true

func setup(p_field: Array[Horse], p_hud: BroadcastHUD) -> void:
	_field = p_field
	_hud = p_hud

func race_start() -> void:
	_say(RACE_START_CALLS.pick_random(), true)

func update(delta: float, fractions: PackedFloat32Array) -> void:
	_leader_cooldown = max(0.0, _leader_cooldown - delta)
	_move_cooldown = max(0.0, _move_cooldown - delta)
	_line_gap = max(0.0, _line_gap - delta)
	_filler_timer += delta

	var order: Array[int] = _sorted_indices(fractions)
	var leader: int = order[0]

	_update_leader_call(delta, leader)
	_update_phase_calls(fractions[leader])
	_update_duel_call(order, fractions)
	_update_filler_call(order)

## Running-order filler — only fires after FILLER_INTERVAL seconds of actual
## silence (see _say resetting _filler_timer on every line, not just this
## one), so it fills genuine dead air rather than piling onto other calls.
func _update_filler_call(order: Array[int]) -> void:
	if _filler_timer < FILLER_INTERVAL or order.size() < 2:
		return
	if order.size() >= 3:
		var names3: Array = [_field[order[0]].horse_name, _field[order[1]].horse_name, _field[order[2]].horse_name]
		_say(FILLER_CALLS_3.pick_random() % names3)
	else:
		var names2: Array = [_field[order[0]].horse_name, _field[order[1]].horse_name]
		_say(FILLER_CALLS_2.pick_random() % names2)

func _update_leader_call(delta: float, leader: int) -> void:
	if leader == _leader_index:
		_pending_leader_index = -1
		_leader_hold = 0.0
		return
	if leader != _pending_leader_index:
		_pending_leader_index = leader
		_leader_hold = 0.0
	_leader_hold += delta
	if _leader_hold < LEADER_HOLD_TIME or _leader_cooldown > 0.0:
		return
	_leader_index = leader
	_leader_cooldown = LEADER_CHANGE_COOLDOWN
	_say(LEADER_CALLS.pick_random() % _field[leader].horse_name)

func _update_phase_calls(leader_fraction: float) -> void:
	if not _announced_turn and leader_fraction >= TURNING_FOR_HOME_FRACTION:
		_announced_turn = true
		_say(TURN_CALLS.pick_random())
	if not _announced_stretch and leader_fraction >= INTO_THE_STRETCH_FRACTION:
		_announced_stretch = true
		_say(STRETCH_CALLS.pick_random())

func _update_duel_call(order: Array[int], fractions: PackedFloat32Array) -> void:
	if _announced_duel or order.size() < 2:
		return
	if fractions[order[0]] < INTO_THE_STRETCH_FRACTION:
		return
	if fractions[order[0]] - fractions[order[1]] <= DUEL_GAP_FRACTION:
		_announced_duel = true
		_say(DUEL_CALLS.pick_random(), false, true)
		if has_audio_focus:
			AudioManager.play_crowd_reaction(0.7)

## Fired by RaceTrack3D the moment a horse's surge crosses BIG_SURGE_THRESHOLD
## (same edge-trigger RaceTrack3D already uses for the camera punch) — shares
## its own cooldown rather than MIN_LINE_GAP's so a flurry of simultaneous
## surges doesn't turn into a wall of move-calls.
func on_big_move(horse_index: int) -> void:
	if _move_cooldown > 0.0:
		return
	_move_cooldown = MOVE_COOLDOWN
	_say(MOVE_CALLS.pick_random() % _field[horse_index].horse_name)

func on_finish(result: RaceResult) -> void:
	if result.finish_order.is_empty():
		return
	var winner: Horse = _field[result.finish_order[0]]
	var margin: float = 0.0
	if result.finish_order.size() > 1:
		margin = result.field[result.finish_order[1]].finish_time - result.field[result.finish_order[0]].finish_time

	var bank: Array[String] = WIN_CALLS
	if margin < FinishPodium.PHOTO_FINISH_MARGIN:
		bank = PHOTO_WIN_CALLS
	elif margin > FinishPodium.RUNAWAY_MARGIN:
		bank = BLOWOUT_WIN_CALLS
	# No crowd_reaction here (unlike _update_duel_call) — FinishPodium already
	# plays its own finish_fanfare/crowd_cheer moments after this fires, and
	# stacking a second full-volume crowd cheer right on top of that one is
	# exactly what made the finish read as "crazy loud."
	_say(bank.pick_random() % winner.horse_name, true, true)

func _sorted_indices(fractions: PackedFloat32Array) -> Array[int]:
	var order: Array[int] = []
	for i in range(fractions.size()):
		order.append(i)
	order.sort_custom(func(a, b): return fractions[a] > fractions[b])
	return order

func _say(text: String, force: bool = false, excited: bool = false) -> void:
	if not force:
		if _line_gap > 0.0:
			return
		# Waits for the CURRENT clip to actually finish, not just MIN_LINE_GAP,
		# before firing the next line — cranking the calling frequency up
		# without this just meant every new line cut the previous one off
		# mid-word every ~0.5s (talking constantly, but as noise). Only
		# applies when this screen actually has audio focus; an unfocused
		# background screen has no clip playing at all, so MIN_LINE_GAP alone
		# still paces its captions.
		if has_audio_focus and Announcer.is_speaking():
			return
	_line_gap = MIN_LINE_GAP
	_filler_timer = 0.0
	if has_audio_focus:
		Announcer.say(text, excited)
	if _hud != null:
		_hud.show_commentary(text)
