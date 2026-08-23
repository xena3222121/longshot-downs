extends Node

## One-off screenshot capture for FinishPodium's payoff board — a genuinely
## new feature this session with zero visual confirmation before now. Reuses
## finish_podium_check.gd's exact setup pattern (real RaceSim output, not
## fabricated data) but captures a real rendered frame instead of asserting.
## Must run with the REAL (non-headless) binary — headless has no GPU context:
##   godotsteam.441.editor.windows64.exe --path . res://scenes/tools/screenshot_capture_podium.tscn

const OUT_PATH: String = "C:/Users/AJ/AppData/Local/Temp/claude/C--Users-AJ/3f6e8dc3-e1fd-4693-b564-475ff1cffb01/scratchpad/screenshot_podium.png"
## Wall-clock wait, NOT a frame count — the real (uncapped/high-fps) binary
## can burn through hundreds of frames in well under a second, which is
## exactly what happened on the first attempt at this capture (caught mid-
## reveal, before the payoff board/backdrop card had even been built yet).
const WAIT_SECONDS: float = 4.0

func _ready() -> void:
	await get_tree().process_frame # let the engine finish adding this node before touching the tree further — see screenshot_capture.gd's own note on this exact gotcha
	Bankroll.autosave_enabled = false
	Bankroll.balance = 1000

	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = roster.slice(0, 8)
	HorseRoster.assign_race_colors(field)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var result: RaceResult = RaceSim.simulate(field, tiers)

	# Bet the actual winner so the richest visual state shows: WIN outcome
	# text, confetti, achievement toasts, AND the payoff board all at once.
	var winner_idx: int = result.finish_order[0]
	var podium := FinishPodium.new()
	get_tree().root.add_child(podium)
	podium.setup(field, result, {
		"bet_type": OddsTable.BetType.WIN, "horse_index": winner_idx, "second_index": -1,
		"picks": [winner_idx], "amount": 100, "dd_leg": 0,
	})

	await get_tree().create_timer(WAIT_SECONDS).timeout

	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	print("screenshot_capture_podium: save_png -> %s (err=%s)" % [OUT_PATH, err])
	get_tree().quit()
