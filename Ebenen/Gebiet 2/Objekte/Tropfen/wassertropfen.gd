extends Node2D

# Nutzer-Wunsch: Wassertropfen fallen von der Decke/Plattformen und spritzen
# beim Aufprall.
#
# Eigener kleiner Ablauf statt Partikel-Kollision: Der Boden wird per Raycast
# gesucht. Dadurch landet der Tropfen immer genau auf dem Tile darunter, egal
# wo die Instanz steht. Benutzung: Instanz an die Decke oder an die Unterkante
# einer Plattform ziehen, fertig.
#
# Ablauf: warten -> Tropfen bildet sich (wird sichtbar) -> faellt -> Spritzer.

@export_group("Zeitlicher Ablauf")
## Pause zwischen zwei Tropfen, zufaellig zwischen min und max (Sekunden).
@export var interval_min: float = 2.0
@export var interval_max: float = 5.0
## So lange haengt der Tropfen sichtbar, bevor er faellt (Sekunden).
@export var hang_time: float = 0.6

@export_group("Fallen")
## Fallbeschleunigung in Pixel pro Sekunde zum Quadrat.
@export var gravity: float = 420.0
## Maximale Fallhoehe in Pixeln, falls kein Boden gefunden wird.
@export var max_fall: float = 400.0
## Physik-Ebenen, auf denen der Tropfen aufschlaegt (1 = Tile-Ebene).
@export_flags_2d_physics var floor_mask: int = 1

@export_group("Aussehen")
@export var drop_color: Color = Color(0.55, 0.75, 0.95, 0.85)
## Laenge des Tropfens in Pixeln: haengend bzw. bei voller Fallgeschwindigkeit.
@export var drop_length_min: float = 1.0
@export var drop_length_max: float = 3.0

enum Phase { WAIT, HANG, FALL }

var _phase: Phase = Phase.WAIT
var _timer: float = 0.0
var _y: float = 0.0
var _vel: float = 0.0
var _floor_y: float = 0.0

@onready var splash: CPUParticles2D = $Spritzer


func _ready() -> void:
	# Versetzt starten, damit mehrere Instanzen nicht gleichzeitig tropfen.
	_timer = randf_range(0.0, interval_max)
	splash.emitting = false
	splash.color = drop_color


func _physics_process(delta: float) -> void:
	match _phase:
		Phase.WAIT:
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.HANG
				_timer = hang_time
				_y = 0.0
				_vel = 0.0
		Phase.HANG:
			_timer -= delta
			if _timer <= 0.0:
				# Boden erst kurz vor dem Fallen suchen (Raycast nur im Physik-Schritt).
				_floor_y = _find_floor()
				_phase = Phase.FALL
		Phase.FALL:
			_vel += gravity * delta
			_y += _vel * delta
			if _y >= _floor_y:
				_splash_at(_floor_y)
				_phase = Phase.WAIT
				_timer = randf_range(interval_min, interval_max)
	queue_redraw()


func _find_floor() -> float:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	# 1 Pixel tiefer starten: Sitzt die Instanz genau auf der Unterkante einer
	# Plattform, wuerde der Strahl sonst sofort die Plattform selbst treffen.
	var from: Vector2 = global_position + Vector2(0.0, 1.0)
	var to: Vector2 = global_position + Vector2(0.0, max_fall)
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, floor_mask)
	var exclude: Array[RID] = []
	# Spieler und Gegner ignorieren, sonst "landet" der Tropfen auf einem Kopf,
	# der im naechsten Moment schon weg ist.
	for i in 4:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return max_fall
		if hit["collider"] is CharacterBody2D:
			exclude.append(hit["rid"])
			continue
		return to_local(hit["position"]).y
	return max_fall


func _splash_at(y: float) -> void:
	splash.position = Vector2(0.0, y)
	splash.restart()


func _draw() -> void:
	match _phase:
		Phase.HANG:
			# Tropfen bildet sich: wird langsam sichtbar.
			var c: Color = drop_color
			c.a *= 1.0 - clampf(_timer / maxf(hang_time, 0.01), 0.0, 1.0)
			draw_rect(Rect2(-0.5, 0.0, 1.0, drop_length_min), c)
		Phase.FALL:
			# Je schneller, desto laenger (Bewegungsunschaerfe in Pixel-Form).
			var length: float = lerpf(drop_length_min, drop_length_max, clampf(_vel / 200.0, 0.0, 1.0))
			draw_rect(Rect2(-0.5, _y - length, 1.0, length), drop_color)
