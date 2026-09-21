extends Node2D

@export var arrow_scene: PackedScene
@export var direction: float = 1.0
@export var range: float = 160.0
@export var one_shot: bool = true
@export var player_group: StringName = &"player"

@onready var ray: RayCast2D = $RayCast2D
@onready var shoot_point: Marker2D = $ShootPoint

var fired: bool = false


func _ready() -> void:
	ray.enabled = true
	ray.collide_with_bodies = true
	ray.collide_with_areas = false
	ray.exclude_parent = true
	ray.target_position = Vector2(range * direction, 0)


func _physics_process(_delta: float) -> void:
	if fired and one_shot:
		return

	ray.target_position = Vector2(range * direction, 0)
	ray.force_raycast_update()

	if not ray.is_colliding():
		return

	var hit: Object = ray.get_collider()

	if hit == null:
		return

	if hit is Node and (hit as Node).is_in_group(player_group):
		_fire()


func _fire() -> void:
	if arrow_scene == null:
		push_warning("ArrowTrap: Arrow Scene fehlt im Inspector.")
		return

	fired = true

	var arrow = arrow_scene.instantiate()
	get_tree().current_scene.add_child(arrow)

	arrow.global_position = shoot_point.global_position

	if arrow.has_method("setup"):
		arrow.setup(direction, self)
