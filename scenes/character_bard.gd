extends Node2D

const IDLE: StringName = &"idle_animation"
const TEST_ANIMATIONS: Array[StringName] = [
	&"attack_1_animation",
	&"attack_2_animation",
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
	if not event.is_action_pressed(&"ui_accept"):
		return

	if playback.get_current_node() == IDLE:
		playback.travel(TEST_ANIMATIONS[next_animation])
		next_animation = (next_animation + 1) % TEST_ANIMATIONS.size()
		return

	playback.travel(IDLE)
