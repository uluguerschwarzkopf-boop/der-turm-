extends Node

signal potions_changed(current_potions: int, max_potions: int)
signal potion_used

@export var max_potions: int = 3
@export var start_potions: int = 2

var current_potions: int = 0


func _ready() -> void:
	if get_node_or_null("/root/RunState") != null:
		current_potions = clamp(RunState.current_potions, 0, max_potions)
	else:
		current_potions = clamp(start_potions, 0, max_potions)

	potions_changed.emit(current_potions, max_potions)


func use_potion() -> bool:
	if current_potions <= 0:
		return false

	current_potions -= 1

	if get_node_or_null("/root/RunState") != null:
		RunState.current_potions = current_potions

	potions_changed.emit(current_potions, max_potions)
	potion_used.emit()

	return true


func add_potion(amount: int = 1) -> bool:
	if amount <= 0:
		return false

	if current_potions >= max_potions:
		potions_changed.emit(current_potions, max_potions)
		return false

	current_potions += amount
	current_potions = clamp(current_potions, 0, max_potions)

	if get_node_or_null("/root/RunState") != null:
		RunState.current_potions = current_potions

	potions_changed.emit(current_potions, max_potions)
	return true
