extends Node


# ============================================================
# HINWEIS
# ============================================================

# Zentrale Stelle zum Einstellen der UI-Größe-Regler im
# Inspector, ohne Code anfassen zu müssen: die Grundeinstellung
# beim Start, die erlaubten Grenzen (Min/Max/Schrittweite) und
# wie stark die HUD-Gruppen (Herzen, Tränke, Bogen/Pfeil, Zauber,
# Gold) beim Größerstellen zusätzlich zur Bildschirmmitte
# gezogen werden, damit sie nicht über den Rand hinausgehen.
#
# Liegt als Kind-Node im HUD (Player/UI/canvas_layer.tscn) und
# überträgt seine Werte beim Start an SettingsManager (Autoload).
# SettingsManager behält diese Werte danach auch dann, wenn die
# Szene wieder verlassen wird (z.B. im Hauptmenü) - das Setup
# muss also nur in EINER Szene existieren, die immer geladen wird.


@export_group("Grundeinstellung")

# Wert, auf den die Regler bei "Auf Standard zurücksetzen"
# springen bzw. mit dem sie starten, solange nichts gespeichert
# wurde. 1.0 = 100%.
@export_range(0.5, 3.0, 0.05) var default_scale: float = 1.0


@export_group("Grenzen der Regler")

@export_range(0.25, 3.0, 0.05) var min_scale: float = 0.75
@export_range(0.25, 3.0, 0.05) var max_scale: float = 2.0
@export_range(0.01, 0.5, 0.01) var scale_step: float = 0.05


@export_group("Randverschiebung")

# Wie stark der Abstand zum Bildschirmrand zusätzlich zur reinen
# UI-Größe wächst, wenn man größer stellt:
#
# 0.0 = kein Zusatzeffekt (Abstand wächst nur mit der UI-Größe)
# 1.0 = wächst genau im Gleichschritt mit der UI-Größe
# > 1.0 = wächst schneller als die UI-Größe (mehr Sicherheit vor
#         dem Bildschirmrand, aber die Elemente wandern spürbar
#         stärker Richtung Bildschirmmitte)
@export_range(0.0, 3.0, 0.05) var corner_margin_pull: float = 0.5


func _ready() -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	SettingsManager.configure_hud_scale(
		default_scale,
		min_scale,
		max_scale,
		scale_step,
		corner_margin_pull
	)
