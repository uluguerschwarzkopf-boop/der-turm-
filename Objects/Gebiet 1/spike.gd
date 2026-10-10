extends Area2D

@export var damage: int = 1
@export var knockback_from_spike: bool = true

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("take_damage"):
		body.take_damage(damage, global_position)
