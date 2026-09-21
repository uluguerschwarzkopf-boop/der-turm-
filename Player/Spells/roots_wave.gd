extends Area2D


# ============================================================
# WELLENEINSTELLUNGEN
# ============================================================

@export_group("Bewegung")

@export var speed: float = 140.0
@export var lifetime: float = 4.0

# Falls das Sprite ursprünglich nach rechts gezeichnet wurde: An.
# Falls es ursprünglich nach links gezeichnet wurde: Aus.
@export var sprite_points_right: bool = true


# ============================================================
# SCHADEN
# ============================================================

@export_group("Schaden")

@export var damage: int = 1
@export var enemy_group: StringName = &"enemy"

# Jeder Gegner wird von dieser Welle höchstens einmal getroffen.
@export var one_hit_per_enemy: bool = true


# ============================================================
# FESTHALTE-ANIMATION
# ============================================================

@export_group("Roots Hold")

# Hier roots_hold.tscn hineinziehen.
@export var roots_hold_scene: PackedScene

# Position der Festhalte-Animation relativ zur Bodenposition.
@export var hold_position_offset: Vector2 = Vector2.ZERO


# ============================================================
# BODENPRÜFUNG
# ============================================================

@export_group("Bodenprüfung")

# Abstand des Bodenstrahls oberhalb der Welle.
@export var ground_check_start_height: float = 20.0

# Länge des Bodenstrahls nach unten.
@export var ground_check_distance: float = 52.0

# Positioniert die Welle etwas über oder unter der Bodenoberfläche.
@export var ground_surface_offset: float = 0.0

# Abstand des Prüfpunktes vor der Welle.
@export var cliff_check_ahead_distance: float = 10.0

# Bei einer Klippe spielt die Welle End und verschwindet.
@export var stop_at_cliff: bool = true

# Ausschließlich die Collision-Layer des Bodens auswählen.
@export_flags_2d_physics
var ground_collision_mask: int = 1


# ============================================================
# WANDPRÜFUNG
# ============================================================

@export_group("Wandprüfung")

@export var stop_at_wall: bool = true

# Wie weit vor der Welle nach einer Wand gesucht wird.
@export var wall_check_distance: float = 10.0

# Höhe des Wandstrahls über dem Boden.
@export var wall_check_height: float = 7.0

# Ausschließlich die Collision-Layer der Welt/Wände auswählen.
@export_flags_2d_physics
var wall_collision_mask: int = 1


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var move_animation: StringName = &"Move"
@export var end_animation: StringName = &"End"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
)

@onready var collision_shape: CollisionShape2D = (
	get_node_or_null("CollisionShape2D") as CollisionShape2D
)


# ============================================================
# STATUS
# ============================================================

var cast_direction: Vector2 = Vector2.RIGHT
var owner_player: Node = null

var active: bool = false
var ending: bool = false

var already_hit_enemy_ids: Array[int] = []


# ============================================================
# START
# ============================================================

func _ready() -> void:
	monitoring = true
	monitorable = true

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	if sprite != null:
		if not sprite.animation_finished.is_connected(
			_on_animation_finished
		):
			sprite.animation_finished.connect(
				_on_animation_finished
			)

	if collision_shape != null:
		collision_shape.disabled = false

	_update_visual_direction()
	_place_on_ground()

	if sprite != null:
		if (
			sprite.sprite_frames != null
			and sprite.sprite_frames.has_animation(
				move_animation
			)
		):
			sprite.play(move_animation)

	active = true

	_start_lifetime_timer()


# ============================================================
# SETUP DURCH SPELLMANAGER
# ============================================================

func setup(
	new_direction: Vector2,
	new_owner_player: Node = null
) -> void:
	owner_player = new_owner_player

	if new_direction.x < 0.0:
		cast_direction = Vector2.LEFT
	else:
		cast_direction = Vector2.RIGHT

	_update_visual_direction()


# ============================================================
# BEWEGUNG
# ============================================================

func _physics_process(delta: float) -> void:
	if not active or ending:
		return

	var direction_sign: float = (
		-1.0 if cast_direction.x < 0.0 else 1.0
	)

	if stop_at_wall and _wall_is_ahead(direction_sign):
		_start_end()
		return

	if stop_at_cliff and not _ground_is_ahead(direction_sign):
		_start_end()
		return

	global_position.x += direction_sign * speed * delta

	# Hält die Welle auch auf leicht unebenem Boden
	# an der Oberfläche.
	_place_on_ground()


# ============================================================
# BODENPOSITION
# ============================================================

func _place_on_ground() -> void:
	var ground_result: Dictionary = _find_ground_at_x(
		global_position.x
	)

	if ground_result.is_empty():
		return

	var ground_position: Vector2 = (
		ground_result["position"] as Vector2
	)

	global_position.y = (
		ground_position.y
		- ground_surface_offset
	)


func _ground_is_ahead(
	direction_sign: float
) -> bool:
	var check_x: float = (
		global_position.x
		+ cliff_check_ahead_distance
		* direction_sign
	)

	var result: Dictionary = _find_ground_at_x(check_x)

	return not result.is_empty()


func _find_ground_at_x(
	target_x: float
) -> Dictionary:
	var world_2d := get_world_2d()

	if world_2d == null:
		return {}

	var space_state: PhysicsDirectSpaceState2D = (
		world_2d.direct_space_state
	)

	var ray_start := Vector2(
		target_x,
		global_position.y - ground_check_start_height
	)

	var ray_end := Vector2(
		target_x,
		global_position.y + ground_check_distance
	)

	var query := PhysicsRayQueryParameters2D.create(
		ray_start,
		ray_end,
		ground_collision_mask
	)

	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_excluded_collision_rids()

	return space_state.intersect_ray(query)


# ============================================================
# WANDPRÜFUNG
# ============================================================

func _wall_is_ahead(
	direction_sign: float
) -> bool:
	var world_2d := get_world_2d()

	if world_2d == null:
		return false

	var space_state: PhysicsDirectSpaceState2D = (
		world_2d.direct_space_state
	)

	var ray_start: Vector2 = (
		global_position
		+ Vector2.UP * wall_check_height
	)

	var ray_end: Vector2 = (
		ray_start
		+ Vector2(
			wall_check_distance * direction_sign,
			0.0
		)
	)

	var query := PhysicsRayQueryParameters2D.create(
		ray_start,
		ray_end,
		wall_collision_mask
	)

	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_excluded_collision_rids()

	var result: Dictionary = (
		space_state.intersect_ray(query)
	)

	return not result.is_empty()


# ============================================================
# GEGNER TREFFEN
# ============================================================

func _on_body_entered(body: Node) -> void:
	if not active or ending:
		return

	if body == null:
		return

	if body == owner_player:
		return

	if not body.is_in_group(enemy_group):
		return

	var enemy_id: int = body.get_instance_id()

	if (
		one_hit_per_enemy
		and already_hit_enemy_ids.has(enemy_id)
	):
		return

	already_hit_enemy_ids.append(enemy_id)

	if body.has_method("take_damage"):
		body.take_damage(damage)

	if is_instance_valid(body):
		_spawn_roots_hold(body)


# ============================================================
# ROOTS HOLD ERZEUGEN
# ============================================================

func _spawn_roots_hold(enemy: Node) -> void:
	if roots_hold_scene == null:
		push_warning(
			"RootsWave: Roots Hold Scene fehlt im Inspector."
		)
		return

	if enemy == null or not is_instance_valid(enemy):
		return

	var hold_instance: Node = roots_hold_scene.instantiate()

	if hold_instance == null:
		return

	var tree := get_tree()

	if tree == null:
		hold_instance.queue_free()
		return

	var spawn_parent: Node = tree.current_scene

	if spawn_parent == null:
		hold_instance.queue_free()
		return

	spawn_parent.add_child(hold_instance)

	if hold_instance is Node2D:
		var hold_node := hold_instance as Node2D

		var ground_result: Dictionary = _find_ground_below_enemy(
			enemy
		)

		if not ground_result.is_empty():
			var ground_position: Vector2 = (
				ground_result["position"] as Vector2
			)

			hold_node.global_position = (
				ground_position
				+ hold_position_offset
			)
		elif enemy is Node2D:
			hold_node.global_position = (
				(enemy as Node2D).global_position
				+ hold_position_offset
			)

	if hold_instance.has_method("setup"):
		hold_instance.setup(enemy, owner_player)


func _find_ground_below_enemy(
	enemy: Node
) -> Dictionary:
	if not enemy is Node2D:
		return {}

	var enemy_position: Vector2 = (
		enemy as Node2D
	).global_position

	var world_2d := get_world_2d()

	if world_2d == null:
		return {}

	var space_state: PhysicsDirectSpaceState2D = (
		world_2d.direct_space_state
	)

	var ray_start := Vector2(
		enemy_position.x,
		enemy_position.y - ground_check_start_height
	)

	var ray_end := Vector2(
		enemy_position.x,
		enemy_position.y + ground_check_distance
	)

	var query := PhysicsRayQueryParameters2D.create(
		ray_start,
		ray_end,
		ground_collision_mask
	)

	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = _get_excluded_collision_rids()

	return space_state.intersect_ray(query)


# ============================================================
# SPIELER UND GEGNER VON RAYCASTS AUSSCHLIESSEN
# ============================================================

func _get_excluded_collision_rids() -> Array[RID]:
	var excluded_rids: Array[RID] = []

	if owner_player is CollisionObject2D:
		excluded_rids.append(
			owner_player.get_rid()
		)

	var tree := get_tree()

	if tree == null:
		return excluded_rids

	for enemy: Node in tree.get_nodes_in_group(
		enemy_group
	):
		if (
			enemy != null
			and is_instance_valid(enemy)
			and enemy is CollisionObject2D
		):
			excluded_rids.append(
				enemy.get_rid()
			)

	return excluded_rids


# ============================================================
# RICHTUNG
# ============================================================

func _update_visual_direction() -> void:
	if sprite == null:
		return

	var moving_right: bool = cast_direction.x >= 0.0

	if sprite_points_right:
		sprite.flip_h = not moving_right
	else:
		sprite.flip_h = moving_right


# ============================================================
# ENDE
# ============================================================

func _start_end() -> void:
	if ending:
		return

	ending = true
	active = false

	monitoring = false
	monitorable = false

	if collision_shape != null:
		collision_shape.set_deferred(
			"disabled",
			true
		)

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			end_animation
		)
	):
		sprite.play(end_animation)
		return

	queue_free()


func _on_animation_finished() -> void:
	if sprite == null:
		return

	if ending and sprite.animation == end_animation:
		queue_free()


func _start_lifetime_timer() -> void:
	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(lifetime, 0.1)
	).timeout

	if is_instance_valid(self) and not ending:
		_start_end()
