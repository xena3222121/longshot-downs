class_name SavePaths
extends RefCounted

## Cross-machine progress sync: Bankroll/Career saves normally live under
## Godot's per-machine user:// dir, which means "which race class/streak/
## bankroll am I at" doesn't carry over between e.g. a home PC and a work PC.
## Redirecting those two save files into the local OneDrive folder (already
## signed into the same account on both machines, since OneDrive syncs it)
## makes progress follow the player like any other synced file, with zero
## server/account code needed. Falls back to the normal user:// path when
## OneDrive isn't present so saving never breaks on a machine without it.
const CLOUD_SUBDIR: String = "LongshotDowns"

static func resolve(filename: String) -> String:
	var onedrive: String = OS.get_environment("OneDrive")
	if onedrive.is_empty() or not DirAccess.dir_exists_absolute(onedrive):
		return "user://" + filename
	var dir: String = onedrive.replace("\\", "/") + "/" + CLOUD_SUBDIR
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var cloud_path: String = dir + "/" + filename
	var legacy_path: String = "user://" + filename
	# One-time migration: a machine that already had local progress under the
	# old per-machine user:// path would otherwise look at the (empty) cloud
	# path on first run after this change and silently reset to defaults.
	if not FileAccess.file_exists(cloud_path) and FileAccess.file_exists(legacy_path):
		var legacy_file := FileAccess.open(legacy_path, FileAccess.READ)
		var cloud_file := FileAccess.open(cloud_path, FileAccess.WRITE)
		if legacy_file != null and cloud_file != null:
			cloud_file.store_string(legacy_file.get_as_text())
	return cloud_path
