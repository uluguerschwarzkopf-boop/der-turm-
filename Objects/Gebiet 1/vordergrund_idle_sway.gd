extends AnimatedSprite2D

# ============================================================
# Leichtes Idle-Schwanken für Vordergrund-Elemente (allgemein)
# ============================================================
# Gehört zu "vordergrund_parallax_basis.tscn": diese Basis-Szene hat
# als Root bereits einen Parallax2D-Node mit passendem scroll_scale -
# das übernimmt komplett den Parallax-Effekt (Godots eingebautes,
# nicht-deprecated System, Ersatz für ParallaxBackground/ParallaxLayer).
# Dieses Script hier macht NUR noch die optionale, sehr leichte
# Schwank-Bewegung obendrauf und enthält keine Kamera-/Parallax-Logik,
# damit es sich nicht mit dem Parallax2D-Parent beißt.

@export_group("Idle-Schwanken")
## Zusätzliche, sehr leichte Schwank-Bewegung, unabhängig vom Parallax.
@export var enable_idle_sway: bool = false
## Wie viele Pixel das Element seitlich schwankt.
@export var idle_sway_amplitude_px: float = 2.0
## Geschwindigkeit der Schwank-Bewegung.
@export var idle_sway_speed: float = 1.0
## Zusätzliche leichte Rotation in Grad, die mitschwankt (0 = aus).
@export var idle_sway_rotation_degrees: float = 0.0

var _start_local_position: Vector2 = Vector2.ZERO
var _start_rotation: float = 0.0

# Zufälliger Start-Zeitversatz, damit mehrere Instanzen nicht perfekt
# synchron schwanken.
var _idle_time: float = randf() * TAU


func _ready() -> void:
	_start_local_position = position
	_start_rotation = rotation


func _process(delta: float) -> void:
	if not enable_idle_sway:
		return

	_idle_time += delta * idle_sway_speed
	var sway: float = sin(_idle_time)

	position = _start_local_position + Vector2(sway * idle_sway_amplitude_px, 0.0)
	rotation = _start_rotation + deg_to_rad(idle_sway_rotation_degrees) * sway
