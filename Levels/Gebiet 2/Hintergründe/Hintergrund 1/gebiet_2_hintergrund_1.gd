extends Node2D

# Positioniert die Parallax2D-Ebenen selbst.
#
# Grund: Parallax2D berechnet seine Position relativ zum Welt-Nullpunkt.
# Wo dieser Container im Raum platziert wurde und wo die Kamera steht,
# ignoriert es dabei - deshalb sass der Hintergrund im Spiel verschoben,
# obwohl er im Editor richtig lag.
#
# Hier wird stattdessen jeden Frame hart gesetzt:
#   Position = Editor-Position + Kameraversatz * (1 - scroll_scale)
# Der Kameraversatz wird von einem Ankerpunkt aus gemessen (Mitte der
# Kameragrenzen). Genau dort stimmt das Bild exakt mit dem Editor ueberein.
#
# _process() laeuft nach der internen Berechnung von Parallax2D, das
# Ueberschreiben greift also zuverlaessig.
#
# scroll_scale bleibt der Regler fuer die Tiefe:
#   1.0 = bewegt sich mit der Welt (kein Parallax)
#   0.9 = bleibt leicht zurueck (wirkt weiter weg)

## Alle Ebenen bleiben auf konstanter Hoehe, egal wie die Kamera springt.
@export var lock_vertical: bool = true

var _cam: Camera2D = null
var _anchor: Vector2 = Vector2.ZERO
var _layers: Array[Parallax2D] = []
var _base: Array[Vector2] = []
var _armed: bool = false

func _enter_tree() -> void:
	# Editor-Platzierung merken, bevor Parallax2D etwas veraendert.
	_layers.clear()
	_base.clear()
	for child in get_children():
		if child is Parallax2D:
			_layers.append(child)
			# scroll_offset mitnehmen: damit verschiebt man eine Parallax2D-Ebene
			# im Editor. Da dieses Skript die Position selbst setzt, wuerde
			# scroll_offset sonst im Spiel ignoriert.
			_base.append(position + child.position + child.scroll_offset)

func _ready() -> void:
	# Container selbst auf 0, die Platzierung steckt jetzt in _base.
	position = Vector2.ZERO
	# Eine Frame warten, damit die Kamera ihre Limits gesetzt hat.
	await get_tree().process_frame
	_grab_camera()
	_armed = true
	_apply()

func _grab_camera() -> void:
	_cam = get_viewport().get_camera_2d()
	if _cam == null:
		return
	var ax: float = _cam.get_screen_center_position().x
	var ay: float = _cam.get_screen_center_position().y
	if _cam.limit_right > _cam.limit_left and absi(_cam.limit_right) < 10000000:
		ax = (_cam.limit_left + _cam.limit_right) * 0.5
	if _cam.limit_bottom > _cam.limit_top and absi(_cam.limit_bottom) < 10000000:
		ay = (_cam.limit_top + _cam.limit_bottom) * 0.5
	_anchor = Vector2(ax, ay)

func _process(_delta: float) -> void:
	if _armed:
		_apply()

func _apply() -> void:
	if _cam == null or not is_instance_valid(_cam):
		_grab_camera()
		if _cam == null:
			return
	var d: Vector2 = _cam.get_screen_center_position() - _anchor
	for i in _layers.size():
		var layer: Parallax2D = _layers[i]
		if not is_instance_valid(layer):
			continue
		var s: Vector2 = layer.scroll_scale
		var base: Vector2 = _base[i]
		var x: float = base.x + d.x * (1.0 - s.x)
		var y: float = base.y
		if not lock_vertical:
			y = base.y + d.y * (1.0 - s.y)
		layer.global_position = Vector2(x, y)
