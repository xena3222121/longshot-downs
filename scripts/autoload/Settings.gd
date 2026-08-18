extends Node

## Persisted user preferences (audio + display) — a real settings system,
## the kind every shipped game has and this one didn't until now. Autoload
## registered AFTER AudioManager in project.godot, since _ready below calls
## AudioManager.set_music_bus_volume/set_sfx_bus_volume, which need the
## Music/SFX buses AudioManager creates in its own _ready to already exist —
## Godot fires autoload _ready in [autoload] list order, so listing order
## matters here.

const SETTINGS_PATH: String = "user://settings.cfg"

var master_volume: float = 1.0 # linear 0..1
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var fullscreen: bool = false

## See TrackThemes.THEME_IDS / RaceTrack3D.CAMERA_MODE_ORDER for the valid
## value sets. Camera mode also changes live mid-race (see RaceTrack3D's
## cycle-camera input handling) and persists whichever mode was last used,
## the same way it's set here at the start of a race.
var track_theme_id: String = TrackThemes.DEFAULT_THEME_ID
var camera_mode: String = "broadcast"

func _ready() -> void:
	_load()
	_apply_all()

func set_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
	_save()

func set_music_volume(v: float) -> void:
	music_volume = clamp(v, 0.0, 1.0)
	AudioManager.set_music_bus_volume(music_volume)
	_save()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	AudioManager.set_sfx_bus_volume(sfx_volume)
	_save()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	_save()

func set_track_theme_id(id: String) -> void:
	track_theme_id = id
	_save()

func set_camera_mode(mode: String) -> void:
	camera_mode = mode
	_save()

func _apply_all() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
	AudioManager.set_music_bus_volume(music_volume)
	AudioManager.set_sfx_bus_volume(sfx_volume)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("race", "track_theme_id", track_theme_id)
	cfg.set_value("race", "camera_mode", camera_mode)
	cfg.save(SETTINGS_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	master_volume = cfg.get_value("audio", "master", 1.0)
	music_volume = cfg.get_value("audio", "music", 1.0)
	sfx_volume = cfg.get_value("audio", "sfx", 1.0)
	fullscreen = cfg.get_value("display", "fullscreen", false)
	track_theme_id = cfg.get_value("race", "track_theme_id", TrackThemes.DEFAULT_THEME_ID)
	camera_mode = cfg.get_value("race", "camera_mode", "broadcast")
