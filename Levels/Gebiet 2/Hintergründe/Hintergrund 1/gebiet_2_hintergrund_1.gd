extends Node2D

# Nutzer-Wunsch: Parallax2D-Ebenen berechnen ihre eigene Position jeden
# Frame neu, abhängig von der Kamera-Position im Level und ihrem eigenen
# scroll_scale - dabei wird ignoriert, wenn dieser Container-Knoten hier
# ("Gebiet 2 hintergrund 1") im Level verschoben wurde, um den Hintergrund
# an eine bestimmte Stelle im Raum zu setzen. Ergebnis: jede Ebene landet
# an einer anderen, falschen Stelle (je nachdem welchen scroll_scale sie
# hat), statt dort wo der Hintergrund-Knoten im Editor platziert wurde.
#
# Fix Teil 1 (horizontal): beim Start die eigene X-Position auslesen, sie
# in den scroll_offset.x jeder einzelnen Parallax2D-Ebene mit reinrechnen
# (das ist der Wert, den Parallax2D bei seiner automatischen
# Kamera-Berechnung tatsächlich mit einbezieht).
#
# Fix Teil 2 (Höhe/vertikal): Nutzer-Wunsch war, dass alle Ebenen immer
# auf derselben Höhe bleiben, egal wie sich die Kamera vertikal bewegt
# (springen, fallen, usw.). Ein reines scroll_scale.y = 0 hat dazu
# geführt, dass Parallax2D die Ebenen gar nicht mehr sichtbar berechnet
# hat. Deswegen wird die Höhe hier stattdessen jeden Frame hart
# erzwungen: _process() läuft garantiert NACH Parallax2D's eigener
# interner Positions-Berechnung (Godot ruft NOTIFICATION_INTERNAL_PROCESS
# vor NOTIFICATION_PROCESS auf), wir überschreiben also die von Parallax2D
# gerade berechnete Y-Position jeden Frame mit der Höhe, an der der
# Hintergrund-Knoten im Editor platziert wurde - unabhängig davon, was
# Parallax2D intern berechnet.
var _locked_height: float = 0.0

func _ready() -> void:
	var placement_offset: Vector2 = position
	_locked_height = placement_offset.y
	if placement_offset.x != 0.0:
		for child in get_children():
			if child is Parallax2D:
				child.scroll_offset.x += placement_offset.x
	position = Vector2.ZERO

func _process(_delta: float) -> void:
	for child in get_children():
		if child is Parallax2D:
			child.global_position.y = _locked_height
