extends Node

## Play-by-play layer. tools/generate_announcer_audio.py pre-renders every
## (template x horse name) combination worth caching through the ElevenLabs
## API into assets/audio/announcer/, indexed by exact line text in
## manifest.json. say() plays that clip when the line has one.
##
## Deliberately no OS-TTS fallback for lines with no cached clip (used to
## fall back to DisplayServer SAPI voices, which meant races could jump
## between the real ElevenLabs voice and a completely different-sounding
## robotic one mid-broadcast — worse than just staying silent). Any
## uncached line — FILLER_CALLS_2/3, or a bank not yet generated — simply
## doesn't speak; RaceAnnouncerDirector's on-screen commentary caption
## (BroadcastHUD.show_commentary) still carries the line either way, so
## nothing is lost but the voice.
##
## Ducks AudioManager's music (via set_speech_duck) for as long as a cached
## clip is playing, then releases it once it stops — so the announcer is
## never fighting the theme/ambience for attention.

const DUCK_DB: float = -10.0
const DUCK_LERP_SPEED: float = 6.0

const CACHE_DIR: String = "res://assets/audio/announcer/"
const MANIFEST_PATH: String = CACHE_DIR + "manifest.json"

var _target_duck_db: float = 0.0
var _current_duck_db: float = 0.0

var _manifest: Dictionary = {} # exact line text -> clip filename under CACHE_DIR
var _stream_cache: Dictionary = {} # clip filename -> loaded AudioStream
var _clip_player: AudioStreamPlayer

func _ready() -> void:
	_manifest = _load_manifest()

	_clip_player = AudioStreamPlayer.new()
	_clip_player.bus = AudioManager.SFX_BUS
	add_child(_clip_player)

	set_process(true)

func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

## `excited` is accepted for call-site compatibility with RaceAnnouncerDirector
## but no longer changes anything here — a cached clip was already rendered
## excited or not (see generate_announcer_audio.py's BANKS map) at generation
## time, and an uncached line just doesn't speak at all (see class comment).
func say(text: String, excited: bool = false) -> void:
	var clip: String = _manifest.get(text, "")
	if clip == "":
		return
	var stream: AudioStream = _stream_cache.get(clip)
	if stream == null:
		stream = load(CACHE_DIR + clip)
		_stream_cache[clip] = stream
	_clip_player.stream = stream
	_clip_player.play()
	_target_duck_db = DUCK_DB

## RaceAnnouncerDirector gates on this before firing a non-forced line — see
## its own _say() — so a new call waits for the CURRENT clip to actually
## finish instead of cutting it off mid-word. Without this, cranking the
## calling frequency up just meant every clip started interrupting the
## previous one every ~0.5s, which is talking constantly but unintelligibly.
func is_speaking() -> bool:
	return _clip_player.playing

func _process(delta: float) -> void:
	if not _clip_player.playing:
		_target_duck_db = 0.0
	var t: float = 1.0 - exp(-delta * DUCK_LERP_SPEED)
	_current_duck_db = lerp(_current_duck_db, _target_duck_db, t)
	AudioManager.set_speech_duck(_current_duck_db)
