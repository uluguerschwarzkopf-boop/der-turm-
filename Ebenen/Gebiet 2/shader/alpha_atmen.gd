extends CanvasItem

# Nutzer-Wunsch: Der Lichtstrahl am Fenster "atmet" ganz leicht, kaum sichtbar.
# Weiche Sinuswelle auf der Deckkraft (modulate.a), kein Flackern.

@export_group("Atmen")
## Wie stark die Deckkraft schwankt, relativ (0.08 = plus/minus 8 %).
@export_range(0.0, 1.0) var breath_amount: float = 0.08
## Dauer eines Atemzugs in Sekunden.
@export var breath_period: float = 8.0

var _base_alpha: float = 1.0
var _t: float = 0.0


func _ready() -> void:
	_base_alpha = modulate.a


func _process(delta: float) -> void:
	_t += delta
	modulate.a = _base_alpha * (1.0 + breath_amount * sin(_t * TAU / maxf(breath_period, 0.1)))
