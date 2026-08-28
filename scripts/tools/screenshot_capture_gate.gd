extends Node

## One-off capture of the new starting-gate establishing shot (see
## RaceTrack3D._build_starting_gate / ShotState.GATE) — captures the very
## first rendered frame, i.e. right after setup() builds the scene but before
## play() is ever called, so the gate doors are still closed and the camera
## is sitting in its static wide GATE framing. Must run with the REAL
## (non-headless) binary:
##   godotsteam.441.editor.windows64.exe --path . res://scenes/tools/screenshot_capture_gate.tscn

const OUT_PATH: String = "C:/Users/AJ/AppData/Local/Temp/claude/C--Users-AJ/06ae8ae0-e664-4e04-82ab-73b913e21258/scratchpad/store_gate.png"
const WAIT_SECONDS: float = 2.5 # real wall-clock time — lets lighting/shadows/materials finish settling before capture

func _ready() -> void:
	await get_tree().process_frame

	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = roster.slice(0, 8)
	HorseRoster.assign_race_colors(field)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var result: RaceResult = RaceSim.simulate(field, tiers)

	Settings.track_theme_id = "neon_downs" # force the default day theme for this capture regardless of whatever's saved in settings.cfg
	var race_track := RaceTrack3D.new()
	get_tree().root.add_child(race_track)
	race_track.setup(field, result)
	# Deliberately NOT calling play() or play_with_post_time() — this is the
	# pre-race moment, gate closed, horses lined up.

	await get_tree().create_timer(WAIT_SECONDS).timeout

	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	print("screenshot_capture_gate: save_png -> %s (err=%s)" % [OUT_PATH, err])
	get_tree().quit()
