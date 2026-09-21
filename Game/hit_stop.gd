extends Node

@export var hitstop_time_scale: float = 0.15
@export var hitstop_duration: float = 0.08

var active: bool = false


func do_hitstop(duration: float = -1.0, time_scale: float = -1.0) -> void:
	if active:
		return

	active = true

	var real_duration := hitstop_duration
	var real_scale := hitstop_time_scale

	if duration > 0:
		real_duration = duration

	if time_scale > 0:
		real_scale = time_scale

	Engine.time_scale = real_scale

	await get_tree().create_timer(real_duration, true, false, true).timeout

	Engine.time_scale = 1.0
	active = false
