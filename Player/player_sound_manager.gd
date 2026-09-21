extends Node

# ============================================================
# SOUND-BANK FÜR DEN SPIELER (NUTZER-WUNSCH)
# ============================================================
#
# EINE Zeile pro Sound - links der Name, über den der Code ihn
# auslöst, rechts direkt der Sound-Eintrag mit Audiodatei UND
# Geschwindigkeit zusammen (siehe Player/Sounds/sound_bank_entry.gd).
#
# So wird's benutzt:
# 1. Im Inspector bei "Sound Bank" auf "Element hinzufügen" klicken.
# 2. Links (Schlüssel) den Namen eintragen, den der Code schon
#    benutzt (siehe Player/player.gd, Player/player_combat.gd und
#    Objects/Doors/exit_door.gd bzw. spawn_door.gd):
#      footstep              - ein Laufschritt
#      sword_hit_1           - erster Schwertschlag (Attack 1)
#      sword_hit_2           - zweiter Schwertschlag (Attack 2, Combo)
#      skill_charged_strike
#      skill_ground_slam
#      skill_iron_skin
#      skill_dash_slash
#      skill_parry
#      Door Open              - Exit-Tür wird beim Rausgehen berührt
#      Door Close             - SpawnDoor geht beim Betreten eines
#                               Raums zu (jeder normale Raumeintritt)
# 3. Rechts (Wert) steht "<leer>" mit zwei kleinen Icons daneben -
#    NICHT das Ordner-Symbol anklicken, sondern den kleinen Pfeil
#    (⌄) direkt daneben, dann "Neue SoundEntry" auswählen.
# 4. Auf den jetzt dort stehenden Eintrag klicken, um ihn
#    aufzuklappen - darin direkt UNTEREINANDER:
#      Clip   - die Audiodatei aus dem FileSystem-Tab reinziehen
#      Volume - Lautstärke dieses EINEN Sounds (1.0 = normal)
#      Speed  - Geschwindigkeit dieses EINEN Sounds (1.0 = normal)
#
# Groß-/Kleinschreibung ist wichtig - "footstep" und "Footstep" sind
# zwei verschiedene Namen. Ein Name, den der Code (noch) nicht
# benutzt, oder ein Eintrag ohne Audiodatei tut einfach nichts
# (kein Fehler, kein Absturz).
#
# Für einen NEUEN Sound-Zeitpunkt (den der Code noch nicht auslöst,
# z.B. Landung/Sprung/Tod) muss im jeweiligen Script noch ein
# einziger zusätzlicher Aufruf wie unten play(&"...") ergänzt werden -
# die Sound-Bank selbst muss dafür nicht geändert werden.
@export var sound_bank: Dictionary[StringName, SoundEntry] = {}

@export_group("Lautstärke & Stimmen")

# Nutzer-Wunsch: Sounds insgesamt leiser - wirkt ZUSÄTZLICH zum
# "Soundeffekte"-Regler in den Einstellungen (siehe Game/settings_
# manager.gd), multipliziert sich also mit dessen Wert. 0.5 = alle
# Sounds klingen halb so laut, unabhängig davon, wie der Regler in
# den Einstellungen gerade steht (100% dort UND 0.5 hier = so laut
# wie vorher 50%). 1.0 = keine zusätzliche Abschwächung.
@export_range(0.0, 1.0, 0.01) var volume_multiplier: float = 0.5

@export_group("Stimmen (gleichzeitige Sounds)")

# Wie viele Sounds gleichzeitig überlappen können (eigene
# AudioStreamPlayer-"Stimmen"), bevor die älteste wiederverwendet
# wird - z.B. schnelle Fußschritte + gleichzeitig ein Schwertschlag.
@export var voice_count: int = 6

# Leichte zufällige Tonhöhen-Schwankung für JEDEN Sound, ZUSÄTZLICH
# zur Geschwindigkeit, die auf dem jeweiligen Sound-Eintrag steht
# (macht vor allem oft wiederholte Sounds wie Fußschritte
# natürlicher, damit es nicht immer exakt gleich klingt) - 0 = aus,
# immer exakt gleiche Tonhöhe.
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.05

var _players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0


func _ready() -> void:
	for i in range(max(voice_count, 1)):
		var voice := AudioStreamPlayer.new()

		# Nutzer-Wunsch: eigene Lautstärke-Einstellung für Sounds (siehe
		# Game/settings_manager.gd -> AUDIO_BUS_CATEGORIES "sfx") - alle
		# hier abgespielten Sounds laufen über den "SFX"-Bus, damit der
		# neue Regler in den Einstellungen sie tatsächlich steuert.
		voice.bus = "SFX"

		add_child(voice)
		_players.append(voice)


# Spielt den Sound mit diesem Namen ab (siehe sound_bank oben) - tut
# bewusst nichts (kein Fehler), wenn es dafür keinen Eintrag oder
# keine Audiodatei gibt, damit fehlende Sounds das Spiel nie zum
# Absturz bringen.
func play(id: StringName) -> void:
	if id == &"":
		return

	var entry: SoundEntry = sound_bank.get(id, null)

	if entry == null or entry.clip == null:
		return

	var voice: AudioStreamPlayer = _get_next_voice()

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


func has_sound(id: StringName) -> bool:
	var entry: SoundEntry = sound_bank.get(id, null)

	return entry != null and entry.clip != null


func _get_next_voice() -> AudioStreamPlayer:
	if _players.is_empty():
		var fallback := AudioStreamPlayer.new()

		fallback.bus = "SFX"

		add_child(fallback)
		_players.append(fallback)

	var voice: AudioStreamPlayer = _players[_next_voice]

	_next_voice = (_next_voice + 1) % _players.size()

	return voice
