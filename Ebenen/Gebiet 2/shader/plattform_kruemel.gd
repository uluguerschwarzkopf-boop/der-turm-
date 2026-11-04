extends Node2D

# Nutzer-Korrektur: Läuft der Spieler über die Schwebe-Blöcke, fällt der Staub
# direkt an seinen Füßen ab (nicht mehr an der Plattform-Unterseite), zergeht
# sehr schnell und fällt nicht mehr durch alles durch: Trifft ein Krümel auf
# Boden, bleibt er kurz liegen und blendet dort aus.
#
# Erkennt die Schwebe-Blöcke über die Tile-Ebene: Tiles aus der Quelle
# platform_source_id im oberen Bereich des Atlas (Zeilen bis
# platform_max_atlas_row), der Boden liegt weiter unten im Atlas.

@export_group("Erkennung")
@export var tile_layer: TileMapLayer
@export var player_group: StringName = &"player"
## Quelle der Plattform-Tiles im TileSet.
@export var platform_source_id: int = 0
## Atlas-Zeilen 0 bis zu diesem Wert sind Schwebe-Blöcke (darunter: Boden).
@export var platform_max_atlas_row: int = 6
## Kollisions-Ebenen, auf denen der Staub liegen bleibt.
@export_flags_2d_physics var landing_mask: int = 1

@export_group("Partikel")
## Pause zwischen zwei Krümeln, solange der Spieler läuft (Sekunden).
@export var interval: float = 0.1
## Krümel pro Mal (zufällig 1 bis max).
@export var count_max: int = 2
## So lange (Sekunden) lebt ein Krümel höchstens in der Luft.
@export var lifetime: float = 0.45
## So schnell blendet ein gelandeter Krümel aus (Sekunden).
@export var landed_fade_time: float = 0.25
## Kleiner Hüpfer beim Abfallen von den Füßen (Pixel/s nach oben).
@export var pop_min: float = 4.0
@export var pop_max: float = 16.0
## Seitliches Wegfliegen, entgegen der Laufrichtung.
@export var kick_min: float = 3.0
@export var kick_max: float = 14.0
@export var gravity: float = 190.0
## Abstand von der Fußmitte, in dem der Staub entsteht (Pixel).
@export var foot_spread: float = 4.0
## Farbe der Krümel (dunkles Blaugrau wie die Blöcke). Über 1 = heller.
@export var color: Color = Color(1.5, 1.9, 2.1, 0.85)
## Nur beim Laufen (nicht im Stehen).
@export var only_when_moving: bool = true
## Größe eines Krümels in Pixeln.
@export var size: float = 1.0

# Eigene kleine Partikel-Liste (CPUParticles2D kann weder gezielt an einer
# Stelle einzelne Partikel ausstoßen noch auf Boden liegen bleiben).
var _crumbs: Array[Dictionary] = []
var _timer: float = 0.0


func _physics_process(delta: float) -> void:
	_update_crumbs(delta)
	_spawn_from_player(delta)


func _update_crumbs(delta: float) -> void:
	if _crumbs.is_empty():
		return

	var alive: Array[Dictionary] = []

	for c: Dictionary in _crumbs:
		c["age"] += delta

		if c["landed"]:
			if c["age"] < landed_fade_time:
				alive.append(c)
			continue

		if c["age"] >= lifetime:
			continue

		c["vel"].y += gravity * delta

		var next: Vector2 = c["pos"] + c["vel"] * delta

		# Nur beim Fallen prüfen: der Hüpfer nach oben startet direkt an der
		# Oberkante und darf daran nicht sofort hängen bleiben.
		if c["vel"].y > 0.0 and _is_solid(next):
			c["landed"] = true
			c["fade_from"] = _crumb_alpha(c)
			c["age"] = 0.0
		else:
			c["pos"] = next

		alive.append(c)

	_crumbs = alive
	queue_redraw()


func _crumb_alpha(c: Dictionary) -> float:
	if c["landed"]:
		return c["fade_from"] * (1.0 - clampf(c["age"] / maxf(landed_fade_time, 0.01), 0.0, 1.0))

	return 1.0 - clampf(c["age"] / maxf(lifetime, 0.01), 0.0, 1.0)


# Boden/Wand/Plattform: nur Tiles und statische Körper. Spieler und Gegner
# zählen nicht, sonst bliebe der Staub an den eigenen Füßen hängen.
func _is_solid(world_pos: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = landing_mask

	for hit: Dictionary in get_world_2d().direct_space_state.intersect_point(query, 8):
		var collider: Object = hit.get("collider")

		if collider is TileMapLayer or collider is StaticBody2D:
			return true

	return false


func _draw() -> void:
	for c: Dictionary in _crumbs:
		var col: Color = color
		col.a *= _crumb_alpha(c)
		draw_rect(Rect2(to_local(c["pos"]) - Vector2(size, size) * 0.5, Vector2(size, size)), col)


func _spawn_from_player(delta: float) -> void:
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

	var away: float = -signf(player.velocity.x)

	for i in randi_range(1, maxi(count_max, 1)):
		_crumbs.append({
			"pos": player.global_position + Vector2(randf_range(-foot_spread, foot_spread), -1.0),
			"vel": Vector2(away * randf_range(kick_min, kick_max), -randf_range(pop_min, pop_max)),
			"age": 0.0,
			"landed": false,
			"fade_from": 1.0,
		})


func _is_platform(cell: Vector2i) -> bool:
	if tile_layer.get_cell_source_id(cell) != platform_source_id:
		return false
	return tile_layer.get_cell_atlas_coords(cell).y <= platform_max_atlas_row
