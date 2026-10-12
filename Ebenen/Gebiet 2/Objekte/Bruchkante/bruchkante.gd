@tool
extends Node2D

# Nutzer-Wunsch: Eine Plattform-Kante bricht ein, wenn der Spieler darüber läuft.
#
# Benutzung: Diesen Node auf die Ecke einer Plattform setzen. Der orange
# Rahmen im Editor zeigt den Bereich, der wegbricht (break_size). Tritt der
# Spieler darauf, rieselt kurz Staub (warn_time), dann werden die Tiles in
# diesem Bereich aus der TileMap entfernt (Kollision ist damit weg) und fallen
# als Bruchstücke herunter. Beim Neuladen des Raums ist alles wieder ganz.
#
# @tool nur, damit der Rahmen im Editor gezeichnet wird.

@export_group("Bruchbereich")
## Die Tile-Ebene, aus der Tiles herausbrechen (die Spieler-Ebene).
@export var tile_layer: TileMapLayer
## Größe des Bereichs, der wegbricht (um diesen Node zentriert, in Pixeln).
@export var break_size: Vector2 = Vector2(32, 32):
	set(v):
		break_size = v
		queue_redraw()
## So viel höher als der Bruchbereich reicht der Auslöser (dort stehen die Füße).
@export var trigger_extra_height: float = 10.0
@export var player_group: StringName = &"player"

@export_group("Ablauf")
## Vorwarnzeit: so lange rieselt Staub, bevor es bricht (Sekunden).
@export var warn_time: float = 0.45
## Schwerkraft der Bruchstücke.
@export var piece_gravity: float = 520.0
## Seitlicher Schwung und Drehung der Bruchstücke.
@export var piece_spread: float = 22.0
@export var piece_spin: float = 4.0
## Nach so vielen Sekunden werden die Bruchstücke entfernt.
@export var piece_lifetime: float = 2.5

@export_group("Staub")
## Werte dürfen über 1 liegen, falls "Darkness" den Staub zu stark abdunkelt.
@export var dust_color: Color = Color(0.7, 0.76, 0.88, 0.6)
@export var dust_amount: int = 14

var _triggered: bool = false
var _pieces: Array[Dictionary] = []


func _draw() -> void:
	if Engine.is_editor_hint():
		var r := Rect2(-break_size * 0.5, break_size)
		draw_rect(r, Color(1.0, 0.55, 0.1, 0.9), false, 1.0)
		var t := Rect2(r.position - Vector2(0, trigger_extra_height), Vector2(r.size.x, trigger_extra_height))
		draw_rect(t, Color(1.0, 0.9, 0.2, 0.6), false, 1.0)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _triggered:
		return
	var player: Node2D = get_tree().get_first_node_in_group(player_group) as Node2D
	if player == null:
		return
	# Füße des Spielers im Bereich direkt über/auf dem Bruchstück?
	var local: Vector2 = to_local(player.global_position)
	var half: Vector2 = break_size * 0.5
	if absf(local.x) <= half.x and local.y >= -half.y - trigger_extra_height and local.y <= -half.y + 6.0:
		_triggered = true
		_start_break()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _pieces.is_empty():
		return
	for p in _pieces:
		var spr: Sprite2D = p["sprite"]
		if not is_instance_valid(spr):
			continue
		p["vel"] += Vector2(0, piece_gravity * delta)
		spr.global_position += p["vel"] * delta
		spr.rotation += p["spin"] * delta
		p["age"] += delta
		# Am Ende ausblenden statt hart verschwinden.
		spr.modulate.a = clampf((piece_lifetime - p["age"]) / 0.4, 0.0, 1.0)
		if p["age"] >= piece_lifetime:
			spr.queue_free()
	var rest: Array[Dictionary] = []
	for p in _pieces:
		if is_instance_valid(p["sprite"]) and p["age"] < piece_lifetime:
			rest.append(p)
	_pieces = rest


func _start_break() -> void:
	# Vorwarnung: Staub rieselt unter der Kante heraus.
	var warn := _make_dust(maxi(dust_amount / 2, 1), warn_time + 0.3, false)
	warn.position = Vector2(0, break_size.y * 0.5)
	warn.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	warn.emission_rect_extents = Vector2(break_size.x * 0.5, 1.0)
	warn.direction = Vector2(0, 1)
	warn.spread = 15.0
	warn.initial_velocity_min = 8.0
	warn.initial_velocity_max = 20.0
	warn.gravity = Vector2(0, 60)
	warn.restart()
	await get_tree().create_timer(maxf(warn_time, 0.01)).timeout
	if not is_inside_tree():
		return
	_break()


func _break() -> void:
	if tile_layer == null or not is_instance_valid(tile_layer):
		push_warning("Bruchkante: keine Tile-Ebene gesetzt (tile_layer).")
		return
	var rect := Rect2(global_position - break_size * 0.5, break_size)
	for cell in tile_layer.get_used_cells():
		var center: Vector2 = tile_layer.to_global(tile_layer.map_to_local(cell))
		if not rect.has_point(center):
			continue
		_spawn_piece(cell, center)
		tile_layer.erase_cell(cell)

	var burst := _make_dust(dust_amount, 0.9, true)
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = break_size * 0.5
	burst.direction = Vector2(0, 1)
	burst.spread = 70.0
	burst.initial_velocity_min = 10.0
	burst.initial_velocity_max = 40.0
	burst.gravity = Vector2(0, 90)
	burst.restart()


# Bruchstück = Kopie der Tile-Grafik, die frei herunterfällt.
func _spawn_piece(cell: Vector2i, center: Vector2) -> void:
	var source_id: int = tile_layer.get_cell_source_id(cell)
	var atlas: TileSetAtlasSource = tile_layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if atlas == null:
		return
	var coords: Vector2i = tile_layer.get_cell_atlas_coords(cell)
	var spr := Sprite2D.new()
	spr.texture = atlas.texture
	spr.region_enabled = true
	spr.region_rect = atlas.get_tile_texture_region(coords)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(spr)
	spr.global_position = center
	var side: float = signf(center.x - global_position.x)
	if side == 0.0:
		side = 1.0 if randf() > 0.5 else -1.0
	_pieces.append({
		"sprite": spr,
		"vel": Vector2(side * randf_range(piece_spread * 0.3, piece_spread), randf_range(-30.0, 0.0)),
		"spin": side * randf_range(piece_spin * 0.4, piece_spin),
		"age": 0.0,
	})


func _make_dust(amount: int, life: float, one_shot_burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.9 if one_shot_burst else 0.0
	p.emitting = false
	p.color = dust_color
	# Weiche runde Staubpunkte statt eckiger Pixel.
	p.texture = _get_dust_texture()
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	add_child(p)
	return p


var _dust_texture: Texture2D = null


func _get_dust_texture() -> Texture2D:
	if _dust_texture == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 32
		tex.height = 32
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_dust_texture = tex
	return _dust_texture
