class_name HorseMarker3D
extends Node3D

## 3D counterpart of HorseMarker.gd — same optional-asset graceful fallback:
## a crude placeholder capsule+box shape until a real rigged horse model
## exists at MODEL_PATH, at which point setup() swaps in the real model and
## plays its run animation instead. RaceTrack3D calls setup() the same way
## either way and positions/orients this node externally via look_at, so it
## doesn't need to know or care which mode is active.

## assets/horse3d_candidate/horse-01.glb was left wired in here mid-experiment
## (uncommitted) — turned out to be a generic PBR material-swatch test asset,
## not a real horse texture, and its metallic=1.0 material is why every
## horse rendered as a flat black silhouette regardless of scene lighting or
## theme brightness (a fully metallic surface has no diffuse response — it
## only shows anything via strong specular/reflection, which this scene
## never gave it). Reverted to the real, tint-verified model every comment
## in this file (_tint_coat, COAT_SURFACE_NAMES, etc.) was actually built
## and tested against. The candidate files are left on disk untouched in
## case that model swap was intentional and worth finishing properly later
## with a real horse texture.
## A second, separate temporary-test-then-revert: MODEL_PATH was pointed at
## assets/horse3d/candidates/horse_candidate_09_scale_fix.glb (the final
## step of a full AI-generation/decimation/rigging pipeline aimed at fixing
## the "hot dog horses" complaint) for live in-game review, left wired in
## uncommitted-decision-pending. Compared side by side against a screenshot:
## the raw model itself looked fine, but run through the REAL _tint_coat
## pipeline below (built and tuned against the old model's specific surface
## names/UVs) it renders as a blotchy, mottled, diseased-looking mess — worse
## than the model it was meant to replace, not better. Reverted for that
## reason. The candidate files stay on disk (see the comment above on why)
## in case a future pass wants to either re-texture that model or adapt
## _tint_coat to its actual surface layout properly instead of assuming the
## old model's names/UVs carry over.
const MODEL_PATH: String = "res://assets/horse3d/horse.glb"
const RUN_ANIMATION_CANDIDATES: Array[String] = [
	"Gallop", "gallop", "Run", "run", "Canter", "canter", "Armature|Gallop", "Armature|Run",
]
const IDLE_ANIMATION_CANDIDATES: Array[String] = [
	"Idle", "idle", "AnimalArmature|Idle",
]

static var _cached_model: PackedScene

var body_color: Color = Color.WHITE
var accent_color: Color = Color.BLACK
var horse_id: int = 0

var _surge_trail: CPUParticles3D
var _dust_trail: CPUParticles3D
var _is_surging: bool = false
var _anim_player: AnimationPlayer
var _run_anim_name: String = ""
var _run_anim: Animation
var _skeleton: Skeleton3D # only set for the real model — see _build_saddle_cloth
var _visual_root: Node3D
var _bob_phase: float = 0.0

func setup(p_body_color: Color, p_accent_color: Color, p_horse_id: int = 0, p_post_position: int = 0) -> void:
	body_color = p_body_color
	accent_color = p_accent_color
	horse_id = p_horse_id

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
	if p_post_position > 0:
		_build_saddle_cloth(p_post_position)

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

## Real racehorses ARE individually identifiable mid-race by exactly this —
## a numbered cloth on the saddle, in the owner's own silk colors — so this
## isn't a "floating badge" compromise, it's what actually happens at a real
## track. Needed once coat color went from race-specific silk hues to a
## small fixed NATURAL_COAT_COLORS palette keyed by horse_id (see
## _tint_coat): that palette repeats across an 8-horse field constantly
## (e.g. two bay horses drawn into the same race), so coat color alone
## stopped being a reliable way to tell the field apart mid-race.
##
## Tried attaching this to the skeleton's "Torso2" bone (the withers, where
## FrontShoulder.L/R also attach) via BoneAttachment3D so it would track the
## gallop animation's own body-root bob instead of sitting at one fixed
## height. That required a measured 0.01 scale correction to cancel a 100x
## bone-space blow-up (a real, confirmed Godot/glTF quirk) — which worked
## correctly under the editor binary but NOT identically in the actual
## exported release template (confirmed by finally screenshotting the real
## export, not just the editor, after AJ reported the horses looked broken
## on the build he was about to hand to his brother): the badges rendered
## as giant blobs again, swallowing the model. Whatever that scale
## resolves to differs between the two contexts, which makes the whole
## approach too fragile to trust. Reverted to the simpler, fully predictable
## fixed-height-under-_visual_root placement — the real model's back sits
## at y≈2.9 (measured directly with a ruler probe screenshot), and yes, this
## means the badge no longer tracks the animation's own subtle body bob
## stride-to-stride, but a slightly-desynced-but-correctly-sized badge is a
## FAR smaller problem than one that can silently blow up to 100x depending
## on context.
const SADDLE_HEIGHT: float = 2.9
const SADDLE_FORWARD_OFFSET: float = -0.3 # slightly toward the withers/front of the back, where a saddle actually sits
const SADDLE_FALLBACK_HEIGHT: float = 0.95 # placeholder-model-only — that capsule shape is a totally different, much smaller scale than the real model
const SADDLE_CLOTH_SIZE: Vector2 = Vector2(1.1, 0.75) # width x height — a wide rectangle like a real saddle pad, not a square badge
const SADDLE_NUMBER_PANEL_SIZE: float = 0.44 # the white number panel inset within the cloth

## Real saddle cloths are the silk color with a separate white number
## panel — not a solid-color chip with a plain numeral — because a numeral
## printed straight onto a colored chip is illegible against light silk
## colors. Splitting it into cloth (silk_primary, wide rectangle roughly
## matching a real saddle pad's proportions) + a small white/near-white
## panel + dark numeral guarantees the number reads regardless of which
## silk color this horse drew. All three pieces are billboarded (always
## face the camera).
func _build_saddle_cloth(post_position: int) -> void:
	var mount_parent: Node3D = _visual_root
	# Real model gets the real measured height; the placeholder capsule is a
	# totally different, much smaller scale and has no skeleton anyway.
	var mount_pos := Vector3(0.0, SADDLE_HEIGHT if _skeleton != null else SADDLE_FALLBACK_HEIGHT, SADDLE_FORWARD_OFFSET if _skeleton != null else 0.0)

	# All four pieces below use no_depth_test (needed so the cloth clears the
	# coat mesh at all — see the cloth comment further down) — but
	# no_depth_test also means Godot skips depth-testing these against EACH
	# OTHER, so with nothing else to go on, draw order between same-priority
	# opaque quads a few cm apart falls back to submission order, which is
	# NOT guaranteed stable across camera angles. Real symptom this caused:
	# screenshots showing a solid color block with no visible number at all
	# (the panel/label losing the draw-order coin flip to the cloth behind
	# them). Fixed with explicit `render_priority` on every piece (border <
	# cloth < panel < label) — this is a real depth-independent draw-order
	# override, not just a position offset, so the stacking is now
	# guaranteed regardless of viewing angle.
	const PRIORITY_BORDER: int = 0
	const PRIORITY_CLOTH: int = 1
	const PRIORITY_PANEL: int = 2
	const PRIORITY_LABEL: int = 3

	# Thin dark border quad behind the cloth — real saddle cloths/silks
	# almost always have a contrasting piped edge; without it a flat
	# unshaded silk-colored rectangle floating in space just reads as a
	# stray UI bug rather than a piece of racing tack.
	var border := MeshInstance3D.new()
	var border_mesh := QuadMesh.new()
	border_mesh.size = SADDLE_CLOTH_SIZE + Vector2(0.1, 0.1)
	border.mesh = border_mesh
	border.position = mount_pos + Vector3(0.0, 0.0, 0.01)
	var border_mat := StandardMaterial3D.new()
	border_mat.albedo_color = Color(0.08, 0.08, 0.08)
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	border_mat.no_depth_test = true
	border_mat.render_priority = PRIORITY_BORDER
	border.material_override = border_mat
	mount_parent.add_child(border)

	var cloth := MeshInstance3D.new()
	var cloth_mesh := QuadMesh.new()
	cloth_mesh.size = SADDLE_CLOTH_SIZE
	cloth.mesh = cloth_mesh
	cloth.position = mount_pos
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = body_color
	cloth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # reads as a clear ID chip regardless of floodlight/theme lighting, same reasoning BroadcastHUD's leaderboard chips are flat UI, not lit 3D geometry
	cloth_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# A skeleton bone's pivot sits INSIDE the body (bones are internal — well
	# short of the skin surface), so mount_pos's modest offset up from it
	# isn't enough to clear the actual coat mesh: without this the cloth was
	## rendering fine but entirely hidden behind the opaque coat (confirmed via
	# a close-up screenshot — the panel/label already had this exact fix and
	# showed through correctly, the cloth alone didn't and was invisible).
	cloth_mat.no_depth_test = true
	cloth_mat.render_priority = PRIORITY_CLOTH
	cloth.material_override = cloth_mat
	mount_parent.add_child(cloth)

	# Slightly forward of the cloth (not just a positive Z offset — billboard
	# mode re-orients for rendering but keeps the authored local position, so
	# this reliably renders in front and avoids depth-fighting with the cloth
	# behind it) plus no_depth_test and render_priority as guarantees.
	var panel := MeshInstance3D.new()
	var panel_mesh := QuadMesh.new()
	panel_mesh.size = Vector2(SADDLE_NUMBER_PANEL_SIZE, SADDLE_NUMBER_PANEL_SIZE)
	panel.mesh = panel_mesh
	panel.position = mount_pos + Vector3(0.0, 0.0, -0.02)
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_color = Color(0.96, 0.95, 0.9)
	panel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	panel_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	panel_mat.no_depth_test = true
	panel_mat.render_priority = PRIORITY_PANEL
	panel.material_override = panel_mat
	mount_parent.add_child(panel)

	var label := Label3D.new()
	label.text = str(post_position)
	label.font_size = 72
	label.pixel_size = SADDLE_NUMBER_PANEL_SIZE / 72.0 * 0.85 # numeral fills most of the panel without overflowing it
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.05, 0.05, 0.05) # dark numeral on the light panel — guaranteed contrast regardless of silk color
	label.position = mount_pos + Vector3(0.0, 0.0, -0.04)
	label.no_depth_test = true # guarantees the numeral never z-fights with the cloth/panel behind it
	label.render_priority = PRIORITY_LABEL
	mount_parent.add_child(label)

## Called every playback frame by RaceTrack3D based on this horse's current
## surge value crossing SURGING_THRESHOLD — cheap to call every frame since
## it only touches `.emitting` when the state actually flips.
func set_surging(active: bool) -> void:
	if active == _is_surging:
		return
	_is_surging = active
	_surge_trail.emitting = active


## AJ: "they look like sheep from the flash drive" — every horse fell back
## to the placeholder capsule shape (see the class comment above). First fix
## attempt (removing a "_model_checked forever" flag) turned out to be
## treating the wrong symptom — confirmed with a direct diagnostic probe run
## from an actually-extracted-fresh copy of the export: FileAccess.file_exists
## on this raw .glb path returned FALSE in that exact context, while load()
## on the SAME path immediately afterward succeeded fine and returned a
## valid PackedScene. Godot resolves an imported resource like this through
## its own import/UID remap table when you load() it — that doesn't
## necessarily line up with a literal raw-file existence check once it's
## sitting in an exported .pck rather than on real disk in the editor
## (where this was tested exclusively, all session, until now — every
## earlier "confirmed working" screenshot was via the editor binary against
## the live project folder, where the raw file trivially exists and this
## gap never surfaces). The fix is simply to stop gating on file_exists at
## all and just attempt the load, exactly as load() itself already proved
## it can handle regardless of what file_exists says.
static func _get_model() -> PackedScene:
	if _cached_model != null:
		return _cached_model
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
	_skeleton = _find_skeleton(instance) # found before either early-return below so _build_saddle_cloth can still bone-attach even if no run animation is found
	var anim_player: AnimationPlayer = _find_animation_player(instance)
	if anim_player == null:
		return
	_anim_player = anim_player
	anim_player.speed_scale = 1.0 # normal speed for the pre-race idle hold below; start_running() bumps this to GAIT_SPEED_SCALE

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
	_run_anim_name = anim_name
	_run_anim = anim

	# AJ: "they look stupid moving before the race starts" — setup() runs
	# when RaceTrack3D builds the scene, well before the post-time countdown/
	# gate-open beat (see play_with_post_time), so every horse used to start
	# galloping in place immediately and just stood there thrashing through
	# the whole riders-up/odds-board sequence. Hold an idle pose instead;
	# start_running() (called by RaceTrack3D right as the gate actually
	# opens) is what switches to the real gait. Falls back to a static first
	# frame of the run animation (seek without play) if no idle clip exists,
	# rather than requiring one.
	var idle_name: String = ""
	for candidate in IDLE_ANIMATION_CANDIDATES:
		if anim_player.has_animation(candidate):
			idle_name = candidate
			break
	if idle_name != "":
		var idle_anim: Animation = anim_player.get_animation(idle_name)
		if idle_anim != null:
			idle_anim.loop_mode = Animation.LOOP_LINEAR
		anim_player.play(idle_name)
	elif anim != null:
		anim_player.seek(0.0, true)

## Switches from the pre-race idle hold to the actual running gait — called
## by RaceTrack3D at the moment the gate opens, not at setup() time (see the
## comment above where _run_anim_name is captured).
func start_running() -> void:
	if _anim_player == null or _run_anim_name == "":
		return
	_anim_player.speed_scale = GAIT_SPEED_SCALE
	_anim_player.play(_run_anim_name)
	# Every horse starts this clip at the same moment, at the same
	# speed_scale — without a random phase offset they gallop in perfect
	# lockstep (identical leg position on every horse, every frame), which
	# reads as a synchronized toy/clone effect rather than a real herd.
	# Jumping to a random point in the clip right away desyncs each horse's
	# stride from the others.
	if _run_anim != null and _run_anim.length > 0.0:
		_anim_player.seek(randf() * _run_anim.length, true)

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

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null

## horse.glb's single mesh has 8 named surfaces: Main/Main_Dark/Main_Light
## (the coat's base/shadow/highlight tones), Hair (mane+tail), and
## Muzzle/Hooves/Eye_Black/Eye_White (left alone — recoloring eyes or hooves
## would look wrong regardless of silk color).
##
## AJ, twice, increasingly emphatically: "the horses look like hot dogs" then
## "the horses dont look like fucking horses this is a huge problem." A first
## attempt just lowered the coat's SATURATION (kept the raw silk hue, e.g.
## teal or purple, just dimmer) — confirmed via screenshot to help a little
## but not enough, because the actual problem was never saturation, it was
## HUE: horses aren't teal or purple at ANY saturation. Real fix: coat hue+
## saturation now come from a small fixed palette of actual horse coat colors
## (NATURAL_COAT_COLORS), keyed by horse_id so a given horse always has the
## same real-world coat across races (matching Horse.gd's own "persistent
## identity" framing, same as its jockey_name) rather than tracking this
## race's silk assignment at all. Coat surfaces still keep their own original
## VALUE per-surface (preserves the light/dark shading between Main/
## Main_Dark/Main_Light instead of flattening them to one flat color) — only
## the hue/saturation source changed. Mane/tail (Hair) keeps the full silk
## accent_color untouched — a bold colored mane (braided ribbons/tack are a
## real racing detail) still carries identification without the whole animal
## looking painted. On-screen/bet-slip/leaderboard/minimap identification
## never depended on coat color anyway (see silk_primary/silk_secondary),
## so nothing else needed to change for "find your horse" to keep working.
const COAT_SURFACE_NAMES: Array[String] = ["Main", "Main_Dark", "Main_Light"]
const MANE_SURFACE_NAME: String = "Hair"
const NATURAL_COAT_COLORS: Array[Color] = [
	Color(0.35, 0.2, 0.12),   # bay
	Color(0.22, 0.14, 0.09),  # dark bay / brown
	Color(0.45, 0.24, 0.12),  # chestnut
	Color(0.3, 0.16, 0.1),    # liver chestnut
	Color(0.08, 0.07, 0.07),  # black
	Color(0.55, 0.53, 0.5),   # gray
	Color(0.62, 0.6, 0.58),   # dapple gray
	Color(0.72, 0.55, 0.28),  # palomino
]

func _tint_coat(instance: Node3D) -> void:
	var mesh_instance: MeshInstance3D = _find_mesh_instance(instance)
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	var natural_coat: Color = NATURAL_COAT_COLORS[horse_id % NATURAL_COAT_COLORS.size()]

	# Single-surface models (e.g. a textured horse with one combined material
	# covering the whole body, unlike the original rig's separate Main/
	# Main_Dark/Main_Light/Hair surfaces) have nothing to distinguish coat
	# from mane by name — multiply-tint the one surface directly instead.
	# albedo_color multiplies the existing albedo_texture per-pixel, so a
	# white-based texture (confirmed via a throwaway debug_inspect_model.gd
	# check on this specific pack) picks up the tint while the texture's own
	# baked shading/markings still supply real detail, rather than flattening
	# to one solid color the way overriding a textureless flat material would.
	if mesh_instance.mesh.get_surface_count() == 1:
		var only_material: Material = mesh_instance.get_active_material(0)
		if only_material == null:
			return
		var tinted_only: Material = only_material.duplicate()
		if tinted_only is StandardMaterial3D:
			tinted_only.albedo_color = natural_coat
		mesh_instance.set_surface_override_material(0, tinted_only)
		return

	for i in range(mesh_instance.mesh.get_surface_count()):
		var original: Material = mesh_instance.get_active_material(i)
		if original == null:
			continue

		var tint: Color
		if original.resource_name in COAT_SURFACE_NAMES:
			tint = natural_coat
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
