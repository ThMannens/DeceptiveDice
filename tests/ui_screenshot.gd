extends SceneTree

## Development helper: drives the interface through its main stages and writes a
## PNG of each one so the layout can be checked without playing by hand.
## Run with: godot --path . --script res://tests/ui_screenshot.gd
##
## Captures at both supported sizes. The window is resized between passes rather
## than run twice, because the layout regressions this catches are the ones that
## only appear when the roster columns are squeezed.

const Roster = preload("res://src/core/roster.gd")

const SHOT_DIR := "res://.godot/shots"
## The full-screen target first, then the two smaller supported sizes.
const SIZES := [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 640)]
## The stages worth a second capture at the smaller size: these are the three
## where a primary control has historically fallen below the fold.
const SMALL_SIZE_STAGES := ["05_select", "08_challenge", "09_resolution"]

var _size_label := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for size: Vector2i in SIZES:
		_size_label = "%dx%d" % [size.x, size.y]
		root.get_window().size = size
		await process_frame
		await _capture_pass(size == SIZES[0])
	print("Screenshots written to %s" % SHOT_DIR)
	quit(0)


## One walk through the interface. The first pass captures every stage; later
## passes capture only the stages listed in SMALL_SIZE_STAGES.
func _capture_pass(capture_all: bool) -> void:
	var packed_scene: PackedScene = load("res://src/presentation/main.tscn")
	var main = packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	await _shot(main, "01_start", capture_all)

	# The draft, which is where a new match now begins.
	main._start_match()
	await _shot(main, "02_draft_empty", capture_all)

	var roster_ids: Array = Roster.character_ids()
	for player in [0, 1]:
		for pick_index in 4:
			main._toggle_draft_pick(str(roster_ids[pick_index]))
			if player == 0 and pick_index == 2:
				await _shot(main, "03_draft_three", capture_all)
		if player == 0:
			await _shot(main, "04_draft_four", capture_all)
		main._submit_draft()
		if player == 0:
			main.ui_stage = "DRAFT"
	main.ui_stage = "PLACEMENT"
	await _shot(main, "04b_placement", capture_all)
	for player in [0, 1]:
		main.ui_stage = "PLACEMENT"
		main._render()
		main._submit_formation()

	# A preset match for the exchange stages, so the walk does not depend on
	# which four the draft above happened to pick.
	main._start_quick_match()
	await _shot(main, "05_select", true)

	var player := int(main.game.state["active_player"])
	var actor_id := str(main.game.available_actors(player)[0]["id"])
	main._on_card_clicked(player, actor_id)
	await _shot(main, "06_actor_picked", capture_all)

	main.selected_move_id = "light_attack"
	main._render()
	await _shot(main, "06b_move_picked", capture_all)

	var target_id := str(main.game.valid_targets(player, actor_id, "light_attack")[0]["id"])
	main._on_card_clicked(1 - player, target_id)
	await _shot(main, "07_handoff", capture_all)

	main.ui_stage = "CLAIM"
	main._render()
	await _shot(main, "07b_claim", capture_all)

	main._submit_claim(int(main.game.true_rolls[0]))
	main._submit_claim(int(main.game.true_rolls[1]))
	main.ui_stage = "CHALLENGE"
	main._render()
	await _shot(main, "08_challenge", true)

	main._submit_challenge(false)
	main._submit_challenge(false)
	await _shot(main, "09_resolution", true)

	main.queue_free()
	await process_frame


func _shot(main: Node, name: String, capture: bool = true) -> void:
	main._render()
	# Let the containers settle before capturing.
	for i in 4:
		await process_frame
	if not capture and name not in SMALL_SIZE_STAGES:
		return
	var image := root.get_texture().get_image()
	var path := "%s/%s_%s.png" % [SHOT_DIR, name, _size_label]
	image.save_png(path)
	print("wrote %s  (%dx%d)" % [path, image.get_width(), image.get_height()])
