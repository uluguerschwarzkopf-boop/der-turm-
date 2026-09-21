extends Node

signal health_changed(current_hp: int, max_hp: int)
signal died

@export var max_hp: int = 12

var current_hp: int = 12
var dead: bool = false


func _ready() -> void:
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)


func take_damage(amount: int) -> void:
	if dead:
		return

	current_hp = max(current_hp - amount, 0)
	health_changed.emit(current_hp, max_hp)

	if current_hp <= 0:
		dead = true
		died.emit()
