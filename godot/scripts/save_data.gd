extends Node

## Autoload singleton ("Save") holding all persistent state: a set of
## named profiles ("who's playing"), each with its own level stars / best
## scores, plus which profile and level are currently active. Saved to
## user:// as JSON, loaded once at startup.

const SAVE_PATH := "user://save.json"

var profiles: Dictionary = {} # id (String) -> {name, level_stars, best_scores}
var active_profile_id: String = ""
var current_level: int = 1 # set by LevelSelect before changing to Main.tscn

func _ready() -> void:
	load_data()

func create_profile(name: String) -> String:
	var id := "%d-%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	profiles[id] = {"name": name, "level_stars": {}, "best_scores": {}}
	active_profile_id = id
	save_data()
	return id

func delete_profile(id: String) -> void:
	profiles.erase(id)
	if active_profile_id == id:
		active_profile_id = ""
	save_data()

func set_active(id: String) -> void:
	active_profile_id = id
	save_data()

func active_profile() -> Dictionary:
	return profiles.get(active_profile_id, {})

func active_profile_name() -> String:
	return active_profile().get("name", "")

func level_stars() -> Dictionary:
	return active_profile().get("level_stars", {})

func best_scores() -> Dictionary:
	return active_profile().get("best_scores", {})

func highest_unlocked() -> int:
	# Level 1 is always unlocked; each additional level unlocks once the one
	# before it has been won (has any stars recorded).
	var stars := level_stars()
	var n := 1
	while stars.has(n):
		n += 1
	return n

func record_level_result(level: int, stars: int, score: int) -> void:
	var profile := active_profile()
	if profile.is_empty():
		return
	var prev_stars: int = profile["level_stars"].get(level, 0)
	if stars > prev_stars:
		profile["level_stars"][level] = stars
	var prev_best: int = profile["best_scores"].get(level, 0)
	if score > prev_best:
		profile["best_scores"][level] = score
	save_data()

func total_stars() -> int:
	var total := 0
	for v in level_stars().values():
		total += v
	return total

func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Save.save_data: could not open %s for writing" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"profiles": profiles,
		"active_profile_id": active_profile_id,
	}))

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var raw_profiles: Dictionary = parsed.get("profiles", {})
	profiles = {}
	for id in raw_profiles.keys():
		var p: Dictionary = raw_profiles[id]
		profiles[id] = {
			"name": p.get("name", "Player"),
			# JSON object keys are always strings; convert back to the int
			# level numbers the rest of the game uses.
			"level_stars": _int_keys(p.get("level_stars", {})),
			"best_scores": _int_keys(p.get("best_scores", {})),
		}
	active_profile_id = parsed.get("active_profile_id", "")

func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[int(k)] = d[k]
	return out
