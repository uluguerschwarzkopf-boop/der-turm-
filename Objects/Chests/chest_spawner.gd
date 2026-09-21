extends Marker2D


@export_group("Chest Scenes")

@export var bronze_chest_scene: PackedScene = preload(
	"res://Objects/Chests/bronze_chest.tscn"
)

@export var silver_chest_scene: PackedScene = preload(
	"res://Objects/Chests/silber_chest.tscn"
)

@export var gold_chest_scene: PackedScene = preload(
	"res://Objects/Chests/gold_chest.tscn"
)


@export_group("Spawn")

@export_range(0.0, 100.0, 1.0)
var spawn_chance: float = 100.0


@export_group("Weights")

@export_range(0.0, 100.0, 1.0)
var bronze_weight: float = 60.0

@export_range(0.0, 100.0, 1.0)
var silver_weight: float = 30.0

@export_range(0.0, 100.0, 1.0)
var gold_weight: float = 10.0


@export_group("Debug")

@export var force_bronze_for_test: bool = false
@export var debug_messages: bool = true


func _ready() -> void:
	if debug_messages:
		print(
			"=== CHEST SPAWNER READY ==="
		)

		print(
			"Spawner: ",
			name
		)

		print(
			"Position: ",
			global_position
		)

		print(
			"Bronze Scene: ",
			bronze_chest_scene
		)

		print(
			"Silber Scene: ",
			silver_chest_scene
		)

		print(
			"Gold Scene: ",
			gold_chest_scene
		)

	await get_tree().process_frame

	_spawn_chest()


func _spawn_chest() -> void:
	if force_bronze_for_test:
		if debug_messages:
			print(
				"ChestSpawner TEST: Bronze wird erzwungen."
			)

		_create_chest(
			bronze_chest_scene
		)

		return

	var spawn_roll: float = randf_range(
		0.0,
		100.0
	)

	if debug_messages:
		print(
			"Spawn Roll: ",
			spawn_roll,
			" / ",
			spawn_chance
		)

	if spawn_roll > spawn_chance:
		if debug_messages:
			print(
				"ChestSpawner: Keine Kiste."
			)

		return

	var chosen_scene: PackedScene = _pick_chest_scene()

	if chosen_scene == null:
		push_error(
			"ChestSpawner: chosen_scene ist NULL."
		)
		return

	_create_chest(
		chosen_scene
	)


func _create_chest(
	chest_scene: PackedScene
) -> void:
	if chest_scene == null:
		push_error(
			"ChestSpawner: Chest Scene ist NULL."
		)
		return

	var chest: Node = chest_scene.instantiate()

	if chest == null:
		push_error(
			"ChestSpawner: instantiate() fehlgeschlagen."
		)
		return

	var parent_node: Node = get_parent()

	if parent_node == null:
		push_error(
			"ChestSpawner: Kein Parent gefunden."
		)

		chest.queue_free()
		return

	parent_node.add_child(
		chest
	)

	if chest is Node2D:
		(chest as Node2D).global_position = (
			global_position
		)

	if debug_messages:
		print(
			"=== CHEST ERFOLGREICH GESPAWNT ==="
		)

		print(
			"Chest: ",
			chest.name
		)

		print(
			"Position: ",
			(chest as Node2D).global_position
			if chest is Node2D
			else "kein Node2D"
		)

		print(
			"Parent: ",
			parent_node.name
		)


func _pick_chest_scene() -> PackedScene:
	var bronze: float = max(
		bronze_weight,
		0.0
	)

	var silver: float = max(
		silver_weight,
		0.0
	)

	var gold: float = max(
		gold_weight,
		0.0
	)

	var total: float = (
		bronze
		+ silver
		+ gold
	)

	if total <= 0.0:
		push_error(
			"ChestSpawner: Alle Weights sind 0."
		)

		return null

	var roll: float = randf_range(
		0.0,
		total
	)

	if debug_messages:
		print(
			"Chest Roll: ",
			roll,
			" / ",
			total
		)

	if roll < bronze:
		if debug_messages:
			print(
				"Auswahl: BRONZE"
			)

		return bronze_chest_scene

	roll -= bronze

	if roll < silver:
		if debug_messages:
			print(
				"Auswahl: SILBER"
			)

		return silver_chest_scene

	if debug_messages:
		print(
			"Auswahl: GOLD"
		)

	return gold_chest_scene
