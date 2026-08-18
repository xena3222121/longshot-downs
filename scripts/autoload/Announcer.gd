extends Node

## Text-to-speech play-by-play layer, spoken through the OS's own speech
## voices via DisplayServer (Windows SAPI, etc.) — silently no-ops if the
## machine has no TTS engine/voices installed (DisplayServer doesn't expose
## FEATURE_TEXT_TO_SPEECH the same way it exposes plain features, so
## availability is instead confirmed by actually finding a voice), the same
## optional-capability pattern AudioManager uses for missing sound files and
## HorseMarker3D uses for the missing horse model — the race calls out
## identically either way, RaceAnnouncerDirector's on-screen commentary
## caption (BroadcastHUD.show_commentary) always carries the same line
## regardless of whether TTS is actually available.
##
## Ducks AudioManager's music (via set_speech_duck) for as long as a line is
## being spoken, then releases it once tts_is_speaking() goes false — so the
## announcer is never fighting the theme/ambience for attention.

const RATE: float = 1.5 # rapid-fire race-caller pace, closer to a real track announcer than a narrator
const EXCITED_RATE: float = 1.7 # for the biggest moments — a duel call, the win call
const PITCH: float = 0.92 # slightly lower than the voice's default reads as more "announcer," less flat narrator
const EXCITED_PITCH: float = 1.05
const VOLUME: int = 100
const DUCK_DB: float = -10.0
const DUCK_LERP_SPEED: float = 6.0

## Preference order for which installed OS voice to use — earlier names win.
## These are common deeper/more energetic Windows SAPI voice names; if none
## of them are installed this just falls through to the first English voice,
## same as before.
const PREFERRED_VOICE_NAME_HINTS: Array[String] = ["david", "mark", "male"]

var _voice_id: String = ""
var _available: bool = false
var _target_duck_db: float = 0.0
var _current_duck_db: float = 0.0

func _ready() -> void:
	_voice_id = _pick_voice()
	_available = _voice_id != ""
	set_process(_available)

func _pick_voice() -> String:
	var voices: Array = DisplayServer.tts_get_voices()
	var english: Array = []
	for voice in voices:
		if String(voice.get("language", "")).begins_with("en"):
			english.append(voice)

	for hint in PREFERRED_VOICE_NAME_HINTS:
		for voice in english:
			if hint in String(voice.get("name", "")).to_lower():
				return String(voice.get("id", ""))

	if not english.is_empty():
		return String(english[0].get("id", ""))
	if not voices.is_empty():
		return String(voices[0].get("id", ""))
	return ""

## `interrupt = true` — a fresh line always cuts off whatever's still being
## read, matching a real announcer adjusting to the moment rather than
## finishing a stale sentence about a lead that's already changed again.
## `excited` bumps rate/pitch further for the biggest moments (a stretch
## duel, the win call) so they read as a bigger beat than a routine leader
## update, the same way a real caller's voice rises for the finish.
func say(text: String, excited: bool = false) -> void:
	if not _available:
		return
	var rate: float = EXCITED_RATE if excited else RATE
	var pitch: float = EXCITED_PITCH if excited else PITCH
	DisplayServer.tts_speak(text, _voice_id, VOLUME, pitch, rate, 0, true)
	_target_duck_db = DUCK_DB

func _process(delta: float) -> void:
	if not DisplayServer.tts_is_speaking():
		_target_duck_db = 0.0
	var t: float = 1.0 - exp(-delta * DUCK_LERP_SPEED)
	_current_duck_db = lerp(_current_duck_db, _target_duck_db, t)
	AudioManager.set_speech_duck(_current_duck_db)
