extends Node2D

# Nutzer-Wunsch: Läuft der Spieler über die Schwebe-Blöcke, rieseln an der
# Unterseite einzelne winzige Partikel herab und lösen sich auf (bleiben nicht
# am Boden liegen). Sehr subtil.
#
# Erkennt die Schwebe-Blöcke über die Tile-Ebene: Tiles aus der Quelle
# "Blöcke.png" (platform_source_id) im oberen Bereich des Atlas
# (Zeilen bis platform_max_atlas_row), der Boden liegt weiter unten im Atlas.

@export_group("Erkennung")
@export var tile_layer: TileMapLayer
@export var player_group: StringName = &"player"
## Quelle der Plattform-Tiles im TileSet (Blöcke.png).
@export var platform_source_id: int = 0
## Atlas-Zeilen 0 bis zu diesem Wert sind Schwebe-Blöcke (darunter: Boden).
@export var platform_max_atlas_row: int = 6

@export_group("Partikel")
## Pause zwischen zwei Krümeln, solange der Spieler läuft (Sekunden).
@export var interval: float = 0.14
## Krümel pro Mal (zufällig 1 bis max).
@export var count_max: int = 2
## Wie lange ein Krümel lebt, bevor er ganz verschwunden ist (Sekunden).
@export var lifetime: float = 0.9
@export var fall_speed_min: float = 12.0
@export var fall_speed_max: float = 28.0
@export var gravity: float = 40.0
## Farbe der Krümel (dunkles Blaugrau wie die Blöcke). Über 1 = heller.
@export var color: Color = Color(1.5, 1.9, 2.1, 0.85)
## Nur beim Laufen (nicht im Stehen).
@export var only_when_moving: bool = true

## Größe eines Krümels in Pixeln.
@export var size: float = 1.0

# Eigene kleine Partikel-Liste (CPUParticles2D kann nicht gezielt an einer
# Stelle einzelne Partikel ausstoßen).
var _crumbs: Array[Dictionary] = []
var _timer: float = 0.0


func _process(delta: float) -> void:
	if _crumbs.is_empty():
		return
	var alive: Array[Dictionary] = []
	for c in _crumbs:
		c["age"] += delta
		if c["age"] >= lifetime:
			continue
		c["vel"].y += gravity * delta
		c["pos"] += c["vel"] * delta
		alive.append(c)
	_crumbs = alive
	queue_redraw()


func _draw() -> void:
	for c in _crumbs:
		var col: Color = color
		# Weich ausblenden statt am Boden liegen zu bleiben.
		col.a *= 1.0 - clampf(c["age"] / maxf(lifetime, 0.01), 0.0, 1.0)
		draw_rect(Rect2(c["pos"] - Vector2(size, size) * 0.5, Vector2(size, size)), col)


func _physics_process(delta: float) -> void:
	if tile_layer == null:
		return
	var player: CharacterBody2D = get_tree().get_first_node_in_group(player_group) as CharacterBody2D
	if player == null or not player.is_on_floor():
		return
	if only_when_moving and absf(player.velocity.x) < 5.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval

	# Tile direkt unter den Füßen.
	var feet: Vector2 = player.global_position + Vector2(0.0, 2.0)
	var cell: Vector2i = tile_layer.local_to_map(tile_layer.to_local(feet))
	if not _is_platform(cell):
		return
	# Nach unten bis zur Unterkante der Plattform (inkl. Lianen).
	var bottom: Vector2i = cell
	while _is_platform(bottom + Vector2i(0, 1)):
		bottom += Vector2i(0, 1)
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	var bottom_y: float = tile_layer.to_global(tile_layer.map_to_local(bottom)).y + tile_size.y * 0.5 - 3.0

	for i in randi_range(1, maxi(count_max, 1)):
		_crumbs.append({
			"pos": to_local(Vector2(player.global_position.x + randf_range(-5.0, 5.0), bottom_y - randf_range(0.0, 6.0))),
			"vel": Vector2(randf_range(-3.0, 3.0), randf_range(fall_speed_min, fall_speed_max)),
			"age": 0.0,
		})


func _is_platform(cell: Vector2i) -> bool:
	if tile_layer.get_cell_source_id(cell) != platform_source_id:
		return false
	return tile_layer.get_cell_atlas_coords(cell).y <= platform_max_atlas_row
