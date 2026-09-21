extends CanvasLayer


# ============================================================
# HINWEIS
# ============================================================

# Persistentes Autoload-Pause-Menü: wird einmal beim Spielstart
# erzeugt und bleibt über alle Räume hinweg erhalten. Die
# komplette Oberfläche wird hier per Code gebaut (kein eigenes
# .tscn), damit sie unabhängig vom jeweiligen Raum funktioniert
# und nicht in jede Level-Szene eingebaut werden muss.
#
# WICHTIG: get_tree().paused friert automatisch alle Nodes ein,
# die nicht auf PROCESS_MODE_ALWAYS stehen - Gegner, Timer,
# Animationen. EIN Sonderfall im Projekt: await
# get_tree().create_timer(...) läuft laut Godot-Standard
# (process_always=true) auch WÄHREND der Pause weiter (z.B. der
# Angriffs-Cooldown eines Gegners tickt im Hintergrund kurz
# weiter). Für die allermeisten Fälle unkritisch, aber falls das
# irgendwo visuell auffällt: das ist der Grund.


const ESC_ACTION: StringName = &"ui_cancel"

# Skaliert alle Panels (Haupt-, Einstellungen-Kategorien-Übersicht,
# die drei Einstellungen-Kategorie-Seiten, Bestätigen-Panel)
# einheitlich hoch, statt jede einzelne Schriftgröße/Abstand im Code
# anzupassen. Bleibt dabei über pivot_offset immer exakt in der
# Bildschirmmitte zentriert - auch wenn sich die Panel-Größe durch
# Inhalt ändert (z.B. längere Steuerungsliste nach Rebind, anderer
# Sprachtext), siehe _on_scaled_panel_resized().
const PAUSE_PANEL_SCALE: float = 1.3


# ============================================================
# STATUS
# ============================================================

var _is_open: bool = false
var _listening_action: StringName = &""


# ============================================================
# NODES (per Code gebaut)
# ============================================================

var _root: Control
var _background: ColorRect
var _center_container: CenterContainer

var _main_panel: PanelContainer
var _title_label: Label
var _resume_button: Button
var _settings_button: Button
var _save_button: Button
var _main_menu_button: Button

# TEMPORÄRER TEST-BUTTON - siehe _build_main_panel()/
# _on_debug_add_skill_point_pressed() und RunState.
# debug_add_skill_point() weiter unten. Wieder komplett entfernen,
# sobald der Skill-Baum nicht mehr getestet werden muss.
var _debug_skill_point_button: Button

var _toast_label: Label

# Einstellungen sind jetzt zweistufig: erst eine Kategorie-
# Übersicht (_settings_panel), dann pro Kategorie eine eigene Seite
# mit den tatsächlich einstellbaren Werten plus "Zurücksetzen"
# (nur für diese eine Kategorie) und "Zurück" (zur Kategorie-
# Übersicht). Siehe _build_settings_category_list() und die drei
# _build_*_panel()-Funktionen weiter unten.

# Kategorie-Übersicht.
var _settings_panel: PanelContainer
var _settings_title_label: Label
var _game_options_category_button: Button
var _audio_category_button: Button
var _controls_category_button: Button
var _settings_list_back_button: Button

# Kategorie "Spieloptionen" (Sprache, UI-Größe, Vollbild).
var _game_options_panel: PanelContainer
var _game_options_title_label: Label
var _language_tab_label: Label
var _language_de_button: Button
var _language_en_button: Button
var _hud_scale_tab_label: Label
var _hud_scale_list: VBoxContainer
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

var _confirm_panel: PanelContainer
var _confirm_title_label: Label
var _confirm_text_label: Label
var _confirm_yes_button: Button
var _confirm_no_button: Button
var _confirm_hint_label: Label

# action_name -> {"name_label": Label, "binding_label": Label, "rebind_button": Button}
var _action_rows: Dictionary = {}


# ============================================================
# START
# ============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_build_ui()
	_refresh_texts()
	_refresh_controls_list()
	_close_all_panels()

	_root.visible = false

	if get_node_or_null("/root/SettingsManager") != null:
		SettingsManager.language_changed.connect(
			_on_language_changed
		)


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
	if not event.is_action_pressed(ESC_ACTION):
		return

	# Solange der Skill-Baum offen ist, soll Escape NUR ihn
	# schließen (siehe skill_tree_menu.gd -> _unhandled_input()) -
	# das Pause-Menü tut hier bewusst gar nichts, egal in welcher
	# Reihenfolge beide Autoloads das Event bekommen.
	if (
		get_node_or_null("/root/SkillTreeMenu") != null
		and SkillTreeMenu.is_open()
	):
		return

	if _listening_action != &"":
		return

	if _confirm_panel.visible:
		_close_confirm()
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

	if _is_open:
		resume()
		get_viewport().set_input_as_handled()
		return

	if (
		_is_shop_open()
		or _is_cutscene_active()
		or _is_main_menu_active()
	):
		return

	open_pause_menu()
	get_viewport().set_input_as_handled()


func _is_main_menu_active() -> bool:
	var scene: Node = get_tree().current_scene

	if scene == null:
		return false

	return scene.is_in_group(&"main_menu")


func _is_shop_open() -> bool:
	var scene: Node = get_tree().current_scene

	if scene == null:
		return false

	var shop: Node = scene.get_node_or_null(
		"CanvasLayer/HUD/ShopOverlay"
	)

	if shop == null:
		return false

	return shop is CanvasItem and (shop as CanvasItem).visible


func _is_cutscene_active() -> bool:
	if get_node_or_null("/root/CutsceneManager") == null:
		return false

	return CutsceneManager.is_cutscene_active()


# ============================================================
# ÖFFNEN / SCHLIESSEN
# ============================================================

func open_pause_menu() -> void:
	_is_open = true

	get_tree().paused = true

	_close_all_panels()
	_main_panel.visible = true
	_root.visible = true

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	_is_open = false

	get_tree().paused = false

	_root.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_open() -> bool:
	return _is_open


# ============================================================
# UI AUFBAUEN
# ============================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_background = ColorRect.new()
	_background.name = "Background"
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0.0, 0.0, 0.0, 0.6)
	_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_background)

	# CenterContainer statt manueller Anker-Berechnung, damit die
	# Panels auch dann exakt mittig bleiben, wenn sich ihre Größe
	# durch Inhalt (z.B. die Steuerungsliste) ändert.
	_center_container = CenterContainer.new()
	_center_container.name = "CenterContainer"
	_center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center_container)

	_build_main_panel()
	_build_settings_category_list()
	_build_game_options_panel()
	_build_audio_panel()
	_build_controls_panel()
	_build_confirm_panel()

	_apply_panel_scaling()


func _build_main_panel() -> void:
	_main_panel = _make_panel()
	_center_container.add_child(_main_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_main_panel.add_child(box)

	_title_label = _make_title_label()
	box.add_child(_title_label)

	_resume_button = _make_button()
	_resume_button.pressed.connect(resume)
	box.add_child(_resume_button)

	_settings_button = _make_button()
	_settings_button.pressed.connect(_open_settings)
	box.add_child(_settings_button)

	_save_button = _make_button()
	_save_button.pressed.connect(_on_save_pressed)
	box.add_child(_save_button)

	_main_menu_button = _make_button()
	_main_menu_button.pressed.connect(_open_confirm)
	box.add_child(_main_menu_button)

	# TEMPORÄRER TEST-BUTTON (später wieder entfernen, siehe
	# RunState.debug_add_skill_point()) - bewusst rötlich eingefärbt
	# und fest beschriftet (kein Übersetzungsschlüssel), damit er beim
	# Aufräumen sofort ins Auge fällt.
	_debug_skill_point_button = _make_button()
	_debug_skill_point_button.text = "[DEBUG] +1 Skillpunkt"
	_debug_skill_point_button.modulate = Color(1.0, 0.55, 0.55, 1.0)
	_debug_skill_point_button.pressed.connect(
		_on_debug_add_skill_point_pressed
	)
	box.add_child(_debug_skill_point_button)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	_toast_label.add_theme_color_override(
		"font_color",
		Color(0.5, 1.0, 0.5, 1.0)
	)
	box.add_child(_toast_label)


# Kategorie-Übersicht: nur die drei Oberkategorien-Buttons plus
# Zurück - die eigentlichen einstellbaren Werte stecken in den drei
# eigenen Kategorie-Seiten weiter unten.
func _build_settings_category_list() -> void:
	_settings_panel = _make_panel()
	_center_container.add_child(_settings_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(280, 0)
	_settings_panel.add_child(box)

	_settings_title_label = _make_title_label()
	box.add_child(_settings_title_label)

	_game_options_category_button = _make_button()
	_game_options_category_button.pressed.connect(_open_game_options)
	box.add_child(_game_options_category_button)

	_audio_category_button = _make_button()
	_audio_category_button.pressed.connect(_open_audio_settings)
	box.add_child(_audio_category_button)

	_controls_category_button = _make_button()
	_controls_category_button.pressed.connect(_open_controls_settings)
	box.add_child(_controls_category_button)

	_settings_list_back_button = _make_button()
	_settings_list_back_button.pressed.connect(_close_settings)
	box.add_child(_settings_list_back_button)


func _build_game_options_panel() -> void:
	_game_options_panel = _make_panel()
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

	_hud_scale_list = VBoxContainer.new()
	_hud_scale_list.add_theme_constant_override("separation", 4)
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
	box.add_child(_game_options_reset_button)

	_game_options_back_button = _make_button()
	_game_options_back_button.pressed.connect(_close_game_options)
	box.add_child(_game_options_back_button)


func _build_audio_panel() -> void:
	_audio_panel = _make_panel()
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
	box.add_child(_audio_reset_button)

	_audio_back_button = _make_button()
	_audio_back_button.pressed.connect(_close_audio_settings)
	box.add_child(_audio_back_button)


func _build_controls_panel() -> void:
	_controls_panel = _make_panel()
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
	box.add_child(_controls_reset_button)

	_controls_back_button = _make_button()
	_controls_back_button.pressed.connect(_close_controls_settings)
	box.add_child(_controls_back_button)


func _build_confirm_panel() -> void:
	_confirm_panel = _make_panel()
	_center_container.add_child(_confirm_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(340, 0)
	_confirm_panel.add_child(box)

	_confirm_title_label = _make_title_label()
	box.add_child(_confirm_title_label)

	_confirm_text_label = Label.new()
	_confirm_text_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_confirm_text_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	box.add_child(_confirm_text_label)

	_confirm_yes_button = _make_button()
	_confirm_yes_button.pressed.connect(_on_confirm_yes)
	box.add_child(_confirm_yes_button)

	_confirm_hint_label = Label.new()
	_confirm_hint_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_confirm_hint_label.visible = false
	_confirm_hint_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.85, 0.4, 1.0)
	)
	box.add_child(_confirm_hint_label)

	_confirm_no_button = _make_button()
	_confirm_no_button.pressed.connect(_close_confirm)
	box.add_child(_confirm_no_button)


# ============================================================
# PANEL-GRÖSSE (EINHEITLICHE SKALIERUNG)
# ============================================================

func _apply_panel_scaling() -> void:
	# Wird nur einmal beim Aufbau der UI aufgerufen (siehe
	# _build_ui()) - kein doppeltes Verbinden möglich, darum ohne
	# is_connected()-Prüfung.
	var scaled_panels: Array[Control] = [
		_main_panel,
		_settings_panel,
		_game_options_panel,
		_audio_panel,
		_controls_panel,
		_confirm_panel
	]

	for panel in scaled_panels:
		if panel == null:
			continue

		_center_scaled_panel(panel)
		panel.resized.connect(_on_scaled_panel_resized.bind(panel))


func _center_scaled_panel(panel: Control) -> void:
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2.ONE * PAUSE_PANEL_SCALE


# Die drei Panels ändern ihre Größe zur Laufzeit (z.B. längere
# Steuerungsliste nach Rebind, anderer Text nach Sprachwechsel) -
# pivot_offset muss dann neu berechnet werden, sonst wandert das
# Panel beim Skalieren aus der Bildschirmmitte.
func _on_scaled_panel_resized(panel: Control) -> void:
	_center_scaled_panel(panel)


# ============================================================
# UI-BAUSTEINE
# ============================================================

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()

	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	style.border_color = Color(0.85, 0.85, 0.85, 0.85)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

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
# Funktion. Genau dieselbe Liste wie im Hauptmenü (main_menu.gd ->
# _refresh_audio_settings_list()), nur eben auch hier im
# Pause-Menü verfügbar, damit man die Lautstärke auch während des
# Spielens anpassen kann.
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


# ============================================================
# PANEL-NAVIGATION
# ============================================================

func _close_all_panels() -> void:
	_main_panel.visible = false
	_settings_panel.visible = false
	_game_options_panel.visible = false
	_audio_panel.visible = false
	_controls_panel.visible = false
	_confirm_panel.visible = false

	_toast_label.visible = false
	_confirm_hint_label.visible = false

	_cancel_listening()


# Öffnet die Kategorie-Übersicht (Spieloptionen/Audio/Steuerung),
# NICHT mehr direkt die einstellbaren Werte - die stecken jetzt
# jeweils in einer eigenen Kategorie-Seite, siehe unten.
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


func _open_confirm() -> void:
	_close_all_panels()

	_confirm_panel.visible = true


func _close_confirm() -> void:
	_confirm_panel.visible = false

	_main_panel.visible = true


func _on_confirm_yes() -> void:
	if get_node_or_null("/root/RunState") != null:
		RunState.stop_time_tracking()

	# Gebiets-Hintergrundmusik ausfaden, statt sie über das
	# Hauptmenü hinweg weiterlaufen zu lassen - main_menu.gd startet
	# beim Neuaufbau ganz normal wieder seine eigene Musik.
	if get_node_or_null("/root/MusicManager") != null:
		MusicManager.fade_out_area_music()

	# resume() hebt get_tree().paused wieder auf - notwendig,
	# sonst würde das frisch geladene Hauptmenü im pausierten
	# Zustand starten und auf keine Klicks reagieren (Buttons
	# im Hauptmenü sind bewusst NICHT PROCESS_MODE_ALWAYS).
	resume()

	get_tree().change_scene_to_file("res://Game/main_menu.tscn")


func _on_save_pressed() -> void:
	if get_node_or_null("/root/SaveManager") == null:
		return

	var success: bool = SaveManager.save_game()

	if not success:
		return

	_show_toast(SettingsManager.t("pause.save_done"))


# ============================================================
# TEMPORÄRER TEST-BUTTON (SPÄTER WIEDER ENTFERNEN)
# ============================================================

# Nur zum Testen des Skill-Baums, ohne dafür wirklich Gegner
# besiegen zu müssen - siehe RunState.debug_add_skill_point().
# Diese Funktion UND der zugehörige Button in _build_main_panel()
# sind bewusst so markiert, dass sie sich später leicht wiederfinden
# und komplett entfernen lassen.
func _on_debug_add_skill_point_pressed() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	RunState.debug_add_skill_point(1)

	_show_toast("[DEBUG] +1 Skillpunkt")


func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(1.5).timeout

	if is_instance_valid(_toast_label):
		_toast_label.visible = false


# ============================================================
# TEXTE
# ============================================================

func _refresh_texts() -> void:
	if get_node_or_null("/root/SettingsManager") == null:
		return

	_title_label.text = SettingsManager.t("pause.title")
	_resume_button.text = SettingsManager.t("pause.resume")
	_settings_button.text = SettingsManager.t("pause.settings")
	_save_button.text = SettingsManager.t("pause.save")
	_main_menu_button.text = SettingsManager.t("pause.main_menu")

	_settings_title_label.text = SettingsManager.t(
		"settings.title"
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

	_confirm_title_label.text = SettingsManager.t(
		"pause.confirm_title"
	)

	_confirm_text_label.text = SettingsManager.t(
		"pause.confirm_text"
	)

	_confirm_yes_button.text = SettingsManager.t(
		"pause.confirm_yes"
	)

	_confirm_no_button.text = SettingsManager.t(
		"pause.confirm_no"
	)

	_language_de_button.disabled = (
		SettingsManager.get_language() == "de"
	)

	_language_en_button.disabled = (
		SettingsManager.get_language() == "en"
	)
