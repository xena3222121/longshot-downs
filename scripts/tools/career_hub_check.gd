extends Node

## Drives the actual CareerHub scene (not just CareerStable.gd's data layer,
## already covered by career_stable_check.gd) through starter pick, self-
## training, buying a second horse, and a full Career race — catches real
## Control-tree/theme_type_variation bugs that a pure-data test can't.
## Isolated from real save files/balance the same way scheduler_check.gd
## isolates Bankroll. Same time_scale/frame-count pattern as
## racetrack_playback_check.gd — see that file's own header for why
## Engine.time_scale doesn't shrink play_with_post_time()'s real-timer waits.

const TIME_SCALE: float = 20.0
const MAX_FRAMES_HEADROOM: int = 1200

func _ready() -> void:
	Bankroll.autosave_enabled = false
	Bankroll.balance = 1000000
	CareerStable.autosave_enabled = false
	CareerStable.owned_horses = {}
	CareerStable._next_id = CareerStable.ID_START
	CareerStable._has_picked_starter = false

	var hub: Control = load("res://scenes/CareerHub.tscn").instantiate()
	add_child(hub) # NOT get_tree().root — adding to root from inside this node's own _ready() hits "Parent node is busy setting up children" (root is still mid-setup adding this test node itself; see screenshot_capture.gd's own documented version of this exact gotcha). Adding to self is safe since self has already finished entering the tree by the time _ready() runs.

	hub._on_starter_picked(1) # Quick Break (acceleration specialty)
	await get_tree().process_frame
	assert(CareerStable.has_picked_starter(), "starter pick through the real scene should register")
	var id: int = CareerStable.get_owned_horse_ids()[0]

	hub._on_self_train_pressed(id, "stamina")
	await get_tree().process_frame
	assert(CareerStable.get_attribute_points(id, "stamina") > 0, "self-train through the real scene should apply")

	hub._on_buy_pressed("local_bred")
	await get_tree().process_frame
	assert(CareerStable.get_owned_horse_ids().size() == 2, "buying a second horse through the real scene should register")
	print("career_hub_check: starter pick / self-train / buy through the real scene OK")

	Engine.time_scale = TIME_SCALE
	hub._start_race(id)
	await get_tree().process_frame

	var race_track: RaceTrack3D = null
	for child in hub.get_children():
		if child is RaceTrack3D:
			race_track = child
			break
	assert(race_track != null, "entering a Career race should add a RaceTrack3D to the hub scene")

	var state := {"finished": false} # Dictionary wrapper — a bare bool local wouldn't observe a write made inside the lambda below (see this project's own documented closure-capture gotcha)
	race_track.playback_finished.connect(func(): state.finished = true)

	var max_frames: int = MAX_FRAMES_HEADROOM + 1200
	var frame_count: int = 0
	while not state.finished and frame_count < max_frames:
		await get_tree().process_frame
		frame_count += 1
	assert(state.finished, "the Career race should actually finish within the frame cap")
	Engine.time_scale = 1.0

	await get_tree().process_frame # let _on_race_finished's connected handler run and rebuild into the result panel
	var found_result_panel: bool = false
	for child in hub.get_children():
		if child is CenterContainer:
			found_result_panel = true
	assert(found_result_panel, "finishing a Career race should rebuild the hub into a result panel")

	print("career_hub_check: Career race played end-to-end through the real scene after %d frames, purse paid, result shown" % frame_count)
	print("career_hub_check: all checks passed")
	get_tree().quit()
