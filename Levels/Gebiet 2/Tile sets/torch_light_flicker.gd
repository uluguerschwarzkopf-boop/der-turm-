extends PointLight2D



@export var base_energy := 1.4
@export var flicker_amount := 0.2
@export var speed := 7.0
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta * speed
	energy = base_energy + (sin(_t) + sin(_t * 1.7)) * 0.5 * flicker_amount
