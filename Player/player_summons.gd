extends Node

signal summon_spawned(summon: Node2D)
signal summon_removed
signal summons_changed(current_summons: int, max_summons: int)
signal summon_failed(message: String)

@export_group("Summon Settings")
@export_range(1, 10, 1) var max_summons: int = 1
@export var summon_scene: PackedScene
@export var spawn_offset: Vector2 = Vector2(30, 0)
@export var use_player_direction_for_spawn: bool = true

# The summon body collides only with this physics mask.
# In your project, layer 1 is normally the world.
@export_flags_2d_physics var world_collision_mask: int = 1

# Extra positions tested if the preferred side is blocked.
@export var safe_spawn_offsets: Array[Vector2] = [
	Vector2(30, 0),
	Vector2(-30, 0),
	Vector2(18, -24),
	Vector2(-18, -24),
	Vector2(0, -32)
]

@export_group("Groups")
@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"

var player: Node2D = null
var active_summons: Dictionary = {}


func _ready() -> void:
	_find_player()
	_emit_summons_changed()


func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D


func _player_is_valid() -> bool:
	_find_player()

	return (
		player != null
		and is_instance_valid(player)
	)


func summon() -> bool:
	return _create_summon(-1, false)


func restore_from_run_state() -> bool:
	if get_node_or_null("/root/RunState") == null:
		return false

	if not RunState.has_saved_summon():
		return false

	_cleanup_invalid_summons()

	if not active_summons.is_empty():
		return true

	return _create_summon(
		RunState.summon_health,
		true
	)


func _create_summon(
	saved_health: int,
	from_room_change: bool
) -> bool:
	_cleanup_invalid_summons()

	if not _player_is_valid():
		return _fail_summon("Player could not be found.")

	if summon_scene == null:
		return _fail_summon("Summon Scene is missing.")

	if active_summons.size() >= max_summons:
		return _fail_summon(
			"Maximum number of summons reached."
		)

	var summon_instance: Node = summon_scene.instantiate()

	if not summon_instance is Node2D:
		if summon_instance != null:
			summon_instance.queue_free()

		return _fail_summon(
			"Summon Scene root must be Node2D."
		)

	var summon_node := summon_instance as Node2D
	var scene_parent: Node = get_tree().current_scene

	if scene_parent == null:
		summon_node.queue_free()
		return _fail_summon("Current scene was not found.")

	var spawn_position: Vector2 = _find_safe_spawn_position(
		summon_node
	)

	scene_parent.add_child(summon_node)
	summon_node.global_position = spawn_position

	# The CharacterBody itself only collides with the world.
	# Player, enemies and other summons are handled through Areas.
	if summon_node is CollisionObject2D:
		var collision_object := summon_node as CollisionObject2D
		collision_object.collision_layer = 0
		collision_object.collision_mask = world_collision_mask

	if not summon_node.is_in_group(summon_group):
		summon_node.add_to_group(summon_group)

	var summon_id: int = summon_node.get_instance_id()
	active_summons[summon_id] = summon_node

	if summon_node.has_method("setup_summon"):
		summon_node.setup_summon(player, self)

	if saved_health > 0 and summon_node.has_method(
		"restore_summon_state"
	):
		summon_node.restore_summon_state(
			saved_health,
			from_room_change
		)

	summon_node.tree_exited.connect(
		_on_summon_tree_exited.bind(summon_id),
		CONNECT_ONE_SHOT
	)

	if get_node_or_null("/root/RunState") != null:
		var health_to_save: int = saved_health

		if health_to_save <= 0:
			health_to_save = _get_summon_health(
				summon_node
			)

		RunState.save_summon_data(
			true,
			health_to_save
		)

	summon_spawned.emit(summon_node)
	_emit_summons_changed()

	return true


func _find_safe_spawn_position(
	summon_node: Node2D
) -> Vector2:
	var preferred_offsets: Array[Vector2] = []

	var direction: float = 1.0

	if (
		use_player_direction_for_spawn
		and "facing_right" in player
		and not bool(player.facing_right)
	):
		direction = -1.0

	preferred_offsets.append(
		Vector2(
			abs(spawn_offset.x) * direction,
			spawn_offset.y
		)
	)

	for offset in safe_spawn_offsets:
		var adjusted: Vector2 = offset

		if use_player_direction_for_spawn:
			adjusted.x *= direction

		if not preferred_offsets.has(adjusted):
			preferred_offsets.append(adjusted)

	for offset in preferred_offsets:
		var candidate: Vector2 = (
			player.global_position + offset
		)

		if _position_is_free(summon_node, candidate):
			return candidate

	# Last fallback: directly above the player.
	return player.global_position + Vector2(0, -40)


func _position_is_free(
	summon_node: Node2D,
	position_to_test: Vector2
) -> bool:
	var body_shape := summon_node.get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D

	if body_shape == null or body_shape.shape == null:
		return true

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = body_shape.shape
	query.transform = Transform2D(
		0.0,
		position_to_test + body_shape.position
	)
	query.collision_mask = world_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hits: Array[Dictionary] = (
		player.get_world_2d().direct_space_state.intersect_shape(
			query,
			1
		)
	)

	return hits.is_empty()


func save_to_run_state() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	var summon_node: Node2D = get_first_active_summon()

	if summon_node == null:
		RunState.clear_summon_data()
		return

	RunState.save_summon_data(
		true,
		_get_summon_health(summon_node)
	)


func _get_summon_health(summon_node: Node) -> int:
	if summon_node.has_method("get_current_health"):
		return int(summon_node.get_current_health())

	if "hp" in summon_node:
		return int(summon_node.hp)

	return 1


func can_summon() -> bool:
	_cleanup_invalid_summons()
	return active_summons.size() < max_summons


func get_current_summon_count() -> int:
	_cleanup_invalid_summons()
	return active_summons.size()


func has_active_summon() -> bool:
	return get_current_summon_count() > 0


func get_active_summons() -> Array[Node2D]:
	_cleanup_invalid_summons()

	var result: Array[Node2D] = []

	for value in active_summons.values():
		if value is Node2D and is_instance_valid(value):
			result.append(value as Node2D)

	return result


func get_first_active_summon() -> Node2D:
	var summons: Array[Node2D] = get_active_summons()

	if summons.is_empty():
		return null

	return summons[0]


func unregister_summon(
	summon_node: Node,
	permanently_dead: bool = true
) -> void:
	if summon_node == null:
		return

	active_summons.erase(summon_node.get_instance_id())

	if (
		permanently_dead
		and get_node_or_null("/root/RunState") != null
	):
		RunState.clear_summon_data()

	summon_removed.emit()
	_emit_summons_changed()


func _on_summon_tree_exited(summon_id: int) -> void:
	active_summons.erase(summon_id)
	_emit_summons_changed()


func clear_all_summons() -> void:
	var summons: Array[Node2D] = get_active_summons()
	active_summons.clear()

	for summon_node in summons:
		if is_instance_valid(summon_node):
			summon_node.queue_free()

	if get_node_or_null("/root/RunState") != null:
		RunState.clear_summon_data()

	summon_removed.emit()
	_emit_summons_changed()


func teleport_all_summons_to_player() -> void:
	for summon_node in get_active_summons():
		if summon_node.has_method("teleport_to_player"):
			summon_node.teleport_to_player()


func _cleanup_invalid_summons() -> void:
	var invalid_ids: Array[int] = []

	for summon_id in active_summons.keys():
		var summon_node = active_summons[summon_id]

		if summon_node == null or not is_instance_valid(
			summon_node
		):
			invalid_ids.append(int(summon_id))

	for summon_id in invalid_ids:
		active_summons.erase(summon_id)

	if not invalid_ids.is_empty():
		_emit_summons_changed()


func _emit_summons_changed() -> void:
	summons_changed.emit(
		active_summons.size(),
		max_summons
	)


func _fail_summon(message: String) -> bool:
	summon_failed.emit(message)
	push_warning("PlayerSummons: " + message)
	return false
