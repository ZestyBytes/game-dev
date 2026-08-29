extends Node

## Autoload singleton ("Save") holding persistent progress: stars and best
## score per level, plus which level is currently selected for the Main
## scene to read. Saved to user:// as JSON, loaded once at startup.
##
## Scope note: this is a single local player, not the web version's
## multi-profile "who's playing" system - that would need its own
## profile-picker UI on top of this. Everything here (stars, best scores)
## is what a real profile system would store per-profile.

const SAVE_PATH := "user://save.json"

var level_stars: Dictionary = {} # level number (int) -> stars (0-3)
var best_scores: Dictionary = {} # level number (int) -> best score
var current_level: int = 1 # set by LevelSelect before changing to Main.tscn

func _ready() -> void:
	load_data()

func highest_unlocked() -> int:
	# Level 1 is always unlocked; each additional level unlocks once the one
	# before it has been won (has any stars recorded).
	var n := 1
	while level_stars.has(n):
		n += 1
	return n

func record_level_result(level: int, stars: int, score: int) -> void:
	var prev_stars: int = level_stars.get(level, 0)
	if stars > prev_stars:
		level_stars[level] = stars
	var prev_best: int = best_scores.get(level, 0)
	if score > prev_best:
		best_scores[level] = score
	save_data()

func total_stars() -> int:
	var total := 0
	for v in level_stars.values():
		total += v
	return total

func save_data() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Save.save_data: could not open %s for writing" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"level_stars": level_stars,
		"best_scores": best_scores,
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
	# JSON object keys are always strings; convert back to the int level
	# numbers the rest of the game uses.
	level_stars = _int_keys(parsed.get("level_stars", {}))
	best_scores = _int_keys(parsed.get("best_scores", {}))

func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[int(k)] = d[k]
	return out
