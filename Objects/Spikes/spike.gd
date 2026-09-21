extends Area2D

@export var damage: int = 1
@export var spike_variant: StringName = &"stone"

@export var only_damage_from_above: bool = true
@export var top_tolerance: float = 6.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	if sprite.sprite_frames.has_animation(spike_variant):
		sprite.play(spike_variant)
		sprite.frame = 0
		sprite.pause()
	else:
		push_warning("Spike Variante nicht gefunden: " + str(spike_variant))


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if only_damage_from_above:
		if body.global_position.y > global_position.y + top_tolerance:
			return

	if body.has_method("take_damage"):
		body.take_damage(damage, global_position)
