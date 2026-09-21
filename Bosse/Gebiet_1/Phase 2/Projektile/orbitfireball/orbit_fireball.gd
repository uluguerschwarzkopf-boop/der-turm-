extends Area2D

@export var player_group: StringName = &"player"

@export_group("Movement")
@export var speed: float = 180.0
@export var lifetime: float = 6.0
@export var target_player_on_spawn: bool = true
@export var sprite_points_right: bool = true

@export_group("Damage")
@export var core_damage: int = 1
@export var orb_damage: int = 1

@export_group("Orbit")
@export var orbit_radius: float = 28.0
@export var orbit_speed_degrees: float = 220.0
@export var start_angle_degrees: float = 0.0

@export_group("Animations")
@export var anim_spawn: StringName = &"spawn"
@export var anim_loop: StringName = &"loop"
@export var anim_impact: StringName = &"impact"

@export var orb_anim_spawn: StringName = &"spawn"
@export var orb_anim_loop: StringName = &"loop"
@export var orb_anim_impact: StringName = &"impact"

@onready var core_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var small_orbs: Array[Area2D] = [
	$SmallOrb1,
	$SmallOrb2,
	$SmallOrb3
]

var target: Node2D = null
var direction: Vector2 = Vector2.LEFT
var active: bool = false
var dying: bool = false
var angle: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_core_body_entered)

	core_sprite.animation_finished.connect(_on_core_animation_finished)

	for orb in small_orbs:
		orb.body_entered.connect(_on_small_orb_body_entered.bind(orb))
		orb.monitoring = true
		orb.monitorable = true

		var orb_sprite := _get_orb_sprite(orb)

		if orb_sprite != null:
			orb_sprite.animation_finished.connect(_on_orb_animation_finished.bind(orb, orb_sprite))

			if orb_sprite.sprite_frames.has_animation(orb_anim_spawn):
				orb_sprite.play(orb_anim_spawn)
			elif orb_sprite.sprite_frames.has_animation(orb_anim_loop):
				orb_sprite.play(orb_anim_loop)

	monitoring = true
	monitorable = true

	angle = deg_to_rad(start_angle_degrees)

	if core_sprite.sprite_frames.has_animation(anim_spawn):
		core_sprite.play(anim_spawn)
	else:
		_start_fly()

	await get_tree().create_timer(lifetime).timeout

	if is_instance_valid(self):
		queue_free()


func setup(new_target: Node2D, new_damage: int = -1, new_speed: float = -1.0) -> void:
	target = new_target

	if new_damage >= 0:
		core_damage = new_damage
		orb_damage = new_damage

	if new_speed > 0:
		speed = new_speed


func _physics_process(delta: float) -> void:
	if not active:
		_update_orbs(delta)
		return

	if dying:
		return

	global_position += direction * speed * delta
	_update_orbs(delta)


func _get_orb_sprite(orb: Area2D) -> AnimatedSprite2D:
	for child in orb.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D

	return null


func _start_fly() -> void:
	if target_player_on_spawn:
		if target == null:
			target = get_tree().get_first_node_in_group(player_group) as Node2D

		if target != null and is_instance_valid(target):
			direction = (target.global_position - global_position).normalized()

	if direction == Vector2.ZERO:
		direction = Vector2.LEFT

	if sprite_points_right:
		rotation = direction.angle()
	else:
		rotation = direction.angle() + PI

	active = true

	if core_sprite.sprite_frames.has_animation(anim_loop):
		core_sprite.play(anim_loop)

	for orb in small_orbs:
		var orb_sprite := _get_orb_sprite(orb)

		if orb_sprite != null and orb_sprite.sprite_frames.has_animation(orb_anim_loop):
			orb_sprite.play(orb_anim_loop)


func _update_orbs(delta: float) -> void:
	angle += deg_to_rad(orbit_speed_degrees) * delta

	var alive_orbs: Array[Area2D] = []

	for orb in small_orbs:
		if orb != null and is_instance_valid(orb) and orb.visible and orb.monitoring:
			alive_orbs.append(orb)

	if alive_orbs.is_empty():
		return

	for i in alive_orbs.size():
		var orb := alive_orbs[i]
		var a := angle + TAU * float(i) / float(alive_orbs.size())

		orb.position = Vector2(cos(a), sin(a)) * orbit_radius


func _on_core_animation_finished() -> void:
	if core_sprite.animation == anim_spawn:
		_start_fly()
		return

	if core_sprite.animation == anim_impact:
		queue_free()


func _on_core_body_entered(body: Node) -> void:
	if dying:
		return

	if body.is_in_group(player_group):
		if body.has_method("take_damage"):
			body.take_damage(core_damage, global_position)

	_die_all()
	return

	_die_all()


func _on_small_orb_body_entered(body: Node, orb: Area2D) -> void:
	if dying:
		return

	if orb == null or not is_instance_valid(orb):
		return

	if not orb.monitoring:
		return

	if body.is_in_group(player_group):
		if body.has_method("take_damage"):
			body.take_damage(orb_damage, orb.global_position)

	_die_single_orb(orb)
	return

	_die_single_orb(orb)


func _die_all() -> void:
	if dying:
		return

	dying = true
	active = false
	monitoring = false

	for orb in small_orbs:
		if orb != null and is_instance_valid(orb):
			orb.monitoring = false
			orb.visible = false

	if core_sprite.sprite_frames.has_animation(anim_impact):
		core_sprite.play(anim_impact)
	else:
		queue_free()


func _die_single_orb(orb: Area2D) -> void:
	orb.monitoring = false

	var orb_sprite := _get_orb_sprite(orb)

	if orb_sprite != null and orb_sprite.sprite_frames.has_animation(orb_anim_impact):
		orb_sprite.play(orb_anim_impact)
	else:
		orb.visible = false


func _on_orb_animation_finished(orb: Area2D, orb_sprite: AnimatedSprite2D) -> void:
	if orb_sprite.animation == orb_anim_spawn:
		if orb_sprite.sprite_frames.has_animation(orb_anim_loop):
			orb_sprite.play(orb_anim_loop)
		return

	if orb_sprite.animation == orb_anim_impact:
		orb.visible = false
