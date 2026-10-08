@tool
extends Node2D

# Nutzer-Wunsch: Pro Fenster ein ovaler Schein direkt auf dem Fenster.
# Nutzer-Korrektur: Die Lichtkegel unter den Fenstern sind wieder raus; nur
# das freie Fenster bekommt einen eigenen geraden Lichtstrahl (in raum_1).
#
# Benutzung: Instanz von fensterlicht.tscn auf ein Fenster setzen (Position =
# Mitte des Fensters). Die Werte unten gelten pro Instanz; die Standardwerte
# aendert man in fensterlicht.tscn, dann aendern sich alle Fenster mit.
#
# @tool, damit Aenderungen sofort im Editor sichtbar sind.

@export_group("Fenster-Schein (oval)")
## Helligkeit des Scheins auf dem Fenster.
@export var glow_energy: float = 0.5:
	set(v):
		glow_energy = v
		_apply()
## Groesse des Scheins (1 = etwa fensterbreit).
@export var glow_size: float = 1.3:
	set(v):
		glow_size = v
		_apply()
@export var glow_color: Color = Color(0.5, 0.75, 1.0):
	set(v):
		glow_color = v
		_apply()

func _ready() -> void:
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var glow: PointLight2D = get_node_or_null("Schein") as PointLight2D
	if glow != null:
		glow.energy = glow_energy
		glow.texture_scale = glow_size
		glow.color = glow_color
