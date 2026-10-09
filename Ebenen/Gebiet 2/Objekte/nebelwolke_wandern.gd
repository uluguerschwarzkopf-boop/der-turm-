extends Control

# Nutzer-Wunsch: Eine dichte Nebelwolke zieht auf der Spieler-Ebene schneller
# als der restliche Nebel von rechts nach links durch den Raum und verdeckt
# den Spieler dabei einmal kurz. Danach kommt sie nach einer Pause wieder.
# Die Wolke selbst ist ein ColorRect mit nebel_blur.gdshader.

@export_group("Weg")
## Startpunkt rechts und Endpunkt links (Welt-x der linken Kante der Wolke).
@export var start_x: float = 1900.0
@export var end_x: float = -500.0
## Geschwindigkeit in Pixeln pro Sekunde.
@export var speed: float = 45.0
## Pause zwischen zwei Durchgaengen (zufaellig zwischen min und max, Sekunden).
@export var pause_min: float = 3.0
@export var pause_max: float = 8.0

var _wait: float = 0.0


func _ready() -> void:
	position.x = start_x


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	position.x -= speed * delta
	if position.x < end_x:
		position.x = start_x
		_wait = randf_range(pause_min, pause_max)
