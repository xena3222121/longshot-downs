extends Node

## One-off capture of a live RaceTrack3D mid-race — AJ: "the horses look like
## hot dogs wtf bro." Needed an actual look at the 3D horse model/coat-tinting
## in context before guessing what's wrong with it. Mirrors
## racetrack_playback_check.gd's setup pattern but captures a real rendered
## frame partway through instead of asserting on completion. Must run with
## the REAL (non-headless) binary:
##   godotsteam.441.editor.windows64.exe --path . res://scenes/tools/screenshot_capture_race.tscn

const OUT_PATH: String = "C:/Users/AJ/AppData/Local/Temp/claude/C--Users-AJ/3f6e8dc3-e1fd-4693-b564-475ff1cffb01/scratchpad/screenshot_race.png"
const WAIT_SECONDS: float = 6.0 # real wall-clock time, not a frame count — see screenshot_capture_podium.gd's own note on why

func _ready() -> void:
	await get_tree().process_frame

	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = roster.slice(0, 8)
	HorseRoster.assign_race_colors(field)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var result: RaceResult = RaceSim.simulate(field, tiers)

	var race_track := RaceTrack3D.new()
	get_tree().root.add_child(race_track)
	race_track.setup(field, result)
	race_track.play()

	await get_tree().create_timer(WAIT_SECONDS).timeout

	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	print("screenshot_capture_race: save_png -> %s (err=%s)" % [OUT_PATH, err])
	get_tree().quit()
