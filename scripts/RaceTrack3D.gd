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

## Automatic broadcast-style camera CUTS layered on top of the one chase-cam
## rig above — AJ asked what a real TVG broadcast has that this doesn't, and
## "one continuous pan for the whole race" was the single biggest tell versus
## real coverage, which always cuts: a static wide gate shot, the chase cam
## once running, one elevated cutaway at the far turn, a fixed low finish-line
## camera for the stretch drive. Every non-CHASE shot below sets camera
## position/look_at directly (no exponential smoothing) so the transition
## reads as an instant CUT, the way a broadcast truck switches feeds, rather
## than the camera physically flying across the track. camera_focus_fraction/
## camera_look_target keep updating every frame regardless of which shot is
## live (see _update_camera) specifically so CHASE never has to visibly "catch
## up" once a cutaway ends.
enum ShotState { GATE, CHASE, TURN_CUTAWAY, STRETCH }
var _shot_state: ShotState = ShotState.GATE
var _shot_state_time: float = 0.0
var _did_turn_cutaway: bool = false # once-per-race latch, not re-armed until the next _build_scene()

const GATE_SHOT_DURATION: float = 2.2 # holds even if a horse somehow jumps out to an early fractional lead
## Pulled in from an earlier 34/15 — a first screenshot check showed the gate
## reading as a tiny curb with the grandstand (much closer, on the infield
## side near the same fraction) dominating the frame instead. Closer/lower,
## similar proportions to the STRETCH shot's own successful framing, reads as
## an actual establishing shot of the gate rather than a wide unrelated vista.
const GATE_SHOT_BACK: float = 16.0
const GATE_SHOT_HEIGHT: float = 7.0
const GATE_SHOT_FOV_DELTA: float = 8.0 # wider than the chase cam's normal FOV — an establishing shot, not a close-up

const TURN_CUTAWAY_START_FRACTION: float = 0.42 # far turn is the straight's mirror image, i.e. fraction 0.5
const TURN_CUTAWAY_END_FRACTION: float = 0.58
const TURN_CUTAWAY_DURATION: float = 2.5
const TURN_CAM_BACK: float = 46.0
const TURN_CAM_HEIGHT: float = 34.0 # a genuinely elevated "blimp/crane" angle, not just a taller chase cam

const STRETCH_SHOT_START_FRACTION: float = 0.85
const STRETCH_CAM_BACK: float = 9.0 # just outside the rail, near the finish line
const STRETCH_CAM_HEIGHT: float = 6.0 # low, head-on, dramatic — the classic finish-line wire-cam angle

var result: RaceResult
var field: Array[Horse] = []
var _bet_context: Dictionary = {} # see BroadcastHUD._build_bet_panel — what the player actually wagered on THIS race
var horse_nodes: Array[HorseMarker3D] = []
var frame_index: int = 0
var playback_time: float = 0.0
var playing: bool = false

var camera: Camera3D
var camera_base_fov: float = 50.0 # reverted a tighter 44 tried this session — AJ: zooming in
	# risks making the low-poly horse model look worse up close, not better; left as-is.
var camera_focus_fraction: float = 0.0
var camera_look_target: Vector3 = Vector3.ZERO
var _camera_shake_time: float = 0.0
var _camera_punch_time: float = 0.0

var broadcast_hud: BroadcastHUD
var announcer_director: RaceAnnouncerDirector
var _was_big_surging: Array[bool] = []

## Visible mechanical starting gate — horses used to just appear already
## running, with nothing marking the actual moment of departure. Built the
## same procedural-primitive way as the grandstand/rail (no imported assets,
## no risk of guessing an imported model's scale/pivot wrong — see
## _build_environment's own comment on why this project prefers that). One
## hinge Node3D per lane (the door mesh is its child, offset to one side) so
## "opening" is just rotating the hinge around Y — see _open_starting_gate.
const GATE_HEIGHT: float = 2.6
const GATE_DEPTH: float = 0.9
const GATE_SETBACK: float = 0.6 # front face sits this far behind the actual start/finish line
const GATE_FRAME_COLOR: Color = Color(0.5, 0.07, 0.07) # traditional starting-gate red
const GATE_DOOR_COLOR: Color = Color(0.82, 0.82, 0.85)
const GATE_DOOR_OPEN_ANGLE_DEG: float = 100.0
const GATE_DOOR_OPEN_DURATION: float = 0.3
## The gate is a "before the race" object, not a permanent track fixture like
## the finish arch (_make_finish_arch below) — it fades out and is removed
## once the field has visibly cleared it, rather than sitting in the scene
## (out of frame for most of the race, but still technically present) the
## whole time. Delay is measured from when the doors finish opening.
const GATE_FADE_DELAY: float = 2.2
const GATE_FADE_DURATION: float = 1.0

var _gate_doors: Array[Node3D] = [] # hinge nodes, one per lane
var _gate_world_center: Vector3 = Vector3.ZERO # what the GATE establishing shot looks at
var _gate_root: Node3D
var _gate_frame_mat: StandardMaterial3D
var _gate_door_mat: StandardMaterial3D
var _gate_fade_started: bool = false

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

## AJ: "make it so they randomly race on turf or dirt" — decided once per
## race by RaceScheduler._draw_field (see its own comment) and passed in
## here; RaceTrack3D itself just renders whichever surface it's told rather
## than deciding.
var _is_turf: bool = false

## Venue-specific extra dressing (backstretch bleachers + a fairgrounds
## Ferris-wheel/tent backdrop) — read straight from Venues.gd's own per-venue
## dict like STRAIGHT_LEN/INNER_RADIUS/theme_id below, not passed as a
## separate setup() param, since it's a fixed property of the venue itself
## rather than something that varies per-race the way _is_turf does.
var _has_fairgrounds: bool = false

func setup(p_field: Array[Horse], p_result: RaceResult, bet_context: Dictionary = {}, venue_id: String = "", p_has_audio_focus: bool = true, p_is_turf: bool = false) -> void:
	field = p_field
	result = p_result
	_bet_context = bet_context
	_venue_id = venue_id
	has_audio_focus = p_has_audio_focus
	_is_turf = p_is_turf
	_has_fairgrounds = false
	if venue_id != "":
		var venue: Dictionary = Venues.get_venue(venue_id)
		STRAIGHT_LEN = float(venue.get("straight_len", 140.0))
		INNER_RADIUS = float(venue.get("inner_radius", 26.0))
		_has_fairgrounds = bool(venue.get("has_fairgrounds", false))
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
	# Turf is literally the same grass as the infield in real life — reusing
	# the theme's own infield_color rather than inventing a separate turf
	# constant keeps a turf race's surface color consistent with that same
	# theme's grass mood (bluegrass_night's turf reads differently from
	# desert_dusk's, same as their infields already do).
	TRACK_SURFACE_COLOR = _theme.infield_color if _is_turf else _theme.track_surface_color
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
	_build_starting_gate()
	_build_environment()
	_build_camera()

	var venue_label: String = "LONGSHOT DOWNS"
	if _venue_id != "":
		venue_label = Venues.label_for(_venue_id).to_upper()

	broadcast_hud = BroadcastHUD.new()
	add_child(broadcast_hud)
	broadcast_hud.setup(field, result, _bet_context, STRAIGHT_LEN, INNER_RADIUS, venue_label, _is_turf)

	announcer_director = RaceAnnouncerDirector.new()
	announcer_director.setup(field, broadcast_hud)
	announcer_director.has_audio_focus = has_audio_focus

	_was_big_surging.resize(field.size())
	_was_big_surging.fill(false)

	# No focused Control exists during the race at all (see InputHints'
	# generic focus-based gate) — visible_without_focus=true is what keeps
	# these shown here.
	InputHints.set_context_hints([
		{"button": "R-Stick/RT-LT", "ps_button": "R-Stick/R2-L2", "label": "Look/Zoom"},
	], true)

	for i in range(field.size()):
		var horse: Horse = field[i]
		# AJ: "the horses [are] all stand[ing] on the same square" at the
		# gate — real bug, not a report to dismiss. RaceSim.simulate's own
		# lane_offsets start every horse at 0.0 for tick 0 ("all start at
		# 0.0 (rail)", see its own comment) since the per-tick lane-merge
		# smoothing hasn't run yet; using that tick-0 value here via
		# _dynamic_radius put every horse at the SAME radius (and the same
		# fraction=0.0), i.e. literally the same point in space, before the
		# gate ever opens. Fixed by using each horse's own fixed lane index
		# (_lane_radius(i), the same formula _build_starting_gate already
		# uses for that horse's own gate-door position) for this INITIAL
		# idle placement only — start_running()'s first real _apply_frame
		# call takes over from here using the real (still tick-0, still
		# rail-collapsed) lane_offsets, which is fine since the gate is
		# already open and the field visibly fans back out from there
		# within the first second or so of real movement.
		# The "horses start behind the gate, bugle plays, then they slide
		# forward into their stalls" post-parade beat (added earlier this
		# session) read as "weird" in practice — AJ asked to simplify back
		# to horses just standing in their real gate-stall position from the
		# start, rather than chase a more elaborate loading animation this
		# project has no walk-cycle asset to do properly. Reverted.
		var start_pos: Vector3 = _sample_track(0.0, _lane_radius(i)).position
		var ahead_pos: Vector3 = _sample_track(0.001, _lane_radius(i)).position

		var marker := HorseMarker3D.new()
		add_child(marker)
		marker.setup(horse.silk_primary, horse.silk_secondary, horse.id, i + 1)
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
	# light_angular_distance simulates a real sun's apparent size, softening
	# shadow edges instead of the razor-sharp default (a hard-edged shadow is
	# one of the fastest "cheap 3D" tells) — directional_shadow_max_distance
	# bumped past its 100m default since the skyline ring alone sits well
	# past that (outer_radius + SKYLINE_RADIUS_MARGIN, see _build_skyline),
	# which was clipping the far skyline's own shadows.
	sun.light_angular_distance = 0.5
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)

	var hdri_texture: Texture2D = _get_cached_texture(String(_theme.get("sky_hdri", "")))
	if hdri_texture == null:
		_build_moon(sun) # the procedural sky has no real sun disc of its own to explain the DirectionalLight3D — see _build_moon's own comment. A real HDRI already shows its own sun, so this only applies to the procedural fallback.

	_build_floodlights()

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if hdri_texture != null:
		# Real CC0 photographed sky (see TrackThemes' per-theme "sky_hdri" key)
		# — this is the single highest-leverage realism swap available without
		# new 3D art: a procedural gradient dome reads as a render immediately,
		# a real photographed sky doesn't. Graceful fallback to the existing
		# procedural sky_material below if the file's missing, same pattern as
		# HorseMarker3D falling back to a placeholder when horse.glb is absent.
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = hdri_texture
		sky.sky_material = panorama
	else:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = _theme.sky_top
		sky_material.sky_horizon_color = _theme.sky_horizon
		sky_material.ground_bottom_color = _theme.ground_bottom
		sky_material.ground_horizon_color = _theme.ground_horizon
		sky_material.sky_curve = 0.15 # keeps most of the dome close to its top color instead of washing out toward the horizon
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

	# Screen-space reflections — mostly subtle (the track/grass materials are
	# fairly rough), but it's what puts a real sheen on the rail trim, the
	# floodlight-lit horse coats, and the finish line's checkered tiles
	# instead of everything reading as flat matte plastic.
	env.ssr_enabled = true
	env.ssr_max_steps = 64

	# A thin haze that scales with distance — sells real depth/scale on a
	# track this size (skyline, distant grandstand) the way a flat, fogless
	# render never quite does. AJ: a trailing horse — legitimately 10-30
	# units farther from the camera than the leader in a spread-out field —
	# was getting visibly swallowed by this at the original density/length.
	# Spreading the same total haze over a much longer volumetric_fog_length
	# (default 64) means it stays thin across the whole pack's depth range
	# and only really thickens out toward the genuinely distant background
	# (skyline/grandstand), not a horse merely running a bit further back.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_albedo = _theme.ambient_color
	env.volumetric_fog_gi_inject = 0.6

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
	# ground-level broadcast look — the one camera this game has, so every
	# lighting/post-processing choice above is tuned against exactly this
	# angle and distance with nothing else to compromise for.

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
		light.light_size = 0.5 # soft-edged shadow falloff instead of the hard default, matching the sun's light_angular_distance softening above
		add_child(light) # must be in the tree before look_at — it needs a global transform to compute against
		light.position = base_pos + Vector3(0.0, FLOODLIGHT_HEIGHT, 0.0)
		light.look_at(target_pos, Vector3.UP)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = camera_base_fov
	add_child(camera)

	# Depth of field was here (a telephoto-lens "pack sharp, background soft"
	# look) — AJ: "the blur is too much get rid of it you cant see the
	# horses at times." The tuned distances assumed a fixed ~24-unit
	# camera-to-pack gap (CAMERA_RAIL_OFFSET/CAMERA_HEIGHT), but the chase
	# camera's actual distance varies a lot more than that in practice
	# (turns, camera punches, free-look), so the pack itself was drifting
	# into the blur zone instead of staying reliably sharp. Removed outright
	# rather than re-tuned — "can't see the horses" is a correctness problem,
	# not a taste call to iterate on blind.
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = false
	camera.attributes = attributes

	camera_focus_fraction = 0.0
	camera_look_target = _sample_track(0.0, INNER_RADIUS * 0.5).position
	camera.current = true

	# Opens on the GATE establishing shot (see ShotState) rather than the old
	# fixed chase-cam framing — _update_camera takes over every subsequent
	# frame once _process starts running, this just makes the very first
	# rendered frame (before any _process tick) already show the right shot
	# instead of a one-frame flash of the old framing.
	_shot_state = ShotState.GATE
	_shot_state_time = 0.0
	_did_turn_cutaway = false
	_apply_camera_gate_shot()

## "Riders up... post time..." beat before the race actually starts —
## real broadcasts don't cut straight from the odds board to a running
## race. Awaits BroadcastHUD's countdown display, then fires the gate SFX
## and the announcer's opening call at the exact moment `play()` starts
## ticking frames, instead of firing them the instant the track is built.
func play_with_post_time() -> void:
	await broadcast_hud.show_odds_board()
	# "POST TIME" bugle beat, ~10s — horses already stand in their real gate-
	# stall position throughout (see the horse-placement loop above; an
	# earlier version of this session had them start further back and slide
	# forward into the gate after the bugle, but that read as "weird" in
	# practice and was reverted in favor of this simpler hold).
	#
	# Duck the theme music BEFORE the bugle plays, not just once the actual
	# race starts (the old timing) — a code trace confirmed the bugle was
	# genuinely firing but was inaudible against the still-full-volume theme
	# track, not actually silent.
	if has_audio_focus:
		AudioManager.duck_music_for_post_time()
	await broadcast_hud.play_bugle_call_beat(has_audio_focus)
	# AJ (later session): hearing both the riders-up bugle AND the gate bell
	# in the same pre-race sequence read as "the horn firing twice" — he
	# wants exactly ONE horn-family cue, timed to the actual gate-open
	# moment (countdown reaching zero), not an earlier separate one at
	# riders-up. Reversing the previous session's separate post_time_bugle
	# call (its own comment history is above/superseded) in favor of that:
	# race_start_bell below is now the ONLY such cue, fired once, exactly
	# when the doors actually open. post_time_bugle.mp3 stays on disk
	# unused, per this project's convention of not deleting shipped assets
	# just because code stops referencing them.
	await broadcast_hud.play_post_time_sequence()
	if has_audio_focus:
		AudioManager.play_sfx("race_start_bell")
		# horse_neigh.mp3 dropped from this beat: it's a raw digitized clip from
		# craigsmith's vintage-optical-reel archive (filename "G38-15-..."), and
		# reels from that specific collection are known to carry a spoken
		# archival slate (the engineer voicing the reel/take number, e.g.
		# "38-15") baked into the head of the recording, not just the whinny.
		# AJ heard exactly that ("a guy says #15 or #16") stepping on the
		# announcer's opening "And they're off!" line every single race, since
		# this fired in the same breath as announcer_director.race_start()
		# below. Cut rather than trimmed blind (no audio-editing tool in this
		# environment to verify a trim actually removes the slate and not the
		# whinny) — re-add a cleaner-sourced whinny later if the gate still
		# wants one.
	InputHints.rumble(0.3, 0.55, 0.3) # gate-open thump, felt not just heard on a connected controller
	_open_starting_gate() # synced to the same beat as the bell above, not the announcer's opening call
	announcer_director.race_start()
	play()

## AJ: "the other screens' horses were just sliding with no galloping
## animation" — real bug. horse_nodes[i].start_running() used to only be
## called from play_with_post_time(), right before ITS OWN call to play()
## here — but join_in_progress() (the entry point for a screen that tunes
## into a venue whose race is ALREADY underway, e.g. multi-screen simulcast
## catching a background race mid-flight) calls play(elapsed) DIRECTLY,
## skipping play_with_post_time() and its ceremony entirely by design (the
## gate already opened off-screen). That left every horse marker frozen in
## its idle-at-the-gate animation forever while _apply_frame kept moving its
## `position` forward every tick regardless — the mesh visually slid across
## the ground without ever switching to the gallop clip. Moved the
## start_running() call into THIS function instead, the one true entry point
## every playback path (fresh gate-open AND mid-race join) actually goes
## through — safe to call even if a horse is already running (see
## HorseMarker3D.start_running()'s own re-seek behavior, harmless either way).
func play(start_offset: float = 0.0) -> void:
	frame_index = 0
	playback_time = start_offset
	playing = true
	for marker in horse_nodes:
		marker.start_running()
	if start_offset <= 0.01:
		_shot_state = ShotState.GATE
		_shot_state_time = 0.0
		_did_turn_cutaway = false
	else:
		# Joining a race already in progress (see join_in_progress below) —
		# the gate ceremony already happened off-screen, so open straight into
		# CHASE and skip the once-per-race turn cutaway (an unrelated cutaway
		# firing the instant someone tunes in would read as broken, not
		# broadcast-authentic).
		_shot_state = ShotState.CHASE
		_did_turn_cutaway = true
		_snap_starting_gate_open()
	if has_audio_focus:
		AudioManager.start_race_ambience()

## Entry point for a screen assigned to a venue whose race is already
## underway (see RaceScheduler.get_live_race) — AJ: "if im not watching it it
## still runs and remains live until the race is over, if i choose to tune
## in itll open at whatever part of the race its at." Skips the entire
## pre-race ceremony play_with_post_time() runs (odds board, riders-up
## countdown, gate SFX, announcer's opening call) since all of that already
## "happened" during the time nobody was watching — seeking straight to
## `elapsed` makes every frame from the very first one land wherever the
## race actually is, no catch-up animation needed.
func join_in_progress(elapsed: float) -> void:
	if broadcast_hud != null:
		broadcast_hud.show_commentary("Joining the race live, in progress...")
	play(elapsed)

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
	_update_gate_fade(playback_time)
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

## Continuous crowd-swell bed (ramped up via AudioManager.set_crowd_swell_intensity
## during the stretch) was tried and cut — AJ: "the audience cheering the whole
## time is annoying," wanted crowd noise only at genuine bookend moments
## (start/finish), not a continuous ambient layer. Removed outright rather
## than re-tuned, matching this project's own established pattern for a cut
## audio addition (see AudioManager.gd's own history). The discrete one-shot
## reactions (RaceAnnouncerDirector's duel call, FinishPodium's finish cheer)
## are untouched — those are exactly the "only at a real moment" shape AJ
## wants, unlike the removed continuous bed.

## One horse just started a big surge — a punchy camera shake / quick FOV
## zoom-in, both eased back out over CAMERA_SHAKE_DURATION/
## CAMERA_PUNCH_DURATION in _update_camera.
func _trigger_big_move(horse_index: int) -> void:
	_camera_shake_time = CAMERA_SHAKE_DURATION
	_camera_punch_time = CAMERA_PUNCH_DURATION
	InputHints.rumble(0.15, 0.35, CAMERA_SHAKE_DURATION) # same window as the camera shake it's paired with
	announcer_director.on_big_move(horse_index)

## Right-stick "look around" + trigger zoom for the broadcast camera —
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

## Always runs (called once per frame from _update_camera) so the offsets
## ease back to 0 whenever no controller is connected instead of freezing at
## whatever they last were.
func _update_free_look(delta: float) -> void:
	var joypads: Array = Input.get_connected_joypads()
	if joypads.is_empty():
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

## Dispatcher: keeps the smoothed chase-cam tracking state (camera_focus_
## fraction/camera_look_target) current every frame regardless of which shot
## is actually on screen — see the ShotState comment for why — then hands off
## to whichever shot function is live. _update_shot_state runs the actual cut
## logic (thresholds/timers) against the same avg_fraction computed here.
func _update_camera(delta: float, fractions: PackedFloat32Array) -> void:
	if camera == null:
		return
	_update_free_look(delta)

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

	_camera_shake_time = max(0.0, _camera_shake_time - delta)
	_camera_punch_time = max(0.0, _camera_punch_time - delta)

	_update_shot_state(delta, avg_fraction)

	match _shot_state:
		ShotState.GATE:
			_apply_camera_gate_shot()
		ShotState.TURN_CUTAWAY:
			_apply_camera_turn_shot()
		ShotState.STRETCH:
			_apply_camera_stretch_shot()
		_:
			_apply_camera_chase_shot()

## Pure state-machine step — no camera writes here, just deciding which shot
## should be live this frame. Every transition is a hard CUT (see _cut_to),
## never a blend between two shots' positions.
func _update_shot_state(delta: float, avg_fraction: float) -> void:
	_shot_state_time += delta
	match _shot_state:
		ShotState.GATE:
			if _shot_state_time >= GATE_SHOT_DURATION or avg_fraction > 0.02:
				_cut_to(ShotState.CHASE)
		ShotState.TURN_CUTAWAY:
			if _shot_state_time >= TURN_CUTAWAY_DURATION or avg_fraction > TURN_CUTAWAY_END_FRACTION:
				_cut_to(ShotState.CHASE)
		ShotState.CHASE:
			if not _did_turn_cutaway and avg_fraction >= TURN_CUTAWAY_START_FRACTION and avg_fraction <= TURN_CUTAWAY_END_FRACTION:
				_did_turn_cutaway = true
				_cut_to(ShotState.TURN_CUTAWAY)
			elif avg_fraction >= STRETCH_SHOT_START_FRACTION:
				_cut_to(ShotState.STRETCH)
		ShotState.STRETCH:
			pass # holds through the finish; play_replay()/the podium take over from there

func _cut_to(state: ShotState) -> void:
	_shot_state = state
	_shot_state_time = 0.0

## Static wide establishing shot of the gate — see _build_starting_gate.
func _apply_camera_gate_shot() -> void:
	var outer_radius: float = _lane_radius(max(horse_nodes.size(), field.size()) - 1) + RAIL_GAP
	camera.position = _sample_track(-0.01, outer_radius + GATE_SHOT_BACK).position + Vector3(0.0, GATE_SHOT_HEIGHT, 0.0)
	camera.fov = camera_base_fov + GATE_SHOT_FOV_DELTA
	camera.look_at(_gate_world_center, Vector3.UP)

## Elevated "blimp" cutaway at the far turn — a genuinely different angle
## (much higher, much further back) rather than just a taller chase cam, so
## it reads as a broadcast truck switching to a second camera, not the same
## shot zoomed out. Still tracks camera_look_target (the smoothed pack
## centroid) so the pack stays framed even though the camera itself is fixed
## out at the turn rather than riding along with them.
func _apply_camera_turn_shot() -> void:
	var outer_radius: float = _lane_radius(horse_nodes.size() - 1) + RAIL_GAP
	camera.position = _sample_track(0.5, outer_radius + TURN_CAM_BACK).position + Vector3(0.0, TURN_CAM_HEIGHT, 0.0)
	camera.fov = camera_base_fov
	camera.look_at(camera_look_target, Vector3.UP)

## Fixed low finish-line "wire cam" for the stretch drive — position never
## moves once this shot is live, only the look_at pans/tilts to track the
## approaching pack, exactly like a real fixed finish-line camera.
func _apply_camera_stretch_shot() -> void:
	var outer_radius: float = _lane_radius(horse_nodes.size() - 1) + RAIL_GAP
	camera.position = _sample_track(0.03, outer_radius + STRETCH_CAM_BACK).position + Vector3(0.0, STRETCH_CAM_HEIGHT, 0.0)
	camera.fov = camera_base_fov
	camera.look_at(camera_look_target, Vector3.UP)

## The original broadcast dolly cam: rides a virtual rail outside the track,
## tracking the pack's average progress and centroid with exponential
## smoothing (frame-rate independent, unlike a flat lerp factor) so the pan
## feels like a trackside dolly rather than snapping straight to each frame's
## raw average. Camera shake/punch-zoom (see _trigger_big_move) and free-look
## are layered on top of that base position/FOV every frame, decaying
## linearly to zero over their duration — deliberately NOT applied to the
## other three shots above, since a shake/zoom on a fixed broadcast cutaway
## would read as a camera operator problem rather than an in-race moment.
func _apply_camera_chase_shot() -> void:
	var outer_radius: float = _lane_radius(horse_nodes.size() - 1) + RAIL_GAP
	var rail_radius: float = outer_radius + CAMERA_RAIL_OFFSET
	var rail_fraction: float = camera_focus_fraction + _free_look_fraction_offset
	var base_position: Vector3 = _sample_track(rail_fraction, rail_radius).position + Vector3(0.0, CAMERA_HEIGHT + _free_look_height_offset, 0.0)

	var shake_strength: float = _camera_shake_time / CAMERA_SHAKE_DURATION
	var shake_offset: Vector3 = Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
	) * CAMERA_SHAKE_MAGNITUDE * shake_strength

	var punch_strength: float = _camera_punch_time / CAMERA_PUNCH_DURATION
	camera.fov = camera_base_fov + CAMERA_PUNCH_FOV_DELTA * punch_strength + _free_look_fov_offset

	camera.position = base_position + shake_offset
	camera.look_at(camera_look_target, Vector3.UP)

## Samples a stadium curve of the given `radius` at lap `fraction` (0..1,
## wraps), on the XZ ground plane (Y always 0). Direct 3D port of the 2D
## version's _sample_track — same four-segment stadium shape, same
## continuity across all segment joins — just (x,y)->(x,0,z) and no
## analytical heading (facing is handled by look_at at the call site).
##
## AJ: "when you get to the top of the stretch it's so fucking short... make
## the finish line way after where just the bend is, like a real race." Before
## HOME_STRETCH_FRACTION existed, fraction 0 (where the finish line/gate are
## both planted — see _make_finish_line's comment) was exactly the point the
## final turn ends, i.e. zero straight track between "exiting the turn" and
## "crossing the wire" — the two 140-unit straights were being spent entirely
## as gate-runup + backstretch, none of it as an actual home stretch.
## HOME_STRETCH_FRACTION * STRAIGHT_LEN phase-shifts the fraction->position
## mapping so fraction 0 instead lands most of the way ALONG the front
## straight: the segment order for increasing fraction becomes [short
## post-gate run-up][turn1][back straight][turn2][long home stretch]->finish,
## without changing total lap distance (RaceSim.TRACK_LENGTH/perimeter are
## untouched) or any other fraction-based system below (grandstand, camera,
## scenery) — they all read fraction through this same function, so they
## relocate consistently for free. _build_starting_gate/_make_finish_line/
## _make_finish_arch are the only three things that DON'T go through
## fraction/this function (they place a raw Cartesian prop instead) and so
## each needed their own matching offset — see their own comments.
const HOME_STRETCH_FRACTION: float = 0.8

func _sample_track(fraction: float, radius: float) -> Dictionary:
	var half: float = STRAIGHT_LEN * 0.5
	var turn_len: float = PI * radius
	var perimeter: float = 2.0 * STRAIGHT_LEN + 2.0 * turn_len
	var s: float = fposmod(STRAIGHT_LEN * HOME_STRETCH_FRACTION + fposmod(fraction, 1.0) * perimeter, perimeter)

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

## Converts a fraction tuned by eye BEFORE HOME_STRETCH_FRACTION existed
## (i.e. against the old mapping where fraction 0 was turn2's exit) into the
## fraction that lands at that exact same physical spot now. Any fixed
## fraction constant meant to sit on a SPECIFIC segment (a straight, not
## whichever turn happens to be there now) needs this — otherwise the same
## literal fraction can silently land on a totally different segment once
## HOME_STRETCH_FRACTION shifts the mapping. Concretely what broke: the
## grandstand/bleachers (GRANDSTAND_FRACTION/BLEACHER_FRACTION, both tuned
## against the old mapping to sit "well inside" a specific straight) instead
## landed mid-TURN after that shift — flat, axis-aligned scenery built for a
## straight doesn't follow a turn's curve, so its footprint swung out across
## the actual lanes. AJ: "the horses just went right through the freaking
## stands." Needs the SAME radius the caller passes to _sample_track (the
## shift amount depends on perimeter, which depends on radius), so this
## can't be a single constant — it has to be computed per call site.
func _shifted_fraction(old_fraction: float, radius: float) -> float:
	var turn_len: float = PI * radius
	var perimeter: float = 2.0 * STRAIGHT_LEN + 2.0 * turn_len
	return fposmod(old_fraction - (STRAIGHT_LEN * HOME_STRETCH_FRACTION) / perimeter, 1.0)

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
	# Same HOME_STRETCH_FRACTION phase shift as _sample_track above — this
	# has to stay in lock-step with it, or the minimap's dot would drift away
	# from the real 3D horse position over the course of a race.
	var s: float = fposmod(straight_len * HOME_STRETCH_FRACTION + fposmod(fraction, 1.0) * perimeter, perimeter)

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

	var grass: Dictionary = _ground_surface_textures("grass", INFIELD_COLOR, _get_grass_detail_texture(), _get_grass_normal_texture())
	var dirt: Dictionary = _ground_surface_textures("dirt", TRACK_SURFACE_COLOR, _get_dirt_detail_texture(), _get_dirt_normal_texture())
	# Full effect from a real roughness map when one's present; the original
	# flat scalar otherwise (a real map's own values already ARE the surface's
	# roughness, so multiplying by anything less than 1.0 would just mute it).
	var grass_roughness: float = 1.0 if grass.roughness != null else 0.95
	var dirt_roughness: float = 1.0 if dirt.roughness != null else 0.85

	add_child(_make_fan_mesh(_track_loop_points(infield_radius), grass.tint, grass_roughness, grass.albedo, grass.normal, grass.roughness))
	add_child(_make_ring_mesh(_track_loop_points(infield_radius), _track_loop_points(outer_radius), dirt.tint, dirt_roughness, dirt.albedo, dirt.normal, dirt.roughness))
	# Everything past the outer rail (skyline buildings, perimeter flags, the
	# fairgrounds/bleachers on venues that have them) previously had no
	# ground under it at all — just the sky material's flat ground_horizon
	# color showing through, which read as "the floor is see-through" once
	# there was finally enough background geometry (the new fairgrounds
	# dressing) sitting out there to notice it against. OUTER_GROUND_RADIUS
	# reaches well past SKYLINE_RADIUS_MARGIN (55) so the skyline ring sits
	# ON solid ground rather than right at this plane's own edge, and well
	# past the camera's own DOF far-blur distance (45, see _build_camera)
	# so there's no visible edge even at the farthest the camera ever
	# resolves detail. Same grass texture/material as the infield — real
	# tracks' surrounding grounds are grass, and reusing the material this
	# scene already builds costs nothing extra.
	const OUTER_GROUND_MARGIN: float = 180.0
	add_child(_make_ring_mesh(_track_loop_points(outer_radius), _track_loop_points(outer_radius + OUTER_GROUND_MARGIN), grass.tint, grass_roughness, grass.albedo, grass.normal, grass.roughness))
	add_child(_make_rail_mesh(_track_loop_points(infield_radius), RAIL_HEIGHT, RAIL_COLOR, 0.35))
	add_child(_make_rail_mesh(_track_loop_points(outer_radius), RAIL_HEIGHT, RAIL_COLOR, 0.35))
	add_child(_make_finish_line(infield_radius, outer_radius))
	add_child(_make_finish_arch(infield_radius, outer_radius))

## A visible mechanical gate at the start/finish line — see the _gate_doors
## class comment. Sits on the STRAIGHT segment (fraction ~0), so this uses
## _make_finish_line's own direct-coordinate approach (x/z computed straight
## from STRAIGHT_LEN/radius, no _sample_track call) rather than trying to
## thread a small negative fraction through the stadium curve math — exact
## and simple, since the gate never needs to sit anywhere but flat across the
## straight.
func _build_starting_gate() -> void:
	_gate_doors.clear()
	_gate_fade_started = false
	var infield_radius: float = INNER_RADIUS - RAIL_GAP
	var outer_radius: float = _lane_radius(field.size() - 1) + RAIL_GAP
	var half: float = STRAIGHT_LEN * 0.5
	# fraction 0 (gate/finish) sits at HOME_STRETCH_FRACTION along the
	# straight now, not at its very start — see _sample_track's own comment.
	var gate_x: float = -half + STRAIGHT_LEN * HOME_STRETCH_FRACTION - GATE_SETBACK - GATE_DEPTH * 0.5
	var span: float = outer_radius - infield_radius

	_gate_root = Node3D.new()
	_gate_root.name = "StartingGate"
	add_child(_gate_root)

	_gate_world_center = Vector3(gate_x, GATE_HEIGHT * 0.5, infield_radius + span * 0.5)

	_gate_frame_mat = _make_material(GATE_FRAME_COLOR, 0.4)
	_gate_door_mat = _make_material(GATE_DOOR_COLOR, 0.5)
	# Both need per-instance alpha tweening later (see _fade_out_starting_gate)
	# — StandardMaterial3D doesn't blend alpha at all unless transparency is
	# explicitly turned on, regardless of what the albedo color's own alpha
	# channel says.
	_gate_frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gate_door_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var beam := MeshInstance3D.new()
	beam.mesh = BoxMesh.new()
	beam.mesh.size = Vector3(GATE_DEPTH, 0.25, span + 0.4)
	beam.material_override = _gate_frame_mat
	beam.position = Vector3(gate_x, GATE_HEIGHT, infield_radius + span * 0.5)
	_gate_root.add_child(beam)

	for end_z in [infield_radius - 0.2, outer_radius + 0.2]:
		var post := MeshInstance3D.new()
		post.mesh = BoxMesh.new()
		post.mesh.size = Vector3(GATE_DEPTH, GATE_HEIGHT, 0.2)
		post.material_override = _gate_frame_mat
		post.position = Vector3(gate_x, GATE_HEIGHT * 0.5, end_z)
		_gate_root.add_child(post)

	# One swinging "saloon door" per lane, alternating which side it hinges
	# from so neighboring doors swing away from each other rather than all
	# sweeping the same direction and overlapping mid-open (see
	# _gate_open_angle for the matching rotation-sign derivation).
	for i in range(field.size()):
		var lane_center: float = _lane_radius(i)
		var door_width: float = LANE_GAP * 0.88
		var hinge_sign: float = 1.0 if i % 2 == 0 else -1.0

		var hinge := Node3D.new()
		hinge.position = Vector3(gate_x, 0.0, lane_center - hinge_sign * door_width * 0.5)
		_gate_root.add_child(hinge)

		var door := MeshInstance3D.new()
		door.mesh = BoxMesh.new()
		door.mesh.size = Vector3(0.05, GATE_HEIGHT, door_width)
		door.material_override = _gate_door_mat
		door.position = Vector3(0.0, GATE_HEIGHT * 0.5, hinge_sign * door_width * 0.5)
		hinge.add_child(door)

		_gate_doors.append(hinge)

## Rotating a hinge by +angle around Y swings a door whose local Z offset is
## positive toward +X (the direction of travel, per _sample_track: fraction
## increasing along the straight increases X) — so a door hinged with
## hinge_sign=+1 needs +angle to swing forward, and hinge_sign=-1 needs
## -angle for the same forward swing. Used by the tweened open (see
## _open_starting_gate) — joining a race already in progress skips this
## entirely and just removes the gate outright (_snap_starting_gate_open).
func _gate_open_angle(lane_index: int) -> float:
	var hinge_sign: float = 1.0 if lane_index % 2 == 0 else -1.0
	return hinge_sign * deg_to_rad(GATE_DOOR_OPEN_ANGLE_DEG)

## Tweened open, timed to the gate bell — see play_with_post_time(). Also
## kicks off the delayed fade/removal below, since "doors just opened" is the
## only moment this needs to be scheduled from.
func _open_starting_gate() -> void:
	for i in range(_gate_doors.size()):
		var tw: Tween = create_tween()
		tw.tween_property(_gate_doors[i], "rotation:y", _gate_open_angle(i), GATE_DOOR_OPEN_DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

## AJ: the gate structure should read as "before the race" scenery, not a
## permanent fixture like the finish arch — fades to transparent and is freed
## once the field has had time to visibly clear it, rather than sitting in
## the background (mostly out of frame after the camera cuts away, but still
## technically present) for the rest of the race. Driven off `playback_time`
## (see _process's call to this) rather than a real-world get_tree().
## create_timer() coroutine on purpose: SceneTree timers here run on actual
## wall-clock time regardless of Engine.time_scale (see
## racetrack_playback_check.gd's own comment on this exact quirk), so a
## timer-based fade left this coroutine still suspended — and its Tween/
## material refs still alive — when a time_scale-compressed test race
## finished and quit() before the real-world delay had elapsed, showing up as
## a genuine "resources still in use at exit" leak. Gating on playback_time
## instead scales correctly with everything else this class already ties to
## the race clock (shot cuts, crowd swell), and can never outlive the node
## that owns it.
func _update_gate_fade(current_time: float) -> void:
	if _gate_fade_started or _gate_root == null:
		return
	if current_time < GATE_DOOR_OPEN_DURATION + GATE_FADE_DELAY:
		return
	_gate_fade_started = true
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(_gate_frame_mat, "albedo_color:a", 0.0, GATE_FADE_DURATION)
	tw.tween_property(_gate_door_mat, "albedo_color:a", 0.0, GATE_FADE_DURATION)
	tw.chain().tween_callback(_free_gate_root)

func _free_gate_root() -> void:
	if _gate_root != null and is_instance_valid(_gate_root):
		_gate_root.queue_free()
	_gate_root = null

## Used when joining a race already underway (see play()) — the gate already
## opened (and, realistically, already faded) off-screen before anyone tuned
## in, so this just removes it outright rather than animating anything nobody
## would see anyway.
func _snap_starting_gate_open() -> void:
	if _gate_root != null and is_instance_valid(_gate_root):
		_gate_root.queue_free()
	_gate_root = null

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
	_build_grandstand_reflection_probe()
	_build_perimeter_flags(outer_radius)
	_build_skyline(outer_radius)
	_build_spectators(infield_radius)
	if _has_fairgrounds:
		_build_backstretch_bleachers(infield_radius)
		_build_fairgrounds_backdrop()

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

## "coastal_hills" swaps the distant-city skyline for low rolling hills —
## dark skyscraper silhouettes (right, under a night/neon theme) read as a
## backdrop error under a bright sunny coastal theme instead, where real
## Del Mar's own backdrop is inland bluffs, not a downtown skyline. Opt-in
## per-theme (TrackThemes' skyline_style key, default "skyscraper") so
## every other theme's skyline is untouched.
const HILL_MIN_HEIGHT: float = 5.0
const HILL_MAX_HEIGHT: float = 11.0
const HILL_COLOR: Color = Color(0.56, 0.63, 0.58) # hazy blue-green, atmospheric-perspective distant hill, not a saturated near-field green

func _build_skyline(outer_radius: float) -> void:
	var skyline_radius: float = outer_radius + SKYLINE_RADIUS_MARGIN
	var coastal_hills: bool = String(_theme.get("skyline_style", "skyscraper")) == "coastal_hills"
	for i in range(SKYLINE_COUNT):
		var frac: float = float(i) / float(SKYLINE_COUNT) + randf_range(-0.01, 0.01)
		var pos: Vector3 = _sample_track(frac, skyline_radius).position
		add_child(_make_coastal_hill(pos) if coastal_hills else _make_building(pos))

func _make_coastal_hill(pos: Vector3) -> Node3D:
	var hill := Node3D.new()
	hill.position = pos

	var height: float = randf_range(HILL_MIN_HEIGHT, HILL_MAX_HEIGHT)
	var width: float = height * randf_range(2.4, 3.4)
	var mound := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = width * 0.5
	mesh.height = height * 2.0 # half buried at y=0 so only a dome of the intended `height` shows above ground
	mound.mesh = mesh
	var shade: float = randf_range(0.9, 1.1)
	mound.material_override = _make_material(Color(HILL_COLOR.r * shade, HILL_COLOR.g * shade, HILL_COLOR.b * shade), 0.95)
	hill.add_child(mound)

	return hill

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

## Real film/broadcast productions fill background stands the same way:
## flat cutout cards painted with many people, not individually modeled
## extras — reads as a genuinely denser, more convincing crowd than discrete
## capsule "people" at similar or lower cost (a handful of billboarded quads
## vs. 45 separate small meshes). Texture is procedurally generated (see
## scripts/tools/generate_crowd_billboard.gd) rather than a sourced photo —
## avoids any license-verification risk, and at the distance a broadcast
## camera ever actually sees the grandstand from, a painted card and a photo
## cutout read almost identically anyway. Falls back to the original capsule
## standees (_build_spectators_legacy) if that PNG is ever missing, same
## graceful-fallback pattern as HorseMarker3D/horse.glb.
const CROWD_BILLBOARD_PATH: String = "res://assets/textures/crowd_billboard.png"
const CROWD_CARD_WIDTH: float = 7.0
const CROWD_CARD_HEIGHT: float = 2.2 # matches the generated texture's ~3.2:1 aspect
const CROWD_CARD_COUNT: int = 10

func _make_billboard_material(texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	# Scissor, not blend — these cards never need soft/antialiased edges (the
	# generated texture's shapes are hard-edged anyway), and scissor avoids
	# any transparency sort-order fighting between overlapping cards or with
	# the grandstand/rail behind them.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	return mat

func _build_spectators(infield_radius: float) -> void:
	var texture: Texture2D = _get_cached_texture(CROWD_BILLBOARD_PATH)
	if texture == null:
		_build_spectators_legacy(infield_radius)
		return

	var mesh_instance := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(CROWD_CARD_WIDTH, CROWD_CARD_HEIGHT)
	quad.material = _make_billboard_material(texture)
	multimesh.mesh = quad
	multimesh.instance_count = CROWD_CARD_COUNT

	# Same placement footprint as the old capsule cluster (just inside the
	# infield rail, centered on the grandstand's own fraction) — a row of
	# overlapping-enough cards spanning that same arc instead of a scatter of
	# individual points.
	var cluster_radius: float = infield_radius - 1.2
	var grandstand_frac: float = _shifted_fraction(GRANDSTAND_FRACTION, cluster_radius)
	for i in range(CROWD_CARD_COUNT):
		var t: float = float(i) / float(max(CROWD_CARD_COUNT - 1, 1))
		var frac: float = grandstand_frac + lerp(-0.05, 0.05, t)
		var pos: Vector3 = _sample_track(frac, cluster_radius).position
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos + Vector3(0.0, CROWD_CARD_HEIGHT * 0.5, 0.0)))

	mesh_instance.multimesh = multimesh
	add_child(mesh_instance)

## Original capsule-standee crowd — kept as the fallback for
## _build_spectators above if the billboard texture is ever missing.
func _build_spectators_legacy(infield_radius: float) -> void:
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
	var grandstand_frac: float = _shifted_fraction(GRANDSTAND_FRACTION, cluster_radius)
	for i in range(SPECTATOR_COUNT):
		var frac: float = grandstand_frac + randf_range(-0.045, 0.045)
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
	# Trees each land at their own random radius (r, below) chosen AFTER this
	# clearance check, so there's no single exact radius to shift against —
	## a fuzzy exclusion zone this wide (TREE_CLEAR_FRACTION_HALF_WIDTH=0.09)
	# doesn't need per-tree precision anyway; shifting against the actual
	# grandstand/bleacher structure's own radius is representative enough.
	var grandstand_frac: float = _shifted_fraction(GRANDSTAND_FRACTION, GRANDSTAND_CENTER_RADIUS)
	var bleacher_frac: float = _shifted_fraction(BLEACHER_FRACTION, BLEACHER_CENTER_RADIUS)
	for i in range(TREE_COUNT):
		var frac: float = float(i) / float(TREE_COUNT) + randf_range(-0.02, 0.02)
		var dist_from_grandstand: float = abs(fposmod(frac - grandstand_frac + 0.5, 1.0) - 0.5)
		if dist_from_grandstand < TREE_CLEAR_FRACTION_HALF_WIDTH:
			continue # stay clear of the grandstand's footprint
		if _has_fairgrounds:
			var dist_from_bleachers: float = abs(fposmod(frac - bleacher_frac + 0.5, 1.0) - 0.5)
			if dist_from_bleachers < TREE_CLEAR_FRACTION_HALF_WIDTH:
				continue # stay clear of the backstretch bleachers' footprint too, this venue only
		var r: float = lerp(4.0, max_tree_radius, randf())
		var pos: Vector3 = _sample_track(frac, r).position
		if String(_theme.get("tree_style", "round")) == "palm":
			add_child(_make_palm_tree(pos))
		else:
			add_child(_make_tree(pos))

## Opt-in per-theme (TrackThemes' tree_style key, default "round") — round
## leafy-canopy trees don't fit a sunny coastal theme the way palms do. Same
## "flat local space, no need for anything fancier" shape language as the
## round tree: a tall thin trunk plus a fan of flat frond blades radiating
## outward and drooping from a single crown point.
const PALM_TRUNK_HEIGHT: float = 4.6
const PALM_TRUNK_TOP_RADIUS: float = 0.11
const PALM_TRUNK_BOTTOM_RADIUS: float = 0.22
const PALM_TRUNK_COLOR: Color = Color(0.45, 0.34, 0.2)
const PALM_FROND_COUNT: int = 7
const PALM_FROND_LENGTH: float = 2.0
const PALM_FROND_WIDTH: float = 0.35
const PALM_FROND_THICKNESS: float = 0.05
const PALM_FROND_DROOP_DEGREES: float = 35.0
const PALM_FROND_COLOR: Color = Color(0.2, 0.5, 0.22)

func _make_palm_tree(pos: Vector3) -> Node3D:
	var tree := Node3D.new()
	tree.position = pos
	tree.rotation.y = randf_range(0.0, TAU)
	tree.scale = Vector3.ONE * randf_range(0.85, 1.25)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = PALM_TRUNK_TOP_RADIUS
	trunk_mesh.bottom_radius = PALM_TRUNK_BOTTOM_RADIUS
	trunk_mesh.height = PALM_TRUNK_HEIGHT
	trunk.mesh = trunk_mesh
	trunk.position = Vector3(0.0, PALM_TRUNK_HEIGHT * 0.5, 0.0)
	trunk.rotation.z = randf_range(-0.12, 0.12) # a slight natural lean, no two palms perfectly vertical
	trunk.material_override = _make_material(PALM_TRUNK_COLOR, 0.85)
	tree.add_child(trunk)

	var crown := Node3D.new()
	crown.position = Vector3(0.0, PALM_TRUNK_HEIGHT, 0.0)
	tree.add_child(crown)
	for i in range(PALM_FROND_COUNT):
		var pivot := Node3D.new()
		pivot.rotation.y = (float(i) / float(PALM_FROND_COUNT)) * TAU + randf_range(-0.08, 0.08)
		pivot.rotation.x = deg_to_rad(PALM_FROND_DROOP_DEGREES + randf_range(-5.0, 5.0))
		crown.add_child(pivot)

		var frond := MeshInstance3D.new()
		var frond_mesh := BoxMesh.new()
		frond_mesh.size = Vector3(PALM_FROND_WIDTH, PALM_FROND_THICKNESS, PALM_FROND_LENGTH)
		frond.mesh = frond_mesh
		frond.position = Vector3(0.0, 0.0, -PALM_FROND_LENGTH * 0.5) # extends outward along local -Z, then the pivot's own rotation aims it out/down
		frond.material_override = _make_material(PALM_FROND_COLOR, 0.8)
		pivot.add_child(frond)

	return tree

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
## geometrically valid where the track itself is actually straight — this
## constant is tuned (by the s-math this comment used to describe) to sit
## well inside the front straight with real margin on both sides, clear of
## both the finish-line cluster and the turn where a straight box can't
## follow the curve.
##
## MUST be passed through _shifted_fraction(GRANDSTAND_FRACTION, radius)
## wherever it's used as a _sample_track fraction, never used bare — this
## literal value was tuned against the OLD (pre-HOME_STRETCH_FRACTION)
## mapping, where fraction 0 was the finish line at the very start of the
## straight. HOME_STRETCH_FRACTION moved the finish deep into the straight,
## and this same literal fraction, unshifted, no longer lands on the straight
## at all — it lands mid-turn instead (see _shifted_fraction's own comment:
## this is exactly what put the grandstand through the track).
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

## A single UPDATE_ONCE ReflectionProbe centered on the grandstand — SSR
## (env.ssr_enabled, see _build_lighting) only reflects whatever's already
## on-screen, so the grandstand's own near-mirror tiers (GRANDSTAND_COLOR_
## LOWER/UPPER, see below) still went flat whenever the sky/skyline that
## should be glinting off them was out of frame. The grandstand and its roof
## never move once built, so one bake at race start is enough — UPDATE_ALWAYS
## would spend real per-frame cost reflecting a scene that's already static,
## for no visible gain. Doesn't touch SSR/tonemap/glow or anything else
## _build_lighting already tuned; it only adds a reflection source those
## couldn't reach.
func _build_grandstand_reflection_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(70.0, 26.0, 70.0)
	probe.position = _sample_track(_shifted_fraction(GRANDSTAND_FRACTION, GRANDSTAND_CENTER_RADIUS), GRANDSTAND_CENTER_RADIUS).position \
		+ Vector3(0.0, GRANDSTAND_TIER_HEIGHT * GRANDSTAND_TIERS * 0.5, 0.0)
	add_child(probe)

func _build_grandstand(infield_radius: float) -> void:
	if GRANDSTAND_CENTER_RADIUS + GRANDSTAND_TIER_DEPTH * GRANDSTAND_TIERS >= infield_radius:
		return # safety guard in case field size ever shrinks infield_radius below what this needs

	var stand := Node3D.new()
	var base_pos: Vector3 = _sample_track(_shifted_fraction(GRANDSTAND_FRACTION, GRANDSTAND_CENTER_RADIUS), GRANDSTAND_CENTER_RADIUS).position
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

	_build_grandstand_crowd(stand)

const GRANDSTAND_CROWD_CARDS_PER_TIER: int = 3
const GRANDSTAND_CROWD_CARD_WIDTH: float = 10.0 # card_height is now DERIVED from this at the same aspect ratio CROWD_CARD_WIDTH/CROWD_CARD_HEIGHT already establishes, not a separate fixed constant — see _build_grandstand_crowd_on's own comment

## Every tier was previously bare chrome — an empty grandstand undercuts the
## "real broadcast" read as much as an empty infield does. Same billboard
## crowd-card technique/texture as _build_spectators, added as children of
## `stand` (the same Node3D _build_grandstand already builds the tiers
## under) so they automatically inherit the grandstand's own position — no
## separate world-space placement math needed. No-ops gracefully (matching
## _build_spectators' own fallback) if the billboard texture is missing;
## unlike the infield crowd there's no capsule-standee equivalent for empty
## tiers worth building, so this simply skips rather than substituting
## something else.
func _build_grandstand_crowd(stand: Node3D) -> void:
	_build_grandstand_crowd_on(stand, GRANDSTAND_TIERS, GRANDSTAND_TIER_HEIGHT, GRANDSTAND_TIER_DEPTH, GRANDSTAND_LENGTH)

## Venue-specific extras (_has_fairgrounds only, currently just Mesa
## Fairgrounds — see Venues.gd) — open bleacher seating on the BACK straight,
## opposite side of the oval from the main grandstand, plus a fairgrounds
## Ferris-wheel/tent backdrop looming behind the grandstand itself. AJ asked
## for "bleachers on the sides and a fairgrounds background... as the
## backdrop of this horse venue" when this venue was built as a Del Mar-
## inspired track (Del Mar's own real-world identity is literally sharing
## its infield with the county fairgrounds — a Ferris wheel visible over the
## backstretch is one of that track's most recognizable real broadcast
## shots) — obviously different geometry/names throughout, per that same ask.
##
## Same straight-sided-box-in-local-space approach as _build_grandstand (see
## its own header comment for why that's only valid on a straight section),
## just mirrored to the BACK straight instead of the front one. Simpler than
## the grandstand on purpose (3 open tiers, no roof/struts) — real trackside
## bleachers vs. the clubhouse-style main grandstand.
## Centered well inside the back straight. Same caveat as GRANDSTAND_FRACTION
## above: MUST go through _shifted_fraction(BLEACHER_FRACTION, radius)
## wherever it's used, never bare — tuned against the pre-HOME_STRETCH_
## FRACTION mapping.
const BLEACHER_FRACTION: float = 0.65
const BLEACHER_CENTER_RADIUS: float = 15.0
const BLEACHER_LENGTH: float = 26.0
const BLEACHER_TIERS: int = 3
const BLEACHER_TIER_HEIGHT: float = 1.4
const BLEACHER_TIER_DEPTH: float = 1.8

func _build_backstretch_bleachers(infield_radius: float) -> void:
	if BLEACHER_CENTER_RADIUS + BLEACHER_TIER_DEPTH * BLEACHER_TIERS >= infield_radius:
		return # same safety guard as _build_grandstand, in case field size ever shrinks infield_radius below what this needs

	var stand := Node3D.new()
	stand.position = _sample_track(_shifted_fraction(BLEACHER_FRACTION, BLEACHER_CENTER_RADIUS), BLEACHER_CENTER_RADIUS).position
	# The back straight runs the opposite winding direction from the front
	# one (_sample_track's own s-math: x decreases with s here, vs.
	# increasing on the front straight) — a 180° turn keeps each tier's
	# local +X "front row" facing back toward the track/camera instead of
	# away from it, and z_offset below can stay the same sign convention
	# _build_grandstand already uses ("steps back toward center as it rises").
	stand.rotation.y = PI
	add_child(stand)

	for tier in range(BLEACHER_TIERS):
		var block := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(BLEACHER_LENGTH, BLEACHER_TIER_HEIGHT, BLEACHER_TIER_DEPTH)
		block.mesh = mesh
		var y: float = BLEACHER_TIER_HEIGHT * (float(tier) + 0.5)
		var z_offset: float = -BLEACHER_TIER_DEPTH * 0.5 * float(tier)
		block.position = Vector3(0.0, y, z_offset)
		var t: float = float(tier) / float(max(BLEACHER_TIERS - 1, 1))
		block.material_override = _make_material(GRANDSTAND_COLOR_LOWER.lerp(GRANDSTAND_COLOR_UPPER, t), 0.35)
		stand.add_child(block)

		var trim := MeshInstance3D.new()
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(BLEACHER_LENGTH, 0.08, 0.08)
		trim.mesh = trim_mesh
		trim.position = Vector3(0.0, y + BLEACHER_TIER_HEIGHT * 0.5, z_offset + BLEACHER_TIER_DEPTH * 0.5)
		trim.material_override = _make_material(GRANDSTAND_TRIM_COLOR, 0.4, null, GRANDSTAND_TRIM_COLOR, 2.0)
		stand.add_child(trim)

	_build_grandstand_crowd_on(stand, BLEACHER_TIERS, BLEACHER_TIER_HEIGHT, BLEACHER_TIER_DEPTH, BLEACHER_LENGTH)

## _build_grandstand_crowd itself is hardcoded to the GRANDSTAND_* constants
## — generalized into this parameterized version so the bleachers above can
## reuse the exact same billboard-crowd technique against their own (smaller)
## tier dimensions instead of duplicating the whole function body. Behavior
## for the original call site is unchanged (it just forwards the GRANDSTAND_*
## constants it already used inline).
func _build_grandstand_crowd_on(stand: Node3D, tiers: int, tier_height: float, tier_depth: float, length: float) -> void:
	var texture: Texture2D = _get_cached_texture(CROWD_BILLBOARD_PATH)
	if texture == null:
		return

	# AJ: "the scaling on the people in the stands sucks" — real bug: this
	# card used a FIXED height (GRANDSTAND_CROWD_CARD_HEIGHT, a ~5.88:1
	# width:height ratio) regardless of card_width, which itself gets
	# clamped narrower on shorter tiers (length / CARDS_PER_TIER, e.g. the
	# Mesa Fairgrounds bleachers). The source texture's own native aspect is
	# ~3.2:1 (see CROWD_CARD_WIDTH/CROWD_CARD_HEIGHT above, which correctly
	# preserves it for the infield spectator cards) — using a mismatched
	# fixed height here stretched/squished the same painted crowd image
	# non-uniformly, worse the narrower card_width got clamped. Fixed by
	# deriving height from card_width at the SAME aspect ratio the infield
	# cards already use, instead of a second, inconsistent hardcoded height.
	var card_width: float = min(GRANDSTAND_CROWD_CARD_WIDTH, length / float(GRANDSTAND_CROWD_CARDS_PER_TIER))
	var card_height: float = card_width * (CROWD_CARD_HEIGHT / CROWD_CARD_WIDTH)
	var mesh_instance := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(card_width, card_height)
	quad.material = _make_billboard_material(texture)
	multimesh.mesh = quad
	multimesh.instance_count = tiers * GRANDSTAND_CROWD_CARDS_PER_TIER

	var idx: int = 0
	for tier in range(tiers):
		var y: float = tier_height * (float(tier) + 0.85)
		var z_offset: float = -tier_depth * 0.5 * float(tier) + tier_depth * 0.3
		for c in range(GRANDSTAND_CROWD_CARDS_PER_TIER):
			var t: float = float(c) / float(max(GRANDSTAND_CROWD_CARDS_PER_TIER - 1, 1))
			var x: float = lerp(-length * 0.5 + card_width * 0.5, length * 0.5 - card_width * 0.5, t)
			multimesh.set_instance_transform(idx, Transform3D(Basis(), Vector3(x, y, z_offset)))
			idx += 1

	mesh_instance.multimesh = multimesh
	stand.add_child(mesh_instance)

## Ferris wheel + a few striped fair tents, positioned deeper in the infield
## than the grandstand (smaller radius = further from the outer rail = further
## from the camera, which always sits just outside it — see
## _build_environment's own header comment on why that reads as "background"
## rather than an obstruction) at the SAME fraction as the grandstand, so it
## naturally looms up behind the grandstand's roofline (roof height 8.5) from
## the camera's usual angle, exactly like Del Mar's real fairgrounds midway is
## visible over the grandstand in real broadcast shots of that track.
const FAIRGROUNDS_RADIUS: float = 7.0

## First version of this positioned the wheel via its own separate
## _sample_track(GRANDSTAND_FRACTION, FAIRGROUNDS_RADIUS) call — but
## _sample_track's straight-segment X depends on the PERIMETER, which
## depends on the radius passed in (perimeter = 2*straight_len +
## 2*PI*radius) — so the same fraction at a different radius lands at a
## different X, drifting the whole fairgrounds cluster sideways relative to
## the grandstand instead of sitting directly behind it. Fixed by reusing
## the grandstand's OWN already-computed X directly (same fraction, radius
## GRANDSTAND_CENTER_RADIUS) and only changing Z/depth, which keeps the two
## structures aligned regardless of straight_len.
func _build_fairgrounds_backdrop() -> void:
	var grandstand_pos: Vector3 = _sample_track(_shifted_fraction(GRANDSTAND_FRACTION, GRANDSTAND_CENTER_RADIUS), GRANDSTAND_CENTER_RADIUS).position
	var base_pos: Vector3 = Vector3(grandstand_pos.x, 0.0, FAIRGROUNDS_RADIUS)
	add_child(_build_ferris_wheel(base_pos))
	# Offsets kept OUTSIDE the grandstand's own footprint (half-width
	# GRANDSTAND_LENGTH/2 + roof overhang ≈ 18.5) rather than directly behind
	# it — tents/NPCs are ground-level and short (a few units tall), unlike
	# the Ferris wheel above, which solved this same occlusion problem by
	# growing tall enough to clear the roofline entirely. A short prop can't
	# do that, so it has to sit beside the grandstand instead of behind it.
	var tent_colors: Array[Color] = [Color(0.75, 0.15, 0.15), Color(0.15, 0.35, 0.7), Color(0.85, 0.75, 0.15)]
	var tent_offsets: Array[float] = [-24.0, -21.0, 21.0, 24.0]
	for i in range(tent_offsets.size()):
		var pos: Vector3 = base_pos + Vector3(tent_offsets[i], 0.0, 2.0)
		add_child(_build_fair_tent(pos, tent_colors[i % tent_colors.size()]))
	_build_fairgrounds_crowd(base_pos)

## AJ: "add some npcs" — a small midway crowd milling around the tents/wheel
## base, same billboard-card technique (and same texture) as
## _build_spectators, just scattered loosely across the fairgrounds footprint
## instead of packed in a single row along the rail. Falls back to nothing
## (not the capsule-standee legacy path _build_spectators has) if the
## texture's missing — this is extra background flavor for one venue, not
## load-bearing "does the infield look empty" scenery the way the main
## grandstand crowd is.
const FAIRGROUNDS_CROWD_COUNT: int = 8
const FAIRGROUNDS_CROWD_CARD_WIDTH: float = 3.5
const FAIRGROUNDS_CROWD_CARD_HEIGHT: float = 1.1 # same aspect ratio as CROWD_CARD_WIDTH/CROWD_CARD_HEIGHT (~3.2:1, the source texture's real native aspect) — was 2.0 (a mismatched ~1.75:1), stretching the same painted crowd image, same underlying bug as _build_grandstand_crowd_on's own fix

func _build_fairgrounds_crowd(base_pos: Vector3) -> void:
	var texture: Texture2D = _get_cached_texture(CROWD_BILLBOARD_PATH)
	if texture == null:
		return

	var mesh_instance := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(FAIRGROUNDS_CROWD_CARD_WIDTH, FAIRGROUNDS_CROWD_CARD_HEIGHT)
	quad.material = _make_billboard_material(texture)
	multimesh.mesh = quad
	multimesh.instance_count = FAIRGROUNDS_CROWD_COUNT

	# Same "stay outside the grandstand's own footprint" reasoning as the
	# tents in _build_fairgrounds_backdrop — a ground-level billboard this
	# short is fully hidden if placed directly behind the grandstand's
	# taller structure. Split into two clusters flanking left/right (near
	# each side's pair of tents) instead of one centered scatter.
	for i in range(FAIRGROUNDS_CROWD_COUNT):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var offset := Vector3(side * randf_range(19.0, 26.0), 0.0, randf_range(0.5, 3.0))
		var pos: Vector3 = base_pos + offset + Vector3(0.0, FAIRGROUNDS_CROWD_CARD_HEIGHT * 0.5, 0.0)
		multimesh.set_instance_transform(i, Transform3D(Basis(), pos))

	mesh_instance.multimesh = multimesh
	add_child(mesh_instance)

## Built "flat" in local XZ space (a Ferris wheel viewed face-on, like a clock
## face lying on a table) since that's the plane every primitive here
## naturally sizes/rotates in with plain 2D trig — then the WHOLE assembly is
## tipped up 90° around X in one shot at the end, which rigidly preserves
## every child's relative position/rotation. Confirmed working via an
## isolated throwaway test (a ring of colored boxes under a rotation.x=PI/2
## parent, screenshotted face-on) before trusting it here — this project has
## been burned before by unverified 3D orientation assumptions.
##
## First real version of this used a much smaller radius/height and got hit
## by a DIFFERENT bug entirely: the grandstand structure (closer to the
## camera, at GRANDSTAND_CENTER_RADIUS=15) physically occluded the wheel's
## lower half (which sat at world Y down to ~1.5, well inside the
## grandstand's own silhouette) — not a rotation problem, a "the closer
## opaque object is hiding the farther one" composition problem. Fixed by
## raising the whole wheel high enough that even its BOTTOM edge
## (HUB_HEIGHT - RADIUS) clears the grandstand's roof (GRANDSTAND_ROOF_HEIGHT
## 8.5) with real margin, so it reads as looming above/behind the stands
## instead of peeking through gaps in them.
const FERRIS_WHEEL_RADIUS: float = 8.0
const FERRIS_WHEEL_HUB_HEIGHT: float = 17.0 # bottom of wheel at 17-8=9, clears the grandstand's 8.5 roof; top reaches 25
const FERRIS_WHEEL_SPOKE_COUNT: int = 8
const FERRIS_WHEEL_RIM_SEGMENTS: int = 20
const FERRIS_WHEEL_RIM_THICKNESS: float = 0.55 # was 0.35 — too thin to read as a solid ring against a bright sky, looked like loose scaffolding
const FERRIS_WHEEL_SPOKE_THICKNESS: float = 0.32 # was 0.22, same reasoning
const FERRIS_WHEEL_STRUCTURE_COLOR: Color = Color(0.32, 0.3, 0.28) # was near-black 0.16/0.15/0.14 — a near-black wireframe has almost no contrast against a bright daytime sky; a mid gray reads as painted steel instead
const FERRIS_WHEEL_GONDOLA_COLORS: Array[Color] = [Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.9), Color(0.95, 0.8, 0.2), Color(0.35, 0.8, 0.4)]

func _build_ferris_wheel(base_pos: Vector3) -> Node3D:
	var wheel := Node3D.new()
	wheel.position = base_pos

	# Two angled A-frame support towers holding the hub up off the ground —
	# built in real 3D (not the flat-plane trick below), same simple
	# angled-strut idea as _build_grandstand's own roof struts, just taller
	# and with a cross-brace since this tower is much taller than that one.
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = 0.3
		leg_mesh.bottom_radius = 0.45
		leg_mesh.height = FERRIS_WHEEL_HUB_HEIGHT + 1.5
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 3.2, FERRIS_WHEEL_HUB_HEIGHT * 0.5, 0.0)
		leg.rotation.z = side * -0.22
		leg.material_override = _make_material(FERRIS_WHEEL_STRUCTURE_COLOR, 0.6)
		wheel.add_child(leg)

	var brace := MeshInstance3D.new()
	var brace_mesh := BoxMesh.new()
	brace_mesh.size = Vector3(7.0, 0.25, 0.25)
	brace.mesh = brace_mesh
	brace.position = Vector3(0.0, FERRIS_WHEEL_HUB_HEIGHT * 0.55, 0.0)
	brace.material_override = _make_material(FERRIS_WHEEL_STRUCTURE_COLOR, 0.6)
	wheel.add_child(brace)

	# The flat "face" — rim/spokes/hub built in local XZ (Y = face normal),
	# tipped up to stand vertically (facing the camera along its new local Z)
	# by rotating this one sub-node 90° around X.
	var face := Node3D.new()
	face.position = Vector3(0.0, FERRIS_WHEEL_HUB_HEIGHT, 0.0)
	face.rotation.x = PI * 0.5
	wheel.add_child(face)

	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 1.0
	hub_mesh.bottom_radius = 1.0
	hub_mesh.height = 0.8
	hub.mesh = hub_mesh
	hub.material_override = _make_material(FERRIS_WHEEL_STRUCTURE_COLOR, 0.4)
	face.add_child(hub)

	for i in range(FERRIS_WHEEL_SPOKE_COUNT):
		var angle: float = float(i) / float(FERRIS_WHEEL_SPOKE_COUNT) * TAU
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(FERRIS_WHEEL_SPOKE_THICKNESS, FERRIS_WHEEL_SPOKE_THICKNESS, FERRIS_WHEEL_RADIUS)
		spoke.mesh = spoke_mesh
		# Rotating local +Z by rotation.y = theta sends it to
		# (sin(theta), 0, cos(theta)); solving sin(theta)=cos(angle),
		# cos(theta)=sin(angle) gives theta = PI/2 - angle, so the spoke's
		# long (Z) axis points at (cos(angle), 0, sin(angle)) as intended —
		# confirmed via the isolated rotation test referenced above.
		spoke.rotation.y = PI * 0.5 - angle
		spoke.position = Vector3(cos(angle), 0.0, sin(angle)) * (FERRIS_WHEEL_RADIUS * 0.5)
		spoke.material_override = _make_material(FERRIS_WHEEL_STRUCTURE_COLOR, 0.6)
		face.add_child(spoke)

	for i in range(FERRIS_WHEEL_RIM_SEGMENTS):
		var a: float = float(i) / float(FERRIS_WHEEL_RIM_SEGMENTS) * TAU
		var b: float = float(i + 1) / float(FERRIS_WHEEL_RIM_SEGMENTS) * TAU
		var p_a: Vector3 = Vector3(cos(a), 0.0, sin(a)) * FERRIS_WHEEL_RADIUS
		var p_b: Vector3 = Vector3(cos(b), 0.0, sin(b)) * FERRIS_WHEEL_RADIUS
		var mid_angle: float = (a + b) * 0.5
		var seg := MeshInstance3D.new()
		var seg_mesh := BoxMesh.new()
		seg_mesh.size = Vector3(FERRIS_WHEEL_RIM_THICKNESS, FERRIS_WHEEL_RIM_THICKNESS, p_a.distance_to(p_b) * 1.15) # generous overlap so the polygon rim reads as a continuous ring, not gapped segments
		seg.mesh = seg_mesh
		seg.position = (p_a + p_b) * 0.5
		seg.rotation.y = PI * 0.5 - mid_angle
		seg.material_override = _make_material(FERRIS_WHEEL_STRUCTURE_COLOR, 0.5)
		face.add_child(seg)

		# A short hanger arm plus an inward-set "bucket" (AJ: "add some
		# buckets") reads as a suspended gondola cabin rather than a cube
		# glued flush to the rim — true gravity-correct hanging would need
		# the bucket offset along local +Z (which maps to -Y/"down" after
		# the face's own tip-up rotation, per this function's own derivation
		# above), but for a static background prop at broadcast-camera
		# distance an inward-radial offset reads close enough without that
		# extra complexity.
		var hanger := MeshInstance3D.new()
		var hanger_mesh := BoxMesh.new()
		hanger_mesh.size = Vector3(0.08, 0.08, 0.6)
		hanger.mesh = hanger_mesh
		hanger.position = p_a * 0.92
		hanger.rotation.y = PI * 0.5 - a
		hanger.material_override = _make_material(FERRIS_WHEEL_STRUCTURE_COLOR, 0.6)
		face.add_child(hanger)

		var gondola := MeshInstance3D.new()
		var gondola_mesh := BoxMesh.new()
		gondola_mesh.size = Vector3(1.0, 1.15, 1.0)
		gondola.mesh = gondola_mesh
		gondola.position = p_a * 0.82
		var gondola_color: Color = FERRIS_WHEEL_GONDOLA_COLORS[i % FERRIS_WHEEL_GONDOLA_COLORS.size()]
		gondola.material_override = _make_material(gondola_color, 0.5, null, gondola_color, 1.0)
		face.add_child(gondola)

	return wheel

## Simple striped fair tent — a cone roof + cylinder body, one solid canvas
## color per tent (the alternating RED/BLUE/YELLOW cluster from
## _build_fairgrounds_backdrop is what reads as "striped midway," rather than
## literal stripes painted on any single tent).
const FAIR_TENT_BODY_RADIUS: float = 1.6
const FAIR_TENT_BODY_HEIGHT: float = 2.2
const FAIR_TENT_ROOF_HEIGHT: float = 1.8

func _build_fair_tent(pos: Vector3, color: Color) -> Node3D:
	var tent := Node3D.new()
	tent.position = pos

	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = FAIR_TENT_BODY_RADIUS
	body_mesh.bottom_radius = FAIR_TENT_BODY_RADIUS
	body_mesh.height = FAIR_TENT_BODY_HEIGHT
	body.mesh = body_mesh
	body.position = Vector3(0.0, FAIR_TENT_BODY_HEIGHT * 0.5, 0.0)
	body.material_override = _make_material(Color(0.92, 0.9, 0.86), 0.8) # plain canvas-white body, the color goes on the roof
	tent.add_child(body)

	var roof := MeshInstance3D.new()
	var roof_mesh := CylinderMesh.new() # a cone (top_radius 0) reusing the same primitive as the body
	roof_mesh.top_radius = 0.0
	roof_mesh.bottom_radius = FAIR_TENT_BODY_RADIUS * 1.15
	roof_mesh.height = FAIR_TENT_ROOF_HEIGHT
	roof.mesh = roof_mesh
	roof.position = Vector3(0.0, FAIR_TENT_BODY_HEIGHT + FAIR_TENT_ROOF_HEIGHT * 0.5, 0.0)
	roof.material_override = _make_material(color, 0.7)
	tent.add_child(roof)

	var pennant := MeshInstance3D.new()
	var pennant_mesh := BoxMesh.new()
	pennant_mesh.size = Vector3(0.08, 0.5, 0.08)
	pennant.mesh = pennant_mesh
	pennant.position = Vector3(0.0, FAIR_TENT_BODY_HEIGHT + FAIR_TENT_ROOF_HEIGHT + 0.25, 0.0)
	pennant.material_override = _make_material(color, 0.4, null, color, 1.2)
	tent.add_child(pennant)

	return tent

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

## Generic path->Texture2D cache, shared by the ground PBR textures, the sky
## HDRIs, and the crowd billboard below — same "load once, cache by name
## (null cached too, so a missing file isn't re-`ResourceLoader.exists`-
## checked every race), reuse forever" pattern AudioManager._sfx_cache
## already established for optional audio assets. `null` in the cache means
## "checked, confirmed missing" — every caller treats that as "fall back
## gracefully," never as an error.
static var _texture_cache: Dictionary = {}

static func _get_cached_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path)
	_texture_cache[path] = tex
	return tex

## Real CC0 PBR photo textures (Poly Haven/ambientCG — see ATTRIBUTION.md)
## for the track's dirt/grass surfaces, replacing the original procedural
## noise-based mottling with actual photographed ground detail — falls back
## to that original noise texture (passed in as `noise_albedo`/`noise_normal`)
## if the photo set is missing, same graceful-fallback pattern as
## HorseMarker3D/horse.glb. A real photo already carries its own natural
## color, so it gets a near-white tint (StandardMaterial3D always multiplies
## albedo_texture * albedo_color) rather than the full saturated theme color
## the noise texture needs — full theme color would double-tint/darken a
## real photo, but a light tint still lets each theme's day/overcast/night
## mood come through on top of the real texture.
func _ground_surface_textures(name: String, theme_color: Color, noise_albedo: NoiseTexture2D, noise_normal: NoiseTexture2D) -> Dictionary:
	var albedo: Texture2D = _get_cached_texture("res://assets/textures/%s/albedo.jpg" % name)
	if albedo != null:
		return {
			"albedo": albedo,
			"normal": _get_cached_texture("res://assets/textures/%s/normal.jpg" % name),
			"roughness": _get_cached_texture("res://assets/textures/%s/roughness.jpg" % name),
			"tint": Color.WHITE.lerp(theme_color, 0.2),
		}
	return {"albedo": noise_albedo, "normal": noise_normal, "roughness": null, "tint": theme_color}

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

static var _dirt_normal_texture: NoiseTexture2D
static var _grass_normal_texture: NoiseTexture2D

## Real surface relief instead of a flat plane that only ever looks
## textured from directly overhead — same noise-based approach as the
## albedo detail textures above, but rendered as a tangent-space normal map
## (NoiseTexture2D.as_normal_map) so the floodlights/sun actually pick out
## bump detail at grazing broadcast-camera angles. Higher frequency than the
## albedo variants (finer grain reads as "surface roughness," not the same
## broad mottling already carried by albedo) and a separate noise seed so
## the two don't look like one texture doing double duty.
static func _get_dirt_normal_texture() -> NoiseTexture2D:
	if _dirt_normal_texture == null:
		_dirt_normal_texture = _build_normal_texture(11, 0.35, 4.0)
	return _dirt_normal_texture

static func _get_grass_normal_texture() -> NoiseTexture2D:
	if _grass_normal_texture == null:
		_grass_normal_texture = _build_normal_texture(12, 0.45, 2.5)
	return _grass_normal_texture

static func _build_normal_texture(noise_seed: int, frequency: float, bump_strength: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = noise_seed
	noise.frequency = frequency

	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = bump_strength
	tex.width = 256
	tex.height = 256
	return tex

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
func _make_material(color: Color, roughness: float = 0.9, detail_texture: Texture2D = null, emission: Color = Color(0.0, 0.0, 0.0, 0.0), emission_energy: float = 1.0, normal_texture: Texture2D = null, roughness_texture: Texture2D = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = detail_texture # multiplies with albedo_color when set — null is a no-op, same as before
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission.a > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	if normal_texture != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_texture
	if roughness_texture != null:
		mat.roughness_texture = roughness_texture # multiplies with the `roughness` scalar above, same relationship as albedo_texture*albedo_color
	return mat

## Fills a convex loop (the stadium shape is convex) as a triangle fan from
## its own center point — used for the infield. UVs are planar (world XZ /
## GROUND_TEXTURE_SCALE) so `detail_texture` tiles across the surface based
## on actual world position rather than reading as one flat, undefined color
## (SurfaceTool defaults every vertex to UV (0,0) if never explicitly set).
func _make_fan_mesh(points: Array[Vector3], color: Color, roughness: float = 0.9, detail_texture: Texture2D = null, normal_texture: Texture2D = null, roughness_texture: Texture2D = null) -> MeshInstance3D:
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
	st.generate_tangents() # required for StandardMaterial3D.normal_texture to have any effect
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _make_material(color, roughness, detail_texture, Color(0.0, 0.0, 0.0, 0.0), 1.0, normal_texture, roughness_texture)
	return mesh_instance

## Fills the annulus between two same-length, same-parameterization loops
## (inner/outer at matching fractions) as a strip of quads — used for the
## dirt track surface between the infield and the outer rail. Same planar
## world-space UV approach as _make_fan_mesh above.
func _make_ring_mesh(inner: Array[Vector3], outer: Array[Vector3], color: Color, roughness: float = 0.9, detail_texture: Texture2D = null, normal_texture: Texture2D = null, roughness_texture: Texture2D = null) -> MeshInstance3D:
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
	st.generate_tangents() # required for StandardMaterial3D.normal_texture to have any effect
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _make_material(color, roughness, detail_texture, Color(0.0, 0.0, 0.0, 0.0), 1.0, normal_texture, roughness_texture)
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
## (see RaceSim.TRACK_LENGTH), so start and finish coincide, HOME_STRETCH_
## FRACTION of the way along the front straight (_sample_track(0.0, r) for
## any radius r — see that function's own comment for why it's not at the
## straight's start anymore). Sits slightly above the dirt ring mesh
## (y = FINISH_LINE_Y) to avoid z-fighting.
func _make_finish_line(infield_radius: float, outer_radius: float) -> MeshInstance3D:
	var half: float = STRAIGHT_LEN * 0.5
	var finish_x: float = -half + STRAIGHT_LEN * HOME_STRETCH_FRACTION
	var x0: float = finish_x - FINISH_LINE_WIDTH * 0.5
	var x1: float = finish_x + FINISH_LINE_WIDTH * 0.5
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

const FINISH_ARCH_HEIGHT: float = 4.2 # well above a galloping horse's head — the field needs to visibly pass UNDER this, never clip it
const FINISH_ARCH_POST_SIZE: float = 0.18
const FINISH_ARCH_WIRE_THICKNESS: float = 0.07
const FINISH_ARCH_POST_COLOR: Color = Color(0.82, 0.82, 0.85) # neutral white-metal — deliberately NOT the gate's red, see the gate/arch comment below

## AJ: the finish line needs real vertical height — a wire the field passes
## UNDER, like a real finish line — not just the flat checkered ground tile
## above (_make_finish_line, kept as-is; real finish lines have both a
## painted stripe on the track AND an overhead wire/arch). Also needs to read
## as visually distinct from the starting gate (_build_starting_gate): this
## is a permanent fixture that stays up the whole race, so it deliberately
## does NOT reuse the gate's red-frame/white-door look or its fade-out
## behavior — thin white posts, a slim continuously-glowing gold wire (reuses
## UITheme.COLOR_GOLD, tying into the same broadcast-gold language as the
## rail's own emissive glow) rather than the gate's opaque red/white boxes.
func _make_finish_arch(infield_radius: float, outer_radius: float) -> Node3D:
	var half: float = STRAIGHT_LEN * 0.5
	# Same finish_x as _make_finish_line — keep these two in lock-step, they're
	# the same physical line (a painted stripe plus the overhead wire above it).
	var finish_x: float = -half + STRAIGHT_LEN * HOME_STRETCH_FRACTION
	var arch := Node3D.new()
	arch.name = "FinishArch"

	var post_mat: StandardMaterial3D = _make_material(FINISH_ARCH_POST_COLOR, 0.4)
	for z in [infield_radius, outer_radius]:
		var post := MeshInstance3D.new()
		post.mesh = BoxMesh.new()
		post.mesh.size = Vector3(FINISH_ARCH_POST_SIZE, FINISH_ARCH_HEIGHT, FINISH_ARCH_POST_SIZE)
		post.material_override = post_mat
		post.position = Vector3(finish_x, FINISH_ARCH_HEIGHT * 0.5, z)
		arch.add_child(post)

	var wire := MeshInstance3D.new()
	wire.mesh = BoxMesh.new()
	wire.mesh.size = Vector3(FINISH_ARCH_WIRE_THICKNESS, FINISH_ARCH_WIRE_THICKNESS, outer_radius - infield_radius + FINISH_ARCH_POST_SIZE)
	wire.material_override = _make_material(Color.BLACK, 0.4, null, UITheme.COLOR_GOLD, 3.0)
	wire.position = Vector3(finish_x, FINISH_ARCH_HEIGHT, infield_radius + (outer_radius - infield_radius) * 0.5)
	arch.add_child(wire)

	return arch
