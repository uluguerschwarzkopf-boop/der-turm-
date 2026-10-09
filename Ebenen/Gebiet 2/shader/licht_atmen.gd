extends PointLight2D

# Nutzer-Wunsch: Fensterlicht atmet ganz langsam, ohne Flackern.
# Eine weiche Sinuswelle auf der Energie, kein Zufallsrauschen,
# damit nichts zuckt (Stilregel: Lichtstrahlen statisch, nur leichtes Atmen).
# Im Editor laeuft das Skript nicht, dort bleibt die eingestellte Energie.

@export_group("Atmen")
## Energie in der Mitte der Atmung. -1 = beim Start den Energie-Wert aus dem Inspektor nehmen.
@export var breath_base_energy: float = -1.0
## Wie stark die Energie schwankt, relativ (0.15 = plus/minus 15 %).
@export_range(0.0, 1.0) var breath_amount: float = 0.15
## Dauer eines Atemzugs in Sekunden.
@export var breath_period: float = 7.0
## Startversatz in Sekunden. Lichter mit gleichem Versatz atmen im Gleichtakt
## (z. B. Fensterstrahl und sein Lichtfleck am Boden).
@export var breath_offset: float = 0.0
## An = jedes Licht startet an einer zufaelligen Stelle, damit mehrere
## Lichtkegel nicht im Gleichtakt atmen.
@export var random_phase: bool = false

var _base: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	_base = energy if breath_base_energy < 0.0 else breath_base_energy
	_t = breath_offset
	if random_phase:
		_t += randf() * breath_period


func _process(delta: float) -> void:
	_t += delta
	var phase: float = _t * TAU / maxf(breath_period, 0.1)
	energy = _base * (1.0 + breath_amount * sin(phase))
