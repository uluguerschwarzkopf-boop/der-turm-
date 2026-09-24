extends Control


# ============================================================
# HINWEIS
# ============================================================

# Hauptmenü / Startbildschirm: Spielen (3 Spielstand-Slots),
# Einstellungen, Credits, Beenden. Komplett per Code gebaut wie
# das Pause-Menü (Game/pause_menu.gd), aus demselben Grund: ohne
# visuelle Live-Vorschau in diesem Setup ist Hand-Layout in einer
# .tscn riskant, Code mit CenterContainer nicht.
#
# HINTERGRUND: background_texture ist absichtlich ein @export-
# Feld. Sobald das finale Artwork (z.B. das gemalte Turm-Bild)
# als Textur-Datei im Projekt liegt, reicht es, sie im Inspector
# auf diesem Node einzutragen - kein Code-Update nötig. Bis
# dahin läuft ein einfacher dunkler Platzhalter-Hintergrund.
#
# WICHTIG: Die Einstellungen hier sind eine EIGENE Kopie der
# Rebind-Logik aus pause_menu.gd (nicht geteilt). Eine gemeinsame
# Komponente wäre sauberer, aber ein Umbau des bereits laufenden
# Pause-Menüs ohne visuelle Testmöglichkeit ist ein unnötiges
# Risiko - das kann bei Bedarf separat nachgezogen werden.


# ============================================================
# EINSTELLUNGEN (Inspector)
# ============================================================

@export_group("Hintergrund")

@export var background_texture: Texture2D = null
@export var background_color: Color = Color(0.05, 0.05, 0.07, 1.0)


@export_group("Atmosphäre (lebendiger Hintergrund)")

# Rein per Code, ohne neues Artwork: langsames Heranzoomen des
# Hintergrunds ("Ken Burns"-Effekt) plus aufsteigende Glut/Funken
# und ein leichtes Flackern an Fackel-Positionen.
#
# Die Fackel-Positionen kommen jetzt NICHT mehr aus Zahlen hier
# im Code, sondern aus Marker2D-Nodes in main_menu.tscn (Kind-
# Nodes von "BackgroundTexture"). Die kannst du im Godot-Editor
# in der 2D-Ansicht direkt mit der Maus auf die Fackeln im Bild
# ziehen - der Hintergrund ist dort jetzt sichtbar, weil er als
# echter Szenen-Node existiert (nicht mehr nur zur Laufzeit per
# Code gebaut). Beliebig viele Marker2D hinzufügen/löschen geht
# ohne Code-Änderung.
@export var background_atmosphere_enabled: bool = true

# Der Godot-2D-Editor zeigt einen Control ohne eigene Fenstergröße
# (wie BackgroundTexture) immer in der PROJEKT-Basisauflösung an
# (siehe project.godot -> Display -> Window -> Viewport Width/
# Height). Wenn du also ein Marker2D oder ein Banner-Sprite2D im
# Editor mit der Maus auf die richtige Bildstelle ziehst, ist die
# gespeicherte position in Pixeln DIESER Basisauflösung - nicht in
# echten Bild-Pixeln von background_texture (die z.B. 1536x1024
# groß sein kann) und auch nicht in der tatsächlichen Fenstergröße
# zur Laufzeit (die kann jede beliebige Größe/Seitenverhältnis
# haben). Dieser Wert wird nur einmalig beim Start benutzt, um
# Editor-Positionen in echte Bild-Pixel umzurechnen (siehe
# _design_to_native_image_position) - ändert sich das Projekt-
# Setting jemals, hier mit anpassen.
@export var background_design_size: Vector2 = Vector2(1920, 1080)

@export var background_drift_enabled: bool = false
@export_range(1.0, 1.2, 0.01) var background_drift_max_scale: float = 1.05
@export_range(2.0, 120.0, 1.0) var background_drift_seconds: float = 10.0

# Zusätzlich zum reinen Heranzoomen noch ein sehr leichtes,
# gleichmäßiges Schwenken ("Pan") wie bei einer echten
# Kamerafahrt - kein Sprite/Frame-Trick, sondern reine Mathematik
# in _process(). Läuft automatisch nur innerhalb des Bereichs, den
# der aktuelle Zoom sowieso schon an Überstand erzeugt (siehe
# _process weiter unten), kann also NIE einen Bildrand aufdecken,
# egal wie background_pan_strength eingestellt ist.
@export var background_pan_enabled: bool = false
@export_range(0.0, 1.0, 0.05) var background_pan_strength: float = 0.6


@export_group("Titel")

@export var game_title: String = "OCCULTRA"
@export var version_text: String = "v1.0.0"

# Optional: eigenes Logo-Bild statt Text-Titel. Solange dieses
# Feld leer bleibt (Standard), wird game_title als Text
# angezeigt wie bisher. Sobald hier ein Bild eingetragen wird,
# ersetzt es den Text automatisch (kein Code-Update nötig).
@export var title_texture: Texture2D = null

# Genau wie title_texture, nur für die eigenständige "Spielstand
# wählen"-Überschrift über der Spielstand-Auswahl (siehe
# _build_slots_title_display()) - bleibt das Feld leer, wird
# stattdessen SettingsManager.t("menu.slot_title") als reiner Text
# angezeigt (siehe _refresh_texts()).
@export var slots_title_texture: Texture2D = null

# Englische Version desselben Bildes ("SELECT SAVE") - wird in
# _refresh_texts() automatisch statt slots_title_texture angezeigt,
# sobald SettingsManager.get_language() == "en" ist. Bleibt DIESES
# Feld leer, fällt Englisch auf den reinen (übersetzten) Text zurück,
# genau wie slots_title_texture das für Deutsch tut.
@export var slots_title_texture_en: Texture2D = null

# Ornamentale Rahmen-Grafik für jede Spielstand-Zeile (siehe
# _build_slots_panel()): ein Diamant-Ornament mit einem nach unten
# hängenden Schweif links, verbunden mit einem geraden Steg, der nach
# rechts läuft und in einer kleinen Pfeilspitze endet. Sitzt bewusst
# OBEN LINKS AN DER ECKE jeder Zeile (der Steg auf Höhe der Zeilen-
# Oberkante, der Schweif hängt von dort an der linken Kante nach
# unten) - rahmt die Zeile damit wirklich ein, statt nur als Trennstrich
# darunter zu schweben. Als NinePatchRect eingebaut, damit sich nur
# der gerade Mittelteil auf jede Zeilenbreite streckt, ohne die beiden
# Ornament-Enden zu verzerren - siehe _SLOT_FRAME_PATCH_MARGIN_LEFT/
# RIGHT und _SLOT_ROW_TOP_OFFSET weiter unten. Bleibt dieses Feld
# leer, wird einfach keine Rahmengrafik gezeichnet.
@export var slot_frame_texture: Texture2D = null

# Genau dasselbe Muster nochmal für die "EINSTELLUNGEN"/"SETTINGS"-
# Überschrift über dem Einstellungen-Panel (siehe
# _build_settings_title_display()) - deutsches Bild hier,
# englisches in settings_title_texture_en. Bleibt eines der beiden
# Felder leer, fällt _apply_floating_title() für diese Sprache
# automatisch auf den echten, übersetzten Text zurück.
@export var settings_title_texture: Texture2D = null
@export var settings_title_texture_en: Texture2D = null


@export_group("Credits")

@export_multiline var credits_body_override: String = ""


@export_group("Debug")

# TEMPORÄR zur Fehlersuche beim Zoom-Ruckeln - zeigt oben rechts
# die tatsächliche Bilder-pro-Sekunde-Zahl an. Vor der Demo wieder
# auf false stellen bzw. den ganzen Debug-Kram wieder entfernen.
@export var debug_show_fps: bool = false


# ============================================================
# NODES (per Code gebaut)
# ============================================================

var _background_color_rect: ColorRect
var _background_texture_rect: TextureRect
var _center_container: CenterContainer

# Fackel-Effekte/Banner: statt sich auf automatisches Control-
# Anker-Neuberechnen zu verlassen (das bei einem nachträglich per
# Code angehängten Punkt-Control mit Größe 0x0 nicht zuverlässig
# neu ausgelöst wurde - deshalb blieben Glut/Banner beim Ändern
# der Fenstergröße an der alten Stelle stehen), wird die Position
# hier bei jeder Größenänderung von BackgroundTexture explizit
# neu berechnet. "node" ist ein einfaches Node2D, "native_position"
# ist seine Position in ECHTEN Bild-Pixeln (also der nativen
# Auflösung von background_texture, z.B. 1536x1024) - NICHT
# Bruchteile (0..1) und NICHT Design-Canvas-Pixel. Das ist nötig,
# weil STRETCH_KEEP_ASPECT_COVERED das Bild je nach aktuellem
# Fenster-Seitenverhältnis unterschiedlich beschneidet/skaliert -
# ein einfacher Bruchteil der aktuellen Rect-Größe passt nur beim
# Seitenverhältnis, für das er berechnet wurde. Siehe
# _reposition_atmosphere_effects() für die eigentliche Umrechnung.
var _atmosphere_effect_roots: Array[Dictionary] = []

# Vergangene Zeit (Sekunden) für die Ken-Burns-Zoom-Welle in
# _process() - siehe dort für den Grund, warum das jetzt per
# Cosinus-Welle statt per Tween läuft.
var _background_drift_time: float = 0.0

var _main_panel: PanelContainer

# Der Titel ("TOWER OF ECHOES") lebt bewusst NICHT im selben Baum wie
# die Menü-Buttons (siehe _build_title_display()) - er wird an einer
# fest verankerten Stelle oben am Bildschirmrand angezeigt, komplett
# unabhängig davon, wie groß/klein die Buttons darunter gerade sind.
# Vorher stand der Titel in derselben VBoxContainer/CenterContainer
# wie die Buttons - wenn ein Button beim Hovern größer wurde, änderte
# das die Gesamthöhe dieser Box, wodurch der CenterContainer alles
# (inklusive Titel) neu zentrierte und der Titel sichtbar nach oben/
# unten "sprang".
var _title_root: Control
var _title_container: Control
var _title_label: Label
var _title_texture_rect: TextureRect
var _title_glow_texture_rect: TextureRect

# Eigenständiger, isolierter Titel ("SPIELSTAND WÄHLEN") über der
# Spielstand-Auswahl - genau nach demselben Muster wie _title_root
# oben (siehe _build_slots_title_display()), damit er sich beim
# Hovern über einen der Spielstand-Buttons NICHT mitbewegt.
var _slots_title_root: Control
var _slots_title_container: Control
var _slots_title_texture_rect: TextureRect
var _slots_title_glow_texture_rect: TextureRect

var _play_button: Button
var _settings_button: Button
var _credits_button: Button
var _quit_button: Button

var _slots_panel: PanelContainer
var _slots_title_label: Label

# Eine Zeile pro Spielstand-Slot: Name/Klick-Button links, direkt
# rechts davon (falls ein Spielstand existiert) der "Löschen"-Link,
# dann Gebiet, dann Raum, dann - durch einen Füll-Abstandshalter nach
# rechts gedrückt - die Spielzeit ganz am rechten Rand. Siehe
# _build_slots_panel()/_refresh_slots().
var _slot_buttons: Array[Button] = []
var _slot_delete_buttons: Array[Button] = []
var _slot_area_labels: Array[Label] = []
var _slot_room_labels: Array[Label] = []
var _slot_playtime_labels: Array[Label] = []
var _slot_frame_rects: Array[NinePatchRect] = []

var _slots_back_button: Button

var _delete_confirm_panel: PanelContainer
var _delete_confirm_title_label: Label
var _delete_confirm_text_label: Label
var _delete_confirm_yes_button: Button
var _delete_confirm_no_button: Button

var _slot_pending_delete: int = -1

# ============================================================
# DEV-MODUS (TEMPORÄR - vor der Demo wieder komplett entfernen!)
# Alle Stellen sind mit "DEV-MODUS" markiert, damit sie sich per
# Suche leicht wiederfinden lassen.
# ============================================================

var _dev_button: Button
var _dev_panel: PanelContainer
var _dev_title_label: Label
var _dev_rooms_scroll: ScrollContainer
var _dev_rooms_list: VBoxContainer
var _dev_room_buttons: Array[Button] = []
var _dev_back_button: Button

var _settings_panel: PanelContainer

# Eigenständiger, isolierter Titel ("EINSTELLUNGEN"/"SETTINGS") über
# dem Einstellungen-Panel - genau nach demselben Muster wie
# _slots_title_root (siehe _build_settings_title_display()), damit
# er sich beim Hovern über einen der Einstellungen-Buttons NICHT
# mitbewegt und nicht mehr als normaler Text-Titel IN der Box steht.
var _settings_title_root: Control
var _settings_title_container: Control
var _settings_title_label: Label
var _settings_title_texture_rect: TextureRect
var _settings_title_glow_texture_rect: TextureRect

# Die Einstellungen sind jetzt zweistufig, genau wie im Pause-Menü
# (siehe Game/pause_menu.gd): _settings_panel (oben, unter der
# "Einstellungen"-Titel-Grafik) zeigt nur noch die drei
# Oberkategorien - die tatsächlich einstellbaren Werte stecken in
# drei eigenen Kategorie-Seiten weiter unten, jede mit eigenem
# "Zurücksetzen" (nur für diese eine Kategorie) und "Zurück".
var _game_options_category_button: Button
var _audio_category_button: Button
var _controls_category_button: Button
var _settings_list_back_button: Button

# Kategorie "Spieloptionen" (Sprache, UI-Größe, Vollbild) - eigene
# Seite wie _credits_panel, mit normalem Text-Titel statt einer
# eigenen Titel-Grafik.
var _game_options_panel: PanelContainer
var _game_options_title_label: Label
var _language_tab_label: Label
var _language_de_button: Button
var _language_en_button: Button
var _hud_scale_tab_label: Label
var _hud_scale_list: GridContainer
var _display_tab_label: Label
var _fullscreen_checkbox: CheckBox
var _game_options_reset_button: Button
var _game_options_back_button: Button

# Kategorie "Audio" (Gesamtlautstärke, Musik).
var _audio_panel: PanelContainer
var _audio_title_label: Label
var _audio_tab_label: Label
var _audio_settings_list: VBoxContainer
var _audio_reset_button: Button
var _audio_back_button: Button

# Kategorie "Steuerung" (Tastenbelegung).
var _controls_panel: PanelContainer
var _controls_title_label: Label
var _controls_list: GridContainer
var _controls_reset_button: Button
var _controls_back_button: Button

var _credits_panel: PanelContainer
var _credits_title_label: Label
var _credits_body_label: Label
var _credits_back_button: Button

var _version_label: Label
var _debug_fps_label: Label

# action_name -> {"name_label": Label, "binding_label": Label, "rebind_button": Button}
var _action_rows: Dictionary = {}
var _listening_action: StringName = &""


# ============================================================
# SCHRIFTART (NUR HAUPTMENÜ)
# ============================================================

# Das restliche Spiel nutzt jetzt überall die Pixel-Schrift
# Pixelify Sans (project.godot -> [gui] theme/custom_font). Für
# das Hauptmenü selbst (Titelbildschirm + alle von hier aus
# erreichbaren Unter-Panels: Spielstände, Einstellungen, Credits)
# soll es stattdessen eine Schrift sein, die optisch zum
# gemeißelten/eingekerbten Titel-Logo passt - "Metamorphous", eine
# freie Google-Schrift (SIL Open Font License, siehe
# Fonts/metamorphous_LICENSE.txt), genau wie die beiden anderen
# Schriften im Projekt lizenziert.
#
# Umgesetzt als eigenes Theme NUR auf diesem MainMenu-Root-Node
# (statt projektweit in project.godot): ein Theme, das auf einem
# Control gesetzt wird, gilt automatisch für den gesamten Kind-
# Baum darunter, überschreibt hier also den Projekt-Standard
# (Pixelify Sans) für das komplette Hauptmenü, ohne dass sich das
# restliche Spiel (HUD, Pause-Menü, Dialoge, Shop im laufenden
# Run) dadurch ändert.
var _main_menu_theme: Theme = null


func _get_main_menu_theme() -> Theme:
	if _main_menu_theme != null:
		return _main_menu_theme
	_main_menu_theme = Theme.new()
	var decorative_font: Font = load("res://Fonts/metamorphous.woff2")
	if decorative_font != null:
		_main_menu_theme.default_font = decorative_font
	return _main_menu_theme


# ============================================================
# START
# ============================================================

func _ready() -> void:
	add_to_group(&"main_menu")

	_fill_parent_rect(self)

	if get_node_or_null("/root/RunState") != null:
		RunState.stop_time_tracking()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	theme = _get_main_menu_theme()

	_build_ui()
	_refresh_texts()
	_refresh_slots()
	_close_all_panels()

	_main_panel.visible = true

	if get_node_or_null("/root/SettingsManager") != null:
		SettingsManager.language_changed.connect(_on_language_changed)

	if not get_tree().root.size_changed.is_connected(_on_root_size_changed):
		get_tree().root.size_changed.connect(_on_root_size_changed)

	if get_node_or_null("/root/MusicManager") != null:
		MusicManager.play_main_menu_music()


# Das langsame Heranzoomen des Hintergrunds ("Ken Burns") lief
# vorher über einen Tween mit zwei Keyframes (1.0 -> Maximum ->
# 1.0). Das ist mathematisch zwar stetig, hängt aber an Godots
# Tween-Update-Takt und wirkte dadurch spürbar ruckartig statt
# butterweich. Jetzt läuft die Zoom-Bewegung stattdessen als
# durchgehende Cosinus-Welle direkt in _process(), Frame für
# Frame anhand der echten vergangenen Zeit berechnet - dadurch
# gibt es keine Keyframe-Sprünge/Neu-Starts mehr und die Bewegung
# bleibt exakt gleichmäßig, egal wie die Framerate schwankt.
func _process(delta: float) -> void:
	if _debug_fps_label != null:
		_debug_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	if not background_drift_enabled:
		return

	if _background_texture_rect == null or background_drift_seconds <= 0.0:
		return

	_background_drift_time += delta

	var full_cycle_seconds: float = background_drift_seconds * 2.0
	var phase: float = (
		_background_drift_time / full_cycle_seconds
	) * TAU

	var wave: float = (1.0 - cos(phase)) * 0.5
	var scale_factor: float = lerp(
		1.0, background_drift_max_scale, wave
	)

	_background_texture_rect.scale = Vector2.ONE * scale_factor

	# Leichtes Schwenken ("Kamerafahrt") zusätzlich zum Zoom.
	#
	# Der Trick, warum das NIE einen leeren Bildrand aufdecken
	# kann: bei einer Zoom-Vergrößerung um den Faktor scale_factor
	# entsteht pro Seite automatisch ein Überstand von genau
	# (scale_factor - 1) * größe / 2 Pixeln (das ist Standard-
	# Mathematik für Skalierung um einen Mittelpunkt). Verschiebt
	# man den Skalierungs-Mittelpunkt (pivot_offset) innerhalb
	# dieses Überstands, entsteht optisch ein Schwenk, ohne dass
	# jemals eine Kante sichtbar wird - und weil der Überstand bei
	# scale_factor = 1.0 (Anfang/Ende jeder Zoom-Welle) selbst auf
	# 0 schrumpft, schrumpft der mögliche Schwenk automatisch mit
	# auf 0. background_pan_strength (0..1) nutzt davon nur einen
	# Teil, damit auf keiner Seite der Überstand komplett
	# aufgebraucht wird (Sicherheitsabstand gegen Rundungsfehler).
	#
	# WICHTIG: der Schwenk nutzt hier absichtlich dieselbe "wave"-
	# Kurve wie der Zoom (kein eigener, andersschneller Sinus mehr)
	# - vorher liefen Zoom und Schwenk auf zwei unterschiedlich
	# schnellen Wellen, das erzeugte ein leichtes "Schweben"/
	# Gegeneinander-Laufen statt einer einzigen, in sich
	# stimmigen Bewegung. Jetzt sind Heranzoomen und Zur-Seite-
	# Gleiten exakt dieselbe Kamerafahrt, nur in zwei Achsen
	# gleichzeitig - genauso reibungslos wie der Zoom, weil es
	# rechnerisch dieselbe Welle ist.
	if background_pan_enabled:
		var current_size: Vector2 = _background_texture_rect.size
		var overhang: Vector2 = current_size * (scale_factor - 1.0) * 0.5

		var pan_offset: Vector2 = overhang * background_pan_strength

		_background_texture_rect.pivot_offset = (
			current_size * 0.5 + pan_offset
		)
	else:
		_background_texture_rect.pivot_offset = (
			_background_texture_rect.size * 0.5
		)


# Bug-Fix (Vollbild/Fenster-Größe): set_anchors_preset(FULL_RECT)
# zieht sich in der Standard-Einstellung auf die Mindestgröße
# des eigenen Inhalts zusammen, statt wirklich die volle
# Eltern-/Fenstergröße einzunehmen - deshalb war das Hauptmenü
# nur oben links so groß wie Titel+Buttons, egal wie groß das
# echte Fenster war. Hier stattdessen Anker UND Ränder direkt
# und eindeutig auf "volle Fläche" setzen (Ränder = 0 auf allen
# Seiten), damit die Größe immer exakt der Elterngröße
# entspricht und sich live mitverändert.
func _fill_parent_rect(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0

	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


# Sicherheitsnetz: Falls der Vollbild-/Fenstermodus-Wechsel beim
# Start erst kurz nach diesem Frame abgeschlossen wird, hier
# noch einmal neu ausrichten, damit das Menü sicher auf die
# endgültige Fenstergröße mitgeht.
func _on_root_size_changed() -> void:
	_fill_parent_rect(self)


# ============================================================
# INPUT
# ============================================================

func _input(event: InputEvent) -> void:
	if _listening_action == &"":
		return

	if (
		event is InputEventKey
		and event.pressed
		and not (event as InputEventKey).echo
	):
		var key_event: InputEventKey = event as InputEventKey

		if key_event.physical_keycode == KEY_ESCAPE:
			_cancel_listening()
		else:
			_finish_listening(key_event)

		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		_finish_listening(event as InputEventMouseButton)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return

	if _listening_action != &"":
		return

	if _dev_panel.visible:
		_close_dev_panel()
		get_viewport().set_input_as_handled()
		return

	if _delete_confirm_panel.visible:
		_on_delete_confirm_no()
		get_viewport().set_input_as_handled()
		return

	if _credits_panel.visible:
		_close_credits()
		get_viewport().set_input_as_handled()
		return

	# Kategorie-Seiten zuerst prüfen (die liegen "tiefer" als die
	# Kategorie-Übersicht) - Escape geht immer nur eine Ebene
	# zurück, nicht gleich bis zum Hauptmenü durch.
	if _game_options_panel.visible:
		_close_game_options()
		get_viewport().set_input_as_handled()
		return

	if _audio_panel.visible:
		_close_audio_settings()
		get_viewport().set_input_as_handled()
		return

	if _controls_panel.visible:
		_close_controls_settings()
		get_viewport().set_input_as_handled()
		return

	if _settings_panel.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
		return

	if _slots_panel.visible:
		_close_slots()
		get_viewport().set_input_as_handled()
		return


# ============================================================
# UI AUFBAUEN
# ============================================================

func _build_ui() -> void:
	_background_color_rect = ColorRect.new()
	_background_color_rect.name = "BackgroundColor"
	_fill_parent_rect(_background_color_rect)
	_background_color_rect.color = background_color
	_background_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_color_rect)
	move_child(_background_color_rect, 0)

	# BackgroundTexture kommt jetzt bevorzugt direkt aus der Szene
	# (main_menu.tscn), damit sie im Editor sichtbar ist und man
	# Marker2D-Kinder (Fackel-Positionen) visuell darauf ziehen
	# kann. Falls sie dort (noch) fehlt, hier als Sicherheit wie
	# bisher per Code anlegen.
	_background_texture_rect = get_node_or_null("BackgroundTexture") as TextureRect

	if _background_texture_rect == null:
		_background_texture_rect = TextureRect.new()
		_background_texture_rect.name = "BackgroundTexture"
		add_child(_background_texture_rect)

	_fill_parent_rect(_background_texture_rect)
	_background_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_texture_rect.visible = background_texture != null
	_background_texture_rect.texture = background_texture

	# Projekt-Standard für Texturen ist "Nearest" (project.godot ->
	# Rendering -> Textures -> Canvas Textures -> Default Filter),
	# das ist richtig für knackig-scharfe Pixel-Art-Sprites im
	# Gameplay. Für den GEMALTEN Hintergrund hier (kein Pixel-Art,
	# sondern ein Artwork-Bild) sorgt genau dieses "Nearest" beim
	# langsamen Ken-Burns-Zoom aber dafür, dass das Bild zwischen
	# einzelnen Textur-Pixeln hin- und herspringt statt sich
	# gleichmäßig zu bewegen ("Ruckeln"/"Stufen", egal wie fein die
	# Zoom-Berechnung in _process() eigentlich läuft - das Problem
	# liegt am Rendering, nicht an der Anzahl "Frames"). Hier
	# deshalb gezielt NUR für diesen einen Node auf weiche,
	# interpolierte Filterung umstellen. Wird an Kind-Nodes
	# (Fackel-Marker, Banner-Sprites) automatisch mitvererbt, sieht
	# also überall sauberer aus, ohne die Pixel-Art-Sprites im
	# restlichen Spiel zu beeinflussen.
	_background_texture_rect.texture_filter = (
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)

	if background_atmosphere_enabled and background_texture != null:
		_setup_background_atmosphere()

	_center_container = CenterContainer.new()
	_center_container.name = "CenterContainer"
	_fill_parent_rect(_center_container)
	_center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center_container)

	_build_title_display()
	_build_main_panel()

	# Der Titel steht zwar strukturell für sich allein (siehe
	# _build_title_display()), soll aber weiterhin nur auf dem
	# eigentlichen Hauptmenü-Bildschirm zu sehen sein - nicht in den
	# Unter-Panels (Einstellungen, Spielstände, ...). Statt an jeder
	# einzelnen Stelle, die _main_panel.visible setzt, extra auch noch
	# _title_root.visible mitzupflegen, wird das hier EINMALIG über
	# das visibility_changed-Signal automatisch synchron gehalten.
	_main_panel.visibility_changed.connect(
		func() -> void:
			_title_root.visible = _main_panel.visible
	)

	_build_slots_panel()
	_build_slots_title_display()

	# Genau dasselbe Prinzip wie beim Haupttitel oben: die isolierte
	# "Spielstand wählen"-Überschrift folgt automatisch der Sichtbar-
	# keit von _slots_panel, statt an jeder Öffnen/Schließen-Stelle
	# separat mitgepflegt werden zu müssen.
	_slots_panel.visibility_changed.connect(
		func() -> void:
			_slots_title_root.visible = _slots_panel.visible
	)

	_build_settings_panel()
	_build_settings_title_display()

	# Genau dasselbe Prinzip wie beim Haupttitel/der Spielstand-
	# Überschrift oben: die isolierte "Einstellungen"-Überschrift folgt
	# automatisch der Sichtbarkeit von _settings_panel.
	_settings_panel.visibility_changed.connect(
		func() -> void:
			_settings_title_root.visible = _settings_panel.visible
	)

	_build_game_options_panel()
	_build_audio_panel()
	_build_controls_panel()

	_build_credits_panel()
	_build_delete_confirm_panel()

	# DEV-MODUS (TEMPORÄR - vor der Demo wieder entfernen!)
	_build_dev_panel()

	_version_label = Label.new()
	_version_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_version_label.position = Vector2(16, -32)
	_version_label.add_theme_color_override(
		"font_color",
		Color(1.0, 1.0, 1.0, 0.5)
	)
	add_child(_version_label)

	# TEMPORÄR zum Debuggen des Zoom-Ruckelns: zeigt die echte
	# Bilder-pro-Sekunde-Zahl oben rechts an. Vor der Demo wieder
	# entfernen bzw. debug_show_fps auf false setzen. Wenn das
	# Ruckeln wirklich an der Framerate liegt, siehst du hier eine
	# niedrige/schwankende Zahl statt konstant ~60.
	if debug_show_fps:
		_debug_fps_label = Label.new()
		_debug_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_debug_fps_label.position = Vector2(-120, 16)
		_debug_fps_label.add_theme_color_override(
			"font_color",
			Color(1.0, 1.0, 0.3, 0.9)
		)
		_debug_fps_label.add_theme_font_size_override("font_size", 22)
		add_child(_debug_fps_label)


# ============================================================
# LEBENDIGER HINTERGRUND (Wind/Feuer-Gefühl per Code)
# ============================================================

# Baut alle atmosphärischen Effekte über dem Hintergrundbild auf:
# ein sehr langsames Heranzoomen ("Ken Burns") plus aufsteigende
# Glut/Funken mit leichtem Flackern an den Fackel-Positionen.
# Alles rein per Code erzeugt (keine zusätzlichen Bild-Dateien
# nötig) und liegt über dem Hintergrund, aber unter dem Menü-Panel.
func _setup_background_atmosphere() -> void:
	if background_drift_enabled:
		_setup_background_drift()

	for marker in _get_torch_markers():
		var native_position: Vector2 = _design_to_native_image_position(
			marker.position
		)

		_setup_torch_effect(native_position)

	for banner_sprite in _get_wind_banner_sprites():
		_setup_banner_sway(banner_sprite)

	if not _background_texture_rect.resized.is_connected(
		_reposition_atmosphere_effects
	):
		_background_texture_rect.resized.connect(
			_reposition_atmosphere_effects
		)

	_reposition_atmosphere_effects()


# Findet alle Marker2D-Kinder von BackgroundTexture - das sind
# die Fackel-Positionen. Im Godot-Editor unter main_menu.tscn ->
# BackgroundTexture kannst du dort beliebig viele Marker2D-Nodes
# hinzufügen/verschieben/löschen, ohne dieses Skript anzufassen.
func _get_torch_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []

	if _background_texture_rect == null:
		return markers

	for child in _background_texture_rect.get_children():
		if child is Marker2D:
			markers.append(child as Marker2D)

	return markers


# Findet alle Sprite2D-Kinder von BackgroundTexture, die in der
# Gruppe "wind_banners" sind - das sind die freigestellten
# Banner-Ausschnitte (aus dem Hintergrundbild automatisch
# herausgelöst, siehe main_menu.tscn). Genauso im Editor per
# Hand verschiebbar/ergänzbar wie die Fackel-Marker.
func _get_wind_banner_sprites() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []

	if _background_texture_rect == null:
		return sprites

	for child in _background_texture_rect.get_children():
		if child is Sprite2D and child.is_in_group(&"wind_banners"):
			sprites.append(child as Sprite2D)

	return sprites


# Rechnet eine im Godot-Editor gezogene Marker2D/Sprite2D-Position
# (in Pixeln der Projekt-Basisauflösung background_design_size,
# siehe Kommentar dort) einmalig in echte Bild-Pixel von
# background_texture um. Invertiert dafür genau die Rechnung, die
# STRETCH_KEEP_ASPECT_COVERED beim Anzeigen des Bildes in einer
# background_design_size-großen Fläche macht.
func _design_to_native_image_position(design_position: Vector2) -> Vector2:
	if background_texture == null:
		return design_position

	var image_size: Vector2 = background_texture.get_size()

	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return design_position

	var design_cover_scale: float = max(
		background_design_size.x / image_size.x,
		background_design_size.y / image_size.y
	)

	var scaled_image_size: Vector2 = image_size * design_cover_scale
	var design_crop_offset: Vector2 = (
		(background_design_size - scaled_image_size) * 0.5
	)

	return (design_position - design_crop_offset) / design_cover_scale


# Setzt die Bildschirm-Position ALLER registrierten Atmosphäre-
# Effekte (Fackeln, Banner) neu, ausgehend von ihrer Position in
# ECHTEN Bild-Pixeln (native_position) und der AKTUELLEN Größe von
# BackgroundTexture. Das ist der eigentliche Fix dafür, dass
# Glut/Banner beim Verkleinern/Vergrößern des Fensters bzw. beim
# Verlassen von Vollbild "isoliert in der Luft" schweben statt fest
# auf dem Bild zu bleiben.
#
# Grund: BackgroundTexture nutzt STRETCH_KEEP_ASPECT_COVERED. Dabei
# skaliert Godot das Originalbild so, dass es die GESAMTE Rect-
# Fläche abdeckt (kein Rand), und schneidet den überstehenden Teil
# in einer Achse ab - der Skalierungsfaktor und der abgeschnittene
# Rand hängen vom aktuellen Seitenverhältnis der Rect ab, nicht nur
# von ihrer Größe. Ein einfacher Bruchteil (0..1) der Rect-Größe
# ignoriert genau diesen Crop und "driftet" deshalb bei jedem
# Seitenverhältnis, das nicht zufällig zum Bild passt.
#
# Die korrekte Umrechnung (macht exakt das, was
# STRETCH_KEEP_ASPECT_COVERED intern tut):
#   cover_scale  = max(rect.x / bild.x, rect.y / bild.y)
#   bild_skaliert = bild * cover_scale
#   crop_offset  = (rect - bild_skaliert) * 0.5
#   bildschirm_position = native_position * cover_scale + crop_offset
#
# Zusätzlich wird node.scale auf cover_scale gesetzt, damit auch
# die visuelle Größe der Effekte (Glut, Banner) mit dem Bild
# mitskaliert statt bei jeder Fenstergröße gleich groß zu bleiben.
func _reposition_atmosphere_effects() -> void:
	if _background_texture_rect == null:
		return

	if background_texture == null:
		return

	var rect_size: Vector2 = _background_texture_rect.size
	var image_size: Vector2 = background_texture.get_size()

	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return

	var cover_scale: float = max(
		rect_size.x / image_size.x,
		rect_size.y / image_size.y
	)

	var scaled_image_size: Vector2 = image_size * cover_scale
	var crop_offset: Vector2 = (rect_size - scaled_image_size) * 0.5

	for entry in _atmosphere_effect_roots:
		var node: Node2D = entry.get("node")
		var native_position: Vector2 = entry.get("native_position")

		if node == null or not is_instance_valid(node):
			continue

		node.position = native_position * cover_scale + crop_offset
		node.scale = Vector2.ONE * cover_scale


# Lässt ein freigestelltes Banner leicht im Wind hin- und
# herschwingen. Der Dreh-Ankerpunkt (0,0 im Sprite) liegt schon
# an der richtigen Stelle (Fahnenstange unten bzw. Aufhängung
# oben) - siehe offset/centered=false in main_menu.tscn.
func _setup_banner_sway(sprite: Sprite2D) -> void:
	var native_position: Vector2 = _design_to_native_image_position(
		sprite.position
	)

	var sway_root := Node2D.new()
	sway_root.name = "BannerSwayRoot"
	_background_texture_rect.add_child(sway_root)

	_atmosphere_effect_roots.append({
		"node": sway_root,
		"native_position": native_position,
	})

	var original_parent: Node = sprite.get_parent()

	if original_parent != null:
		original_parent.remove_child(sprite)

	sway_root.add_child(sprite)
	sprite.position = Vector2.ZERO

	var max_angle_degrees: float = randf_range(1.2, 2.4)
	var third_duration: float = randf_range(1.6, 2.6)

	var sway_tween: Tween = create_tween()
	sway_tween.set_loops()
	sway_tween.set_trans(Tween.TRANS_SINE)
	sway_tween.set_ease(Tween.EASE_IN_OUT)

	sway_tween.tween_property(
		sprite, "rotation", deg_to_rad(max_angle_degrees), third_duration
	)
	sway_tween.tween_property(
		sprite,
		"rotation",
		deg_to_rad(-max_angle_degrees),
		third_duration * 2.0
	)
	sway_tween.tween_property(sprite, "rotation", 0.0, third_duration)


func _setup_background_drift() -> void:
	_background_texture_rect.pivot_offset = (
		_background_texture_rect.size * 0.5
	)

	_background_texture_rect.resized.connect(
		func() -> void:
			_background_texture_rect.pivot_offset = (
				_background_texture_rect.size * 0.5
			)
	)

	# Die eigentliche Zoom-Animation läuft jetzt in _process()
	# (durchgehende Cosinus-Welle statt Tween) - hier wird nur
	# noch der Dreh-/Skalierungs-Mittelpunkt aktuell gehalten.


# Erzeugt an einer Position in ECHTEN Bild-Pixeln (native_position,
# siehe Marker2D in main_menu.tscn) einen kleinen warmen Glüh-
# Schein plus aufsteigende Funken - simuliert eine Fackel/Feuer-
# stelle, ohne dass diese im Bild selbst freigestellt werden muss.
func _setup_torch_effect(native_position: Vector2) -> void:
	var anchor_point := Node2D.new()
	anchor_point.name = "TorchEffectRoot"
	_background_texture_rect.add_child(anchor_point)

	_atmosphere_effect_roots.append({
		"node": anchor_point,
		"native_position": native_position,
	})

	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(1.0, 0.6, 0.2, 0.55))
	glow_gradient.set_color(1, Color(1.0, 0.6, 0.2, 0.0))

	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 48
	glow_texture.height = 48

	var glow := Sprite2D.new()
	glow.name = "Glow"
	glow.texture = glow_texture
	glow.scale = Vector2(1.6, 1.6)
	anchor_point.add_child(glow)

	var flicker_tween: Tween = create_tween()
	flicker_tween.set_loops()
	flicker_tween.tween_property(
		glow, "modulate:a", 0.55, 0.12 + randf() * 0.18
	).set_trans(Tween.TRANS_SINE)
	flicker_tween.tween_property(
		glow, "modulate:a", 1.0, 0.12 + randf() * 0.18
	).set_trans(Tween.TRANS_SINE)

	var ember_gradient := Gradient.new()
	ember_gradient.set_color(0, Color(1.0, 0.75, 0.3, 0.95))
	ember_gradient.set_color(1, Color(1.0, 0.3, 0.1, 0.0))

	var embers := CPUParticles2D.new()
	embers.name = "Embers"
	embers.amount = 10
	embers.lifetime = 2.0
	embers.emitting = true
	embers.direction = Vector2(0.0, -1.0)
	embers.spread = 18.0
	embers.gravity = Vector2(0.0, -22.0)
	embers.initial_velocity_min = 8.0
	embers.initial_velocity_max = 20.0
	embers.scale_amount_min = 0.5
	embers.scale_amount_max = 1.2
	embers.color_ramp = ember_gradient
	anchor_point.add_child(embers)


# ============================================================
# HAUPTMENÜ IM "HOLLOW KNIGHT"-STIL
# ============================================================

# Der Startbildschirm (NUR das Hauptmenü - Spielen/Einstellungen/
# Beenden, nicht die Unter-Panels wie Spielstand-Auswahl/
# Einstellungen/Credits) soll ohne sichtbaren Kasten direkt über dem
# gemalten Hintergrund schweben, mit einem großen, leicht leuchtenden
# Titel-Logo oben und reinen Text-Menüpunkten darunter, die beim
# Hovern größer werden und links/rechts kleine Pfeile bekommen - siehe
# _make_borderless_panel()/_add_menu_button_row() weiter unten.

const _TITLE_HEIGHT: float = 260.0
const _TITLE_TOP_MARGIN: float = 32.0

# Die "Spielstand wählen"-Überschrift ist ein deutlich flacheres/
# breiteres Logo als der Haupttitel, deshalb eigene (kleinere) Höhe.
const _SLOTS_TITLE_HEIGHT: float = 280.0
const _SLOTS_TITLE_TOP_MARGIN: float = 40.0

# "EINSTELLUNGEN"/"SETTINGS"-Überschrift über der Kategorie-
# Übersicht (siehe _build_settings_title_display()) - eigene Höhe,
# weil dieses Logo ein anderes Seitenverhältnis als die beiden
# anderen Titel hat.
const _SETTINGS_TITLE_HEIGHT: float = 320.0
const _SETTINGS_TITLE_TOP_MARGIN: float = 20.0

const _TITLE_GLOW_SCALE: float = 1.12
const _TITLE_GLOW_COLOR: Color = Color(1.0, 0.85, 0.55, 0.55)
const _TITLE_GLOW_MIN_ALPHA: float = 0.4
const _TITLE_GLOW_MAX_ALPHA: float = 0.75
const _TITLE_GLOW_PULSE_SECONDS: float = 1.8

const _MENU_ITEM_FONT_SIZE: int = 24
const _MENU_ITEM_HOVER_FONT_SIZE: int = 30
const _MENU_ITEM_COLOR: Color = Color(0.85, 0.83, 0.8, 1.0)
const _MENU_ITEM_HOVER_COLOR: Color = Color(1.0, 0.92, 0.7, 1.0)

# Aus dem Ornament am Ende der Unterstreichung unter "SELECT SAVE"
# (Hauptseite/select_save_logo.png) ausgeschnittenes Pfeilspitzen-
# Motiv - dieselbe Grafik wie beim Titel-Logo, statt eines eigenen,
# nur aus Pixeln gezeichneten Dreiecks. Zusätzlich mit einem
# schwarzen Rand versehen (per Python/PIL-Skript um die Alpha-Maske
# herum "aufgeblasen"), damit die dunkle lila/rote Grafik sich auch
# vor dem ähnlich dunklen Hintergrundbild klar absetzt (82x56 inkl.
# Rand, siehe Hauptseite/menu_arrow.png). Die ausgeschnittene Spitze
# zeigt im Original bereits nach LINKS, deshalb wird für den rechten
# Pfeil einfach die horizontal gespiegelte Variante verwendet (siehe
# flip_h an den jeweiligen Einsatzstellen unten) statt eine zweite
# Datei zu brauchen.
static var _menu_arrow_texture: Texture2D = preload(
	"res://Hauptseite/menu_arrow.png"
)

# Zielgröße auf dem Bildschirm - ungefähr im selben Seitenverhältnis
# wie die Bilddatei (82x56), deutlich herunterskaliert. Kleine
# Abweichungen vom exakten Seitenverhältnis sind unkritisch, weil die
# Pfeile mit STRETCH_KEEP_ASPECT_CENTERED angezeigt werden (siehe
# _configure_menu_arrow()) - das Bild wird also so oder so nie
# verzerrt, sondern höchstens minimal "briefmarkig" zentriert.
const _MENU_ARROW_SIZE: Vector2i = Vector2i(35, 24)

# Spielstand-Zeilen: eigene (etwas kleinere) Schriftgrößen als die
# Hauptmenü-Punkte, weil in einer Zeile hier zusätzlich noch Gebiet/
# Raum/Spielzeit/Löschen-Link Platz haben müssen.
const _SLOT_NAME_FONT_SIZE: int = 22
const _SLOT_NAME_HOVER_FONT_SIZE: int = 26
const _SLOT_STAT_FONT_SIZE: int = 16
const _SLOT_STAT_COLOR: Color = Color(0.75, 0.72, 0.68, 1.0)
const _SLOT_DELETE_FONT_SIZE: int = 15
const _SLOT_DELETE_COLOR: Color = Color(0.8, 0.4, 0.35, 1.0)
const _SLOT_DELETE_HOVER_COLOR: Color = Color(1.0, 0.55, 0.45, 1.0)
const _SLOT_ROW_MIN_WIDTH: float = 560.0

# Die Rahmen-Grafik (slot_frame_texture) ist bewusst KEIN reiner
# Trennstrich - sie zeigt einen Diamant/Ornament, das oben links an
# der Ecke des Spielstands sitzt, mit einem Schweif, der von dort an
# der LINKEN Kante der Zeile nach unten hängt, während der gerade Steg
# nach rechts oben verläuft. Deshalb wird sie hier NICHT als eigene
# Zeile UNTER dem Spielstand eingefügt, sondern als eigenständiges,
# höheres Element OBEN über/hinter jeder Zeile platziert (siehe
# _build_slots_panel()): der gerade Steg liegt auf Höhe der oberen
# Kante des Textes, der Schweif hängt von dort weiter nach unten neben
# dem Zeilentext herab - das Ornament "umrahmt" die Ecke, statt nur
# darunter zu schweben.
#
# Als NinePatchRect eingebaut, damit sich nur der plane Mittelsteg
# horizontal streckt und die beiden Ornament-Enden (Diamant links,
# Pfeilspitze rechts) unverzerrt bleiben, egal wie breit die Zeile
# ist. Alle Werte hier sind auf die ENDGÜLTIGE Pixelgröße von
# Hauptseite/slot_frame.png (238x72, bereits herunterskaliert von der
# Original-Bildvorlage) abgestimmt - bei einem Austausch dieser Datei
# ggf. neu abmessen (siehe Kommentar bei slot_frame_texture oben).
const _SLOT_FRAME_HEIGHT: float = 72.0
const _SLOT_FRAME_PATCH_MARGIN_LEFT: int = 34
const _SLOT_FRAME_PATCH_MARGIN_RIGHT: int = 32

# Der gerade Steg der Rahmengrafik liegt NICHT an ihrem oberen Rand,
# sondern schon ein Stück weiter unten (der Diamant und sein oberer
# Zacken ragen darüber hinaus) - dieser Wert ist genau die Pixel-
# Höhe, an der der Steg in slot_frame_texture sitzt. Die eigentliche
# Zeile (Name/Löschen/Gebiet/Raum/Spielzeit) wird um genau diesen
# Betrag nach unten versetzt, damit ihre Oberkante exakt auf dem Steg
# aufliegt statt mittig im Ornament zu schweben.
const _SLOT_ROW_TOP_OFFSET: float = 21.0

# Gesamthöhe pro Spielstand-Zeile INKLUSIVE des Rahmen-Ornaments
# (Steg-Versatz oben + Platz für die Zeile selbst darunter).
const _SLOT_WRAPPER_HEIGHT: float = 76.0

# Weicher Glow-Schein hinter dem Titel-Logo: eine leicht vergrößerte,
# warm eingefärbte Kopie derselben Textur, die per Shader
# weichgezeichnet ("geblurrt") wird - dadurch entsteht ein sanfter
# Lichtschein um die Schrift, ganz ohne eigene Bild-Datei. Als
# Laufzeit-Shader gebaut, genau wie z.B. das Fenster-Aus-Material bei
# den Skill-Staturen (Objects/Staturen/skill_statue.gd).
const _TITLE_GLOW_SHADER_CODE: String = """
shader_type canvas_item;

uniform float blur_amount = 3.0;

void fragment() {
	vec2 pixel_size = TEXTURE_PIXEL_SIZE * blur_amount;
	vec4 total_color = vec4(0.0);
	float total_weight = 0.0;

	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			vec2 sample_uv = UV + vec2(float(x), float(y)) * pixel_size;

			// Ohne diese Prüfung würden Samples knapp außerhalb von
			// UV 0..1 je nach Textur-Wrap-Modus vom GEGENÜBERLIEGENDEN
			// Bildrand zurückgespiegelt - das erzeugte bei eng
			// zugeschnittenen Logos ein sichtbares "Geister"-Echo des
			// jeweils anderen Randes (z.B. ein zweites "S" am linken
			// Rand). Samples außerhalb des Bildes werden deshalb
			// einfach übersprungen (zählen nicht mit), statt vom
			// falschen Rand zu lesen.
			if (
				sample_uv.x < 0.0 || sample_uv.x > 1.0
				|| sample_uv.y < 0.0 || sample_uv.y > 1.0
			) {
				continue;
			}

			float weight = 1.0 / (1.0 + float(x * x + y * y));

			total_color += texture(TEXTURE, sample_uv) * weight;
			total_weight += weight;
		}
	}

	vec4 blurred = (
		total_weight > 0.0
		? total_color / total_weight
		: vec4(0.0)
	);

	COLOR = blurred * COLOR;
}
"""


func _build_title_glow_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _TITLE_GLOW_SHADER_CODE

	var material := ShaderMaterial.new()
	material.shader = shader

	return material


# Richtet ein TextureRect als linken/rechten Hover-Pfeil ein: setzt
# das ausgeschnittene Ornament-Motiv (_menu_arrow_texture) und spiegelt
# es für die rechte Seite horizontal (siehe Kommentar bei
# _menu_arrow_texture oben).
func _configure_menu_arrow(
	arrow_rect: TextureRect, pointing_right: bool
) -> void:
	arrow_rect.texture = _menu_arrow_texture
	arrow_rect.flip_h = pointing_right

	# Die echte Bild-Datei ist größer als die gewünschte Anzeige-
	# größe (_MENU_ARROW_SIZE) - IGNORE_SIZE + KEEP_ASPECT_CENTERED
	# skaliert sie sauber auf custom_minimum_size herunter, statt
	# (wie EXPAND_KEEP_SIZE es täte) die Original-Pixelgröße der
	# Datei zu erzwingen.
	arrow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


# Hängt einen bestehenden Menü-Button (Text, kein sichtbarer Kasten
# mehr) in eine Reihe mit zwei anfangs unsichtbaren Pfeilen ein und
# lässt Schriftgröße/-farbe sowie die Pfeile beim Hovern reagieren.
func _add_menu_button_row(box: VBoxContainer, button: Button) -> void:
	button.flat = true

	# Reserviert von Anfang an so viel Platz, wie der Button auch im
	# vergrößerten Hover-Zustand braucht - dadurch ändert sich die
	# Gesamthöhe der Button-Liste beim Hovern NICHT mehr, und die
	# anderen Menüpunkte rutschen nicht mit hoch/runter.
	button.custom_minimum_size = Vector2(300, 50)

	var empty_style := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty_style)
	button.add_theme_stylebox_override("hover", empty_style)
	button.add_theme_stylebox_override("pressed", empty_style)
	button.add_theme_stylebox_override("focus", empty_style)
	button.add_theme_stylebox_override("disabled", empty_style)

	button.add_theme_font_size_override("font_size", _MENU_ITEM_FONT_SIZE)
	button.add_theme_color_override("font_color", _MENU_ITEM_COLOR)
	button.add_theme_color_override(
		"font_hover_color", _MENU_ITEM_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_focus_color", _MENU_ITEM_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_pressed_color", _MENU_ITEM_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_hover_pressed_color", _MENU_ITEM_HOVER_COLOR
	)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)

	var left_arrow := TextureRect.new()
	_configure_menu_arrow(left_arrow, false)
	left_arrow.custom_minimum_size = Vector2(_MENU_ARROW_SIZE)
	left_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_arrow.modulate.a = 0.0
	row.add_child(left_arrow)

	row.add_child(button)

	var right_arrow := TextureRect.new()
	_configure_menu_arrow(right_arrow, true)
	right_arrow.custom_minimum_size = Vector2(_MENU_ARROW_SIZE)
	right_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_arrow.modulate.a = 0.0
	row.add_child(right_arrow)

	button.mouse_entered.connect(
		func() -> void:
			button.add_theme_font_size_override(
				"font_size", _MENU_ITEM_HOVER_FONT_SIZE
			)
			left_arrow.modulate.a = 1.0
			right_arrow.modulate.a = 1.0
	)
	button.mouse_exited.connect(
		func() -> void:
			button.add_theme_font_size_override(
				"font_size", _MENU_ITEM_FONT_SIZE
			)
			left_arrow.modulate.a = 0.0
			right_arrow.modulate.a = 0.0
	)

	box.add_child(row)


# ============================================================
# SPIELSTAND-ZEILEN IM "HOLLOW KNIGHT"-STIL
# ============================================================

# Macht aus einem Button den flachen, textartigen Namens-/Klick-
# Teil einer Spielstand-Zeile (z.B. "Slot 1") - optisch genau wie
# ein Hauptmenü-Punkt (siehe _add_menu_button_row()), nur ohne die
# eigenen Pfeile: die Pfeile gehören hier zur GESAMTEN Zeile (Name +
# Löschen-Link + Gebiet/Raum/Spielzeit), siehe _add_slot_row().
func _style_slot_name_button(button: Button) -> void:
	button.flat = true
	button.custom_minimum_size = Vector2(160, 40)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var empty_style := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty_style)
	button.add_theme_stylebox_override("hover", empty_style)
	button.add_theme_stylebox_override("pressed", empty_style)
	button.add_theme_stylebox_override("focus", empty_style)
	button.add_theme_stylebox_override("disabled", empty_style)

	button.add_theme_font_size_override("font_size", _SLOT_NAME_FONT_SIZE)
	button.add_theme_color_override("font_color", _MENU_ITEM_COLOR)
	button.add_theme_color_override(
		"font_hover_color", _MENU_ITEM_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_focus_color", _MENU_ITEM_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_pressed_color", _MENU_ITEM_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_hover_pressed_color", _MENU_ITEM_HOVER_COLOR
	)

	button.mouse_entered.connect(
		func() -> void:
			button.add_theme_font_size_override(
				"font_size", _SLOT_NAME_HOVER_FONT_SIZE
			)
	)
	button.mouse_exited.connect(
		func() -> void:
			button.add_theme_font_size_override(
				"font_size", _SLOT_NAME_FONT_SIZE
			)
	)


# "Spielstand löschen"-Textlink direkt rechts vom Spielstand-Namen
# (siehe _build_slots_panel()) - bewusst in Rot/Orange, damit er sich
# klar von den übrigen (neutralen) Zeilen-Texten abhebt. Bleibt für
# leere Slots unsichtbar (siehe _refresh_slots()).
func _style_slot_delete_button(button: Button) -> void:
	button.flat = true
	button.custom_minimum_size = Vector2(0, 34)

	var empty_style := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty_style)
	button.add_theme_stylebox_override("hover", empty_style)
	button.add_theme_stylebox_override("pressed", empty_style)
	button.add_theme_stylebox_override("focus", empty_style)
	button.add_theme_stylebox_override("disabled", empty_style)

	button.add_theme_font_size_override("font_size", _SLOT_DELETE_FONT_SIZE)
	button.add_theme_color_override("font_color", _SLOT_DELETE_COLOR)
	button.add_theme_color_override(
		"font_hover_color", _SLOT_DELETE_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_focus_color", _SLOT_DELETE_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_pressed_color", _SLOT_DELETE_HOVER_COLOR
	)
	button.add_theme_color_override(
		"font_hover_pressed_color", _SLOT_DELETE_HOVER_COLOR
	)


# Gebiet/Raum/Spielzeit sind reiner (nicht klickbarer) Text - eigene,
# etwas gedämpftere Farbe/Schriftgröße als der Spielstand-Name, damit
# der Name als eigentlicher Klick-Punkt optisch führend bleibt.
func _make_slot_stat_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", _SLOT_STAT_FONT_SIZE)
	label.add_theme_color_override("font_color", _SLOT_STAT_COLOR)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# Hängt den Inhalt EINER GANZEN Spielstand-Zeile (Name, Gebiet, Raum,
# Spielzeit, Löschen-Link - siehe _build_slots_panel()) zwischen zwei
# anfangs unsichtbare Pfeile, genau wie _add_menu_button_row() das für
# einen einzelnen Hauptmenü-Button tut. "parent" ist hier der
# Zeilen-"wrapper"-Control (KEINE Container, siehe _build_slots_panel()),
# deshalb wird die resultierende Zeile per Anker/Offset selbst auf
# volle Breite gebracht und um top_offset nach unten versetzt (damit
# ihre Oberkante auf dem Steg der Rahmengrafik aufliegt), statt sich
# wie in einer VBoxContainer/HBoxContainer automatisch einzupassen.
#
# "hover_triggers" sind die tatsächlich klickbaren Buttons IN der Zeile
# (Name-Button, Löschen-Link) - die Pfeile reagieren direkt auf DEREN
# mouse_entered/mouse_exited, genau wie beim Hauptmenü
# (_add_menu_button_row()). Ein Versuch, stattdessen den gesamten
# "content"-Container selbst per MOUSE_FILTER_PASS hovern zu lassen,
# hat sich als unzuverlässig erwiesen (die Pfeile blieben beim Hovern
# unsichtbar statt zu erscheinen) - deshalb jetzt derselbe bewährte
# Button-für-Button-Ansatz wie im Hauptmenü. Ein kleiner Zähler
# (hover_count) verhindert ein Flackern, falls die Maus innerhalb
# derselben Zeile direkt von einem Trigger zum nächsten wandert (z.B.
# vom Namen zum "Löschen"-Link).
#
# Die Rahmengrafik (slot_frame_texture, siehe _build_slots_panel())
# hat ihre eigenen Ornament-Spitzen genau an den Kanten von "wrapper"
# (0..volle Breite) sitzen - ohne Gegenmaßnahme würden die Hover-
# Pfeile also GENAU auf diesen Ornamenten landen statt daneben.
# _SLOT_ARROW_OUTSET schiebt die Zeile links/rechts über "wrapper"
# hinaus, damit die Pfeile weiter außen (neben statt auf den Rahmen-
# Ornamenten) erscheinen - und erhöht im GLEICHEN Schritt die
# "separation" um denselben Betrag, damit "content" (Name/Gebiet/
# Raum/Spielzeit/Löschen) an EXAKT derselben Stelle stehen bleibt wie
# vorher (die Verbreiterung der Zeile wird also komplett von den
# Pfeil-Außenabständen aufgefangen, nicht vom Zeileninhalt selbst).
const _SLOT_ARROW_OUTSET: int = 18
func _add_slot_row(
	parent: Control,
	content: Control,
	top_offset: float,
	hover_triggers: Array
) -> void:
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override(
		"separation", 10 + _SLOT_ARROW_OUTSET
	)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 0.0
	row.anchor_bottom = 1.0
	row.offset_left = -float(_SLOT_ARROW_OUTSET)
	row.offset_right = float(_SLOT_ARROW_OUTSET)
	row.offset_top = top_offset
	row.offset_bottom = 0.0

	var left_arrow := TextureRect.new()
	_configure_menu_arrow(left_arrow, false)
	left_arrow.custom_minimum_size = Vector2(_MENU_ARROW_SIZE)
	left_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_arrow.modulate.a = 0.0
	row.add_child(left_arrow)

	row.add_child(content)

	var right_arrow := TextureRect.new()
	_configure_menu_arrow(right_arrow, true)
	right_arrow.custom_minimum_size = Vector2(_MENU_ARROW_SIZE)
	right_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_arrow.modulate.a = 0.0
	row.add_child(right_arrow)

	# Array statt int, damit die beiden Lambdas unten (deren jeweils
	# EIGENE Kopie einer einfachen lokalen Zahl wäre) sich denselben
	# Zähler teilen - GDScript-Closures fangen ein Array/Objekt per
	# Referenz ein, einen int/bool dagegen per Wert.
	var hover_count: Array = [0]

	var show_arrows := func() -> void:
		hover_count[0] += 1
		left_arrow.modulate.a = 1.0
		right_arrow.modulate.a = 1.0

	var hide_arrows := func() -> void:
		hover_count[0] = max(hover_count[0] - 1, 0)
		if hover_count[0] == 0:
			left_arrow.modulate.a = 0.0
			right_arrow.modulate.a = 0.0

	for trigger in hover_triggers:
		trigger.mouse_entered.connect(show_arrows)
		trigger.mouse_exited.connect(hide_arrows)

	parent.add_child(row)


# glow_rect: das jeweilige "Glow"-TextureRect (siehe
# _build_title_display()/_build_slots_title_display()) - per Parameter
# statt fest verdrahtet, damit dieselbe Pulsier-Animation für JEDEN
# isolierten Titel (Haupttitel, Spielstand-Titel, ...) wiederverwendet
# werden kann.
func _start_title_glow_pulse(glow_rect: TextureRect) -> void:
	var glow_tween: Tween = create_tween()
	glow_tween.set_loops()
	glow_tween.set_trans(Tween.TRANS_SINE)
	glow_tween.set_ease(Tween.EASE_IN_OUT)

	glow_tween.tween_property(
		glow_rect,
		"modulate:a",
		_TITLE_GLOW_MAX_ALPHA,
		_TITLE_GLOW_PULSE_SECONDS
	)
	glow_tween.tween_property(
		glow_rect,
		"modulate:a",
		_TITLE_GLOW_MIN_ALPHA,
		_TITLE_GLOW_PULSE_SECONDS
	)


# Baut den Titel ("TOWER OF ECHOES") als eigenständigen Baum, fest
# oben am Bildschirmrand verankert (set_anchors_preset(PRESET_TOP_WIDE)
# + feste offset_top/offset_bottom) - KEIN CenterContainer, das er sich
# mit den Menü-Buttons teilt. Dadurch kann im Buttons-Bereich
# (_build_main_panel()) beliebig viel wachsen/schrumpfen (z.B. beim
# Hover-Vergrößern eines Buttons), ohne dass sich das hier auch nur
# um einen Pixel auswirkt - der Titel ist komplett isoliert.
func _build_title_display() -> void:
	_title_root = Control.new()
	_title_root.name = "TitleRoot"
	_title_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_root.offset_top = _TITLE_TOP_MARGIN
	_title_root.offset_bottom = _TITLE_TOP_MARGIN + _TITLE_HEIGHT
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_root)

	var title_center := CenterContainer.new()
	_fill_parent_rect(title_center)
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_root.add_child(title_center)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 64)

	# Fallback-Leuchteffekt für den Fall, dass KEIN title_texture-Bild
	# gesetzt ist und stattdessen der reine Textname angezeigt wird -
	# ein weicher, versatzloser Schriftschatten wirkt wie ein Glühen.
	_title_label.add_theme_color_override(
		"font_shadow_color", Color(1.0, 0.85, 0.55, 0.85)
	)
	_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_title_label.add_theme_constant_override("shadow_offset_y", 0)
	_title_label.add_theme_constant_override("shadow_outline_size", 10)
	title_center.add_child(_title_label)

	# Titel-Logo GROSS und für sich allein (kein Kasten drumherum),
	# mit einem weichen, sanft pulsierenden Leucht-Schein dahinter.
	# Die Breite wird erst in _refresh_texts() anhand des tatsäch-
	# lichen Seitenverhältnisses von title_texture gesetzt (ein
	# CenterContainer streckt Kinder anders als eine VBoxContainer
	# NICHT automatisch auf volle Breite).
	_title_container = Control.new()
	_title_container.name = "TitleContainer"
	_title_container.custom_minimum_size = Vector2(0, _TITLE_HEIGHT)
	_title_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_center.add_child(_title_container)

	_title_glow_texture_rect = TextureRect.new()
	_title_glow_texture_rect.name = "TitleGlow"
	_fill_parent_rect(_title_glow_texture_rect)
	_title_glow_texture_rect.expand_mode = (
		TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	)
	_title_glow_texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_title_glow_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_glow_texture_rect.visible = false
	_title_glow_texture_rect.material = _build_title_glow_material()
	_title_glow_texture_rect.modulate = _TITLE_GLOW_COLOR
	_title_glow_texture_rect.scale = Vector2.ONE * _TITLE_GLOW_SCALE
	_title_glow_texture_rect.resized.connect(
		func() -> void:
			_title_glow_texture_rect.pivot_offset = (
				_title_glow_texture_rect.size * 0.5
			)
	)
	_title_container.add_child(_title_glow_texture_rect)

	_title_texture_rect = TextureRect.new()
	_title_texture_rect.name = "TitleTexture"
	_fill_parent_rect(_title_texture_rect)
	_title_texture_rect.expand_mode = (
		TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	)
	_title_texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_title_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_texture_rect.visible = false
	_title_container.add_child(_title_texture_rect)

	_start_title_glow_pulse(_title_glow_texture_rect)


# Wie _build_title_display(), aber für die "SPIELSTAND WÄHLEN"-
# Überschrift über der Spielstand-Auswahl - eigener, unabhängiger
# Baum, damit sie sich beim Hovern über einen der Spielstand-Buttons
# nicht mitbewegt.
func _build_slots_title_display() -> void:
	_slots_title_root = Control.new()
	_slots_title_root.name = "SlotsTitleRoot"
	_slots_title_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_slots_title_root.offset_top = _SLOTS_TITLE_TOP_MARGIN
	_slots_title_root.offset_bottom = (
		_SLOTS_TITLE_TOP_MARGIN + _SLOTS_TITLE_HEIGHT
	)
	_slots_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_title_root.visible = false
	add_child(_slots_title_root)

	var title_center := CenterContainer.new()
	_fill_parent_rect(title_center)
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_title_root.add_child(title_center)

	_slots_title_label = Label.new()
	_slots_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slots_title_label.add_theme_font_size_override("font_size", 40)
	_slots_title_label.add_theme_color_override(
		"font_shadow_color", Color(1.0, 0.85, 0.55, 0.85)
	)
	_slots_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_slots_title_label.add_theme_constant_override("shadow_offset_y", 0)
	_slots_title_label.add_theme_constant_override(
		"shadow_outline_size", 8
	)
	title_center.add_child(_slots_title_label)

	_slots_title_container = Control.new()
	_slots_title_container.name = "SlotsTitleContainer"
	_slots_title_container.custom_minimum_size = Vector2(
		0, _SLOTS_TITLE_HEIGHT
	)
	_slots_title_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_center.add_child(_slots_title_container)

	_slots_title_glow_texture_rect = TextureRect.new()
	_slots_title_glow_texture_rect.name = "SlotsTitleGlow"
	_fill_parent_rect(_slots_title_glow_texture_rect)
	_slots_title_glow_texture_rect.expand_mode = (
		TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	)
	_slots_title_glow_texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_slots_title_glow_texture_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_slots_title_glow_texture_rect.visible = false
	_slots_title_glow_texture_rect.material = _build_title_glow_material()
	_slots_title_glow_texture_rect.modulate = _TITLE_GLOW_COLOR
	_slots_title_glow_texture_rect.scale = (
		Vector2.ONE * _TITLE_GLOW_SCALE
	)
	_slots_title_glow_texture_rect.resized.connect(
		func() -> void:
			_slots_title_glow_texture_rect.pivot_offset = (
				_slots_title_glow_texture_rect.size * 0.5
			)
	)
	_slots_title_container.add_child(_slots_title_glow_texture_rect)

	_slots_title_texture_rect = TextureRect.new()
	_slots_title_texture_rect.name = "SlotsTitleTexture"
	_fill_parent_rect(_slots_title_texture_rect)
	_slots_title_texture_rect.expand_mode = (
		TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	)
	_slots_title_texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_slots_title_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots_title_texture_rect.visible = false
	_slots_title_container.add_child(_slots_title_texture_rect)

	_start_title_glow_pulse(_slots_title_glow_texture_rect)


# Wie _build_slots_title_display(), aber für die
# "EINSTELLUNGEN"/"SETTINGS"-Überschrift über dem Einstellungen-Panel
# - eigener, unabhängiger Baum, damit sie sich beim Hovern über einen
# der Einstellungen-Buttons nicht mitbewegt.
func _build_settings_title_display() -> void:
	_settings_title_root = Control.new()
	_settings_title_root.name = "SettingsTitleRoot"
	_settings_title_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_settings_title_root.offset_top = _SETTINGS_TITLE_TOP_MARGIN
	_settings_title_root.offset_bottom = (
		_SETTINGS_TITLE_TOP_MARGIN + _SETTINGS_TITLE_HEIGHT
	)
	_settings_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_title_root.visible = false
	add_child(_settings_title_root)

	var title_center := CenterContainer.new()
	_fill_parent_rect(title_center)
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_title_root.add_child(title_center)

	_settings_title_label = Label.new()
	_settings_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_settings_title_label.add_theme_font_size_override("font_size", 40)
	_settings_title_label.add_theme_color_override(
		"font_shadow_color", Color(1.0, 0.85, 0.55, 0.85)
	)
	_settings_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_settings_title_label.add_theme_constant_override("shadow_offset_y", 0)
	_settings_title_label.add_theme_constant_override(
		"shadow_outline_size", 8
	)
	title_center.add_child(_settings_title_label)

	_settings_title_container = Control.new()
	_settings_title_container.name = "SettingsTitleContainer"
	_settings_title_container.custom_minimum_size = Vector2(
		0, _SETTINGS_TITLE_HEIGHT
	)
	_settings_title_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_center.add_child(_settings_title_container)

	_settings_title_glow_texture_rect = TextureRect.new()
	_settings_title_glow_texture_rect.name = "SettingsTitleGlow"
	_fill_parent_rect(_settings_title_glow_texture_rect)
	_settings_title_glow_texture_rect.expand_mode = (
		TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	)
	_settings_title_glow_texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_settings_title_glow_texture_rect.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_settings_title_glow_texture_rect.visible = false
	_settings_title_glow_texture_rect.material = (
		_build_title_glow_material()
	)
	_settings_title_glow_texture_rect.modulate = _TITLE_GLOW_COLOR
	_settings_title_glow_texture_rect.scale = (
		Vector2.ONE * _TITLE_GLOW_SCALE
	)
	_settings_title_glow_texture_rect.resized.connect(
		func() -> void:
			_settings_title_glow_texture_rect.pivot_offset = (
				_settings_title_glow_texture_rect.size * 0.5
			)
	)
	_settings_title_container.add_child(_settings_title_glow_texture_rect)

	_settings_title_texture_rect = TextureRect.new()
	_settings_title_texture_rect.name = "SettingsTitleTexture"
	_fill_parent_rect(_settings_title_texture_rect)
	_settings_title_texture_rect.expand_mode = (
		TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	)
	_settings_title_texture_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_settings_title_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_title_texture_rect.visible = false
	_settings_title_container.add_child(_settings_title_texture_rect)

	_start_title_glow_pulse(_settings_title_glow_texture_rect)


func _build_main_panel() -> void:
	# Bewusst OHNE den dunklen Kasten mit Rahmen (siehe _make_panel())
	# - das Hauptmenü soll wie bei "Hollow Knight" direkt frei über
	# dem gemalten Hintergrund schweben.
	_main_panel = _make_borderless_panel()
	_center_container.add_child(_main_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_main_panel.add_child(box)

	_play_button = _make_button()
	_play_button.pressed.connect(_open_slots)
	_add_menu_button_row(box, _play_button)

	_settings_button = _make_button()
	_settings_button.pressed.connect(_open_settings)
	_add_menu_button_row(box, _settings_button)

	# Credits-Button absichtlich NICHT mehr im Hauptmenü sichtbar
	# (auf Wunsch entfernt - Credits sollen stattdessen am Ende des
	# Spiels gezeigt werden). Der Button/das Panel dahinter bleiben
	# im Code bestehen (nur eben nicht mehr in den sichtbaren
	# Baum eingehängt), damit an anderen Stellen (z.B.
	# _refresh_texts, _close_all_panels) weiterhin gefahrlos darauf
	# zugegriffen werden kann, ohne alles umbauen zu müssen.
	_credits_button = _make_button()
	_credits_button.pressed.connect(_open_credits)

	_quit_button = _make_button()
	_quit_button.pressed.connect(_quit_game)
	_add_menu_button_row(box, _quit_button)

	# DEV-MODUS (TEMPORÄR - vor der Demo wieder entfernen!) - bewusst
	# NICHT im neuen Hollow-Knight-Stil (bleibt ein normaler Button),
	# damit er als Debug-Werkzeug klar von den echten Menüpunkten zu
	# unterscheiden ist.
	_dev_button = _make_button()
	_dev_button.text = "[DEV] Raum wählen"
	_dev_button.pressed.connect(_open_dev_panel)
	box.add_child(_dev_button)


func _build_slots_panel() -> void:
	# Auf Wunsch ohne Kasten, genau wie das Hauptmenü selbst.
	_slots_panel = _make_borderless_panel()
	_center_container.add_child(_slots_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(_SLOT_ROW_MIN_WIDTH, 0)
	_slots_panel.add_child(box)

	# Die "Spielstand wählen"-Überschrift steht jetzt NICHT mehr hier
	# in der Box, sondern isoliert oben am Bildschirmrand - siehe
	# _build_slots_title_display().

	_slot_buttons.clear()
	_slot_delete_buttons.clear()
	_slot_area_labels.clear()
	_slot_room_labels.clear()
	_slot_playtime_labels.clear()
	_slot_frame_rects.clear()

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		# Eigenständiger Control (KEIN weiterer VBox-Eintrag) pro
		# Zeile, damit sich die Rahmengrafik (oben, an der Ecke) und
		# der eigentliche Zeileninhalt (weiter unten versetzt, siehe
		# _SLOT_ROW_TOP_OFFSET) überlappen können, statt stur
		# untereinander gestapelt zu werden.
		var wrapper := Control.new()
		wrapper.custom_minimum_size = Vector2(
			_SLOT_ROW_MIN_WIDTH, _SLOT_WRAPPER_HEIGHT
		)
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(wrapper)

		var frame := NinePatchRect.new()
		frame.texture = slot_frame_texture
		frame.anchor_left = 0.0
		frame.anchor_right = 1.0
		frame.anchor_top = 0.0
		frame.anchor_bottom = 0.0
		frame.offset_left = 0.0
		frame.offset_right = 0.0
		frame.offset_top = 0.0
		frame.offset_bottom = _SLOT_FRAME_HEIGHT
		frame.patch_margin_left = _SLOT_FRAME_PATCH_MARGIN_LEFT
		frame.patch_margin_right = _SLOT_FRAME_PATCH_MARGIN_RIGHT
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.texture_filter = (
			CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		)
		wrapper.add_child(frame)
		_slot_frame_rects.append(frame)

		var content := HBoxContainer.new()
		content.add_theme_constant_override("separation", 14)

		var slot_button := _make_button()
		_style_slot_name_button(slot_button)
		slot_button.pressed.connect(
			func() -> void: _on_slot_pressed(slot)
		)
		content.add_child(slot_button)
		_slot_buttons.append(slot_button)

		var area_label := _make_slot_stat_label()
		content.add_child(area_label)
		_slot_area_labels.append(area_label)

		var room_label := _make_slot_stat_label()
		content.add_child(room_label)
		_slot_room_labels.append(room_label)

		# Füll-Abstandshalter: drückt Spielzeit UND den "Löschen"-Link
		# ganz an den rechten Rand, während Name/Gebiet/Raum links
		# davon eng beieinander bleiben.
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(spacer)

		var playtime_label := _make_slot_stat_label()
		content.add_child(playtime_label)
		_slot_playtime_labels.append(playtime_label)

		# Der "Löschen"-Link kommt bewusst als LETZTES Kind - er soll
		# ganz rechts stehen, rechts sogar noch von der Spielzeit.
		var delete_button := _make_button()
		_style_slot_delete_button(delete_button)
		delete_button.pressed.connect(
			func() -> void: _on_slot_delete_pressed(slot)
		)
		content.add_child(delete_button)
		_slot_delete_buttons.append(delete_button)

		_add_slot_row(
			wrapper,
			content,
			_SLOT_ROW_TOP_OFFSET,
			[slot_button, delete_button]
		)

	_slots_back_button = _make_button()
	_slots_back_button.pressed.connect(_close_slots)
	_add_menu_button_row(box, _slots_back_button)


func _build_delete_confirm_panel() -> void:
	_delete_confirm_panel = _make_panel()
	_center_container.add_child(_delete_confirm_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(340, 0)
	_delete_confirm_panel.add_child(box)

	_delete_confirm_title_label = _make_title_label()
	box.add_child(_delete_confirm_title_label)

	_delete_confirm_text_label = Label.new()
	_delete_confirm_text_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_delete_confirm_text_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	box.add_child(_delete_confirm_text_label)

	_delete_confirm_yes_button = _make_button()
	_delete_confirm_yes_button.pressed.connect(_on_delete_confirm_yes)
	box.add_child(_delete_confirm_yes_button)

	_delete_confirm_no_button = _make_button()
	_delete_confirm_no_button.pressed.connect(_on_delete_confirm_no)
	box.add_child(_delete_confirm_no_button)


# ============================================================
# DEV-MODUS (TEMPORÄR - vor der Demo wieder komplett entfernen!)
# ============================================================

# Liste aller Räume, in denen man direkt spawnen kann: die 7
# normalen Level, der Shop-Raum, der Mini-Boss-Raum und der
# Boss-Raum - dieselben Pfad-Konstanten, die RunState auch für
# den normalen Run-Aufbau benutzt (Game/run_state.gd).
func _get_dev_room_list() -> Array:
	if get_node_or_null("/root/RunState") == null:
		return []

	var rooms: Array = []

	for i in range(RunState.NORMAL_ROOM_PATHS.size()):
		rooms.append({
			"label": "Level " + str(i + 1),
			"path": RunState.NORMAL_ROOM_PATHS[i]
		})

	rooms.append({
		"label": "Shop",
		"path": RunState.SHOP_ROOM_PATH
	})

	rooms.append({
		"label": "Mini-Boss",
		"path": RunState.MINIBOSS_ROOM_PATH
	})

	rooms.append({
		"label": "Boss",
		"path": RunState.BOSS_ROOM_PATH
	})

	# Kein Teil des normalen Run-Aufbaus (room_order) - nur über die
	# Flammen-Echo-Tür im Bossraum erreichbar (siehe Objects/Doors/
	# Echo Doors/Flame Echo/flame_echo_door.gd -> next_room_path).
	# Zum schnellen Testen hier zusätzlich direkt anwählbar.
	rooms.append({
		"label": "Skill-Tree",
		"path": "res://Levels/Gebiet 1/skill_tree_room.tscn"
	})

	# Nutzer-Wunsch: Testraum für Gebiet 2, ebenfalls kein Teil von
	# room_order - der Spieler spawnt dort über den "PlayerSpawn"-
	# Marker (Levels/room_manager.gd -> _enter_at_normal_spawn()),
	# genau wie bei jedem anderen Raum ohne SpawnDoor-Eintritt.
	rooms.append({
		"label": "Test Raum Verlies",
		"path": "res://Levels/Gebiet 2/Test/Raum1.tscn"
	})

	return rooms


func _build_dev_panel() -> void:
	_dev_panel = _make_panel()
	_center_container.add_child(_dev_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(340, 0)
	_dev_panel.add_child(box)

	_dev_title_label = _make_title_label()
	_dev_title_label.text = "[DEV] Raum wählen"
	box.add_child(_dev_title_label)

	_dev_rooms_scroll = ScrollContainer.new()
	_dev_rooms_scroll.custom_minimum_size = Vector2(320, 320)

	_dev_rooms_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)

	box.add_child(_dev_rooms_scroll)

	_dev_rooms_list = VBoxContainer.new()
	_dev_rooms_list.add_theme_constant_override("separation", 6)
	_dev_rooms_list.custom_minimum_size = Vector2(300, 0)
	_dev_rooms_scroll.add_child(_dev_rooms_list)

	_dev_room_buttons.clear()

	for room_entry in _get_dev_room_list():
		var room_path: String = str(room_entry.get("path", ""))

		var room_button := _make_button()
		room_button.text = str(room_entry.get("label", "?"))
		room_button.pressed.connect(
			func() -> void: _on_dev_room_selected(room_path)
		)

		_dev_rooms_list.add_child(room_button)
		_dev_room_buttons.append(room_button)

	_dev_back_button = _make_button()
	_dev_back_button.text = "Zurück"
	_dev_back_button.pressed.connect(_close_dev_panel)
	box.add_child(_dev_back_button)


func _open_dev_panel() -> void:
	_close_all_panels()

	_dev_panel.visible = true


func _close_dev_panel() -> void:
	_dev_panel.visible = false

	_main_panel.visible = true


# Setzt einen frischen Test-Run auf und springt direkt in den
# gewählten Raum, ohne die vorherigen Räume zu durchspielen.
# current_save_slot bleibt bewusst auf -1 (kein Spielstand), damit
# "Speichern" im Pause-Menü während eines Dev-Tests keinen echten
# Spielstand überschreiben kann.
func _on_dev_room_selected(room_path: String) -> void:
	if room_path.is_empty():
		return

	if get_node_or_null("/root/RunState") == null:
		return

	if not ResourceLoader.exists(room_path):
		push_warning(
			"MainMenu (Dev): Raumdatei fehlt: " + room_path
		)
		return

	RunState.start_new_run()
	RunState.set_active_save_slot(-1)

	# Dieselben Aufräumarbeiten wie beim normalen Einstieg über
	# einen Spielstand (_on_slot_pressed()) - sonst bleiben z.B.
	# "Boss schon besiegt"/"Rückkehr-Spawn"-Flags von einem
	# vorherigen Dev-Test static über den Szenenwechsel hinweg
	# bestehen (RoomManager-Werte sind static var, werden NICHT
	# von RunState.start_new_run() zurückgesetzt) und die
	# Hauptmenü-Musik faded nicht aus.
	RoomManager.boss_defeated_in_current_run = false
	RoomManager.return_to_spawn_name = ""

	if get_node_or_null("/root/MusicManager") != null:
		MusicManager.fade_out_and_stop()
		MusicManager.play_area_music(RunState.START_AREA)

	if not RunState.sync_room_index_from_path(room_path):
		push_warning(
			"MainMenu (Dev): Raum nicht in room_order gefunden: "
			+ room_path
		)

	get_tree().change_scene_to_file(room_path)


func _build_settings_panel() -> void:
	# Auf Wunsch ohne Kasten, genau wie das Hauptmenü selbst.
	#
	# Diese Seite zeigt jetzt nur noch die drei kurzen Oberkategorie-
	# Buttons (statt der früher sehr langen Einstellungen-Liste) - darum
	# jetzt ganz normal in _center_container wie die anderen Kategorie-
	# Seiten, statt fest unterhalb der Überschrift verankert. Bei nur
	# vier Buttons ist die Box klein genug, dass sie beim Zentrieren auf
	# dem ganzen Bildschirm nicht mehr in die Nähe der isolierten
	# "Einstellungen"-Überschrift kommt (siehe
	# _build_settings_title_display()).
	_settings_panel = _make_borderless_panel()
	_center_container.add_child(_settings_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(360, 0)
	_settings_panel.add_child(box)

	# Die "Einstellungen"-Überschrift steht jetzt NICHT mehr hier in der
	# Box, sondern isoliert oben am Bildschirmrand - siehe
	# _build_settings_title_display().
	#
	# Diese Seite zeigt jetzt NUR noch die drei Oberkategorien - die
	# tatsächlich einstellbaren Werte stecken in _build_game_options_
	# panel()/_build_audio_panel()/_build_controls_panel() weiter unten,
	# jede mit eigenem "Zurücksetzen" (nur für diese eine Kategorie).

	_game_options_category_button = _make_button()
	_game_options_category_button.pressed.connect(_open_game_options)
	_add_menu_button_row(box, _game_options_category_button)

	_audio_category_button = _make_button()
	_audio_category_button.pressed.connect(_open_audio_settings)
	_add_menu_button_row(box, _audio_category_button)

	_controls_category_button = _make_button()
	_controls_category_button.pressed.connect(_open_controls_settings)
	_add_menu_button_row(box, _controls_category_button)

	_settings_list_back_button = _make_button()
	_settings_list_back_button.pressed.connect(_close_settings)
	_add_menu_button_row(box, _settings_list_back_button)


# Kategorie "Spieloptionen": Sprache, UI-Größe, Vollbild. Eigene
# zentrierte Seite wie _build_credits_panel(), mit normalem Text-
# Titel statt einer eigenen Titel-Grafik (die gibt es für die drei
# Unterkategorien nicht, nur für die "Einstellungen"-Übersicht
# selbst - siehe _build_settings_title_display()).
func _build_game_options_panel() -> void:
	_game_options_panel = _make_borderless_panel()
	_center_container.add_child(_game_options_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(360, 0)
	_game_options_panel.add_child(box)

	_game_options_title_label = _make_title_label()
	box.add_child(_game_options_title_label)

	_language_tab_label = _make_section_label()
	box.add_child(_language_tab_label)

	var language_row := HBoxContainer.new()
	language_row.alignment = BoxContainer.ALIGNMENT_CENTER
	language_row.add_theme_constant_override("separation", 8)
	box.add_child(language_row)

	_language_de_button = _make_button()
	_language_de_button.text = "Deutsch"
	_language_de_button.pressed.connect(
		func() -> void: _set_language("de")
	)
	language_row.add_child(_language_de_button)

	_language_en_button = _make_button()
	_language_en_button.text = "English"
	_language_en_button.pressed.connect(
		func() -> void: _set_language("en")
	)
	language_row.add_child(_language_en_button)

	_hud_scale_tab_label = _make_section_label()
	box.add_child(_hud_scale_tab_label)

	# 2 Spalten statt einer langen Liste, damit bei immer mehr
	# Einträgen (Skill-Ring, Skill-Slot, Vigor-Leiste, ...) genug
	# Platz bleibt, ohne dass die Liste beliebig nach unten wächst -
	# füllt sich zeilenweise (Reihenfolge = HUD_SCALE_CATEGORIES in
	# Game/settings_manager.gd), also z.B. "Potions" direkt neben
	# "Hearts" in derselben Zeile.
	_hud_scale_list = GridContainer.new()
	_hud_scale_list.columns = 2
	_hud_scale_list.add_theme_constant_override("h_separation", 24)
	_hud_scale_list.add_theme_constant_override("v_separation", 4)
	box.add_child(_hud_scale_list)

	_display_tab_label = _make_section_label()
	box.add_child(_display_tab_label)

	_fullscreen_checkbox = CheckBox.new()
	_fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	box.add_child(_fullscreen_checkbox)

	_game_options_reset_button = _make_button()
	_game_options_reset_button.pressed.connect(
		_on_reset_game_options_pressed
	)
	_add_menu_button_row(box, _game_options_reset_button)

	_game_options_back_button = _make_button()
	_game_options_back_button.pressed.connect(_close_game_options)
	_add_menu_button_row(box, _game_options_back_button)


# Kategorie "Audio": Gesamtlautstärke, Musik.
func _build_audio_panel() -> void:
	_audio_panel = _make_borderless_panel()
	_center_container.add_child(_audio_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(320, 0)
	_audio_panel.add_child(box)

	_audio_title_label = _make_title_label()
	box.add_child(_audio_title_label)

	_audio_tab_label = _make_section_label()
	box.add_child(_audio_tab_label)

	_audio_settings_list = VBoxContainer.new()
	_audio_settings_list.add_theme_constant_override("separation", 4)
	box.add_child(_audio_settings_list)

	_audio_reset_button = _make_button()
	_audio_reset_button.pressed.connect(_on_reset_audio_pressed)
	_add_menu_button_row(box, _audio_reset_button)

	_audio_back_button = _make_button()
	_audio_back_button.pressed.connect(_close_audio_settings)
	_add_menu_button_row(box, _audio_back_button)


# Kategorie "Steuerung": Tastenbelegung.
func _build_controls_panel() -> void:
	_controls_panel = _make_borderless_panel()
	_center_container.add_child(_controls_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(360, 0)
	_controls_panel.add_child(box)

	_controls_title_label = _make_title_label()
	box.add_child(_controls_title_label)

	# GridContainer statt einer HBoxContainer-Reihe pro Zeile, damit
	# Name/Taste/Rebind-Button über ALLE Zeilen hinweg exakt
	# untereinander ausgerichtet sind - eine GridContainer-Spalte ist
	# immer so breit wie der längste Eintrag DIESER Spalte in der
	# GESAMTEN Liste, statt dass jede Zeile für sich ihre eigene
	# Breite hätte (dadurch würde z.B. "Drop through platform" die
	# Spalten dieser einen Zeile nach rechts verschieben, siehe
	# _refresh_controls_list()).
	_controls_list = GridContainer.new()
	_controls_list.columns = 3
	_controls_list.add_theme_constant_override("h_separation", 8)
	_controls_list.add_theme_constant_override("v_separation", 4)
	box.add_child(_controls_list)

	_controls_reset_button = _make_button()
	_controls_reset_button.pressed.connect(_on_reset_controls_pressed)
	_add_menu_button_row(box, _controls_reset_button)

	_controls_back_button = _make_button()
	_controls_back_button.pressed.connect(_close_controls_settings)
	_add_menu_button_row(box, _controls_back_button)


func _build_credits_panel() -> void:
	_credits_panel = _make_borderless_panel()
	_center_container.add_child(_credits_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(340, 0)
	_credits_panel.add_child(box)

	_credits_title_label = _make_title_label()
	box.add_child(_credits_title_label)

	_credits_body_label = Label.new()
	_credits_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_credits_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_credits_body_label)

	_credits_back_button = _make_button()
	_credits_back_button.pressed.connect(_close_credits)
	box.add_child(_credits_back_button)


# ============================================================
# UI-BAUSTEINE
# ============================================================

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()

	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	style.border_color = Color(0.85, 0.85, 0.85, 0.85)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

	return panel


# Wie _make_panel(), aber komplett ohne sichtbaren Hintergrund/Rahmen
# - für das Hauptmenü selbst (siehe _build_main_panel()), das anders
# als die Unter-Panels (Spielstände, Einstellungen, Credits, ...)
# frei über dem Hintergrundbild schweben soll. MOUSE_FILTER_PASS statt
# MOUSE_FILTER_STOP, damit Klicke in den (jetzt unsichtbaren) Bereich
# zwischen den Menüpunkten ganz normal zum Hintergrund durchgereicht
# werden, statt von einem unsichtbaren Kasten "verschluckt" zu werden.
func _make_borderless_panel() -> PanelContainer:
	var panel := PanelContainer.new()

	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	return panel


func _make_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(260, 34)
	return button


func _make_title_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	return label


func _make_section_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_color_override(
		"font_color",
		Color(1.0, 1.0, 1.0, 1.0)
	)
	return label


# ============================================================
# SPIELSTAND-SLOTS
# ============================================================

func _refresh_slots() -> void:
	if get_node_or_null("/root/SaveManager") == null:
		return

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var index: int = slot - 1

		var slot_button: Button = _slot_buttons[index]
		var delete_button: Button = _slot_delete_buttons[index]
		var area_label: Label = _slot_area_labels[index]
		var room_label: Label = _slot_room_labels[index]
		var playtime_label: Label = _slot_playtime_labels[index]

		var summary: Dictionary = SaveManager.peek_save_summary(slot)
		var has_save: bool = not summary.is_empty()

		if has_save:
			slot_button.text = "Slot " + str(slot)

			area_label.text = String(
				SettingsManager.t("menu.area")
			) % int(summary.get("area", 1))

			room_label.text = String(
				SettingsManager.t("menu.room")
			) % int(summary.get("room_number", 1))

			var playtime_text: String = _format_playtime(
				float(summary.get("playtime_seconds", 0.0))
			)

			playtime_label.text = (
				SettingsManager.t("menu.playtime")
				+ ": "
				+ playtime_text
			)
		else:
			slot_button.text = (
				"Slot "
				+ str(slot)
				+ " - "
				+ SettingsManager.t("menu.new_game")
			)

		delete_button.visible = has_save
		area_label.visible = has_save
		room_label.visible = has_save
		playtime_label.visible = has_save


func _on_slot_pressed(slot: int) -> void:
	if get_node_or_null("/root/SaveManager") == null:
		return

	# Gebiets-Intro ("GEBIET 1 - DIE EINGANGSHALLEN") soll NUR beim
	# Einstieg über einen Spielstand hier im Hauptmenü erscheinen -
	# nicht bei einem Tod-Neustart mitten im Lauf (der läuft über
	# RoomManager.reset_run(), setzt dieses Flag bewusst nicht).
	# room_manager.gd zeigt es dann tatsächlich nur an, wenn der
	# gerade betretene Raum auch wirklich Raum 1 ist.
	if get_node_or_null("/root/RunState") != null:
		RunState.show_area_intro_pending = true

	# Hauptmenü-Musik langsam ausfaden statt hart abzuschneiden -
	# der MusicManager-Autoload läuft auch nach dem Szenenwechsel
	# weiter und klingt im Hintergrund sauber aus. Gleichzeitig
	# fadet die Gebiets-Hintergrundmusik ein (aktuell nur Gebiet 1)
	# und loopt von da an die ganze Zeit weiter.
	if get_node_or_null("/root/MusicManager") != null:
		MusicManager.fade_out_and_stop()
		MusicManager.play_area_music(RunState.START_AREA)

	if SaveManager.has_save_file(slot):
		SaveManager.load_and_enter_saved_room(slot)
		return

	if get_node_or_null("/root/RunState") == null:
		return

	RunState.start_new_run()
	RunState.set_active_save_slot(slot)

	var room_path: String = RunState.get_current_room_path()

	if room_path.is_empty():
		return

	get_tree().change_scene_to_file(room_path)


func _format_playtime(seconds: float) -> String:
	var total_seconds: int = int(seconds)
	var hours: int = total_seconds / 3600
	var minutes: int = (total_seconds % 3600) / 60
	var secs: int = total_seconds % 60

	return "%02d:%02d:%02d" % [hours, minutes, secs]


# ============================================================
# EINSTELLUNGEN - STEUERUNG
# ============================================================

func _refresh_controls_list() -> void:
	for child in _controls_list.get_children():
		child.queue_free()

	_action_rows.clear()

	if get_node_or_null("/root/SettingsManager") == null:
		return

	for action_name in SettingsManager.REBINDABLE_ACTIONS:
		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(140, 0)
		name_label.text = SettingsManager.get_action_display_name(
			action_name
		)
		_controls_list.add_child(name_label)

		var binding_label := Label.new()
		binding_label.custom_minimum_size = Vector2(110, 0)
		binding_label.add_theme_color_override(
			"font_color",
			Color(0.6, 0.85, 1.0, 1.0)
		)

		if action_name == _listening_action:
			binding_label.text = SettingsManager.t(
				"settings.press_key"
			)
		else:
			binding_label.text = SettingsManager.get_binding_text(
				action_name
			)

		_controls_list.add_child(binding_label)

		var rebind_button := Button.new()
		rebind_button.text = SettingsManager.t("settings.rebind")
		rebind_button.custom_minimum_size = Vector2(80, 0)
		rebind_button.disabled = _listening_action != &""
		rebind_button.pressed.connect(
			func() -> void: _start_listening(action_name)
		)
		_controls_list.add_child(rebind_button)

		_action_rows[action_name] = {
			"name_label": name_label,
			"binding_label": binding_label,
			"rebind_button": rebind_button
		}


func _start_listening(action_name: StringName) -> void:
	if _listening_action != &"":
		return

	_listening_action = action_name

	_refresh_controls_list()


func _finish_listening(event: InputEvent) -> void:
	var action_name: StringName = _listening_action

	_listening_action = &""

	if action_name == &"":
		return

	if get_node_or_null("/root/SettingsManager") != null:
		SettingsManager.rebind_action(action_name, event)

	_refresh_controls_list()


func _cancel_listening() -> void:
	_listening_action = &""

	_refresh_controls_list()


# ============================================================
# EINSTELLUNGEN - UI-GRÖSSE
# ============================================================

func _refresh_hud_scale_list() -> void:
	for child in _hud_scale_list.get_children():
		child.queue_free()

	if get_node_or_null("/root/SettingsManager") == null:
		return

	for category in SettingsManager.HUD_SCALE_CATEGORIES:
		# "echo_der_flamme" (und später weitere Boss-Echos) sollen
		# hier erst auftauchen, nachdem man das jeweilige Echo
		# tatsächlich erhalten hat - vorher gibt es für den Spieler
		# ja noch gar nichts zu vergrößern/verkleinern.
		if category == &"echo_der_flamme":
			var has_echo: bool = (
				get_node_or_null("/root/RunState") != null
				and RunState.has_echo(&"echo_der_flamme")
			)

			if not has_echo:
				continue

		# "skill_ring" soll hier erst auftauchen, nachdem man einen
		# Skill-Pfad gewählt hat - genau wie bei "echo_der_flamme"
		# oben gibt es vorher nichts, was der Spieler vergrößern/
		# verkleinern könnte.
		if category == &"skill_ring":
			var has_skill_path: bool = (
				get_node_or_null("/root/RunState") != null
				and RunState.has_chosen_skill_path()
			)

			if not has_skill_path:
				continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_hud_scale_list.add_child(row)

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(100, 0)
		name_label.text = SettingsManager.t(
			"hudscale." + String(category)
		)
		row.add_child(name_label)

		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(120, 0)
		slider.min_value = SettingsManager.HUD_SCALE_MIN
		slider.max_value = SettingsManager.HUD_SCALE_MAX
		slider.step = SettingsManager.HUD_SCALE_STEP
		slider.value = SettingsManager.get_hud_scale(category)
		row.add_child(slider)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(44, 0)
		value_label.text = _format_hud_scale(slider.value)
		row.add_child(value_label)

		slider.value_changed.connect(
			func(new_value: float) -> void:
				SettingsManager.set_hud_scale(category, new_value)
				value_label.text = _format_hud_scale(new_value)
		)


func _format_hud_scale(value: float) -> String:
	return str(int(round(value * 100.0))) + "%"


# ============================================================
# EINSTELLUNGEN - AUDIO / LAUTSTÄRKE
# ============================================================

# Baut die Liste der Lautstärke-Regler auf - iteriert bewusst über
# SettingsManager.AUDIO_BUS_CATEGORIES, damit spätere Kategorien
# (Enemy-Sounds, Player-Sounds, ...) automatisch hier auftauchen,
# sobald sie dort ergänzt werden - ohne weitere Änderungen an dieser
# Funktion.
func _refresh_audio_settings_list() -> void:
	for child in _audio_settings_list.get_children():
		child.queue_free()

	if get_node_or_null("/root/SettingsManager") == null:
		return

	for category in SettingsManager.AUDIO_BUS_CATEGORIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_audio_settings_list.add_child(row)

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(100, 0)
		name_label.text = SettingsManager.t(
			"audio." + String(category)
		)
		row.add_child(name_label)

		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(120, 0)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = SettingsManager.get_audio_volume(category)
		row.add_child(slider)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(44, 0)
		value_label.text = _format_audio_volume(slider.value)
		row.add_child(value_label)

		slider.value_changed.connect(
			func(new_value: float) -> void:
				SettingsManager.set_audio_volume(category, new_value)
				value_label.text = _format_audio_volume(new_value)
		)


func _format_audio_volume(value: float) -> String:
	return str(int(round(value * 100.0))) + "%"


# ============================================================
# EINSTELLUNGEN - ANZEIGE (VOLLBILD)
# ============================================================

func _refresh_display_settings() -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	_fullscreen_checkbox.button_pressed = (
		SettingsManager.get_fullscreen()
	)


func _on_fullscreen_toggled(pressed: bool) -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	SettingsManager.set_fullscreen(pressed)


# ============================================================
# EINSTELLUNGEN - AUF STANDARD ZURÜCKSETZEN (PRO KATEGORIE)
# ============================================================

# Jede Kategorie-Seite hat ihren EIGENEN Zurücksetzen-Button, der
# auch nur die Werte DIESER Kategorie zurücksetzt - siehe
# SettingsManager.reset_game_options()/reset_audio()/
# reset_controls().
func _on_reset_game_options_pressed() -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	SettingsManager.reset_game_options()

	_refresh_texts()
	_refresh_hud_scale_list()
	_refresh_display_settings()


func _on_reset_audio_pressed() -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	SettingsManager.reset_audio()

	_refresh_audio_settings_list()


func _on_reset_controls_pressed() -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	SettingsManager.reset_controls()

	_refresh_controls_list()


# ============================================================
# EINSTELLUNGEN - SPRACHE
# ============================================================

func _set_language(language: String) -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	SettingsManager.set_language(language)


func _on_language_changed(_language: String) -> void:
	_refresh_texts()
	_refresh_controls_list()
	_refresh_hud_scale_list()
	_refresh_audio_settings_list()
	_refresh_display_settings()
	_refresh_slots()


# ============================================================
# PANEL-NAVIGATION
# ============================================================

func _close_all_panels() -> void:
	_main_panel.visible = false
	_slots_panel.visible = false
	_settings_panel.visible = false
	_game_options_panel.visible = false
	_audio_panel.visible = false
	_controls_panel.visible = false
	_credits_panel.visible = false
	_delete_confirm_panel.visible = false
	_dev_panel.visible = false

	_cancel_listening()


func _open_slots() -> void:
	_close_all_panels()

	_refresh_slots()

	_slots_panel.visible = true


func _close_slots() -> void:
	_slots_panel.visible = false

	_main_panel.visible = true


# ============================================================
# SPIELSTAND LÖSCHEN
# ============================================================

# Wird jetzt direkt vom "Spielstand löschen"-Link in der jeweiligen
# Spielstand-Zeile ausgelöst (siehe _build_slots_panel()) - die
# separate "Welchen Spielstand löschen?"-Auswahl-Seite ist damit
# überflüssig geworden und wurde entfernt. Der eigentliche Bestätigen-
# Dialog (_delete_confirm_panel) bleibt unverändert: er kehrt so oder
# so zu _slots_panel zurück, egal von wo er geöffnet wurde.
func _on_slot_delete_pressed(slot: int) -> void:
	if get_node_or_null("/root/SaveManager") == null:
		return

	if not SaveManager.has_save_file(slot):
		return

	_slot_pending_delete = slot

	_close_all_panels()

	_delete_confirm_panel.visible = true


func _on_delete_confirm_yes() -> void:
	if _slot_pending_delete == -1:
		return

	if get_node_or_null("/root/SaveManager") != null:
		SaveManager.delete_save(_slot_pending_delete)

	_slot_pending_delete = -1

	_close_all_panels()

	_refresh_slots()

	_slots_panel.visible = true


func _on_delete_confirm_no() -> void:
	_slot_pending_delete = -1

	_close_all_panels()

	_slots_panel.visible = true


func _open_settings() -> void:
	_close_all_panels()

	_settings_panel.visible = true


func _close_settings() -> void:
	_settings_panel.visible = false

	_main_panel.visible = true


func _open_game_options() -> void:
	_close_all_panels()

	_game_options_panel.visible = true

	_refresh_hud_scale_list()
	_refresh_display_settings()


func _close_game_options() -> void:
	_game_options_panel.visible = false

	_settings_panel.visible = true


func _open_audio_settings() -> void:
	_close_all_panels()

	_audio_panel.visible = true

	_refresh_audio_settings_list()


func _close_audio_settings() -> void:
	_audio_panel.visible = false

	_settings_panel.visible = true


func _open_controls_settings() -> void:
	_close_all_panels()

	_controls_panel.visible = true

	_refresh_controls_list()


func _close_controls_settings() -> void:
	_controls_panel.visible = false
	_cancel_listening()

	_settings_panel.visible = true


func _open_credits() -> void:
	_close_all_panels()

	_credits_panel.visible = true


func _close_credits() -> void:
	_credits_panel.visible = false

	_main_panel.visible = true


func _quit_game() -> void:
	get_tree().quit()


# ============================================================
# TEXTE
# ============================================================

# Aktualisiert einen isolierten "schwebenden Titel" (siehe
# _build_title_display()/_build_slots_title_display()): zeigt das
# Bild an, falls eines gesetzt ist (und skaliert seinen Container
# anhand des echten Seitenverhältnisses auf die feste Höhe), sonst
# den reinen Text als Fallback. Wiederverwendet für den Haupttitel UND
# die "Spielstand wählen"-Überschrift, damit beide garantiert exakt
# gleich funktionieren.
func _apply_floating_title(
	texture: Texture2D,
	fallback_text: String,
	label: Label,
	texture_rect: TextureRect,
	glow_rect: TextureRect,
	container: Control,
	height: float
) -> void:
	label.text = fallback_text
	label.visible = texture == null

	texture_rect.texture = texture
	texture_rect.visible = texture != null

	glow_rect.texture = texture
	glow_rect.visible = texture != null

	if texture != null:
		var texture_size: Vector2 = texture.get_size()
		var aspect_ratio: float = (
			texture_size.x / max(texture_size.y, 1.0)
		)

		container.custom_minimum_size = Vector2(
			height * aspect_ratio, height
		)
	else:
		container.custom_minimum_size = Vector2(0, height)


func _refresh_texts() -> void:
	_apply_floating_title(
		title_texture,
		game_title,
		_title_label,
		_title_texture_rect,
		_title_glow_texture_rect,
		_title_container,
		_TITLE_HEIGHT
	)

	_version_label.text = version_text

	if get_node_or_null("/root/SettingsManager") == null:
		return

	_play_button.text = SettingsManager.t("menu.play")
	_settings_button.text = SettingsManager.t("menu.settings")
	_credits_button.text = SettingsManager.t("menu.credits")
	_quit_button.text = SettingsManager.t("menu.quit")

	# slots_title_texture zeigt den DEUTSCHEN Schriftzug ("Spielstand
	# wählen"), slots_title_texture_en die englische Version ("Select
	# Save") - je nach aktueller Sprache wird die passende Textur
	# gewählt. Bleibt für eine Sprache kein Bild gesetzt, fällt
	# _apply_floating_title() automatisch auf den echten, übersetzten
	# Text zurück (texture == null -> fallback_text). Wechselt die
	# Sprache also hin und her, wechselt automatisch mit ihr auch die
	# Anzeige hier.
	var slots_title_texture_for_language: Texture2D = (
		slots_title_texture_en
		if SettingsManager.get_language() == "en"
		else slots_title_texture
	)

	_apply_floating_title(
		slots_title_texture_for_language,
		SettingsManager.t("menu.slot_title"),
		_slots_title_label,
		_slots_title_texture_rect,
		_slots_title_glow_texture_rect,
		_slots_title_container,
		_SLOTS_TITLE_HEIGHT
	)

	_slots_back_button.text = SettingsManager.t("menu.back")

	for delete_button in _slot_delete_buttons:
		delete_button.text = SettingsManager.t("menu.delete_save")

	# Genau dasselbe Prinzip wie bei slots_title_texture oben: je nach
	# aktueller Sprache wird das passende Logo gewählt, fehlt eines,
	# fällt _apply_floating_title() automatisch auf den echten,
	# übersetzten Text zurück.
	var settings_title_texture_for_language: Texture2D = (
		settings_title_texture_en
		if SettingsManager.get_language() == "en"
		else settings_title_texture
	)

	_apply_floating_title(
		settings_title_texture_for_language,
		SettingsManager.t("settings.title"),
		_settings_title_label,
		_settings_title_texture_rect,
		_settings_title_glow_texture_rect,
		_settings_title_container,
		_SETTINGS_TITLE_HEIGHT
	)

	_game_options_category_button.text = SettingsManager.t(
		"settings.category_game_options"
	)

	_audio_category_button.text = SettingsManager.t(
		"settings.category_audio"
	)

	_controls_category_button.text = SettingsManager.t(
		"settings.category_controls"
	)

	_settings_list_back_button.text = SettingsManager.t(
		"settings.back"
	)

	_game_options_title_label.text = SettingsManager.t(
		"settings.category_game_options"
	)

	_language_tab_label.text = SettingsManager.t(
		"settings.language_tab"
	)

	_hud_scale_tab_label.text = SettingsManager.t(
		"settings.hud_scale_tab"
	)

	_display_tab_label.text = SettingsManager.t(
		"settings.display_tab"
	)

	_fullscreen_checkbox.text = SettingsManager.t(
		"settings.fullscreen"
	)

	_game_options_reset_button.text = SettingsManager.t(
		"settings.reset"
	)

	_game_options_back_button.text = SettingsManager.t(
		"settings.back"
	)

	_audio_title_label.text = SettingsManager.t(
		"settings.category_audio"
	)

	_audio_tab_label.text = SettingsManager.t(
		"settings.audio_tab"
	)

	_audio_reset_button.text = SettingsManager.t(
		"settings.reset"
	)

	_audio_back_button.text = SettingsManager.t(
		"settings.back"
	)

	_controls_title_label.text = SettingsManager.t(
		"settings.category_controls"
	)

	_controls_reset_button.text = SettingsManager.t(
		"settings.reset"
	)

	_controls_back_button.text = SettingsManager.t(
		"settings.back"
	)

	_delete_confirm_title_label.text = SettingsManager.t(
		"menu.delete_confirm_title"
	)

	_delete_confirm_text_label.text = SettingsManager.t(
		"menu.delete_confirm_text"
	)

	_delete_confirm_yes_button.text = SettingsManager.t(
		"menu.delete_confirm_yes"
	)

	_delete_confirm_no_button.text = SettingsManager.t(
		"menu.delete_confirm_no"
	)

	_language_de_button.disabled = (
		SettingsManager.get_language() == "de"
	)

	_language_en_button.disabled = (
		SettingsManager.get_language() == "en"
	)

	# Zeigt den Spieltitel statt des generischen Worts "Credits",
	# damit es wie eine richtige Abspann-Seite aussieht (Titel,
	# dann "Created by", dann die Rollen).
	_credits_title_label.text = game_title

	_credits_body_label.text = (
		credits_body_override
		if not credits_body_override.is_empty()
		else SettingsManager.t("menu.credits_body")
	)

	_credits_back_button.text = SettingsManager.t("menu.back")
