extends Node

## Autoload singleton (registered in project.godot). Plays background music
## and one-shot SFX by name if a matching file exists under ASSET_DIR;
## silently no-ops otherwise, so the game behaves identically before and
## after audio assets are added — same optional-asset pattern HorseMarker
## uses for the sprite sheet. Deliberately no class_name (see Bankroll.gd
## for why: autoloads are referenced by their registered global name, and a
## matching class_name risks a duplicate-identifier collision with that).
##
## Music channel used to be the only channel — a separate "ambient" channel
## that looped hoofbeats under the theme MUSIC was tried and cut because it
## read as two songs competing. Race ambience below revives that hoofbeats
## loop on different terms: it only ever plays once the theme has already
## ducked hard for the race itself (see start_race_ambience), replacing the
## music's role in the mix rather than layering under it — real broadcasts
## don't run a song under a live call either, they run crowd/track sound.
##
## Real "Music"/"SFX" AudioServer buses (created here, not via a checked-in
## bus layout resource — same code-first approach RaceTrack3D uses for its
## meshes) so Settings can expose independent volume sliders instead of every
## sound hard-coding its own dB literal with no user control at all. Ducking
## (race ambience + speech) applies at the MUSIC BUS level, composed with
## Settings' user-chosen music volume in _apply_music_bus_volume — neither
## side needs to know the other's current value to avoid stomping on it.

const ASSET_DIR: String = "res://assets/audio/"
const EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]
const MUSIC_VOLUME_DB: float = -24.0
const AMBIENCE_VOLUME_DB: float = -20.0
const RACE_MUSIC_DUCK_DB: float = -16.0

const MUSIC_BUS: String = "Music"
const SFX_BUS: String = "SFX"

var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _sfx_cache: Dictionary = {} # sound name -> AudioStream, or null if missing (cached either way)

var _race_duck_db: float = 0.0
var _speech_duck_db: float = 0.0
var _user_music_volume: float = 1.0 # linear 0..1, set by Settings

func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	_music_player.volume_db = MUSIC_VOLUME_DB
	add_child(_music_player)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = MUSIC_BUS
	_ambience_player.volume_db = AMBIENCE_VOLUME_DB
	add_child(_ambience_player)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx: int = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func play_music(sound_name: String, p_loop: bool = true) -> void:
	var stream: AudioStream = _load_sound(sound_name)
	if stream == null:
		return
	_set_loop(stream, p_loop)
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

## Ducks the theme hard and brings up a looping hoofbeats bed — call once
## the race itself starts running (not during betting/menus), see the class
## comment above for why this replaces rather than layers under the theme.
func start_race_ambience() -> void:
	_race_duck_db = RACE_MUSIC_DUCK_DB
	_apply_music_bus_volume()
	var stream: AudioStream = _load_sound("hoofbeats_loop")
	if stream == null:
		return
	_set_loop(stream, true)
	_ambience_player.stream = stream
	_ambience_player.play()

func stop_race_ambience() -> void:
	_race_duck_db = 0.0
	_apply_music_bus_volume()
	_ambience_player.stop()

## Called every frame by Announcer while a TTS line is being spoken (and for
## a short release afterward) — stacks on top of whatever race duck is
## already applied above instead of overwriting it.
func set_speech_duck(db: float) -> void:
	_speech_duck_db = db
	_apply_music_bus_volume()

## Called by Settings whenever the player changes the music slider — linear
## 0..1, converted to dB and combined with whatever ducking is currently
## active, same as the two duck sources combine with each other.
func set_music_bus_volume(linear: float) -> void:
	_user_music_volume = clamp(linear, 0.0, 1.0)
	_apply_music_bus_volume()

func _apply_music_bus_volume() -> void:
	var idx: int = AudioServer.get_bus_index(MUSIC_BUS)
	AudioServer.set_bus_volume_db(idx, linear_to_db(_user_music_volume) + _race_duck_db + _speech_duck_db)

func set_sfx_bus_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(clamp(linear, 0.0, 1.0)))

## `volume_db_offset` defaults to 0 (unchanged/original behavior for every
## existing call site) — only cues that are known to stack with another
## sound at the same moment (see FinishPodium's finish_fanfare+crowd_cheer)
## need to pass a negative offset so the combined result doesn't clip/blare.
func play_sfx(sound_name: String, volume_db_offset: float = 0.0) -> void:
	var stream: AudioStream = _load_sound(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.volume_db = volume_db_offset
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

## One-shot crowd reaction scaled by how exciting the moment is (0..1) — a
## routine stretch call gets nothing, a real duel or a photo finish gets a
## full roar, instead of "crowd_cheer" always playing at the same volume
## regardless of what's actually happening on the track. Separate from
## FinishPodium's own finish_fanfare/crowd_cheer cues, which celebrate the
## podium reveal after the race rather than react to the race in progress.
func play_crowd_reaction(intensity: float) -> void:
	var stream: AudioStream = _load_sound("crowd_cheer")
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.volume_db = lerp(-20.0, -4.0, clamp(intensity, 0.0, 1.0)) # never above unity gain — this stacks with other cues, not in place of them
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

func _set_loop(stream: AudioStream, p_loop: bool) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = p_loop
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if p_loop else AudioStreamWAV.LOOP_DISABLED

func _load_sound(sound_name: String) -> AudioStream:
	if _sfx_cache.has(sound_name):
		return _sfx_cache[sound_name]
	var stream: AudioStream = null
	for ext in EXTENSIONS:
		var path: String = "%s%s.%s" % [ASSET_DIR, sound_name, ext]
		if FileAccess.file_exists(path):
			stream = load(path)
			break
	_sfx_cache[sound_name] = stream
	return stream
