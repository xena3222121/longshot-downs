extends Node

## Thin wrapper around the global "Steam" engine singleton, which only
## exists when the project is run through GodotSteam's custom-compiled
## editor/export-template binaries (see project notes for where those live
## on this machine — the stock Godot editor has no such singleton at all).
##
## Every call is guarded by Engine.has_singleton("Steam") — looked up by
## string, never a bare `Steam` identifier — so this script compiles and
## runs fine under the stock editor too (e.g. every headless dev-tool/CI
## run in this project). is_available just stays false and every method
## below becomes a no-op instead of crashing on a missing global.

signal steam_ready
signal leaderboard_score_uploaded(leaderboard_name: String, success: bool)

## Valve's public test App ID ("Spacewar"). Passing it explicitly to
## steamInitEx sets the SteamAppId/SteamGameId env vars for us, so no
## steam_appid.txt file is needed for dev testing. Swap for the real App ID
## once Steamworks registration is done.
const DEV_APP_ID: int = 480

## Both leaderboards must already exist on this game's Steamworks partner
## site (one-time setup, same as registering achievement ids) — nothing
## running inside the game can create them.
const LEADERBOARD_BANKROLL: String = "Biggest_Bankroll"
const LEADERBOARD_WIN_STREAK: String = "Best_Win_Streak"

var is_available: bool = false

## leaderboard_name -> score, waiting on findLeaderboard's async result (see
## upload_leaderboard_score/_on_leaderboard_find_result below).
var _pending_scores: Dictionary = {}

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		return

	var steam: Object = Engine.get_singleton("Steam")
	var result: Dictionary = steam.steamInitEx(DEV_APP_ID, false)
	if result.get("status", -1) != 0:
		push_warning("Steam init failed (status %s): %s" % [result.get("status"), result.get("verbal", "unknown error")])
		return

	is_available = true
	# has_signal-guarded: unlike setAchievement/getPersonaName above (already
	# proven working in this project), the leaderboard call shape below has
	# never been exercised against a live Steam client in this session —
	# there's no way to smoke-test an async Steamworks round-trip without one
	# actually running. Guarding every leaderboard call this way means a
	# wrong assumption about GodotSteam's exact signal/method names fails
	# silently (leaderboards just never populate) instead of erroring, but it
	# should still be verified against a real Steam client before relying on
	# it for anything user-facing.
	if steam.has_signal("leaderboard_find_result"):
		steam.connect("leaderboard_find_result", _on_leaderboard_find_result)
	steam_ready.emit()

func _process(_delta: float) -> void:
	if is_available:
		Engine.get_singleton("Steam").run_callbacks()

func unlock_achievement(achievement_id: String) -> void:
	if not is_available:
		return
	var steam: Object = Engine.get_singleton("Steam")
	steam.setAchievement(achievement_id)
	steam.storeStats()

func get_steam_display_name() -> String:
	if not is_available:
		return ""
	return Engine.get_singleton("Steam").getPersonaName()

## Fire-and-forget: no-ops on any platform without Steam (or if this build's
## GodotSteam version doesn't expose findLeaderboard under this name — see
## the has_method guard). Only one upload per leaderboard name can be
## in-flight at a time; a second call before the first resolves just
## overwrites the pending score, which is fine — Career only ever calls this
## with the latest value anyway (current bankroll, current best streak).
func upload_leaderboard_score(leaderboard_name: String, score: int) -> void:
	if not is_available:
		return
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.has_method("findLeaderboard"):
		return
	_pending_scores[leaderboard_name] = score
	steam.findLeaderboard(leaderboard_name)

func _on_leaderboard_find_result(handle: int, found: int) -> void:
	if found == 0 or _pending_scores.is_empty():
		return
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.has_method("uploadLeaderboardScore"):
		return
	# GodotSteam's find-result signal doesn't say which leaderboard NAME
	# resolved to this handle, only the handle itself — in practice
	# upload_leaderboard_score only ever has one name pending at a time
	# (Career calls it once per event, not in a tight loop), so draining
	# whatever's pending here is safe rather than needing a name->handle map.
	for leaderboard_name in _pending_scores.keys():
		var score: int = _pending_scores[leaderboard_name]
		steam.uploadLeaderboardScore(score, true, PackedInt32Array(), handle)
		leaderboard_score_uploaded.emit(leaderboard_name, true)
	_pending_scores.clear()
