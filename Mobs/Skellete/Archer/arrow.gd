extends Area2D


@export var speed: float = 420.0
@export var damage: int = 1
@export var lifetime: float = 3.0

@export var enemy_hurtbox_group: StringName = &"enemy_hurtbox"
@export var summon_group: StringName = &"player_summon"

var direction: float = 1.0
var shooter: Node = null

var has_hit: bool = false

# Wird von der Lichtkugel-Aura gesetzt, solange der Pfeil sie
# durchfliegt (1.0 = normale Geschwindigkeit).
var speed_multiplier: float = 1.0


func _ready() -> void:
	monitoring = true
	monitorable = true

	if not area_entered.is_connected(
		_on_area_entered
	):
		area_entered.connect(
			_on_area_entered
		)

	if not body_entered.is_connected(
		_on_body_entered
	):
		body_entered.connect(
			_on_body_entered
		)

	await get_tree().create_timer(
		max(lifetime, 0.01)
	).timeout

	if is_instance_valid(self):
		queue_free()


func setup(
	new_direction: float,
	new_shooter: Node = null
) -> void:
	direction = new_direction
	shooter = new_shooter

	if direction > 0.0:
		scale.x = -abs(scale.x)
	else:
		scale.x = abs(scale.x)


func _physics_process(delta: float) -> void:
	if has_hit:
		return

	global_position.x += direction * speed * speed_multiplier * delta


# Wird von light_orb_player.gd aufgerufen, solange der Pfeil
# innerhalb der Aura fliegt.
func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = clampf(multiplier, 0.0, 1.0)


func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	if body == null:
		return

	if _is_shooter_or_child(body):
		return

	var target: Node = _find_damage_target(body)

	if target != null:
		_hit_target(target)
		return

	_destroy_arrow()


func _on_area_entered(area: Area2D) -> void:
	if has_hit:
		return

	if area == null:
		return

	if _is_shooter_or_child(area):
		return

	# Beschworenes Skelett:
	# Nur die echte Hurtbox darf Schaden auslösen.
	if _is_summon_hurtbox(area):
		var summon_target: Node = _find_damage_target(area)

		if summon_target != null:
			_hit_target(summon_target)

		return

	# Bestehende gegnerische Hurtbox-Erkennung.
	if area.is_in_group(enemy_hurtbox_group):
		var enemy_target: Node = _find_damage_target(area)

		if enemy_target != null:
			_hit_target(enemy_target)
			return

		_destroy_arrow()
		return

	# Andere Areas wie DetectionArea oder AttackHitbox
	# werden vollständig ignoriert.


func _is_summon_hurtbox(area: Area2D) -> bool:
	if area.name != &"Hurtbox":
		return false

	var current: Node = area.get_parent()

	while current != null:
		if current.is_in_group(summon_group):
			return true

		current = current.get_parent()

	return false


func _hit_target(target: Node) -> void:
	if has_hit:
		return

	if target == null:
		return

	if not is_instance_valid(target):
		return

	if not target.has_method("take_damage"):
		return

	has_hit = true

	monitoring = false
	monitorable = false

	target.take_damage(
		damage,
		global_position
	)

	queue_free()


func _destroy_arrow() -> void:
	if has_hit:
		return

	has_hit = true

	monitoring = false
	monitorable = false

	queue_free()


func _find_damage_target(node: Node) -> Node:
	var current: Node = node

	while current != null:
		if current.has_method("take_damage"):
			return current

		current = current.get_parent()

	return null


func _is_shooter_or_child(node: Node) -> bool:
	if shooter == null:
		return false

	if not is_instance_valid(shooter):
		return false

	var current: Node = node

	while current != null:
		if current == shooter:
			return true

		current = current.get_parent()

	return false
