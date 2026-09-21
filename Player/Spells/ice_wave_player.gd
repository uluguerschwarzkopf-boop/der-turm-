extends Node2D


# ============================================================
# KRISTALLSZENE
# ============================================================

@export_group("Kristallszene")

# Hier die Szene Ice_Crystal_Player.tscn hineinziehen.
@export var ice_crystal_scene: PackedScene


# ============================================================
# EISWELLE
# ============================================================

@export_group("Eiswelle")

# Wie viele Kristalle insgesamt entstehen.
@export_range(1, 20, 1)
var crystal_count: int = 4

# Abstand des ersten Kristalls vom Startpunkt der Eiswelle.
@export var first_crystal_distance: float = 24.0

# Abstand zwischen den einzelnen Kristallen.
@export var distance_between_crystals: float = 20.0

# Zeit zwischen den Kristall-Spawns.
@export var spawn_delay: float = 0.08


# ============================================================
# GRÖSSE
# ============================================================

@export_group("Größe")

# Größe des ersten Kristalls.
@export var first_crystal_scale: float = 0.75

# So viel größer wird jeder weitere Kristall.
@export var scale_increase_per_crystal: float = 0.15

# Sicherheitswert gegen zu kleine oder negative Skalierung.
@export var minimum_crystal_scale: float = 0.1


# ============================================================
# SCHADEN
# ============================================================

@export_group("Schaden")

# Schaden pro Kristall.
@export var damage_per_crystal: int = 1


# ============================================================
# BODENPRÜFUNG
# ============================================================

@export_group("Bodenprüfung")

# Der Boden-RayCast beginnt so weit oberhalb der Zielposition.
@export var ground_check_start_height: float = 24.0

# So weit sucht der RayCast nach unten nach Boden.
@export var ground_check_distance: float = 64.0

# Damit kann der Kristall etwas über oder unter dem Boden
# positioniert werden.
@export var ground_surface_offset: float = 0.0

# Wenn kein Boden mehr vorhanden ist, endet die Eiswelle.
@export var stop_at_cliff: bool = true

# Hier muss die Collision-Layer des Bodens aktiviert sein.
@export_flags_2d_physics
var ground_collision_mask: int = 1


# ============================================================
# WANDPRÜFUNG
# ============================================================

@export_group("Wandprüfung")

# Wenn eine Wand erkannt wird, endet die Eiswelle.
@export var stop_at_wall: bool = true

# Höhe des horizontalen Wand-RayCasts über dem Boden.
@export var wall_check_height: float = 8.0

# Hier muss die Collision-Layer der Wände aktiviert sein.
@export_flags_2d_physics
var wall_collision_mask: int = 1


# ============================================================
# GEGNER
# ============================================================

@export_group("Gegner")

# Alle Nodes in dieser Gruppe werden von Boden- und
# Wand-RayCasts ignoriert.
@export var enemy_group: StringName = &"enemy"


# ============================================================
# LEBENSDAUER
# ============================================================

@export_group("Lebensdauer")

# Kurze zusätzliche Zeit nach dem letzten Kristall,
# bevor der Eiswellen-Node entfernt wird.
@export var cleanup_delay: float = 0.2


# ============================================================
# STATUS
# ============================================================

var cast_direction: Vector2 = Vector2.RIGHT
var owner_player: Node = null

var wave_started: bool = false
var cast_generation: int = 0


# ============================================================
# START
# ============================================================

func _ready() -> void:
	# Der SpellManager ruft setup() direkt nach dem Erzeugen auf.
	# Deshalb startet die Welle erst verzögert.
	call_deferred("_start_wave_if_ready")


# ============================================================
# SETUP DURCH DEN SPELLMANAGER
# ============================================================

func setup(
	new_direction: Vector2,
	new_owner_player: Node = null
) -> void:
	owner_player = new_owner_player

	if new_direction == Vector2.ZERO:
		cast_direction = Vector2.RIGHT
	else:
		cast_direction = new_direction.normalized()

	# Die Eiswelle darf nur nach links oder rechts laufen.
	if cast_direction.x < 0.0:
		cast_direction = Vector2.LEFT
	else:
		cast_direction = Vector2.RIGHT


# ============================================================
# EISWELLE STARTEN
# ============================================================

func _start_wave_if_ready() -> void:
	if wave_started:
		return

	wave_started = true
	cast_generation += 1

	var this_generation: int = cast_generation

	_run_ice_wave(this_generation)


# ============================================================
# EISWELLE ERZEUGEN
# ============================================================

func _run_ice_wave(
	this_generation: int
) -> void:
	if ice_crystal_scene == null:
		push_error(
			"IceWave: Ice Crystal Scene fehlt im Inspector."
		)
		queue_free()
		return

	var direction_sign: float = 1.0

	if cast_direction.x < 0.0:
		direction_sign = -1.0

	var previous_ground_position: Vector2 = global_position

	for crystal_index in range(crystal_count):
		if not _can_continue_wave(this_generation):
			return

		var distance_from_start: float = (
			first_crystal_distance
			+ distance_between_crystals
			* float(crystal_index)
		)

		var target_x: float = (
			global_position.x
			+ distance_from_start
			* direction_sign
		)

		# Sucht ausschließlich nach echtem Boden.
		# Spieler und Gegner werden ausgeschlossen.
		var ground_result: Dictionary = (
			_find_ground_at_x(target_x)
		)

		if ground_result.is_empty():
			if stop_at_cliff:
				break

			continue

		var ground_position: Vector2 = (
			ground_result["position"] as Vector2
		)

		# Gegner werden auch hier ignoriert.
		# Nur echte Wände stoppen die Welle.
		if (
			stop_at_wall
			and _wall_between_positions(
				previous_ground_position,
				ground_position
			)
		):
			break

		var crystal_scale_value: float = max(
			first_crystal_scale
			+ scale_increase_per_crystal
			* float(crystal_index),
			minimum_crystal_scale
		)

		_spawn_crystal(
			ground_position,
			crystal_scale_value
		)

		previous_ground_position = ground_position

		if crystal_index < crystal_count - 1:
			if not await _wait_safely(
				spawn_delay,
				this_generation
			):
				return

	if not await _wait_safely(
		cleanup_delay,
		this_generation
	):
		return

	queue_free()


# ============================================================
# EINEN KRISTALL ERZEUGEN
# ============================================================

func _spawn_crystal(
	spawn_position: Vector2,
	crystal_scale_value: float
) -> void:
	if ice_crystal_scene == null:
		return

	var crystal_instance: Node = (
		ice_crystal_scene.instantiate()
	)

	if crystal_instance == null:
		return

	var tree := get_tree()

	if tree == null:
		crystal_instance.queue_free()
		return

	var spawn_parent: Node = tree.current_scene

	if spawn_parent == null:
		crystal_instance.queue_free()
		return

	spawn_parent.add_child(crystal_instance)

	if crystal_instance is Node2D:
		var crystal_node: Node2D = (
			crystal_instance as Node2D
		)

		crystal_node.global_position = (
			spawn_position
			+ Vector2.UP * ground_surface_offset
		)

		crystal_node.scale = Vector2(
			crystal_scale_value,
			crystal_scale_value
		)

	if crystal_instance.has_method("setup"):
		crystal_instance.setup(
			owner_player,
			damage_per_crystal
		)


# ============================================================
# BODEN SUCHEN
# ============================================================

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
# WAND SUCHEN
# ============================================================

func _wall_between_positions(
	from_ground: Vector2,
	to_ground: Vector2
) -> bool:
	var world_2d := get_world_2d()

	if world_2d == null:
		return false

	var space_state: PhysicsDirectSpaceState2D = (
		world_2d.direct_space_state
	)

	var ray_start: Vector2 = (
		from_ground
		+ Vector2.UP * wall_check_height
	)

	var ray_end: Vector2 = (
		to_ground
		+ Vector2.UP * wall_check_height
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
# SPIELER UND GEGNER VON RAYCASTS AUSSCHLIESSEN
# ============================================================

func _get_excluded_collision_rids() -> Array[RID]:
	var excluded_rids: Array[RID] = []

	# Spieler ausschließen.
	if owner_player is CollisionObject2D:
		excluded_rids.append(
			owner_player.get_rid()
		)

	var tree := get_tree()

	if tree == null:
		return excluded_rids

	# Alle normalen Gegner, Minibosse und Bosse ausschließen,
	# sofern sie in der Gruppe "enemy" sind.
	var enemies: Array[Node] = (
		tree.get_nodes_in_group(enemy_group)
	)

	for enemy: Node in enemies:
		if enemy == null:
			continue

		if not is_instance_valid(enemy):
			continue

		if enemy is CollisionObject2D:
			excluded_rids.append(
				enemy.get_rid()
			)

	return excluded_rids


# ============================================================
# SICHERE TIMER
# ============================================================

func _wait_safely(
	wait_time: float,
	this_generation: int
) -> bool:
	if not _can_continue_wave(this_generation):
		return false

	var tree := get_tree()

	if tree == null:
		return false

	await tree.create_timer(
		max(wait_time, 0.001)
	).timeout

	return _can_continue_wave(this_generation)


func _can_continue_wave(
	this_generation: int
) -> bool:
	if this_generation != cast_generation:
		return false

	if not is_inside_tree():
		return false

	if get_tree() == null:
		return false

	return true
