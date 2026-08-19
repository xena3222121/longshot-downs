class_name RaceTrack3D
extends Node3D

## 3D counterpart of the old RaceView.gd. Same stadium/oval parametric track
## (position for any lane at any lap fraction via one radius-parameterized
## function — offsetting the curve outward by a constant distance yields
## another curve of the same shape, so every lane reuses _sample_track
## unchanged) — just mapped onto the XZ ground plane instead of a 2D
## canvas, with Node3D.look_at used for facing instead of a hand-derived
## heading formula (sidesteps guessing Godot's rotation-sign convention).

signal playback_finished
signal replay_finished

## Scaled up alongside RaceSim.TRACK_LENGTH/DISTANCE_PER_STAMINA (see that
## file) so a real ~60s race corresponds to an actually-longer physical
## track, not the old ~13s race artificially slowed down for viewing —
## horses cover more real ground in more real time at their natural gait
## speed, instead of the same short track played back in slow motion.
##
## Per-VENUE now (see Venues.gd / _apply_venue), not fixed constants — the
## multi-track scheduler gives each venue its own straight/turn proportions,
## same math (4-segment stadium) just a different aspect ratio. Defaults
## below match Longshot Downs exactly, so any caller that never sets a venue
## (every dev tool in scripts/tools/, which only ever call
## RaceTrack3D.setup(field, result) with no venue_id) behaves identically to
## before this existed.
var STRAIGHT_LEN: float = 140.0
var INNER_RADIUS: float = 26.0
const LANE_GAP: float = 2.6
const RAIL_GAP: float = 1.4
const RAIL_HEIGHT: float = 0.6

## Per-theme colors (see TrackThemes / _apply_theme) rather than consts — the
## night "synthetic track under floodlights" look is now just one of
## Settings.track_theme_id's presets, not the only option. RAIL_COLOR stays
## emissive by default regardless of which theme is active (see
## _make_rail_mesh) so it reads as a glowing boundary strip rather than a
## painted fence in every theme — the bloom pass (_build_lighting's
## env.glow_enabled) is what turns that emission into a genuine neon glow.
var RAIL_COLOR: Color
var TRACK_SURFACE_COLOR: Color
var INFIELD_COLOR: Color
const LOOP_SAMPLES: int = 96

const FINISH_LINE_WIDTH: float = 3.0 # along the direction of travel
const FINISH_LINE_ROWS: int = 2 # tiles along the direction of travel
const FINISH_LINE_COLS: int = 10 # tiles across the track's width
const FINISH_LINE_Y: float = 0.02 # just above the dirt ring mesh, avoids z-fighting

## Broadcast-style chase camera: rides a virtual rail outside the track,
## always facing the pack, smoothly panning to follow the race rather than
## sitting on one static wide shot.
const CAMERA_RAIL_OFFSET: float = 20.0
const CAMERA_HEIGHT: float = 13.0
const CAMERA_SMOOTH_SPEED: float = 3.0

## "Arcade excess" pass: react visibly when a horse's RaceSim surge crosses
## into "making a big move" territory instead of only letting it show up as
## a subtle position change. Edge-triggered with hysteresis (fires once
## crossing BIG_SURGE_THRESHOLD, doesn't re-fire until dropping back below
## BIG_SURGE_RESET_THRESHOLD) — tuned via scripts/tools/ so this fires ~5
## times/race (roughly once every 8-10s), not constantly. SURGING_THRESHOLD
## is a lower, non-edge-triggered bar purely for the continuous particle
## trail (see HorseMarker3D.set_surging), so the trail reads as "still going"
## across the whole surge, not just its single peak-crossing moment.
const BIG_SURGE_THRESHOLD: float = 20.0
const BIG_SURGE_RESET_THRESHOLD: float = 10.0
const SURGING_THRESHOLD: float = 8.0

const CAMERA_SHAKE_DURATION: float = 0.35
const CAMERA_SHAKE_MAGNITUDE: float = 0.5 # world units of random jitter at peak
const CAMERA_PUNCH_DURATION: float = 0.6
const CAMERA_PUNCH_FOV_DELTA: float = -6.0 # negative = zoom in (lower FOV)

var result: RaceResult
var field: Array[Horse] = []
var _bet_context: Dictionary = {} # see BroadcastHUD._build_bet_panel — what the player actually wagered on THIS race
var horse_nodes: Array[HorseMarker3D] = []
var frame_index: int = 0
var playback_time: float = 0.0
var playing: bool = false

var camera: Camera3D
var camera_base_fov: float = 50.0
var camera_focus_fraction: float = 0.0
var camera_look_target: Vector3 = Vector3.ZERO
var _camera_shake_time: float = 0.0
var _camera_punch_time: float = 0.0

var broadcast_hud: BroadcastHUD
var announcer_director: RaceAnnouncerDirector
var _was_big_surging: Array[bool] = []

var _theme: Dictionary = {}
var _venue_id: String = "" # "" = no venue set, single-race mode — falls back to Settings.track_theme_id exactly like before Venues existed

## With several venues racing simultaneously on separate TrackLobby screens,
## only ONE of them should ever actually be heard (TTS/ambience/gate SFX) —
## otherwise every screen's announcer/crowd/bell talks over the others at
## once. Defaults true so single-race/dev-tool usage (no TrackLobby involved)
## is unaffected; TrackLobby passes this explicitly per screen and can flip it
## live via set_audio_focus as the player switches which screen they're
## listening to.
var has_audio_focus: bool = true

func setup(p_field: Array[Horse], p_result: RaceResult, bet_context: Dictionary = {}, venue_id: String = "", p_has_audio_focus: bool = true) -> void:
	field = p_field
	result = p_result
	_bet_context = bet_context
	_venue_id = venue_id
	has_audio_focus = p_has_audio_focus
	if venue_id != "":
		var venue: Dictionary = Venues.get_venue(venue_id)
		STRAIGHT_LEN = float(venue.get("straight_len", 140.0))
		INNER_RADIUS = float(venue.get("inner_radius", 26.0))
	_build_scene()

## Called live by TrackLobby when the player switches which screen they're
## listening to — immediately silences/resumes this screen's continuous
## ambience bed rather than waiting for the next race to pick up the change.
## One-shot cues (gate bell, replay whoosh) just check has_audio_focus at the
## moment they'd fire, no special handling needed here.
func set_audio_focus(focused: bool) -> void:
	if focused == has_audio_focus:
		return
	has_audio_focus = focused
	if announcer_director != null:
		announcer_director.has_audio_focus = focused
	if focused:
		if playing:
			AudioManager.start_race_ambience()
	else:
		AudioManager.stop_race_ambience()

## Pulls every color/light value this track's visuals depend on from either
## the active venue's own fixed theme (see Venues.gd — a real venue always
## looks like itself, not whatever the player's cosmetic Settings choice
## happens to be) or, with no venue set, Settings.track_theme_id exactly like
## before Venues existed. Called once per race, before any of the _build_*
## functions that read them, so a mid-race Settings change never half-applies
## to a track that's already built.
func _apply_theme() -> void:
	var theme_id: String = Settings.track_theme_id
	if _venue_id != "":
		theme_id = String(Venues.get_venue(_venue_id).get("theme_id", TrackThemes.DEFAULT_THEME_ID))
	_theme = TrackThemes.get_theme(theme_id)
	RAIL_COLOR = _theme.rail_color
	TRACK_SURFACE_COLOR = _theme.track_surface_color
	INFIELD_COLOR = _theme.infield_color
	FLOODLIGHT_COLOR = _theme.floodlight_color
	FLOODLIGHT_ENERGY = _theme.floodlight_energy
	GRANDSTAND_COLOR_LOWER = _theme.grandstand_lower
	GRANDSTAND_COLOR_UPPER = _theme.grandstand_upper
	GRANDSTAND_ROOF_COLOR = _theme.grandstand_roof
	GRANDSTAND_TRIM_COLOR = _theme.trim_color
	var themed_flags: Array[Color] = []
	for c in _theme.flag_colors:
		themed_flags.append(c)
	FLAG_COLORS = themed_flags

func _lane_radius(lane_index: int) -> float:
	return INNER_RADIUS + lane_index * LANE_GAP

## Per-horse radius from a dynamic lane offset (RaceResult.lane_offsets, in
## abstract lane units) rather than a fixed per-horse index — this is what
## lets horses converge toward the rail in single file when there's daylight
## between them and only fan out across lanes when actually contesting the
## same patch of track. _lane_radius above is still used for track geometry
## sizing (the widest a horse can ever be pushed out is field.size()-1 lanes).
func _dynamic_radius(lane_offset: float) -> float:
	return INNER_RADIUS + lane_offset * LANE_GAP

func _build_scene() -> void:
	for child in get_children():
		child.queue_free()
	horse_nodes.clear()
	_camera_shake_time = 0.0
	_camera_punch_time = 0.0

	_apply_theme()
	_build_lighting()
	_build_track_visual()
	_build_environment()
	_build_camera()

	var venue_label: String = "LONGSHOT DOWNS"
	if _venue_id != "":
		venue_label = Venues.label_for(_venue_id).to_upper()

	broadcast_hud = BroadcastHUD.new()
	add_child(broadcast_hud)
	broadcast_hud.setup(field, result, _bet_context, STRAIGHT_LEN, INNER_RADIUS, venue_label)

	announcer_director = RaceAnnouncerDirector.new()
	announcer_director.setup(field, broadcast_hud)
	announcer_director.has_audio_focus = has_audio_focus

	_was_big_surging.resize(field.size())
	_was_big_surging.fill(false)

	# No focused Control exists during the race at all (see InputHints'
	# generic focus-based gate) — visible_without_focus=true is what keeps
	# these shown here.
	InputHints.set_context_hints([
		{"button": "Y", "ps_button": "△", "label": "Camera View"},
		{"button": "R-Stick/RT-LT", "ps_button": "R-Stick/R2-L2", "label": "Look/Zoom"},
	], true)

	for i in range(field.size()):
		var horse: Horse = field[i]
		var start_offset: float = result.lane_offsets[0][i]
		var start_pos: Vector3 = _sample_track(0.0, _dynamic_radius(start_offset)).position
		var ahead_pos: Vector3 = _sample_track(0.001, _dynamic_radius(start_offset)).position

		var marker := HorseMarker3D.new()
		add_child(marker)
		marker.setup(horse.silk_primary, horse.silk_secondary)
		marker.position = start_pos
		if start_pos.distance_to(ahead_pos) > 0.0001:
			marker.look_at(global_position + ahead_pos, Vector3.UP)
		horse_nodes.append(marker)

## Night race under stadium floodlights, not daytime — a dim, cool-tinted
## "moonlight" DirectionalLight3D provides only enough fill light to keep
## shadow-side detail readable; FLOODLIGHT_COUNT SpotLight3Ds ringing the
## track (see _build_floodlights) do the actual heavy lifting, the same way
## a real night meet is lit almost entirely by the tower lights rather than
## ambient sky light. That contrast (dark sky, bright pools of light on the
## track) plus env.glow_enabled is what sells "broadcast night race" instead
## of "daytime scene with the brightness turned down."
const FLOODLIGHT_COUNT: int = 6
const FLOODLIGHT_HEIGHT: float = 22.0
const FLOODLIGHT_MARGIN: float = 6.0 # beyond the outer rail
var FLOODLIGHT_COLOR: Color
var FLOODLIGHT_ENERGY: float

const MOON_DISTANCE: float = 450.0
const MOON_RADIUS: float = 18.0
const MOON_COLOR: Color = Color(0.85, 0.87, 0.95)

## A visible disc explaining where the key light is actually coming from —
## the DirectionalLight3D itself has no visual representation, so the sky
## previously had a light source with no visible object behind it. Uses
## `sun.basis` (local rotation, set two lines up) rather than
## `global_transform` so this doesn't depend on `sun` already being inside
## the live SceneTree — safe to call immediately after constructing it.
func _build_moon(sun: DirectionalLight3D) -> void:
	var moon := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = MOON_RADIUS
	mesh.height = MOON_RADIUS * 2.0
	moon.mesh = mesh
	var direction: Vector3 = -sun.basis.z.normalized()
	moon.position = -direction * MOON_DISTANCE + Vector3(0.0, MOON_DISTANCE * 0.35, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = MOON_COLOR
	mat.emission_enabled = true
	mat.emission = MOON_COLOR
	mat.emission_energy_multiplier = 1.6
	moon.material_override = mat
	add_child(moon)

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_color = _theme.sun_color
	sun.light_energy = _theme.sun_energy
	sun.shadow_enabled = true
	add_child(sun)
	_build_moon(sun)

	_build_floodlights()

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = _theme.sky_top
	sky_material.sky_horizon_color = _theme.sky_horizon
	sky_material.ground_bottom_color = _theme.ground_bottom
	sky_material.ground_horizon_color = _theme.ground_horizon
	sky_material.sky_curve = 0.15 # keeps most of the dome close to its top color instead of washing out toward the horizon
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	# Deliberately NOT sky-sourced ambient: at night the sky itself is
	# near-black, and floodlight pools only cover part of the track (see
	# _build_floodlights) — sky-sourced ambient would scale that same
	# near-zero sky color, leaving the gaps between light pools essentially
	# unlit and the field unreadable whenever the pack isn't directly under a
	# tower. A flat, explicit per-theme ambient color guarantees a visible
	# baseline everywhere on the track regardless of camera angle or which
	# floodlight is nearest, while the floodlights/emission still add real
	# highlights and shadow contrast on top of it.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _theme.ambient_color
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# Bloom is what turns the rail/pylon/finish-line emission and the
	# floodlights themselves into an actual neon glow instead of just a flat
	# bright color — tuned low-threshold/moderate-strength so only genuinely
	# bright (emissive or floodlit) surfaces bleed light, not the whole scene.
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.ssao_enabled = true
	env.ssao_intensity = 1.4
	env.ssil_enabled = true

	# Punchier, more "broadcast color grade" contrast/saturation than the
	# tonemapper alone gives — cheap, engine-native alternative to a
	# hand-authored color-grading LUT.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.18

	env_node.environment = env
	add_child(env_node)

	# The floodlights are angled ~32° down at the track surface for a good
	# ground-level broadcast/jockey look — from straight overhead that's
	# almost grazing incidence on a horse's back, so the overhead camera
	# would otherwise read as near-black. A brighter duplicate Environment,
	# assigned only to the camera while in overhead mode (see
	# _apply_camera_environment), fixes that without touching how every
	# other camera mode is lit.
	_overhead_environment = env.duplicate()
	# Absolute values, not a multiplier on the theme's own (often very dark —
	# night/storm themes especially) ambient color: a relative boost was
	# still nearly unreadable from directly overhead, since a small dark
	# color times a few stays small. A bright, theme-independent flat fill
	# guarantees the top-down read works the same in every theme. SSAO also
	# gets disabled here — contact shadowing under near-flat top lighting
	# just re-darkens the exact areas this is trying to brighten.
	_overhead_environment.ambient_light_color = Color(0.85, 0.88, 0.92)
	_overhead_environment.ambient_light_energy = 2.4
	_overhead_environment.ssao_enabled = false
	_overhead_environment.adjustment_brightness = 1.3

## Ring of SpotLight3Ds standing in for stadium light towers — angled inward
## and down at the track so their cones overlap over the racing surface
## rather than each other's poles. Purely lighting fixtures (no visible pole
## mesh yet; the glow bloom on the cone itself already reads as a light
## source) so field.size() changing the track's outer radius just means the
## ring scales with it, same as the rail/flags already do.
func _build_floodlights() -> void:
	var outer_radius: float = _lane_radius(max(field.size() - 1, 0)) + RAIL_GAP
	var tower_radius: float = outer_radius + FLOODLIGHT_MARGIN
	for i in range(FLOODLIGHT_COUNT):
		var frac: float = float(i) / float(FLOODLIGHT_COUNT)
		var base_pos: Vector3 = _sample_track(frac, tower_radius).position
		var target_pos: Vector3 = _sample_track(frac, tower_radius * 0.55).position

		var light := SpotLight3D.new()
		light.light_color = FLOODLIGHT_COLOR
		light.light_energy = FLOODLIGHT_ENERGY
		light.spot_range = FLOODLIGHT_HEIGHT * 2.2
		light.spot_angle = 32.0
		light.spot_angle_attenuation = 1.6
		light.shadow_enabled = i % 2 == 0 # alternating shadow casters — full ring of shadow lights is needlessly expensive
		add_child(light) # must be in the tree before look_at — it needs a global transform to compute against
		light.position = base_pos + Vector3(0.0, FLOODLIGHT_HEIGHT, 0.0)
		light.look_at(target_pos, Vector3.UP)

func _build_camera() -> void:
	_camera_mode = Settings.camera_mode
	camera = Camera3D.new()
	camera.fov = camera_base_fov
	add_child(camera)
	_apply_camera_environment()

	var outer_radius: float = _lane_radius(field.size() - 1) + RAIL_GAP
	var rail_radius: float = outer_radius + CAMERA_RAIL_OFFSET
	camera_focus_fraction = 0.0
	camera_look_target = _sample_track(0.0, INNER_RADIUS * 0.5).position
	camera.position = _sample_track(0.0, rail_radius).position + Vector3(0.0, CAMERA_HEIGHT, 0.0)
	camera.look_at(camera_look_target, Vector3.UP)
	camera.current = true

## "Riders up... post time..." beat before the race actually starts —
## real broadcasts don't cut straight from the odds board to a running
## race. Awaits BroadcastHUD's countdown display, then fires the gate SFX
## and the announcer's opening call at the exact moment `play()` starts
## ticking frames, instead of firing them the instant the track is built.
func play_with_post_time() -> void:
	await broadcast_hud.play_post_time_sequence()
	if has_audio_focus:
		AudioManager.play_sfx("race_start_bell")
		AudioManager.play_sfx("horse_neigh")
	InputHints.rumble(0.3, 0.55, 0.3) # gate-open thump, felt not just heard on a connected controller
	announcer_director.race_start()
	play()

func play() -> void:
	frame_index = 0
	playback_time = 0.0
	playing = true
	if has_audio_focus:
		AudioManager.start_race_ambience()

func _process(delta: float) -> void:
	if not playing or result == null or result.frames.is_empty():
		return

	playback_time += delta
	var max_index: int = result.frames.size() - 1
	var raw_tick: float = playback_time / RaceSim.DT
	frame_index = min(int(raw_tick), max_index)
	var frac: float = clamp(raw_tick - frame_index, 0.0, 1.0)

	# RaceSim only computes a new position 20 times/sec (DT=0.05); rendering
	# runs much faster than that, so snapping straight to result.frames[i]
	# would hold each position for several rendered frames then jump to the
	# next — a classic fixed-timestep stutter. Interpolating between the
	# current and next simulation tick every rendered frame (both here and
	# in the camera below, from the same values, so they never desync) gives
	# genuinely smooth motion regardless of display refresh rate.
	var fractions: PackedFloat32Array = _interpolated(result.frames, frame_index, frac, max_index)
	var offsets: PackedFloat32Array = _interpolated(result.lane_offsets, frame_index, frac, max_index)
	var surges: PackedFloat32Array = _interpolated(result.surges, frame_index, frac, max_index)
	var speeds: PackedFloat32Array = _interpolated(result.speeds, frame_index, frac, max_index)
	_apply_frame(fractions, offsets)
	_apply_gait_speeds(speeds)
	_handle_surges(surges)
	_update_camera(delta, fractions)
	broadcast_hud.update(delta, playback_time, fractions)
	announcer_director.update(delta, fractions)

	if frame_index >= max_index:
		playing = false
		if has_audio_focus:
			AudioManager.stop_race_ambience()
		announcer_director.on_finish(result)
		InputHints.clear_context_hints() # the podium overlay's own buttons take over Select/Back next; camera hints no longer apply
		playback_finished.emit()

const REPLAY_TICKS_BACK: int = 100 # ~5 in-race seconds (RaceSim.DT * 100) replayed, not the whole race
const REPLAY_TIME_SCALE: float = 0.5 # slow-mo — half real-time speed
const REPLAY_CAMERA_HEIGHT: float = 4.5
const REPLAY_CAMERA_BACK: float = 14.0

## TVG-style "here's the stretch run again" replay: re-plays the final
## REPLAY_TICKS_BACK ticks of ALREADY-SIMULATED frame data (no re-simulation,
## just re-reading result.frames — the finish order/payout were already
## decided the instant RaceSim.simulate returned) from a fixed low
## finish-line camera, in slow motion, then hands back to Main.gd to build
## the podium. Reuses _interpolated/_apply_frame exactly like live playback
## (see _process) for the same tick-to-tick smoothness, just driven by a
## local slow-motion virtual clock instead of `playback_time` — `playing` is
## already false by the time Main.gd calls this (playback_finished only
## fires after _process sets it false), so there's no risk of this and the
## live per-frame update running against the same horses/camera at once.
func play_replay() -> void:
	if result == null or result.frames.is_empty() or camera == null:
		replay_finished.emit()
		return

	if broadcast_hud != null:
		broadcast_hud.show_commentary("REPLAY")
	if has_audio_focus:
		AudioManager.play_sfx("whoosh")

	var max_index: int = result.frames.size() - 1
	var start_index: int = max(0, max_index - REPLAY_TICKS_BACK)

	var infield_radius: float = INNER_RADIUS - RAIL_GAP
	var outer_radius: float = _lane_radius(field.size() - 1) + RAIL_GAP
	var finish_point: Vector3 = _sample_track(0.0, (infield_radius + outer_radius) * 0.5).position
	camera.position = _sample_track(-0.02, outer_radius + REPLAY_CAMERA_BACK).position + Vector3(0.0, REPLAY_CAMERA_HEIGHT, 0.0)
	camera.fov = camera_base_fov
	camera.look_at(finish_point, Vector3.UP)

	var virtual_time: float = start_index * RaceSim.DT
	var end_time: float = max_index * RaceSim.DT
	while virtual_time < end_time:
		await get_tree().process_frame
		virtual_time += get_process_delta_time() * REPLAY_TIME_SCALE
		var clamped_time: float = min(virtual_time, end_time)
		var raw_tick: float = clamped_time / RaceSim.DT
		var index: int = clamp(int(raw_tick), start_index, max_index)
		var frac: float = clamp(raw_tick - index, 0.0, 1.0)
		var fractions: PackedFloat32Array = _interpolated(result.frames, index, frac, max_index)
		var offsets: PackedFloat32Array = _interpolated(result.lane_offsets, index, frac, max_index)
		var speeds: PackedFloat32Array = _interpolated(result.speeds, index, frac, max_index)
		_apply_frame(fractions, offsets)
		_apply_gait_speeds(speeds, REPLAY_TIME_SCALE)
		camera.look_at(finish_point, Vector3.UP)

	replay_finished.emit()

## Generic per-tick interpolation, shared by fraction-along-track and
## lane-offset series — both are PackedFloat32Array-per-tick data recorded at
## RaceSim's fixed DT, and both need the same "current tick lerped toward the
## next tick" smoothing to avoid the fixed-timestep stutter described above.
func _interpolated(series: Array[PackedFloat32Array], index: int, frac: float, max_index: int) -> PackedFloat32Array:
	var current: PackedFloat32Array = series[index]
	if frac <= 0.0 or index >= max_index:
		return current
	var next_tick: PackedFloat32Array = series[index + 1]
	var out := PackedFloat32Array()
	out.resize(current.size())
	for i in range(current.size()):
		out[i] = lerp(current[i], next_tick[i], frac)
	return out

func _apply_frame(fractions: PackedFloat32Array, offsets: PackedFloat32Array) -> void:
	for i in range(horse_nodes.size()):
		var radius: float = _dynamic_radius(offsets[i])
		var f: float = fractions[i]
		var pos: Vector3 = _sample_track(f, radius).position
		var ahead: Vector3 = _sample_track(f + 0.001, radius).position
		horse_nodes[i].position = pos
		if pos.distance_to(ahead) > 0.0001:
			horse_nodes[i].look_at(global_position + ahead, Vector3.UP)

## Drives each horse's leg-cycle rate off its actual recorded speed that
## tick (see RaceResult.speeds / HorseMarker3D.set_gait_speed) instead of
## every horse animating at one fixed cadence regardless of whether it's
## surging, fatigued, or easing to a stop after the finish.
func _apply_gait_speeds(speeds: PackedFloat32Array, time_scale: float = 1.0) -> void:
	for i in range(horse_nodes.size()):
		horse_nodes[i].set_gait_speed(speeds[i], time_scale)

## "Arcade excess" pass: drives each horse's continuous surge particle trail
## (HorseMarker3D.set_surging) every frame, and edge-triggers the one-shot
## "big move" camera punch (see _trigger_big_move) the moment a horse's
## surge first crosses BIG_SURGE_THRESHOLD. Hysteresis
## (BIG_SURGE_RESET_THRESHOLD, well below the trigger threshold) stops it
## re-firing every frame while a horse just sits above the threshold,
## without needing to track exact crossing ticks.
func _handle_surges(surges: PackedFloat32Array) -> void:
	for i in range(horse_nodes.size()):
		horse_nodes[i].set_surging(surges[i] > SURGING_THRESHOLD)

		if surges[i] > BIG_SURGE_THRESHOLD and not _was_big_surging[i]:
			_was_big_surging[i] = true
			_trigger_big_move(i)
		elif surges[i] < BIG_SURGE_RESET_THRESHOLD:
			_was_big_surging[i] = false

## One horse just started a big surge — a punchy camera shake / quick FOV
## zoom-in, both eased back out over CAMERA_SHAKE_DURATION/
## CAMERA_PUNCH_DURATION in _update_camera.
func _trigger_big_move(horse_index: int) -> void:
	_camera_shake_time = CAMERA_SHAKE_DURATION
	_camera_punch_time = CAMERA_PUNCH_DURATION
	InputHints.rumble(0.15, 0.35, CAMERA_SHAKE_DURATION) # same window as the camera shake it's paired with
	announcer_director.on_big_move(horse_index)

## Three selectable camera rigs (see CAMERA_MODE_ORDER) sharing one dispatch
## point — every _process caller (and the replay system) just calls
## _update_camera and doesn't need to know which rig is active.
const CAMERA_MODE_ORDER: Array[String] = ["broadcast", "overhead", "jockey"]
var _camera_mode: String = "broadcast"
var _overhead_environment: Environment

## Right-stick "look around" + trigger zoom for the broadcast camera only —
## the broadcast rig is a dolly riding a virtual rail around the track (see
## _update_camera_broadcast), so the natural free-look control for THIS rig
## is nudging how far ahead of/behind the pack along that rail the camera
## sits, plus a height offset and an FOV-based zoom, rather than an arbitrary
## free-fly orbit that rig was never built to support. Read directly via
## Input.get_joy_axis (no InputMap action) for the same reason
## _unhandled_input's camera-cycle check reads raw button indices — this
## project has no [input] section in project.godot and avoids adding one.
## Purely additive on top of the automatic tracking: with the stick/triggers
## at rest every offset eases back to exactly 0, so a player who never
## touches the right stick sees identical behavior to before this existed.
const FREE_LOOK_FRACTION_RANGE: float = 0.035 # ~13 degrees of extra look-ahead/behind along the rail
const FREE_LOOK_HEIGHT_RANGE: float = 6.0
const FREE_LOOK_FOV_RANGE: float = 10.0
const FREE_LOOK_DEADZONE: float = 0.15
const FREE_LOOK_EASE_SPEED: float = 3.0

var _free_look_fraction_offset: float = 0.0
var _free_look_height_offset: float = 0.0
var _free_look_fov_offset: float = 0.0

## Always runs (called once per frame from _update_camera before the mode
## dispatch) so the offsets keep easing back to 0 even while a different
## camera mode is active — without this, switching away from broadcast mid
## stick-push would freeze the offsets at whatever they last were, then pop
## visibly the instant the player cycles back to broadcast.
func _update_free_look(delta: float) -> void:
	var joypads: Array = Input.get_connected_joypads()
	if _camera_mode != "broadcast" or joypads.is_empty():
		var ease_t: float = 1.0 - exp(-delta * FREE_LOOK_EASE_SPEED)
		_free_look_fraction_offset = lerp(_free_look_fraction_offset, 0.0, ease_t)
		_free_look_height_offset = lerp(_free_look_height_offset, 0.0, ease_t)
		_free_look_fov_offset = lerp(_free_look_fov_offset, 0.0, ease_t)
		return

	var device: int = joypads[0]
	var stick_x: float = Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
	var stick_y: float = Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
	if absf(stick_x) < FREE_LOOK_DEADZONE:
		stick_x = 0.0
	if absf(stick_y) < FREE_LOOK_DEADZONE:
		stick_y = 0.0
	var zoom_in: float = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	var zoom_out: float = Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)

	var target_fraction_offset: float = stick_x * FREE_LOOK_FRACTION_RANGE
	var target_height_offset: float = -stick_y * FREE_LOOK_HEIGHT_RANGE # stick up (negative Y) raises the camera
	var target_fov_offset: float = (zoom_out - zoom_in) * FREE_LOOK_FOV_RANGE # trigger held all the way = ±FREE_LOOK_FOV_RANGE

	var t: float = 1.0 - exp(-delta * FREE_LOOK_EASE_SPEED)
	_free_look_fraction_offset = lerp(_free_look_fraction_offset, target_fraction_offset, t)
	_free_look_height_offset = lerp(_free_look_height_offset, target_height_offset, t)
	_free_look_fov_offset = lerp(_free_look_fov_offset, target_fov_offset, t)

## Only the overhead cam needs its own brighter Environment override (see
## _build_lighting's _overhead_environment comment) — every other mode clears
## the override back to null so it inherits the normal WorldEnvironment.
func _apply_camera_environment() -> void:
	camera.environment = _overhead_environment if _camera_mode == "overhead" else null

func _update_camera(delta: float, fractions: PackedFloat32Array) -> void:
	if camera == null:
		return
	_update_free_look(delta)
	match _camera_mode:
		"overhead":
			_update_camera_overhead(delta, fractions)
		"jockey":
			_update_camera_jockey(delta, fractions)
		_:
			_update_camera_broadcast(delta, fractions)

## Cycles BROADCAST -> OVERHEAD -> JOCKEY -> BROADCAST on the C key or the
## controller's Y/Triangle button (checked directly by physical
## keycode/joypad button rather than through a named InputMap action — this
## project has no [input] section in project.godot yet, and hand-authoring
## one as raw text risks a project.godot parse error that would break every
## scene; a direct event check needs no project.godot changes at all).
## Persists the choice via Settings so next race starts on whichever mode was
## last used, and flashes the new mode's name through the existing
## commentary caption instead of adding a whole new HUD element for it.
func _unhandled_input(event: InputEvent) -> void:
	var triggered: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y)
	if not triggered:
		return
	var current_i: int = CAMERA_MODE_ORDER.find(_camera_mode)
	_camera_mode = CAMERA_MODE_ORDER[(current_i + 1) % CAMERA_MODE_ORDER.size()]
	Settings.set_camera_mode(_camera_mode)
	_apply_camera_environment()
	if broadcast_hud != null:
		broadcast_hud.show_commentary("Camera: %s" % _camera_mode.capitalize())

## Rides a virtual rail outside the track, tracking the pack's average
## progress and centroid with exponential smoothing (frame-rate independent,
## unlike a flat lerp factor) so the pan feels like a trackside broadcast
## dolly rather than snapping straight to each frame's raw average. Camera
## shake/punch-zoom (see _trigger_big_move) are layered on top of that base
## position/FOV every frame, decaying linearly to zero over their duration.
func _update_camera_broadcast(delta: float, fractions: PackedFloat32Array) -> void:
	var avg_fraction: float = 0.0
	var centroid: Vector3 = Vector3.ZERO
	for i in range(horse_nodes.size()):
		avg_fraction += fractions[i]
		centroid += horse_nodes[i].position
	avg_fraction /= horse_nodes.size()
	centroid /= horse_nodes.size()

	var t: float = 1.0 - exp(-delta * CAMERA_SMOOTH_SPEED)
	camera_focus_fraction = fposmod(lerp_angle(camera_focus_fraction * TAU, avg_fraction * TAU, t), TAU) / TAU
	camera_look_target = camera_look_target.lerp(centroid, t)

	var outer_radius: float = _lane_radius(horse_nodes.size() - 1) + RAIL_GAP
	var rail_radius: float = outer_radius + CAMERA_RAIL_OFFSET
	var rail_fraction: float = camera_focus_fraction + _free_look_fraction_offset
	var base_position: Vector3 = _sample_track(rail_fraction, rail_radius).position + Vector3(0.0, CAMERA_HEIGHT + _free_look_height_offset, 0.0)

	_camera_shake_time = max(0.0, _camera_shake_time - delta)
	_camera_punch_time = max(0.0, _camera_punch_time - delta)

	var shake_strength: float = _camera_shake_time / CAMERA_SHAKE_DURATION
	var shake_offset: Vector3 = Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
	) * CAMERA_SHAKE_MAGNITUDE * shake_strength

	var punch_strength: float = _camera_punch_time / CAMERA_PUNCH_DURATION
	camera.fov = camera_base_fov + CAMERA_PUNCH_FOV_DELTA * punch_strength + _free_look_fov_offset

	camera.position = base_position + shake_offset
	camera.look_at(camera_look_target, Vector3.UP)

const OVERHEAD_HEIGHT: float = 55.0
const OVERHEAD_SMOOTH_SPEED: float = 4.0

## Straight-down blimp/minimap-style shot tracking the pack's centroid — a
## totally different read on the same race than the broadcast dolly, good
## for seeing the whole field's spacing at a glance.
func _update_camera_overhead(delta: float, fractions: PackedFloat32Array) -> void:
	var centroid: Vector3 = Vector3.ZERO
	for node in horse_nodes:
		centroid += node.position
	centroid /= horse_nodes.size()

	var t: float = 1.0 - exp(-delta * OVERHEAD_SMOOTH_SPEED)
	camera_look_target = camera_look_target.lerp(centroid, t)
	# The tiny Z nudge keeps the camera from ever sitting EXACTLY above
	# camera_look_target — Node3D.look_at degenerates (forward and up vectors
	# collinear) when the camera is perfectly vertical over its target.
	var target_position: Vector3 = camera_look_target + Vector3(0.0, OVERHEAD_HEIGHT, 0.0001)
	camera.position = camera.position.lerp(target_position, t)
	camera.fov = camera_base_fov
	camera.look_at(camera_look_target, Vector3.UP)

const JOCKEY_HEIGHT_MARGIN: float = 0.5 # clearance ABOVE the model's own measured highest point — see HorseMarker3D.get_top_y()
const JOCKEY_MOUNT_OFFSET: float = 0.5 # FORWARD of the horse's own origin, near the withers/shoulders where a jockey actually sits — was a negative (behind) offset when this was a chase cam
const JOCKEY_LOOK_AHEAD: float = 14.0
const JOCKEY_LOOK_HEIGHT_LIFT: float = 0.3 # look slightly ABOVE camera height, not down at the ground/track surface
const JOCKEY_SMOOTH_SPEED: float = 6.0
const JOCKEY_FOV: float = 70.0 # wider than the broadcast cam's 50 — right up in it, GoPro-on-the-jockey visceral

## Mounted POV — sits where a jockey actually would (on the leading horse's
## back, near the withers, looking forward over its head/neck down the
## track) rather than trailing behind it like a chase cam looking at its
## hindquarters (the old rig). Uses the leader HorseMarker3D's own facing
## (local +Z is "behind", per HorseMarker3D's own look_at convention) rather
## than re-deriving a heading from track fractions, so it banks naturally
## through the turns exactly the way the horse models themselves do. Camera
## height comes from HorseMarker3D.get_top_y() (the model's actual measured
## geometry) rather than a guessed constant — two guessed constants in a row
## (1.9, then 2.5) landed too low/clipping into the model, since there was no
## way to visually verify either without AJ testing live.
func _update_camera_jockey(delta: float, fractions: PackedFloat32Array) -> void:
	var leader_i: int = 0
	var leader_progress: float = -INF
	for i in range(fractions.size()):
		if fractions[i] > leader_progress:
			leader_progress = fractions[i]
			leader_i = i

	var leader: HorseMarker3D = horse_nodes[leader_i]
	var forward: Vector3 = -leader.global_transform.basis.z.normalized()
	var camera_height: float = leader.get_top_y() + JOCKEY_HEIGHT_MARGIN
	var target_position: Vector3 = leader.global_position + forward * JOCKEY_MOUNT_OFFSET + Vector3(0.0, camera_height, 0.0)
	var target_look: Vector3 = leader.global_position + forward * JOCKEY_LOOK_AHEAD + Vector3(0.0, camera_height + JOCKEY_LOOK_HEIGHT_LIFT, 0.0)

	var t: float = 1.0 - exp(-delta * JOCKEY_SMOOTH_SPEED)
	camera.position = camera.position.lerp(target_position, t)
	camera_look_target = camera_look_target.lerp(target_look, t)
	camera.fov = JOCKEY_FOV
	camera.look_at(camera_look_target, Vector3.UP)

## Samples a stadium curve of the given `radius` at lap `fraction` (0..1,
## wraps), on the XZ ground plane (Y always 0). Direct 3D port of the 2D
## version's _sample_track — same four-segment stadium shape, same
## continuity across all segment joins — just (x,y)->(x,0,z) and no
## analytical heading (facing is handled by look_at at the call site).
func _sample_track(fraction: float, radius: float) -> Dictionary:
	var half: float = STRAIGHT_LEN * 0.5
	var turn_len: float = PI * radius
	var perimeter: float = 2.0 * STRAIGHT_LEN + 2.0 * turn_len
	var s: float = fposmod(fraction, 1.0) * perimeter

	if s < STRAIGHT_LEN:
		return {"position": Vector3(-half + s, 0.0, radius)}
	s -= STRAIGHT_LEN

	if s < turn_len:
		var theta: float = PI * 0.5 - s / radius
		return {"position": Vector3(half, 0.0, 0.0) + radius * Vector3(cos(theta), 0.0, sin(theta))}
	s -= turn_len

	if s < STRAIGHT_LEN:
		return {"position": Vector3(half - s, 0.0, -radius)}
	s -= STRAIGHT_LEN

	var theta2: float = -PI * 0.5 - s / radius
	return {"position": Vector3(-half, 0.0, 0.0) + radius * Vector3(cos(theta2), 0.0, sin(theta2))}

## Same stadium math as _sample_track above, collapsed to a flat 2D (x,z)
## point at the inner-rail lane — used by BroadcastHUD's minimap so it draws
## the real track's actual shape and winding direction instead of an
## unrelated hardcoded ellipse. Takes straight_len/inner_radius as explicit
## params (not instance STRAIGHT_LEN/INNER_RADIUS) so it can stay a plain
## static helper now that those are per-venue instance vars, not consts —
## BroadcastHUD gets the specific race's values passed into setup() rather
## than needing a live RaceTrack3D instance reference just to call this.
static func sample_shape(fraction: float, straight_len: float, inner_radius: float) -> Vector2:
	var half: float = straight_len * 0.5
	var radius: float = inner_radius
	var turn_len: float = PI * radius
	var perimeter: float = 2.0 * straight_len + 2.0 * turn_len
	var s: float = fposmod(fraction, 1.0) * perimeter

	if s < straight_len:
		return Vector2(-half + s, radius)
	s -= straight_len

	if s < turn_len:
		var theta: float = PI * 0.5 - s / radius
		return Vector2(half, 0.0) + radius * Vector2(cos(theta), sin(theta))
	s -= turn_len

	if s < straight_len:
		return Vector2(half - s, -radius)
	s -= straight_len

	var theta2: float = -PI * 0.5 - s / radius
	return Vector2(-half, 0.0) + radius * Vector2(cos(theta2), sin(theta2))

func _track_loop_points(radius: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in range(LOOP_SAMPLES):
		points.append(_sample_track(float(i) / float(LOOP_SAMPLES), radius).position)
	return points

func _build_track_visual() -> void:
	var infield_radius: float = INNER_RADIUS - RAIL_GAP
	var outer_radius: float = _lane_radius(field.size() - 1) + RAIL_GAP

	add_child(_make_fan_mesh(_track_loop_points(infield_radius), INFIELD_COLOR, 0.95, _get_grass_detail_texture()))
	add_child(_make_ring_mesh(_track_loop_points(infield_radius), _track_loop_points(outer_radius), TRACK_SURFACE_COLOR, 0.85, _get_dirt_detail_texture()))
	add_child(_make_rail_mesh(_track_loop_points(infield_radius), RAIL_HEIGHT, RAIL_COLOR, 0.35))
	add_child(_make_rail_mesh(_track_loop_points(outer_radius), RAIL_HEIGHT, RAIL_COLOR, 0.35))
	add_child(_make_finish_line(infield_radius, outer_radius))

## Original, entirely procedural scenery (no imported/licensed assets —
## every shape below is a primitive mesh sized against constants already
## defined for the track itself) meant to make this read as an actual
## racetrack rather than a bare oval: infield trees, a small infield
## grandstand near the finish line, and perimeter flags along the outer
## rail. Deliberately built the same way the track surface/rails already
## are (SurfaceTool/primitive meshes with known dimensions) rather than
## importing external 3D models — this project already got burned twice
## this session guessing at an imported model's real-world scale/pivot
## (the jockey figure, since reverted); a shape whose every dimension is a
## constant this file already controls can't have that problem.
##
## Placement is deliberately confined to the INFIELD (inside the inner
## rail) for anything with real bulk (trees, the grandstand): the chase
## camera in _update_camera always sits just OUTSIDE the outer rail
## (rail_radius = outer_radius + CAMERA_RAIL_OFFSET) looking back INWARD at
## wherever the horses currently are (camera_look_target tracks the horses'
## own centroid, not the geometric center) — so anything placed in that gap
## between the outer rail and the camera would periodically sit directly
## between the camera and the pack. The infield is on the opposite side of
## the whole track width from that gap, so scenery there can never occlude
## the race itself; it only ever reads as background dressing behind the
## horses. Perimeter flags are the one exception, placed just outside the
## outer rail — thin poles, sparsely spaced, so an occasional pole passing
## through frame reads as a normal foreground-rail artifact rather than an
## obstruction, the same way real broadcast footage briefly clips a rail
## post now and then.
func _build_environment() -> void:
	var infield_radius: float = INNER_RADIUS - RAIL_GAP
	var outer_radius: float = _lane_radius(field.size() - 1) + RAIL_GAP
	_build_trees(infield_radius)
	_build_grandstand(infield_radius)
	_build_perimeter_flags(outer_radius)
	_build_skyline(outer_radius)
	_build_spectators(infield_radius)

## A ring of simple silhouette buildings well beyond the flags — AJ asked for
## "buildings in the distance" instead of the flat sky just ending in
## nothing. Deliberately far enough out (SKYLINE_RADIUS_MARGIN beyond the
## flags) that it reads as background scenery, never anything a horse could
## plausibly run near. A few lit windows per building (small emissive boxes)
## give it life at night without needing a real texture/asset.
const SKYLINE_COUNT: int = 26
const SKYLINE_RADIUS_MARGIN: float = 55.0
const SKYLINE_MIN_HEIGHT: float = 6.0
const SKYLINE_MAX_HEIGHT: float = 22.0
const SKYLINE_WIDTH: float = 6.0
const SKYLINE_COLOR: Color = Color(0.025, 0.03, 0.045)
const SKYLINE_WINDOW_COLOR: Color = Color(0.9, 0.82, 0.5)

func _build_skyline(outer_radius: float) -> void:
	var skyline_radius: float = outer_radius + SKYLINE_RADIUS_MARGIN
	for i in range(SKYLINE_COUNT):
		var frac: float = float(i) / float(SKYLINE_COUNT) + randf_range(-0.01, 0.01)
		var pos: Vector3 = _sample_track(frac, skyline_radius).position
		add_child(_make_building(pos))

func _make_building(pos: Vector3) -> Node3D:
	var building := Node3D.new()
	building.position = pos
	building.rotation.y = randf_range(0.0, TAU)

	var height: float = randf_range(SKYLINE_MIN_HEIGHT, SKYLINE_MAX_HEIGHT)
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SKYLINE_WIDTH, height, SKYLINE_WIDTH)
	block.mesh = mesh
	block.position = Vector3(0.0, height * 0.5, 0.0)
	block.material_override = _make_material(SKYLINE_COLOR, 0.9)
	building.add_child(block)

	var window_count: int = randi_range(3, 6)
	for w in range(window_count):
		var window := MeshInstance3D.new()
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(0.5, 0.5, 0.1)
		window.mesh = window_mesh
		window.position = Vector3(
			randf_range(-SKYLINE_WIDTH * 0.35, SKYLINE_WIDTH * 0.35),
			randf_range(1.0, height - 1.0),
			SKYLINE_WIDTH * 0.5 + 0.05,
		)
		window.material_override = _make_material(SKYLINE_WINDOW_COLOR, 0.4, null, SKYLINE_WINDOW_COLOR, 1.8)
		building.add_child(window)

	return building

## A crowd of simple standee figures near the grandstand — AJ asked for
## "spectators and stuff you'd see on the sidelines instead of just
## emptiness." One MultiMeshInstance3D (a single thin capsule mesh
## instanced many times, each with its own per-instance transform AND
## color) rather than dozens of separate MeshInstance3D nodes — the right
## Godot tool for "lots of identical small objects," and cheap regardless of
## count. Placed on the INFIELD side of the grandstand (see
## _build_environment's own comment elsewhere for why bulk objects stay off
## the side between the camera and the horses) in a loose cluster, like fans
## standing near the rail closest to the finish.
const SPECTATOR_COUNT: int = 45
const SPECTATOR_HEIGHT: float = 1.6
const SPECTATOR_RADIUS: float = 0.16
## Muted, non-silk-like clothing colors — deliberately dull compared to the
## horses' own bright silks so spectators never compete for the eye with the
## actual race.
const SPECTATOR_COLORS: Array[Color] = [
	Color(0.3, 0.28, 0.32), Color(0.22, 0.24, 0.28), Color(0.35, 0.3, 0.25),
	Color(0.28, 0.22, 0.2), Color(0.25, 0.28, 0.24), Color(0.32, 0.32, 0.34),
]

func _build_spectators(infield_radius: float) -> void:
	var mesh_instance := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true

	var capsule := CapsuleMesh.new()
	capsule.radius = SPECTATOR_RADIUS
	capsule.height = SPECTATOR_HEIGHT
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.vertex_color_use_as_albedo = true
	capsule.material = mat # PrimitiveMesh exposes a single `material` property, not surface_set_material (that's ArrayMesh's API)
	multimesh.mesh = capsule
	multimesh.instance_count = SPECTATOR_COUNT

	# A loose cluster centered near the grandstand's own fraction, spread a
	# little wider than the stand itself, standing just inside the infield
	# rail (a believable "crowd pressed up against the rail" read).
	var cluster_radius: float = infield_radius - 1.2
	for i in range(SPECTATOR_COUNT):
		var frac: float = GRANDSTAND_FRACTION + randf_range(-0.045, 0.045)
		var pos: Vector3 = _sample_track(frac, cluster_radius).position
		pos += Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
		var scale: float = randf_range(0.85, 1.1)
		var transform := Transform3D(Basis.from_euler(Vector3(0.0, randf_range(0.0, TAU), 0.0)).scaled(Vector3.ONE * scale), pos + Vector3(0.0, SPECTATOR_HEIGHT * 0.5 * scale, 0.0))
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, SPECTATOR_COLORS[randi() % SPECTATOR_COLORS.size()])

	mesh_instance.multimesh = multimesh
	add_child(mesh_instance)

## Was infield trees; now slim glowing light pylons — same count/placement/
## grandstand-clearance logic (a tree-shaped silhouette would read oddly out
## of place against the chrome grandstand and neon rail), just a different
## mesh on top of it: a dark post topped by an emissive ring, like a stadium
## light/marker tower rather than foliage.
## Real trees again (were briefly reskinned as glowing light pylons during
## the "arcade excess"/neon pass — AJ later asked for the environment to
## read as more natural brown/green instead, so this reverts the VISUAL only;
## the placement/count/scale logic below is untouched, just proven-safe code
## kept as-is).
const TREE_COUNT: int = 22
const TREE_CLEAR_FRACTION_HALF_WIDTH: float = 0.09 # keeps trees out of the grandstand's footprint near fraction 0
const TREE_TRUNK_HEIGHT: float = 3.0
const TREE_TRUNK_RADIUS: float = 0.16
const TREE_CANOPY_RADIUS: float = 0.9
const TREE_TRUNK_COLOR: Color = Color(0.32, 0.2, 0.12)
const TREE_CANOPY_COLOR: Color = Color(0.14, 0.34, 0.12) # plain natural green in every theme now, not a per-theme neon accent

## Scattered across the infield's own interior (well clear of both the
## inner rail and dead center) — see _build_environment's comment for why
## the infield is the safe side of the track for anything with bulk.
func _build_trees(infield_radius: float) -> void:
	var max_tree_radius: float = infield_radius - 3.0
	if max_tree_radius <= 4.0:
		return
	for i in range(TREE_COUNT):
		var frac: float = float(i) / float(TREE_COUNT) + randf_range(-0.02, 0.02)
		var dist_from_grandstand: float = abs(fposmod(frac - GRANDSTAND_FRACTION + 0.5, 1.0) - 0.5)
		if dist_from_grandstand < TREE_CLEAR_FRACTION_HALF_WIDTH:
			continue # stay clear of the grandstand's footprint
		var r: float = lerp(4.0, max_tree_radius, randf())
		var pos: Vector3 = _sample_track(frac, r).position
		add_child(_make_tree(pos))

func _make_tree(pos: Vector3) -> Node3D:
	var tree := Node3D.new()
	tree.position = pos
	tree.rotation.y = randf_range(0.0, TAU)
	tree.scale = Vector3.ONE * randf_range(0.85, 1.3)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = TREE_TRUNK_RADIUS
	trunk_mesh.bottom_radius = TREE_TRUNK_RADIUS * 1.4
	trunk_mesh.height = TREE_TRUNK_HEIGHT
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, TREE_TRUNK_HEIGHT * 0.5, 0.0)
	trunk.material_override = _make_material(TREE_TRUNK_COLOR, 0.85)
	tree.add_child(trunk)

	# Canopy built from 3 overlapping spheres at random offsets/sizes rather
	# than one perfect sphere — a single sphere reads as an obvious primitive
	# at this game's low-poly scale; a small cluster reads more like an
	# actual leafy volume.
	for i in range(3):
		var canopy := MeshInstance3D.new()
		var canopy_mesh := SphereMesh.new()
		var r: float = TREE_CANOPY_RADIUS * randf_range(0.7, 1.0)
		canopy_mesh.radius = r
		canopy_mesh.height = r * 2.0
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(
			randf_range(-0.3, 0.3) * TREE_CANOPY_RADIUS,
			TREE_TRUNK_HEIGHT + TREE_CANOPY_RADIUS * 0.6 + randf_range(-0.1, 0.15) * TREE_CANOPY_RADIUS,
			randf_range(-0.3, 0.3) * TREE_CANOPY_RADIUS,
		)
		var shade: float = randf_range(0.85, 1.15)
		canopy.material_override = _make_material(Color(TREE_CANOPY_COLOR.r * shade, TREE_CANOPY_COLOR.g * shade, TREE_CANOPY_COLOR.b * shade), 0.8)
		tree.add_child(canopy)

	return tree

## A small stepped-tier grandstand + roof along the home stretch. Built as a
## straight-sided box in this node's own local space, so it's only
## geometrically valid where the track itself is actually straight —
## GRANDSTAND_FRACTION (0.15) sits well inside the front straight rather
## than at fraction 0 exactly (the finish line, which is also the corner
## where the straight meets the first turn): at s = 0.15 * (2*STRAIGHT_LEN
## + 2*PI*GRANDSTAND_CENTER_RADIUS) ≈ 56 world units along the straight,
## the stand's full ±(GRANDSTAND_LENGTH/2) ≈ ±17 local-X footprint lands at
## s ≈ 39 to 73, comfortably inside the straight's own s ∈ [0, STRAIGHT_LEN]
## range with margin on both sides — right at the corner, the infield
## boundary starts curving into the turn, which a straight box can't follow.
const GRANDSTAND_FRACTION: float = 0.15
const GRANDSTAND_CENTER_RADIUS: float = 15.0
const GRANDSTAND_LENGTH: float = 34.0
const GRANDSTAND_TIERS: int = 4
const GRANDSTAND_TIER_HEIGHT: float = 1.6
const GRANDSTAND_TIER_DEPTH: float = 2.0
const GRANDSTAND_ROOF_HEIGHT: float = 8.5
## Chrome/glass tiers, per-theme (see TrackThemes) — GRANDSTAND_COLOR_LOWER/
## UPPER stay LOW roughness (near-mirror) so the floodlights and rail glow
## visibly reflect off the tiers, and the roof carries the same emissive trim
## color as the rail (see _build_grandstand's roof edge strip) so the whole
## structure reads as lit stadium architecture rather than a flat-shaded box.
var GRANDSTAND_COLOR_LOWER: Color
var GRANDSTAND_COLOR_UPPER: Color
var GRANDSTAND_ROOF_COLOR: Color
var GRANDSTAND_TRIM_COLOR: Color

func _build_grandstand(infield_radius: float) -> void:
	if GRANDSTAND_CENTER_RADIUS + GRANDSTAND_TIER_DEPTH * GRANDSTAND_TIERS >= infield_radius:
		return # safety guard in case field size ever shrinks infield_radius below what this needs

	var stand := Node3D.new()
	var base_pos: Vector3 = _sample_track(GRANDSTAND_FRACTION, GRANDSTAND_CENTER_RADIUS).position
	stand.position = base_pos
	add_child(stand)

	for tier in range(GRANDSTAND_TIERS):
		var block := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(GRANDSTAND_LENGTH, GRANDSTAND_TIER_HEIGHT, GRANDSTAND_TIER_DEPTH)
		block.mesh = mesh
		var y: float = GRANDSTAND_TIER_HEIGHT * (float(tier) + 0.5)
		var z_offset: float = -GRANDSTAND_TIER_DEPTH * 0.5 * float(tier) # steps back toward center as it rises
		block.position = Vector3(0.0, y, z_offset)
		var t: float = float(tier) / float(max(GRANDSTAND_TIERS - 1, 1))
		block.material_override = _make_material(GRANDSTAND_COLOR_LOWER.lerp(GRANDSTAND_COLOR_UPPER, t), 0.25)
		stand.add_child(block)

		# Thin emissive trim strip along each tier's leading edge — reads as
		# architectural accent lighting on an otherwise dark chrome facade.
		var trim := MeshInstance3D.new()
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(GRANDSTAND_LENGTH, 0.08, 0.08)
		trim.mesh = trim_mesh
		trim.position = Vector3(0.0, y + GRANDSTAND_TIER_HEIGHT * 0.5, z_offset + GRANDSTAND_TIER_DEPTH * 0.5)
		trim.material_override = _make_material(GRANDSTAND_TRIM_COLOR, 0.4, null, GRANDSTAND_TRIM_COLOR, 2.0)
		stand.add_child(trim)

	var roof_z: float = -GRANDSTAND_TIER_DEPTH * 0.5 * float(GRANDSTAND_TIERS - 1)
	var roof := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(GRANDSTAND_LENGTH + 3.0, 0.4, GRANDSTAND_TIER_DEPTH * GRANDSTAND_TIERS)
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, GRANDSTAND_ROOF_HEIGHT, roof_z)
	roof.material_override = _make_material(GRANDSTAND_ROOF_COLOR, 0.15)
	stand.add_child(roof)

	var roof_edge := MeshInstance3D.new()
	var roof_edge_mesh := BoxMesh.new()
	roof_edge_mesh.size = Vector3(GRANDSTAND_LENGTH + 3.2, 0.1, 0.1)
	roof_edge.mesh = roof_edge_mesh
	roof_edge.position = Vector3(0.0, GRANDSTAND_ROOF_HEIGHT - 0.15, roof_z + GRANDSTAND_TIER_DEPTH * GRANDSTAND_TIERS * 0.5)
	roof_edge.material_override = _make_material(GRANDSTAND_TRIM_COLOR, 0.4, null, GRANDSTAND_TRIM_COLOR, 2.5)
	stand.add_child(roof_edge)

	for side in [-1.0, 1.0]:
		var strut := MeshInstance3D.new()
		var strut_mesh := CylinderMesh.new()
		strut_mesh.top_radius = 0.15
		strut_mesh.bottom_radius = 0.15
		strut_mesh.height = GRANDSTAND_ROOF_HEIGHT
		strut.mesh = strut_mesh
		strut.position = Vector3(side * (GRANDSTAND_LENGTH * 0.5 - 1.5), GRANDSTAND_ROOF_HEIGHT * 0.5, roof_z)
		strut.material_override = _make_material(Color(0.08, 0.09, 0.11), 0.2)
		stand.add_child(strut)

const FLAG_COUNT: int = 20
const FLAG_RADIUS_MARGIN: float = 1.6 # beyond the outer rail
const FLAG_POLE_HEIGHT: float = 2.6
const FLAG_POLE_RADIUS: float = 0.05
const FLAG_SIZE: Vector2 = Vector2(0.8, 0.5)
var FLAG_COLORS: Array[Color] = [] # per-theme, see TrackThemes

## Thin poles just outside the outer rail — see _build_environment's comment
## for why these (unlike trees/the grandstand) are allowed trackside: a
## sparse thin pole is a normal foreground artifact even on the rare frame
## it crosses the camera's line to the pack, not an obstruction.
func _build_perimeter_flags(outer_radius: float) -> void:
	var flag_radius: float = outer_radius + FLAG_RADIUS_MARGIN
	for i in range(FLAG_COUNT):
		var frac: float = float(i) / float(FLAG_COUNT)
		var pos: Vector3 = _sample_track(frac, flag_radius).position
		var pole := _make_flag_pole(FLAG_COLORS[i % FLAG_COLORS.size()])
		pole.position = pos
		add_child(pole)

## Was a cloth flag on a pole; now a slim dark post topped by a glowing
## LED marker panel — same silhouette/placement (still just a post + a small
## rectangle near the top) so nothing about _build_perimeter_flags' spacing
## logic had to change, but the rectangle is now emissive signage rather than
## fabric, matching the rail/pylon/grandstand trim's neon language instead of
## reading as a leftover bunting flag on an otherwise futuristic track.
func _make_flag_pole(color: Color) -> Node3D:
	var pole := Node3D.new()

	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = FLAG_POLE_RADIUS
	post_mesh.bottom_radius = FLAG_POLE_RADIUS
	post_mesh.height = FLAG_POLE_HEIGHT
	post.mesh = post_mesh
	post.position = Vector3(0.0, FLAG_POLE_HEIGHT * 0.5, 0.0)
	post.material_override = _make_material(Color(0.1, 0.11, 0.14), 0.3)
	pole.add_child(post)

	var flag := MeshInstance3D.new()
	var flag_mesh := PlaneMesh.new()
	flag_mesh.size = FLAG_SIZE
	flag.mesh = flag_mesh
	flag.position = Vector3(FLAG_SIZE.x * 0.5, FLAG_POLE_HEIGHT - FLAG_SIZE.y * 0.5, 0.0)
	var flag_mat := _make_material(color, 0.4, null, color, 2.2)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED # visible from either side regardless of exact facing
	flag.material_override = flag_mat
	pole.add_child(flag)

	return pole

## World units per tile of the procedural detail textures below — tuned so
## the mottling reads as ground texture at this track's scale, not a huge
## blotchy pattern (too large a scale) or fine static-like noise (too small).
const GROUND_TEXTURE_SCALE: float = 14.0

static var _dirt_detail_texture: NoiseTexture2D
static var _grass_detail_texture: NoiseTexture2D

## Cached per-class (not per-race) since the noise pattern itself has no
## reason to change race to race — same "generate once, reuse forever"
## pattern HorseMarker3D uses for the cached horse model. A narrow
## color_ramp (0.78..1.0) keeps this a SUBTLE brightness variation
## multiplied onto the base albedo_color rather than swinging the surface
## dark-to-light across its full noise range, which would look patchy/wrong.
static func _get_dirt_detail_texture() -> NoiseTexture2D:
	if _dirt_detail_texture == null:
		_dirt_detail_texture = _build_detail_texture(1, 0.06)
	return _dirt_detail_texture

static func _get_grass_detail_texture() -> NoiseTexture2D:
	if _grass_detail_texture == null:
		_grass_detail_texture = _build_detail_texture(2, 0.1)
	return _grass_detail_texture

static func _build_detail_texture(noise_seed: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = noise_seed
	noise.frequency = frequency

	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.78, 0.78))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))

	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.color_ramp = ramp
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	return tex

## `emission` defaults to transparent-black (Color(0,0,0,0)), which added to
## anything is a no-op — passing nothing keeps every existing call site's
## plain matte look exactly as before. Any actual color there both lights
## the surface from within (visible even in unlit shadow) and, combined with
## _build_lighting's env.glow_enabled, blooms — this is what makes the rail/
## pylons/banners read as neon rather than just brightly painted.
func _make_material(color: Color, roughness: float = 0.9, detail_texture: Texture2D = null, emission: Color = Color(0.0, 0.0, 0.0, 0.0), emission_energy: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = detail_texture # multiplies with albedo_color when set — null is a no-op, same as before
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat

## Fills a convex loop (the stadium shape is convex) as a triangle fan from
## its own center point — used for the infield. UVs are planar (world XZ /
## GROUND_TEXTURE_SCALE) so `detail_texture` tiles across the surface based
## on actual world position rather than reading as one flat, undefined color
## (SurfaceTool defaults every vertex to UV (0,0) if never explicitly set).
func _make_fan_mesh(points: Array[Vector3], color: Color, roughness: float = 0.9, detail_texture: Texture2D = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % points.size()]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2.ZERO)
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(a.x, a.z) / GROUND_TEXTURE_SCALE)
		st.add_vertex(a)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(b.x, b.z) / GROUND_TEXTURE_SCALE)
		st.add_vertex(b)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _make_material(color, roughness, detail_texture)
	return mesh_instance

## Fills the annulus between two same-length, same-parameterization loops
## (inner/outer at matching fractions) as a strip of quads — used for the
## dirt track surface between the infield and the outer rail. Same planar
## world-space UV approach as _make_fan_mesh above.
func _make_ring_mesh(inner: Array[Vector3], outer: Array[Vector3], color: Color, roughness: float = 0.9, detail_texture: Texture2D = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(inner.size()):
		var j: int = (i + 1) % inner.size()
		var uv_inner_i: Vector2 = Vector2(inner[i].x, inner[i].z) / GROUND_TEXTURE_SCALE
		var uv_outer_i: Vector2 = Vector2(outer[i].x, outer[i].z) / GROUND_TEXTURE_SCALE
		var uv_outer_j: Vector2 = Vector2(outer[j].x, outer[j].z) / GROUND_TEXTURE_SCALE
		var uv_inner_j: Vector2 = Vector2(inner[j].x, inner[j].z) / GROUND_TEXTURE_SCALE
		st.set_normal(Vector3.UP); st.set_uv(uv_inner_i); st.add_vertex(inner[i])
		st.set_normal(Vector3.UP); st.set_uv(uv_outer_i); st.add_vertex(outer[i])
		st.set_normal(Vector3.UP); st.set_uv(uv_outer_j); st.add_vertex(outer[j])
		st.set_normal(Vector3.UP); st.set_uv(uv_inner_i); st.add_vertex(inner[i])
		st.set_normal(Vector3.UP); st.set_uv(uv_outer_j); st.add_vertex(outer[j])
		st.set_normal(Vector3.UP); st.set_uv(uv_inner_j); st.add_vertex(inner[j])
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _make_material(color, roughness, detail_texture)
	return mesh_instance

## A vertical ribbon standing on a loop — the boundary rail/fence. Emissive
## by default now (see _make_material) so the rail itself is the track's
## primary "neon boundary strip" light source rather than a plain painted
## fence lit only by the floodlights.
func _make_rail_mesh(points: Array[Vector3], height: float, color: Color, roughness: float = 0.9) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()):
		var j: int = (i + 1) % points.size()
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[j]
		var p0_top: Vector3 = p0 + Vector3(0.0, height, 0.0)
		var p1_top: Vector3 = p1 + Vector3(0.0, height, 0.0)
		var normal: Vector3 = (p1 - p0).cross(Vector3.UP).normalized()
		st.set_normal(normal)
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p1_top)
		st.set_normal(normal)
		st.add_vertex(p0); st.add_vertex(p1_top); st.add_vertex(p0_top)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _make_material(color, roughness, null, color, 1.6)
	return mesh_instance

## Checkered finish-line stripe painted across the full width of the dirt
## track (infield_radius to outer_radius), at the one point where fraction
## 0 and fraction 1 are the same physical spot — races are exactly one lap
## (see RaceSim.TRACK_LENGTH), so start and finish coincide at the beginning
## of the front straight (_sample_track(0.0, r) for any radius r). Sits
## slightly above the dirt ring mesh (y = FINISH_LINE_Y) to avoid z-fighting.
func _make_finish_line(infield_radius: float, outer_radius: float) -> MeshInstance3D:
	var half: float = STRAIGHT_LEN * 0.5
	var x0: float = -half - FINISH_LINE_WIDTH * 0.5
	var x1: float = -half + FINISH_LINE_WIDTH * 0.5
	var row_step: float = (x1 - x0) / FINISH_LINE_ROWS
	var col_step: float = (outer_radius - infield_radius) / FINISH_LINE_COLS

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(FINISH_LINE_ROWS):
		for col in range(FINISH_LINE_COLS):
			var tile_color: Color = Color.WHITE if (row + col) % 2 == 0 else Color.BLACK
			var rx0: float = x0 + row * row_step
			var rx1: float = rx0 + row_step
			var rz0: float = infield_radius + col * col_step
			var rz1: float = rz0 + col_step
			var p00 := Vector3(rx0, FINISH_LINE_Y, rz0)
			var p10 := Vector3(rx1, FINISH_LINE_Y, rz0)
			var p11 := Vector3(rx1, FINISH_LINE_Y, rz1)
			var p01 := Vector3(rx0, FINISH_LINE_Y, rz1)
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				st.set_color(tile_color)
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[0])
				st.set_color(tile_color)
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[1])
				st.set_color(tile_color)
				st.set_normal(Vector3.UP)
				st.add_vertex(tri[2])

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat
	return mesh_instance
