extends Node


# ============================================================
# HINWEIS
# ============================================================

# Zentrale Stelle für Hintergrundmusik. Als Autoload angelegt,
# damit die Musik über einen Szenenwechsel hinweg weiterläuft/
# ausfaden kann - z.B. beim Einstieg in einen Spielstand (siehe
# main_menu.gd -> _on_slot_pressed()): die Szene wechselt sofort in
# den Raum, aber dieser Node bleibt als Autoload bestehen und faded
# die Hauptmenü-Musik im Hintergrund sauber aus, während gleich-
# zeitig die Gebiets-Musik reinfadet.
#
# Zwei komplett unabhängige Player, damit beide gleichzeitig laufen
# können (Crossfade): _player für die Hauptmenü-Musik, _area_player
# für die Hintergrundmusik des aktuellen Gebiets (läuft die ganze
# Zeit im Hintergrund weiter, über jeden Raumwechsel hinweg, bis
# man z.B. ins Hauptmenü zurückkehrt - siehe pause_menu.gd ->
# _on_confirm_yes()).
#
# Die Lautstärke selbst läuft NICHT über volume_db an diesen
# Playern, sondern über den "Music"-Audio-Bus (siehe
# SettingsManager.set_audio_volume(&"music", ...)) - volume_db
# hier wird ausschließlich für den Fade-Effekt benutzt. Beide
# Player hängen am selben Bus, der Regler in den Einstellungen
# wirkt also automatisch auf beide.


const MAIN_MENU_MUSIC_PATH: String = (
	"res://Musik/Hauptmenü/echo twr2.mp3"
)

const MUSIC_BUS_NAME: String = "Music"

# area_number -> res://-Pfad der Hintergrundmusik dieses Gebiets.
# Später einfach einen weiteren Eintrag ergänzen, sobald Gebiet 2
# seine eigene Musik bekommt.
const AREA_MUSIC_PATHS: Dictionary = {
	1: "res://Musik/Gebiet 1/dng22.mp3",
}

# room_music_id (siehe Levels/room_manager.gd -> room_music_id) ->
# res://-Pfad der Raum-eigenen Musik, die die Gebiets-Musik beim
# Betreten dieses EINEN Raums übergangsweise ersetzt (Crossfade,
# siehe play_room_music()/stop_room_music() unten) - z.B. der Shop.
const ROOM_MUSIC_PATHS: Dictionary = {
	&"shop": "res://Musik/Gebiet 1/Shop/shop.mp3",
}

# Lautheits-Angleichung: die Rohdateien sind unterschiedlich laut
# abgemischt, per ffmpeg (loudnorm, integrierte Lautheit in LUFS)
# gegen die Hauptmenü-Musik als Referenz gemessen:
#   Hauptmenü (echo twr2.mp3): -29,4 LUFS  (Referenz, Offset 0 dB)
#   Gebiet 1  (dng22.mp3):     -37,4 LUFS  (rechnerisch +8,0 dB
#     nötig für "gleich laut" - auf Nutzer-Wunsch stattdessen
#     bewusst LEISER als die Referenz: -5 dB, die normale
#     Hintergrundmusik soll dezenter sein als der Rest)
#   Shop      (shop.mp3):      -20,1 LUFS  (-9,3 dB nötig)
# Diese Offsets werden NICHT in die Audiodateien selbst eingebrannt
# (die Originale bleiben unangetastet), sondern unten als Ziel-
# Lautstärke des jeweiligen Ein-/Zurück-Fades benutzt statt fest
# 0.0 dB. Kommt ein neues Gebiet/Raum dazu und ist kein Eintrag
# hinterlegt, wird einfach 0.0 dB (unverändert) benutzt.
const AREA_VOLUME_OFFSET_DB: Dictionary = {
	1: -5.0,
}

const ROOM_VOLUME_OFFSET_DB: Dictionary = {
	&"shop": -9.3,
}


# ============================================================
# NODES / STATUS
# ============================================================

var _player: AudioStreamPlayer
var _fade_tween: Tween

var _area_player: AudioStreamPlayer
var _area_fade_tween: Tween

# Welches Gebiet _area_player gerade spielt (oder anfädt) -
# -1 = keins. Verhindert, dass ein erneuter Aufruf für dasselbe
# Gebiet (z.B. beim Betreten mehrerer Räume nacheinander) die
# schon laufende Musik unnötig neu startet.
var _current_area_music: int = -1

var _room_player: AudioStreamPlayer
var _room_fade_tween: Tween

# Separater Tween NUR für das Leiser-/Lauter-Drehen der Gebiets-
# Musik, während man sich in einem Raum mit eigener Musik befindet
# (siehe play_room_music()/stop_room_music() unten) - bewusst
# GETRENNT von _area_fade_tween/fade_out_area_music(): Letzteres
# STOPPT den Player komplett und setzt _current_area_music zurück
# (für den Rückweg ins Hauptmenü), hier soll die Gebiets-Musik
# dagegen nur leiser werden und WEITERLAUFEN, damit sie beim
# Verlassen des Raums exakt an derselben Stelle wieder hochgefadet
# werden kann, statt neu zu starten.
var _area_attenuate_tween: Tween

# &"" = gerade keine Raum-eigene Musik aktiv/anfädend (siehe
# room_music_id in Levels/room_manager.gd).
var _current_room_music: StringName = &""


func _ready() -> void:
	# get_tree().paused friert normalerweise ALLE Nodes ein, die
	# nicht auf PROCESS_MODE_ALWAYS stehen (siehe HINWEIS oben in
	# pause_menu.gd) - das betrifft auch AudioStreamPlayer (Godot
	# pausiert die Wiedergabe selbst automatisch mit). Ohne das hier
	# würde die komplette Musik (Hauptmenü UND Gebiet) im Pause-Menü
	# stumm/einfrieren, statt einfach weiterzulaufen. Die Kind-Player
	# unten erben PROCESS_MODE_ALWAYS automatisch von diesem Node
	# (Standard ist PROCESS_MODE_INHERIT), genauso jeder Fade-Tween,
	# der über create_tween() an diesem Node hängt.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_player = AudioStreamPlayer.new()
	_player.name = "MainMenuMusicPlayer"
	_player.bus = MUSIC_BUS_NAME
	add_child(_player)

	_area_player = AudioStreamPlayer.new()
	_area_player.name = "AreaMusicPlayer"
	_area_player.bus = MUSIC_BUS_NAME
	add_child(_area_player)

	_room_player = AudioStreamPlayer.new()
	_room_player.name = "RoomMusicPlayer"
	_room_player.bus = MUSIC_BUS_NAME
	add_child(_room_player)


# ============================================================
# HAUPTMENÜ-MUSIK
# ============================================================

# Faded jetzt sanft ein statt hart auf volle Lautstärke zu
# springen - wichtig für den Rückweg aus dem Spiel (siehe
# pause_menu.gd -> _on_confirm_yes()): dort läuft die Gebiets-
# Musik gleichzeitig aus (fade_out_area_music()), beide zusammen
# ergeben so einen sauberen Crossfade statt eines kurzen
# Moments, in dem die neue Musik voll und die alte noch hörbar
# gleichzeitig laufen.
func play_main_menu_music(fade_in_duration: float = 3.0) -> void:
	if _player == null:
		return

	if _player.playing:
		# Schon am Laufen (z.B. zurück im Hauptmenü nach einem
		# Spielstand-Ende) - nicht neu starten, nur einen evtl.
		# noch laufenden alten Fade-out abbrechen und wieder auf
		# volle Lautstärke setzen.
		_cancel_fade(_fade_tween)
		_player.volume_db = 0.0
		return

	_cancel_fade(_fade_tween)

	var stream: AudioStream = load(MAIN_MENU_MUSIC_PATH)

	if stream == null:
		push_warning(
			"MusicManager: Hauptmenü-Musik fehlt: "
			+ MAIN_MENU_MUSIC_PATH
		)
		return

	_apply_loop(stream)

	_player.stream = stream
	_player.volume_db = -80.0
	_player.play()

	_fade_tween = create_tween()
	_fade_tween.tween_property(
		_player, "volume_db", 0.0, max(fade_in_duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Blendet die Hauptmenü-Musik sanft aus und stoppt sie danach.
# Läuft unabhängig von der aktuellen Szene weiter (dieser Node ist
# ein Autoload), deshalb kann sie z.B. während des Ladens des
# ersten Raums im Hintergrund fertig ausklingen.
func fade_out_and_stop(duration: float = 3.0) -> void:
	if _player == null or not _player.playing:
		return

	_cancel_fade(_fade_tween)

	_fade_tween = create_tween()
	_fade_tween.tween_property(
		_player, "volume_db", -80.0, max(duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	_fade_tween.tween_callback(_player.stop)


# ============================================================
# GEBIETS-MUSIK (HINTERGRUNDMUSIK IM SPIEL)
# ============================================================

# Faded die Hintergrundmusik eines Gebiets sanft ein und lässt sie
# danach endlos loopen - läuft weiter, egal wie oft man zwischen
# Räumen desselben Gebiets wechselt (siehe main_menu.gd ->
# _on_slot_pressed() / _on_dev_room_selected(), die das beim
# Einstieg in einen Spielstand aufrufen). Ruft man das nochmal mit
# demselben Gebiet auf, während die Musik schon läuft, passiert
# nichts - so bleibt der Loop beim Betreten weiterer Räume
# ungestört.
func play_area_music(
	area_number: int,
	fade_in_duration: float = 3.0
) -> void:
	if _area_player == null:
		return

	if (
		_area_player.playing
		and _current_area_music == area_number
	):
		return

	_cancel_fade(_area_fade_tween)

	var music_path: String = str(
		AREA_MUSIC_PATHS.get(area_number, "")
	)

	if music_path == "":
		push_warning(
			"MusicManager: Keine Gebiets-Musik für Gebiet "
			+ str(area_number)
		)
		return

	var stream: AudioStream = load(music_path)

	if stream == null:
		push_warning(
			"MusicManager: Gebiets-Musik fehlt: " + music_path
		)
		return

	_apply_loop(stream)

	_current_area_music = area_number

	_area_player.stream = stream
	_area_player.volume_db = -80.0
	_area_player.play()

	var area_target_db: float = AREA_VOLUME_OFFSET_DB.get(
		area_number, 0.0
	)

	_area_fade_tween = create_tween()
	_area_fade_tween.tween_property(
		_area_player, "volume_db", area_target_db,
		max(fade_in_duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Blendet die Gebiets-Musik sanft aus und stoppt sie danach - z.B.
# beim Zurückkehren ins Hauptmenü (siehe pause_menu.gd ->
# _on_confirm_yes()), damit sie nicht über das Hauptmenü hinweg
# weiterläuft.
func fade_out_area_music(duration: float = 3.0) -> void:
	_current_area_music = -1

	# Sicherheitsnetz: verlässt man den Lauf z.B. mitten im Shop
	# direkt über das Pause-Menü ins Hauptmenü (siehe pause_menu.gd
	# -> _on_confirm_yes()), muss die Raum-Musik sofort mit
	# verstummen - sonst würde sie über das Hauptmenü hinweg
	# weiterlaufen/"leaken".
	if _current_room_music != &"":
		_current_room_music = &""

		if _room_player != null and _room_player.playing:
			_cancel_fade(_room_fade_tween)

			_room_fade_tween = create_tween()
			_room_fade_tween.tween_property(
				_room_player, "volume_db", -80.0, max(duration, 0.05)
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

			_room_fade_tween.tween_callback(_room_player.stop)

	if _area_player == null or not _area_player.playing:
		return

	_cancel_fade(_area_fade_tween)
	_cancel_fade(_area_attenuate_tween)

	_area_fade_tween = create_tween()
	_area_fade_tween.tween_property(
		_area_player, "volume_db", -80.0, max(duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	_area_fade_tween.tween_callback(_area_player.stop)


# ============================================================
# RAUM-EIGENE MUSIK (Z.B. SHOP)
# ============================================================

# Blendet die Musik EINES einzelnen Raums (siehe Levels/room_
# manager.gd -> room_music_id) sanft ein, während gleichzeitig die
# laufende Gebiets-Musik leiser gedreht (NICHT gestoppt) wird - so
# ist der Übergang ein echter Crossfade, siehe HINWEIS ganz oben.
# Ruft man das nochmal mit derselben room_music_id auf, während sie
# schon läuft, passiert nichts (genau wie play_area_music()).
func play_room_music(
	room_music_id: StringName,
	fade_duration: float = 3.0
) -> void:
	if _room_player == null:
		return

	if (
		_room_player.playing
		and _current_room_music == room_music_id
	):
		return

	var music_path: String = str(
		ROOM_MUSIC_PATHS.get(room_music_id, "")
	)

	if music_path == "":
		push_warning(
			"MusicManager: Keine Raum-Musik für "
			+ str(room_music_id)
		)
		return

	var stream: AudioStream = load(music_path)

	if stream == null:
		push_warning(
			"MusicManager: Raum-Musik fehlt: " + music_path
		)
		return

	_apply_loop(stream)

	_current_room_music = room_music_id

	_cancel_fade(_room_fade_tween)

	_room_player.stream = stream
	_room_player.volume_db = -80.0
	_room_player.play()

	var room_target_db: float = ROOM_VOLUME_OFFSET_DB.get(
		room_music_id, 0.0
	)

	_room_fade_tween = create_tween()
	_room_fade_tween.tween_property(
		_room_player, "volume_db", room_target_db,
		max(fade_duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_attenuate_area_music(-80.0, fade_duration)


# Kehrt play_room_music() um: blendet die Raum-Musik aus (und stoppt
# sie danach) und dreht dabei die Gebiets-Musik wieder auf volle
# Lautstärke hoch, genau an der Stelle, an der sie weiterläuft (sie
# wurde beim Betreten nie gestoppt, nur leiser gedreht).
func stop_room_music(fade_duration: float = 3.0) -> void:
	if _current_room_music == &"":
		return

	_current_room_music = &""

	if _room_player != null and _room_player.playing:
		_cancel_fade(_room_fade_tween)

		_room_fade_tween = create_tween()
		_room_fade_tween.tween_property(
			_room_player, "volume_db", -80.0, max(fade_duration, 0.05)
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		_room_fade_tween.tween_callback(_room_player.stop)

	# WICHTIG: NICHT stur auf 0.0 dB zurückfaden, sondern auf den
	# eigenen normalisierten Zielwert des gerade laufenden Gebiets
	# (siehe AREA_VOLUME_OFFSET_DB oben) - sonst wäre die Gebiets-
	# Musik nach dem Shop-Besuch lauter/leiser als vorher.
	_attenuate_area_music(
		AREA_VOLUME_OFFSET_DB.get(_current_area_music, 0.0),
		fade_duration
	)


# Dreht NUR die Lautstärke von _area_player, OHNE sie zu stoppen und
# OHNE _current_area_music zu verändern (siehe HINWEIS bei
# _area_attenuate_tween oben) - läuft die Gebiets-Musik gerade gar
# nicht (z.B. noch nicht geladen), passiert einfach nichts Sichtbares.
func _attenuate_area_music(
	target_db: float, duration: float
) -> void:
	if _area_player == null:
		return

	_cancel_fade(_area_attenuate_tween)

	_area_attenuate_tween = create_tween()
	_area_attenuate_tween.tween_property(
		_area_player, "volume_db", target_db, max(duration, 0.05)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Setzt den Loop je nach Stream-Typ - AudioStreamMP3 (Hauptmenü-/
# Gebiets-Musik) und AudioStreamWAV (die neue Shop-Musik) haben dafür
# unterschiedliche Properties. Zentral hier statt an jeder Play-
# Stelle einzeln wiederholt.
func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = (
			AudioStreamWAV.LOOP_FORWARD
		)


func _cancel_fade(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
