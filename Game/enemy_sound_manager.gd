extends Node

# ============================================================
# SOUND-BANK FÜR ALLE GEGNER IN GEBIET 1 (NUTZER-WUNSCH)
# ============================================================
#
# EINE gemeinsame Node für ALLE Gegner in Gebiet 1 - als Autoload
# eingetragen (siehe project.godot -> [autoload]), deshalb von
# überall im Spiel einfach als "EnemySoundManager" erreichbar,
# ganz ohne eigene @onready-Suche in jedem Gegner-Script (genau wie
# RunState, GoldSystem usw.).
#
# Im Inspector unterteilt in drei eigene Sound Banks:
#   Skelette   - Mobs/Skellete/Normal/skeleton.gd,
#                Mobs/Skellete/Archer/skeleton_archer.gd
#   Mini Boss  - mini bosse/Skelleton Tank/skeleton_tank.gd
#   Boss       - Bosse/Gebiet_1/Phase 1/fire_knight_p_1.gd,
#                Bosse/Gebiet_1/Phase 2/fire_knight_p_2.gd
#
# Gleiches Format wie beim Spieler (siehe Player/player_sound_
# manager.gd) - EINE Zeile pro Sound, Clip+Volume+Speed direkt
# darunter (siehe Player/Sounds/sound_bank_entry.gd - dieselbe
# SoundEntry-Resource wird hier wiederverwendet). Unterschied: hier
# wird IMMER an der Position des jeweiligen Gegners abgespielt
# (AudioStreamPlayer2D statt dem einfachen AudioStreamPlayer beim
# Spieler), damit der Sound je nach Entfernung/Richtung zum Spieler
# lauter/leiser bzw. links/rechts klingt.
#
# Benutzung im jeweiligen Gegner-Script (einfach global_position
# mitgeben, KEINE eigene SoundManager-Node im Gegner nötig):
#   EnemySoundManager.play(&"skelette", &"hit", global_position)
#   EnemySoundManager.play(&"mini_boss", &"death", global_position)
#   EnemySoundManager.play(&"boss", &"hit", global_position)
#
# Für einen NEUEN Sound-Zeitpunkt (Angriff, Aufwachen usw.) muss im
# jeweiligen Gegner-Script nur ein einziger zusätzlicher Aufruf wie
# oben ergänzt werden - die Sound Bank selbst muss dafür nicht
# geändert werden, nur ein neuer Schlüssel in der passenden
# Kategorie unten im Inspector (gleicher Ablauf wie beim Spieler:
# "Element hinzufügen" -> Schlüssel eintragen -> ⌄-Pfeil -> "Neue
# SoundEntry" -> Clip/Volume/Speed ausfüllen).

@export_group("Gebiet 1 - Skelette")
@export var skelette_sounds: Dictionary[StringName, SoundEntry] = {}

@export_group("Gebiet 1 - Mini Boss")
@export var mini_boss_sounds: Dictionary[StringName, SoundEntry] = {}

@export_group("Gebiet 1 - Boss")
@export var boss_sounds: Dictionary[StringName, SoundEntry] = {}


@export_group("Lautstärke & Stimmen")

# Wirkt ZUSÄTZLICH zum "Soundeffekte"-Regler in den Einstellungen
# (siehe Game/settings_manager.gd) und zur Lautstärke des einzelnen
# Sound-Eintrags (siehe SoundEntry.volume) - alle drei
# multiplizieren sich miteinander, genau wie beim Spieler (siehe
# Player/player_sound_manager.gd -> volume_multiplier).
@export_range(0.0, 1.0, 0.01) var volume_multiplier: float = 1.0

@export_group("Stimmen (gleichzeitige Sounds)")

# Wie viele Gegner-Sounds gleichzeitig überlappen können, bevor der
# älteste wiederverwendet wird - bei mehreren Skeletten im selben
# Raum können z.B. mehrere Hurt-Sounds gleichzeitig kommen.
@export var voice_count: int = 10

# Leichte zufällige Tonhöhen-Schwankung für JEDEN Sound, ZUSÄTZLICH
# zur Geschwindigkeit, die auf dem jeweiligen Sound-Eintrag steht -
# 0 = aus, immer exakt gleiche Tonhöhe.
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.05

var _players: Array[AudioStreamPlayer2D] = []
var _next_voice: int = 0


func _ready() -> void:
	for i in range(max(voice_count, 1)):
		var voice := AudioStreamPlayer2D.new()

		voice.bus = "SFX"

		add_child(voice)
		_players.append(voice)


# Spielt den Sound "id" aus der Kategorie "category" an der
# übergebenen Position ab - tut bewusst nichts (kein Fehler, kein
# Absturz), wenn es die Kategorie, den Namen oder die Audiodatei
# dafür (noch) nicht gibt.
func play(
	category: StringName,
	id: StringName,
	at_position: Vector2
) -> void:
	if id == &"":
		return

	var bank: Dictionary = _get_bank(category)
	var entry: SoundEntry = bank.get(id, null)

	if entry == null or entry.clip == null:
		return

	var voice: AudioStreamPlayer2D = _get_next_voice()

	voice.global_position = at_position
	voice.stream = entry.clip

	var combined_volume: float = volume_multiplier * entry.volume

	voice.volume_db = linear_to_db(max(combined_volume, 0.0001))

	if pitch_variation > 0.0:
		voice.pitch_scale = entry.speed * (1.0 + randf_range(
			-pitch_variation,
			pitch_variation
		))
	else:
		voice.pitch_scale = entry.speed

	voice.play()


func has_sound(category: StringName, id: StringName) -> bool:
	var bank: Dictionary = _get_bank(category)
	var entry: SoundEntry = bank.get(id, null)

	return entry != null and entry.clip != null


# Ordnet den Kategorie-Namen (siehe play() oben) der passenden
# Sound Bank oben im Inspector zu. Ein unbekannter Kategorie-Name
# liefert einfach ein leeres Dictionary zurück (kein Fehler).
func _get_bank(category: StringName) -> Dictionary:
	match category:
		&"skelette":
			return skelette_sounds
		&"mini_boss":
			return mini_boss_sounds
		&"boss":
			return boss_sounds
		_:
			return {}


func _get_next_voice() -> AudioStreamPlayer2D:
	if _players.is_empty():
		var fallback := AudioStreamPlayer2D.new()

		fallback.bus = "SFX"

		add_child(fallback)
		_players.append(fallback)

	var voice: AudioStreamPlayer2D = _players[_next_voice]

	_next_voice = (_next_voice + 1) % _players.size()

	return voice
