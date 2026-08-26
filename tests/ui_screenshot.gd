extends SceneTree

## Development helper: drives the interface through its main stages and writes a
## PNG of each one so the layout can be checked without playing by hand.
## Run with: godot --path . --script res://tests/ui_screenshot.gd

const SHOT_DIR := "res://.godot/shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	var packed_scene: PackedScene = load("res://src/presentation/main.tscn")
	var main = packed_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	await _shot(main, "01_start")

	main._start_match()
	await _shot(main, "02_select")

	# Board-driven selection: pick a character, then a move, then a target.
	var player := int(main.game.state["active_player"])
	var actor_id := str(main.game.available_actors(player)[0]["id"])
	main._on_card_clicked(player, actor_id)
	await _shot(main, "02b_actor_picked")

	main.selected_move_id = "light_attack"
	main._render()
	await _shot(main, "02c_move_picked")

	var target_id := str(main.game.valid_targets(player, actor_id, "light_attack")[0]["id"])
	main._on_card_clicked(1 - player, target_id)
	await _shot(main, "03_handoff")

	main.ui_stage = "CLAIM"
	main._render()
	await _shot(main, "04_claim")

	main._submit_claim(int(main.game.true_rolls[0]))
	main._submit_claim(int(main.game.true_rolls[1]))
	main.ui_stage = "CHALLENGE"
	main._render()
	await _shot(main, "05_challenge")

	main._submit_challenge(false)
	main._submit_challenge(false)
	await _shot(main, "06_resolution")

	print("Screenshots written to %s" % SHOT_DIR)
	quit(0)


func _shot(main: Node, name: String) -> void:
	main._render()
	# Let the containers settle before capturing.
	for i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	image.save_png(path)
	print("wrote %s  (%dx%d)" % [path, image.get_width(), image.get_height()])
