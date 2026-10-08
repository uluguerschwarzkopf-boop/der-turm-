extends Node

# Nutzer-Wunsch: Beim Betreten eines Raums dieses Gebiets läuft die
# Gebiets-Musik (Pfade/Lautstärke in Game/music_manager.gd ->
# AREA_MUSIC_PATHS / AREA_VOLUME_OFFSET_DB). Diesen Node in jeden Raum
# des Gebiets setzen. Läuft die Musik schon, spielt sie einfach weiter
# (kein Neustart beim Raumwechsel).

## Welches Gebiet (Schlüssel in AREA_MUSIC_PATHS).
@export var area_number: int = 2
## Sekunden zum Einblenden.
@export var fade_in_duration: float = 3.0


func _ready() -> void:
	MusicManager.play_area_music(area_number, fade_in_duration)
