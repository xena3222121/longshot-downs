class_name HorseMarker3D
extends Node3D

## 3D counterpart of HorseMarker.gd — same optional-asset graceful fallback:
## a crude placeholder capsule+box shape until a real rigged horse model
## exists at MODEL_PATH, at which point setup() swaps in the real model and
## plays its run animation instead. RaceTrack3D calls setup() the same way
## either way and positions/orients this node externally via look_at, so it
## doesn't need to know or care which mode is active.

const MODEL_PATH: String = "res://assets/horse3d/horse.glb"
const RUN_ANIMATION_CANDIDATES: Array[String] = [
	"Gallop", "gallop", "Run", "run", "Canter", "canter", "Armature|Gallop", "Armature|Run",
]

static var _cached_model: PackedScene
static var _model_checked: bool = false

var body_color: Color = Color.WHITE
var accent_color: Color = Color.BLACK

var _surge_trail: CPUParticles3D
var _dust_trail: CPUParticles3D
var _is_surging: bool = false
var _anim_player: AnimationPlayer
var _visual_root: Node3D
var _bob_phase: float = 0.0

func setup(p_body_color: Color, p_accent_color: Color) -> void:
	body_color = p_body_color
	accent_color = p_accent_color

	_visual_root = Node3D.new() # holds the mesh only, so the stride bob below (see _process) never moves this node's own origin — RaceTrack3D positions THAT via _sample_track, and the dust trail is anchored to it too
	add_child(_visual_root)

	var model: PackedScene = _get_model()
	if model != null:
		_build_real_model(model)
	else:
		_build_placeholder()

	_build_surge_trail()
	_build_dust_trail()
	_build_ground_shadow()

## "Arcade excess" pass: a burst of bright trailing sparks while this horse
## is actively making a big mid-race move (see RaceTrack3D's surge-threshold
## handling, which toggles this on/off every frame) — makes a surge visibly
## read as "this horse is doing something" rather than only being legible
## through the lane-merge/camera-follow behavior. `local_coords = true` so
## the trail streams out behind the horse in its own frame of reference
## (drifting backward relative to the horse) rather than getting dragged
## along rigidly with it.
func _build_surge_trail() -> void:
	_surge_trail = CPUParticles3D.new()
	_surge_trail.emitting = false
	_surge_trail.amount = 28
	_surge_trail.lifetime = 0.5
	_surge_trail.local_coords = true
	_surge_trail.position = Vector3(0.0, 0.9, 0.6) # roughly hindquarters height, just behind center
	_surge_trail.direction = Vector3(0.0, 0.2, 1.0) # local +Z is "behind" (look_at aims -Z at travel direction)
	_surge_trail.spread = 20.0
	_surge_trail.initial_velocity_min = 2.0
	_surge_trail.initial_velocity_max = 4.5
	_surge_trail.gravity = Vector3.ZERO
	_surge_trail.scale_amount_min = 0.12
	_surge_trail.scale_amount_max = 0.22
	_surge_trail.color = accent_color
	add_child(_surge_trail)

## Subtle always-on dirt kick-up at ground level, distinct from the surge
## trail above (which is a bright accent-colored burst gated to big moves
## only). Anchored at local Y near 0 rather than anything derived from the
## model's height — HorseMarker3D's own local origin is always exactly at
## track-surface height (RaceTrack3D._sample_track's Y is always 0), so this
## is correct regardless of which model (or the placeholder) is active.
func _build_dust_trail() -> void:
	_dust_trail = CPUParticles3D.new()
	_dust_trail.emitting = true
	_dust_trail.amount = 14
	_dust_trail.lifetime = 0.4
	_dust_trail.local_coords = true
	_dust_trail.position = Vector3(0.0, 0.05, 0.5)
	_dust_trail.direction = Vector3(0.0, 0.35, 1.0)
	_dust_trail.spread = 25.0
	_dust_trail.initial_velocity_min = 0.6
	_dust_trail.initial_velocity_max = 1.6
	_dust_trail.gravity = Vector3(0.0, -2.0, 0.0)
	_dust_trail.scale_amount_min = 0.08
	_dust_trail.scale_amount_max = 0.16
	_dust_trail.color = Color(0.6, 0.68, 0.78, 0.5) # cool grey-blue kickup off the synthetic track, not brown dirt dust
	add_child(_dust_trail)

## Called every playback frame by RaceTrack3D based on this horse's current
## surge value crossing SURGING_THRESHOLD — cheap to call every frame since
## it only touches `.emitting` when the state actually flips.
func set_surging(active: bool) -> void:
	if active == _is_surging:
		return
	_is_surging = active
	_surge_trail.emitting = active

## Highest point of the actual visual mesh, in THIS node's own local space
## (ground level = 0, same frame RaceTrack3D positions this node in) — unions
## every MeshInstance3D's AABB under _visual_root rather than just the first
## one found, since the placeholder has three separate meshes (body/head/legs)
## and the tallest one isn't necessarily the first child. Used by
## RaceTrack3D's jockey POV camera to sit reliably ABOVE the model regardless
## of its real proportions, instead of a guessed height constant — the same
## "measure the real geometry, don't eyeball it" approach this project used
## for jockey-rider placement before (no way to visually verify 3D placement
## in this headless dev environment, so guessed constants have twice now
## landed the camera either too low or clipping into the model).
func get_top_y() -> float:
	if _visual_root == null:
		return 1.8 # sane fallback if ever called before setup()
	var top: float = _max_top_y(_visual_root, Transform3D.IDENTITY)
	return top if top > -INF else 1.8

## `parent_transform` maps `node`'s PARENT into this node's own local space —
## composing each Node3D's own `.transform` while recursing mirrors exactly
## how the engine itself computes final mesh positions, without needing every
## node already inside a live SceneTree with valid global transforms.
func _max_top_y(node: Node, parent_transform: Transform3D) -> float:
	var local_transform: Transform3D = parent_transform
	if node is Node3D:
		local_transform = parent_transform * node.transform

	var top: float = -INF
	if node is MeshInstance3D and node.mesh != null:
		var aabb: AABB = node.mesh.get_aabb()
		for i in range(8):
			var corner: Vector3 = aabb.position + Vector3(
				aabb.size.x * float(i & 1),
				aabb.size.y * float((i >> 1) & 1),
				aabb.size.z * float((i >> 2) & 1),
			)
			top = max(top, (local_transform * corner).y)

	for child in node.get_children():
		top = max(top, _max_top_y(child, local_transform))
	return top

static func _get_model() -> PackedScene:
	if not _model_checked:
		_model_checked = true
		if FileAccess.file_exists(MODEL_PATH):
			_cached_model = load(MODEL_PATH)
	return _cached_model

## Deliberately way faster than a real gallop cadence — AJ asked for the
## horses to "gallop ridiculously," a cartoonish blur-legged sprint rather
## than a physically accurate stride rate. This is the baseline cadence at a
## "typical" pace (RaceSim.BASE_SPEED); set_gait_speed() below scales it up
## or down from here to track each horse's ACTUAL speed that tick, rather
## than every horse's legs cycling at this exact same rate regardless of
## whether it's surging, fatigued, or coasting to a stop after the finish.
const GAIT_SPEED_SCALE: float = 3.5

## Bounds on the real-speed multiplier applied to GAIT_SPEED_SCALE — without
## a floor a fatigued/coasting horse's legs would nearly freeze (looks like
## the animation broke, not like a horse slowing down); without a ceiling a
## big surge spike would blur the legs into an unreadable flicker.
const GAIT_SPEED_MIN_MULT: float = 0.4
const GAIT_SPEED_MAX_MULT: float = 1.8

## Small stride-synced vertical bounce applied to the visual mesh only (never
## to this node's own origin — RaceTrack3D relies on that staying exactly on
## the track surface each frame, and the dust trail is anchored to it too).
## absf(sin(...)) stays >= 0 always: a running gait bounces UP off each
## stride, it doesn't dip below the ground. Phase speed tracks the same
## speed_scale set_gait_speed() already drives the leg animation at, so a
## surging horse bounces faster and a fatigued one bounces slower instead of
## bobbing at one fixed rate regardless of pace.
const BOB_AMPLITUDE: float = 0.045
const BOB_BASE_FREQUENCY: float = 2.6

func _process(delta: float) -> void:
	if _visual_root == null:
		return
	var speed_mult: float = 1.0
	if _anim_player != null and GAIT_SPEED_SCALE > 0.0:
		speed_mult = _anim_player.speed_scale / GAIT_SPEED_SCALE
	_bob_phase += delta * BOB_BASE_FREQUENCY * speed_mult
	_visual_root.position.y = absf(sin(_bob_phase * TAU)) * BOB_AMPLITUDE

func _build_real_model(model: PackedScene) -> void:
	var instance: Node3D = model.instantiate()
	_visual_root.add_child(instance)
	instance.rotation.y = PI # this source model's rig faces +Z; look_at() above aims -Z at the travel direction
	_tint_coat(instance)
	var anim_player: AnimationPlayer = _find_animation_player(instance)
	if anim_player == null:
		return
	_anim_player = anim_player
	anim_player.speed_scale = GAIT_SPEED_SCALE

	var anim_name: String = ""
	for candidate in RUN_ANIMATION_CANDIDATES:
		if anim_player.has_animation(candidate):
			anim_name = candidate
			break
	if anim_name == "":
		var list: PackedStringArray = anim_player.get_animation_list()
		if list.size() > 0:
			anim_name = list[0]
	if anim_name == "":
		return

	# The imported clip defaults to "play once and freeze on the last frame"
	# (glTF has no native loop flag) — without forcing it to loop, the horse
	# gallops through the clip once at the start of the race and then holds
	# a static pose in whatever position that clip happened to end on for
	# the rest of the race.
	var anim: Animation = anim_player.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	anim_player.play(anim_name)

	# Every horse starts this clip at the same moment, at the same
	# speed_scale — without a random phase offset they gallop in perfect
	# lockstep (identical leg position on every horse, every frame), which
	# reads as a synchronized toy/clone effect rather than a real herd.
	# Jumping to a random point in the clip right away desyncs each horse's
	# stride from the others.
	if anim != null and anim.length > 0.0:
		anim_player.seek(randf() * anim.length, true)

## Called every playback frame by RaceTrack3D with this horse's actual
## ground speed that tick (RaceSim's effective_speed, straight from
## RaceResult.speeds — no re-derivation from position deltas needed). No-op
## on the placeholder (no AnimationPlayer to drive).
## time_scale lets a caller playing frames slower/faster than real-time (see
## RaceTrack3D.play_replay's slow-mo) keep the leg-cycle rate consistent with
## how fast the body is actually seen to move, not just how fast it's really
## running in sim-time.
func set_gait_speed(sim_speed: float, time_scale: float = 1.0) -> void:
	if _anim_player == null:
		return
	var mult: float = clamp(sim_speed / RaceSim.BASE_SPEED, GAIT_SPEED_MIN_MULT, GAIT_SPEED_MAX_MULT)
	_anim_player.speed_scale = GAIT_SPEED_SCALE * mult * time_scale

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null

## horse.glb's single mesh has 8 named surfaces: Main/Main_Dark/Main_Light
## (the coat's base/shadow/highlight tones), Hair (mane+tail), and
## Muzzle/Hooves/Eye_Black/Eye_White (left alone — recoloring eyes or hooves
## would look wrong regardless of silk color). Coat surfaces get their HUE
## and SATURATION replaced with body_color's while keeping each surface's
## own original VALUE (brightness) — this preserves the light/dark shading
## relationship between the three coat tones instead of flattening them to
## one flat color, so the coat still reads as shaded, just recolored. Hair
## gets the same hue/sat transplant using accent_color, the same "silks"
## pairing (body/accent) used everywhere else in this game.
const COAT_SURFACE_NAMES: Array[String] = ["Main", "Main_Dark", "Main_Light"]
const MANE_SURFACE_NAME: String = "Hair"

func _tint_coat(instance: Node3D) -> void:
	var mesh_instance: MeshInstance3D = _find_mesh_instance(instance)
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	for i in range(mesh_instance.mesh.get_surface_count()):
		var original: Material = mesh_instance.get_active_material(i)
		if original == null:
			continue

		var tint: Color
		if original.resource_name in COAT_SURFACE_NAMES:
			tint = body_color
		elif original.resource_name == MANE_SURFACE_NAME:
			tint = accent_color
		else:
			continue

		# Materials loaded from a PackedScene are shared across every
		# instantiate() call — mutating one in place would recolor every
		# horse using this cached model to whichever horse tinted it last.
		# set_surface_override_material with a duplicated material keeps
		# the change local to this one instance.
		var tinted: Material = original.duplicate()
		if tinted is StandardMaterial3D:
			var orig_value: float = original.albedo_color.v if original is StandardMaterial3D else 1.0
			tinted.albedo_color = Color.from_hsv(tint.h, tint.s, orig_value)
			# Subtle rim light — a built-in StandardMaterial3D feature (no
			# custom shader needed) that catches the floodlights along the
			# coat's edge, matching this game's existing broadcast/neon
			# lighting language instead of the coat reading as flat, unlit
			# plastic.
			tinted.rim_enabled = true
			tinted.rim = 0.25
			tinted.rim_tint = 0.5
		mesh_instance.set_surface_override_material(i, tinted)

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null

## Crude blocky placeholder: a horizontal capsule body + a box head, tinted
## by silk colors — reads as "a horse" from a distance, in the same spirit
## as the 2D version's circles-and-lines silhouette.
func _build_placeholder() -> void:
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.35
	body_mesh.height = 1.5
	body.mesh = body_mesh
	body.rotation.x = deg_to_rad(90.0)
	body.position = Vector3(0.0, 0.6, 0.0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body.material_override = body_mat
	_visual_root.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.28, 0.28, 0.55)
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.0, -0.85)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = accent_color
	head.material_override = head_mat
	_visual_root.add_child(head)

	var legs := MeshInstance3D.new()
	var legs_mesh := BoxMesh.new()
	legs_mesh.size = Vector3(0.55, 0.6, 0.2)
	legs.mesh = legs_mesh
	legs.position = Vector3(0.0, 0.3, 0.0)
	var legs_mat := StandardMaterial3D.new()
	legs_mat.albedo_color = accent_color
	legs.material_override = legs_mat
	_visual_root.add_child(legs)

## A soft radial dark blob flush with the ground, always exactly under the
## horse regardless of the dynamic directional-light shadow (which can be
## faint/absent depending on floodlight angle) — cheap grounding cue so the
## horse reads as touching the track rather than floating over it,
## especially from the broadcast camera's distance. Reuses the same
## GradientTexture2D radial-fade trick RaceTrack3D/TitleScreen already use
## elsewhere in this project rather than a custom shader.
const GROUND_SHADOW_SIZE: Vector2 = Vector2(1.6, 0.9)

func _build_ground_shadow() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.45))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64

	var shadow := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = GROUND_SHADOW_SIZE
	shadow.mesh = mesh
	shadow.rotation.x = -PI * 0.5 # lays the quad flat, normal facing up
	shadow.position = Vector3(0.0, 0.015, 0.0) # just above track surface, avoids z-fighting like FINISH_LINE_Y does

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow.material_override = mat
	add_child(shadow)
