extends AnimatedSprite2D

# ============================================================
# Leichtes Idle-Schwanken für Vordergrund-Ranken
# ============================================================
# Der eigentliche Parallax-Effekt kommt jetzt vom Parallax2D-Node,
# der der Parent dieser Ranke ist (siehe Root-Node "Ranken VOR_"
# dieser Szene, scroll_scale im Inspector einstellbar). Das ist
# Godots eingebautes, nicht-deprecated Parallax-System (Ersatz für
# das alte ParallaxBackground/ParallaxLayer) - es berechnet die
# Kamerabewegung direkt im Rendering, synchron zum tatsächlich
# angezeigten Bild, und ruckelt deshalb nicht wie unser vorheriger
# manueller Kamera-Tracking-Ansatz.
#
# Dieses Script macht deshalb nur noch die optionale, sehr leichte
# Schwank-Bewegung obendrauf - unabhängig vom Parallax und ohne
# jede Kamera-Logik. Läuft auf dem AnimatedSprite2D-Kind, NICHT auf
# dem Parallax2D-Parent, damit es sich nicht mit dessen eigener
# interner Positions-Berechnung beißt.

@export_group("Idle-Schwanken")
## Zusätzliche, sehr leichte Schwank-Bewegung, unabhängig vom Parallax.
@export var enable_idle_sway: bool = false
## Wie viele Pixel die Ranke seitlich schwankt.
@export var idle_sway_amplitude_px: float = 2.0
## Geschwindigkeit der Schwank-Bewegung.
@export var idle_sway_speed: float = 1.0
## Zusätzliche leichte Rotation in Grad, die mitschwankt (0 = aus).
@export var idle_sway_rotation_degrees: float = 0.0

var _start_local_position: Vector2 = Vector2.ZERO
var _start_rotation: float = 0.0

# Zufälliger Start-Zeitversatz, damit mehrere Ranken-Instanzen nicht
# perfekt synchron schwanken.
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
