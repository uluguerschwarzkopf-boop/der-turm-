extends Node2D


# ============================================================
# RANKE (BEGEHBARE HÄNGE-RANKE)
# ============================================================

# Ranke aus dem Tileset "tile set gebiet 1.png" als eigene Szene,
# statt als Tile im TileMap - damit sie sich bewegen kann, wenn
# der Spieler hindurchläuft. Die Original-Tiles hatten die Ranke
# fest auf die Wand gemalt (kein Alpha), deshalb benutzen wir hier
# drei freigestellte Bilder (nur die Blätter, Wand ist transparent):
# "Ranke Oben.png" (Ansatz an der Decke), "Ranke Mitte.png"
# (wiederholbares Segment) und "Ranke Unten.png" (Ende/Quaste) -
# die Wand dahinter kommt weiterhin ganz normal vom TileMap (dort
# steht jetzt wieder ein passendes Wand-Tile statt der Ranke).
# Höhe in Tiles über tile_height.
#
# Jedes Tile ist eine eigene Node2D-Kette (Segment 0 = oben, hängt
# am Deckenansatz, jedes weitere Segment ist Kind des vorherigen).
#
# Der Stiel (Segment 0, der Ansatz an der Wand) bewegt sich NIE -
# nur alles darunter wackelt. Damit die Bewegung trotzdem wie eine
# echte Welle aussieht (nicht wie eine starre Peitsche, die nur an
# einem Ende hängt), gibt es zusätzlich ein paar unsichtbare
# "Phantom-Punkte" oberhalb der Ranke (sway_phantom_points_above) -
# die existieren nur in der Wellen-Berechnung (keine echten Knoten,
# es wird nichts gezeichnet), geben der Welle aber schon "Schwung",
# bevor sie das erste sichtbare, bewegliche Segment erreicht.
#
# Benachbarte Segmente schwingen außerdem gegenphasig zueinander
# (sway_wave_phase_degrees, standardmäßig 180°) - während ein Punkt
# nach rechts ausschlägt, geht der nächste nach links, wie bei einer
# echten Welle/einem Seil, statt dass alle Segmente gleichzeitig in
# dieselbe Richtung kippen.
#
# Jeder Ausschlag wird schwächer, bis alles wieder in Ruhe ist. Geht
# man während des Schwingens nochmal hindurch, wird die Animation
# zurückgesetzt und beginnt von vorne.
#
# Die Ausschlag-Stärke wird automatisch an die Ranken-Höhe
# angepasst (sway_reference_height) - eine lange Ranke braucht
# einen kleineren Winkel, eine kurze einen größeren, damit die
# Bewegung an der Spitze überall ähnlich stark aussieht.


@export_range(1, 12, 1)
var tile_height: int = 2:
	set(value):
		tile_height = value
		if is_inside_tree():
			_build_visual()
			_update_collision_shape()

@export_group("Schwingen")

@export_range(0.5, 45.0, 0.5)
var sway_angle_degrees: float = 4.0

@export var sway_duration: float = 1.1

@export_range(1, 12, 1)
var sway_reference_height: int = 3

@export_range(2, 12, 1)
var sway_swing_count: int = 6

@export_range(0.0, 0.3, 0.005)
var sway_segment_delay: float = 0.05

@export_range(0, 4, 1)
var sway_phantom_points_above: int = 2

@export_range(0.0, 180.0, 5.0)
var sway_wave_phase_degrees: float = 180.0

@export var player_group: StringName = &"player"


const TILE_SIZE: int = 16
const _CAP_TEXTURE_PATH: String = "res://Objects/Ranken/Ranke Oben.png"
const _MID_TEXTURE_PATH: String = "res://Objects/Ranken/Ranke Mitte.png"
const _END_TEXTURE_PATH: String = "res://Objects/Ranken/Ranke Unten.png"


@onready var visual: Node2D = $Visual
@onready var trigger_area: Area2D = $TriggerArea
@onready var collision_shape: CollisionShape2D = $TriggerArea/CollisionShape2D

var _cap_texture: Texture2D = null
var _mid_texture: Texture2D = null
var _end_texture: Texture2D = null

var _segments: Array[Node2D] = []

var _is_swaying: bool = false
var _sway_elapsed: float = 0.0
var _sway_direction: float = 1.0
var _sway_omega: float = 0.0
var _sway_active_duration: float = 0.0


# ============================================================
# START
# ============================================================

func _ready() -> void:
	_cap_texture = load(_CAP_TEXTURE_PATH)
	_mid_texture = load(_MID_TEXTURE_PATH)
	_end_texture = load(_END_TEXTURE_PATH)

	_build_visual()
	_update_collision_shape()

	set_process(false)

	if (
		trigger_area != null
		and not trigger_area.body_entered.is_connected(
			_on_body_entered
		)
	):
		trigger_area.body_entered.connect(
			_on_body_entered
		)


# ============================================================
# OPTIK AUFBAUEN (KETTE AUS SEGMENTEN)
# ============================================================

func _build_visual() -> void:
	if visual == null:
		return

	for child in visual.get_children():
		child.queue_free()

	_segments.clear()

	var height: int = max(tile_height, 1)
	var parent: Node2D = visual

	for i in range(height):
		var segment := Node2D.new()
		segment.position = Vector2(0, 0 if i == 0 else TILE_SIZE)

		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = _get_tile_texture(i, height)

		segment.add_child(sprite)
		parent.add_child(segment)

		_segments.append(segment)
		parent = segment


func _get_tile_texture(
	index: int,
	height: int
) -> Texture2D:
	if index == 0:
		return _cap_texture

	if index == height - 1:
		return _end_texture

	return _mid_texture


func _update_collision_shape() -> void:
	if collision_shape == null:
		return

	var height: int = max(tile_height, 1)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(
		TILE_SIZE,
		height * TILE_SIZE
	)

	collision_shape.shape = shape
	collision_shape.position = Vector2(
		TILE_SIZE / 2.0,
		height * TILE_SIZE / 2.0
	)


# ============================================================
# SPIELER ERKENNEN
# ============================================================

func _on_body_entered(
	body: Node2D
) -> void:
	if body == null:
		return

	if not body.is_in_group(player_group):
		return

	var direction: float = 1.0

	if "velocity" in body:
		var player_velocity: Vector2 = body.velocity

		if absf(player_velocity.x) > 0.1:
			direction = signf(player_velocity.x)

	_start_sway(direction)


# ============================================================
# SCHWING-ANIMATION (WELLE, STIEL BLEIBT FEST)
# ============================================================

# Winkel-Amplitude je nach Ranken-Höhe skalieren, damit die
# Bewegung an der Spitze (Winkel * Länge) bei jeder Ranken-Länge
# ähnlich stark aussieht - lange Ranken bekommen einen kleineren
# Winkel, kurze einen größeren.
func _get_effective_peak_angle() -> float:
	var height: int = max(tile_height, 1)

	var scale: float = float(sway_reference_height) / float(height)
	scale = clampf(scale, 0.5, 3.0)

	return deg_to_rad(sway_angle_degrees) * scale


func _start_sway(
	direction: float
) -> void:
	if _segments.is_empty():
		return

	_sway_direction = direction
	_sway_elapsed = 0.0

	var swing_count: int = max(sway_swing_count, 2)
	_sway_omega = float(swing_count) * PI / sway_duration

	# Segment 0 (der Stiel) macht nie mit, deshalb muss die Kette
	# nur bis zum letzten animierten Segment fertig ausklingen -
	# plus die unsichtbaren Phantom-Punkte, die vor dem ersten
	# beweglichen Segment "dran" wären.
	var animated_segment_count: int = max(_segments.size() - 1, 0)
	var max_phase_index: float = float(
		max(animated_segment_count - 1, 0) + sway_phantom_points_above
	)

	_sway_active_duration = (
		sway_duration
		+ max_phase_index * sway_segment_delay
	)

	_is_swaying = true
	set_process(true)


func _process(delta: float) -> void:
	if not _is_swaying:
		return

	_sway_elapsed += delta

	if _sway_elapsed >= _sway_active_duration:
		_stop_sway()
		return

	var segment_count: int = _segments.size()

	# Der Stiel (Segment 0, Ansatz an der Wand) bleibt immer fest.
	if segment_count > 0:
		_segments[0].rotation = 0.0

	if segment_count <= 1:
		return

	var peak_angle: float = (
		_get_effective_peak_angle()
		* _sway_direction
	)

	var animated_count: int = segment_count - 1
	var per_segment_angle: float = peak_angle / float(animated_count)
	var wave_phase: float = deg_to_rad(sway_wave_phase_degrees)

	for i in range(1, segment_count):
		var phase_index: float = float(
			(i - 1) + sway_phantom_points_above
		)
		var local_time: float = (
			_sway_elapsed
			- phase_index * sway_segment_delay
		)

		var segment: Node2D = _segments[i]

		if local_time <= 0.0:
			segment.rotation = 0.0
			continue

		var envelope: float = clampf(
			1.0 - (local_time / sway_duration),
			0.0,
			1.0
		)
		envelope = envelope * envelope

		segment.rotation = (
			per_segment_angle
			* envelope
			* sin(
				_sway_omega * local_time
				+ float(i) * wave_phase
			)
		)


func _stop_sway() -> void:
	_is_swaying = false
	set_process(false)

	for segment in _segments:
		segment.rotation = 0.0
