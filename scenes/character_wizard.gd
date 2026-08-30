extends Node2D

const IDLE: StringName = &"idle_animation"
const TEST_ANIMATIONS: Array[StringName] = [
	&"wand_attack_animation",
	&"wand_attack_2_animation",
	&"wand_slap_animation",
	&"hurt_animation",
	&"move_animation",
]

@onready var animation_tree: AnimationTree = $AnimationTree

var playback: AnimationNodeStateMachinePlayback
var next_animation := 0


func _ready() -> void:
	animation_tree.active = true
	playback = animation_tree.get(&"parameters/playback") as AnimationNodeStateMachinePlayback
	playback.start(IDLE)


func _unhandled_input(event: InputEvent) -> void:
	# is_action_pressed() ignores key-repeat events by default.
	if not event.is_action_pressed(&"ui_accept"):
		return

	# Ignore additional presses until the current test animation returns to idle.
	if playback.get_current_node() != IDLE:
		return

	playback.travel(TEST_ANIMATIONS[next_animation])
	next_animation = (next_animation + 1) % TEST_ANIMATIONS.size()
