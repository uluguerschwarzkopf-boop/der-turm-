extends Node

@export var gold_reward: int = 3
@export var parent_death_variable_name: String = "dead"
@export var check_interval: float = 0.05
@export var give_gold_only_once: bool = true

var already_dropped: bool = false
var parent_node: Node = null


func _ready() -> void:
	parent_node = get_parent()
	call_deferred("_start_checking")


func _start_checking() -> void:
	while is_inside_tree():
		await get_tree().create_timer(check_interval).timeout

		if parent_node == null or not is_instance_valid(parent_node):
			return

		if _parent_is_dead():
			drop_gold()
			return


func _parent_is_dead() -> bool:
	if parent_node == null:
		return false

	if parent_node.get(parent_death_variable_name) == true:
		return true

	return false


func drop_gold() -> void:
	if give_gold_only_once and already_dropped:
		return

	already_dropped = true

	if GoldSystem:
		GoldSystem.add_gold(gold_reward)
