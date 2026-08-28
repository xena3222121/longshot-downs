extends Node

## Throwaway dev tool, NOT part of the game and NOT covered by the usual
## verification convention noted throughout this project's history ("no way
## to visually confirm in this environment") — this is an attempt to close
## that exact gap. Must run with the REAL rendering binary, NOT --headless
## (headless has no GPU context to actually render a frame): loads a target
## scene, lets it settle so builds/tweens/animations finish, grabs the
## viewport's actual rendered backbuffer, saves it as a PNG, then quits.
## Usage:
##   godotsteam.441.editor.windows64.exe --path . res://scripts/tools/screenshot_capture.tscn
## Edit TARGET_SCENE/OUT_PATH below per capture. Delete once no longer needed
## (or keep — harmless either way, matches this project's convention of not
## deleting shipped tools/assets just because a particular use is done).

const TARGET_SCENE: String = "res://scenes/TitleScreen.tscn"
const OUT_PATH: String = "C:/Users/AJ/AppData/Local/Temp/claude/C--Users-AJ/06ae8ae0-e664-4e04-82ab-73b913e21258/scratchpad/store_title.png"
const SETTLE_TIME: float = 2.5

func _ready() -> void:
	# The engine is still mid-setup adding THIS node to the tree when _ready()
	# fires for the very first scene — calling root.add_child() immediately
	# hit "Parent node is busy setting up children" and silently failed
	# (confirmed: the resulting capture showed only autoload-rendered content
	# like InputHints' toast, not the target scene at all). One frame of
	# delay is enough for that initial setup to finish.
	await get_tree().process_frame

	# Adds the target as an EXTRA child of root rather than
	# get_tree().change_scene_to_file() — that call frees whichever node is
	# the current scene (this one) once its deferred swap runs, which would
	# free `self` out from under the await below before it could ever resume
	# (the exact bug TitleScreen.gd's own _on_play_pressed comment documents;
	# hit it for real once building this tool before switching to this
	# approach). Keeping this node alive as an unrelated sibling means the
	# await/screenshot/quit sequence below has a live owner the whole time.
	var scene: Node = load(TARGET_SCENE).instantiate()
	get_tree().root.add_child(scene)
	await get_tree().create_timer(SETTLE_TIME).timeout
	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	print("screenshot_capture: save_png -> %s (err=%s)" % [OUT_PATH, err])
	get_tree().quit()
