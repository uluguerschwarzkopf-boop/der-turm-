extends CanvasLayer


# ============================================================
# HINWEIS
# ============================================================

# Persistentes Autoload, genau wie PauseMenu (siehe pause_menu.gd) -
# einmal beim Spielstart erzeugt, bleibt über alle Räume hinweg
# erhalten. Zeigt den gewählten Pfad in seiner Farbe, die
# verfügbaren Punkte und den echten "Path of Might"-Baum aus Game/
# skill_tree_data.gd - jeder Skill sitzt auf einer festen Pixel-
# position (siehe _node_center(), aus "tier"/"branch" berechnet)
# innerhalb von _tree_canvas, einem eigenen Control OHNE Container-
# Layout (kein VBox/HBox mehr), damit sich Verbindungslinien
# zwischen den Knoten zeichnen lassen (siehe _draw_tree_
# connections()) - genau wie vom Nutzer per Referenzbild gewünscht.
# Charged Strike (tier 0) und Warlord (tier 4) haben "branch" -1 und
# landen dadurch automatisch mittig über/unter den drei Ästen.
#
# Nutzer-Wunsch (wörtlich): "wenn man ein Upgrade macht, kann man
# dann erst auf das nächste Upgrade, das davor verdeckt wurde" -
# ein Skill zeigt deshalb, solange keine seiner Voraussetzungen
# freigeschaltet ist (siehe RunState.skill_prerequisites_met()),
# weder Namen noch Kosten (nur "🔒 Verdeckt") und ist nicht
# anklickbar.
#
# Weiterer Nutzer-Wunsch (Referenzbild): freigeschaltete Skills
# bekommen einen Rahmen in der Pfad-Farbe (RunState.
# get_skill_path_color()), und die Verbindungslinie zu einem
# freigeschalteten Skill wird ebenfalls in dieser Farbe gezeichnet -
# alles andere bleibt gedämpft/grau (siehe _draw_tree_connections()
# und _apply_skill_button_state()).
#
# Öffnen läuft über die Action "open_skill_tree" (Standardtaste T,
# unter Einstellungen -> Steuerung wie jede andere Taste änderbar).
# Schließen geht über DIESELBE Taste ODER über Escape (ui_cancel) -
# genau wie beim Pause-Menü gewohnt. Damit dabei nicht zusätzlich
# noch das Pause-Menü aufploppt, prüft PauseMenu selbst (siehe
# pause_menu.gd -> _unhandled_input()) VOR seiner eigenen Escape-
# Logik, ob SkillTreeMenu.is_open() ist, und tut in dem Fall gar
# nichts - das Schließen übernimmt dann ausschließlich der
# ui_cancel-Zweig hier unten.
#
# Lässt sich nur öffnen, wenn tatsächlich ein Skill-Pfad gewählt
# wurde (RunState.has_chosen_skill_path()) und gerade nicht schon
# pausiert ist (z.B. weil das Pause-Menü offen ist) - genau wie der
# XP-Ring im HUD (siehe Player/UI/skill_ring_hud.gd) gibt es vorher
# ja noch gar nichts zu zeigen.


# ============================================================
# BAUM-LAYOUT (feste Pixelpositionen statt Container-Zeilen)
# ============================================================

const TIER_HEIGHT: float = 150.0

# Quadratisch statt 130x70 - seit die Knoten übers Icon dargestellt
# werden (siehe _apply_skill_button_state()), brauchen sie keine
# Breite mehr für zweizeiligen Text, dafür etwas mehr Höhe fürs
# größere Icon (Nutzer-Wunsch: "Icons besser sehen").
const NODE_SIZE: Vector2 = Vector2(90.0, 90.0)
const TREE_TOP_MARGIN: float = 45.0

# branch -1 (Charged Strike/Warlord) landet exakt in der Mitte
# zwischen den drei echten Ästen (branch 1 nutzt dieselbe Mitte wie
# -1, damit beide Kapstone-Knoten optisch über/unter dem MITTLEREN
# Ast stehen, wie im Referenzbild).
const BRANCH_X_OFFSETS: Dictionary = {
	-1: 0.0,
	0: -190.0,
	1: 0.0,
	2: 190.0,
}

# Nutzer-Wunsch: der ganze Baum (und damit die Icons) soll größer
# sein - Knotengröße/-abstände oben entsprechend hochskaliert,
# TREE_CANVAS_SIZE hier passend mitgewachsen (siehe _node_center()
# unten für die genaue Positionsberechnung daraus).
const TREE_CANVAS_SIZE: Vector2 = Vector2(560.0, 760.0)

const LINE_WIDTH: float = 4.0

# Gedämpfte Farbe für noch nicht benutzte Verbindungen (siehe
# _draw_tree_connections()) - bewusst neutral/grau, unabhängig vom
# gewählten Pfad, damit sie klar von der Pfad-Farbe abgesetzt bleibt.
const MUTED_LINE_COLOR: Color = Color(0.4, 0.38, 0.4, 0.55)


# ============================================================
# SKILL-ICONS
# ============================================================

# Die eigentlichen Icon-Texturen kommen zentral aus Game/skill_tree_
# data.gd (SkillTreeData.get_skill_icon_texture()/get_locked_icon_
# texture()) - dort auch fürs HUD (Player/hud.gd, aktiver Skill-Slot)
# gebraucht, deshalb nicht hier doppelt gepflegt.

const _SKILL_ICON_SIZE: Vector2 = Vector2(60.0, 60.0)

# Nutzer-Wunsch: der aktuell ausgerüstete aktive Skill bekommt einen
# engen gelben Rahmen NUR um das Icon selbst (siehe _add_skill_icon()
# unten) - eigenständig von der festen Icon-Position, damit der
# Rahmen das Icon nie verschiebt.
const _SKILL_ICON_EQUIPPED_BORDER_COLOR: Color = Color(1.0, 0.85, 0.2, 1.0)
const _SKILL_ICON_EQUIPPED_BORDER_WIDTH: int = 3
const _SKILL_ICON_EQUIPPED_BORDER_PADDING: float = 6.0

# Einfacher Graustufen-Effekt fürs Icon eines noch nicht
# freigeschalteten, aber schon sichtbaren Skills (Nutzer-Wunsch) -
# komplett entsättigt nach Helligkeit, ähnliches Prinzip wie der
# Fenster-Aus-Shader bei den Skill-Staturen (Objects/Staturen/
# skill_statue.gd), hier aber ohne dessen Sättigungs-Ausnahme für
# schon-graue Pixel, weil hier IMMER das ganze Icon grau werden soll.
const _SKILL_ICON_LOCKED_SHADER_CODE: String = """
shader_type canvas_item;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float grey = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(grey), source.a);
}
"""


# ============================================================
# INFO-TEXTBOX (folgt jetzt dem gehoverten Icon)
# ============================================================

# Feste Größe der Info-Textbox (Name/Typ/Kosten/Beschreibung LINKS,
# großes Icon RECHTS, siehe _build_info_overlay()/_show_skill_info())
# - Nutzer-Wunsch: größer, UND erscheint jetzt RECHTS NEBEN dem
# gerade gehoverten Skill-Icon (nicht mehr darüber - das überlappte
# den "Path of Strength"-Titel dahinter, siehe _position_info_panel_
# beside() unten).
const _INFO_PANEL_SIZE: Vector2 = Vector2(520.0, 210.0)
const _INFO_PANEL_ICON_SIZE: Vector2 = Vector2(130.0, 130.0)
const _INFO_PANEL_GAP_BESIDE_NODE: float = 18.0

# Nutzer-Wunsch: der Beschreibungstext in der Info-Box war zu klein
# (lief bisher ohne eigene font_size-Override auf der winzigen
# Engine-Standardgröße) - jetzt explizit größer, angelehnt an
# _points_label (18).
const _INFO_PANEL_TEXT_FONT_SIZE: int = 20

# Rutscht die Box nie über den Bildschirmrand hinaus, egal wo der
# gehoverte Knoten sitzt (Sicherheitsnetz) - reicht nicht genug Platz
# rechts vom Knoten (z.B. rechter Ast), erscheint die Box stattdessen
# LINKS davon (siehe _position_info_panel_beside()).
const _INFO_PANEL_SCREEN_MARGIN: float = 10.0


# ============================================================
# STATUS
# ============================================================

var _is_open: bool = false

# Aktuell angezeigter Pfad - wird beim Neuaufbau des Baums gesetzt
# (siehe _rebuild_skill_buttons()) und von _draw_tree_connections()
# gebraucht, weil das "draw"-Signal selbst keine Parameter mitgibt.
var _current_tree_path: StringName = &""

# skill_id -> Mittelpunkt (Vector2) in _tree_canvas-Koordinaten -
# wird bei jedem Neuaufbau frisch berechnet (siehe _node_center())
# und von _draw_tree_connections() zum Linien-Zeichnen gebraucht.
var _node_positions: Dictionary = {}


# ============================================================
# NODES (per Code gebaut, wie bei PauseMenu)
# ============================================================

var _root: Control
var _background: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _points_label: Label
var _tree_canvas: Control
var _info_panel: PanelContainer
var _info_label: Label
var _info_icon: TextureRect

# skill_id -> Button, wird bei jedem _rebuild_skill_buttons() vor
# dem Neuaufbau komplett geleert (siehe dort).
var _skill_buttons: Dictionary = {}


# ============================================================
# START
# ============================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90

	_build_ui()


# ============================================================
# UI AUFBAUEN
# ============================================================

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.color = Color(0.02, 0.02, 0.03, 0.82)
	_root.add_child(_background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(680, 300)

	# Nutzer-Wunsch: kein grauer Kasten mehr um den Skill-Baum - der
	# abgedunkelte Vollbild-Hintergrund (_background oben) reicht als
	# Abgrenzung, genau wie beim Hauptmenü/Pause-Menü (siehe
	# Game/main_menu.gd -> _make_borderless_panel()).
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_title_label)

	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_points_label)

	# Eigenes Control OHNE Container-Layout (kein VBox/HBox) - jeder
	# Skill-Button bekommt seine Position direkt zugewiesen (siehe
	# _node_center()), damit Verbindungslinien zwischen den Knoten
	# gezeichnet werden können (siehe _draw_tree_connections()).
	_tree_canvas = Control.new()
	_tree_canvas.custom_minimum_size = TREE_CANVAS_SIZE
	_tree_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_canvas.draw.connect(_draw_tree_connections)
	vbox.add_child(_tree_canvas)

	# Nutzer-Wunsch: kein "Test phase - real values coming later"/
	# "Press [Taste] again to close"-Text mehr unter dem Baum (siehe
	# vorher hier gebaute _placeholder_label/_close_hint_label).

	_build_info_overlay()


# Eigene Info-Textbox statt Godots eingebautem Button.tooltip_text
# (Nutzer-Wunsch: "eine Textbox... wo alle Infos drinnen stehen") -
# das eingebaute Tooltip-Popup erschien beim Testen zuverlässig nur
# bei bereits freigeschalteten (deaktivierten) Buttons, nicht bei
# noch anklickbaren (siehe _apply_skill_button_state() weiter unten).
#
# Bewusst NICHT Teil der vbox von oben, sondern ein eigenständiges
# Control direkt unter _root - dadurch ändert ein länger/kürzer
# werdender Info-Text NIE die Größe des eigentlichen Skill-Baum-
# Fensters. Wird NACH "center" zu _root hinzugefügt, damit es beim
# Zeichnen immer über dem Fenster liegt.
#
# Nutzer-Wunsch: erscheint jetzt DIREKT ÜBER dem gerade gehoverten
# Skill-Icon statt fest oben in der Bildschirmmitte zu schweben -
# deshalb feste Pixelgröße (_INFO_PANEL_SIZE) statt fraktionaler
# Anker, Position wird bei jedem Hover neu berechnet (siehe
# _position_info_panel_beside()/_show_skill_info() unten). Text LINKS
# (_info_label), größere Kopie des Icons RECHTS (_info_icon, Nutzer-
# Wunsch: "nochmal dass icon... in gröser"). Startet unsichtbar
# (Nutzer-Wunsch: kein Platzhaltertext mehr, solange nichts gehovert
# wird, siehe _clear_skill_info()).
func _build_info_overlay() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_info_panel.size = _INFO_PANEL_SIZE
	_info_panel.visible = false
	_root.add_child(_info_panel)

	var info_margin := MarginContainer.new()
	info_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_margin.add_theme_constant_override("margin_left", 14)
	info_margin.add_theme_constant_override("margin_right", 14)
	info_margin.add_theme_constant_override("margin_top", 10)
	info_margin.add_theme_constant_override("margin_bottom", 10)
	_info_panel.add_child(info_margin)

	var info_row := HBoxContainer.new()
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_row.add_theme_constant_override("separation", 14)
	info_margin.add_child(info_row)

	_info_label = Label.new()
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_label.add_theme_font_size_override(
		"font_size", _INFO_PANEL_TEXT_FONT_SIZE
	)
	info_row.add_child(_info_label)

	_info_icon = TextureRect.new()
	_info_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_info_icon.custom_minimum_size = _INFO_PANEL_ICON_SIZE
	_info_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_info_icon.visible = false
	info_row.add_child(_info_icon)


# Positioniert die Info-Textbox RECHTS NEBEN "node_control" (Nutzer-
# Wunsch: "rechts vom icon platzieren damit es nicht über den path of
# strength geht"), vertikal auf dessen Mitte zentriert. Reicht der
# Platz rechts nicht (z.B. rechter Ast, nah am Bildschirmrand), springt
# die Box stattdessen auf die LINKE Seite des Knotens - beides zusammen
# mit _INFO_PANEL_SCREEN_MARGIN als Sicherheitsnetz gegen jedes
# Abschneiden am Bildschirmrand (oben/unten/seitlich).
func _position_info_panel_beside(node_control: Control) -> void:
	var node_rect: Rect2 = node_control.get_global_rect()

	var viewport_size: Vector2 = Vector2(1280.0, 720.0)
	var viewport: Viewport = get_viewport()

	if viewport != null:
		viewport_size = viewport.get_visible_rect().size

	var target_left: float = (
		node_rect.position.x
		+ node_rect.size.x
		+ _INFO_PANEL_GAP_BESIDE_NODE
	)

	var fits_on_right: bool = (
		target_left + _INFO_PANEL_SIZE.x
		<= viewport_size.x - _INFO_PANEL_SCREEN_MARGIN
	)

	if not fits_on_right:
		target_left = (
			node_rect.position.x
			- _INFO_PANEL_GAP_BESIDE_NODE
			- _INFO_PANEL_SIZE.x
		)

	target_left = clamp(
		target_left,
		_INFO_PANEL_SCREEN_MARGIN,
		viewport_size.x - _INFO_PANEL_SIZE.x - _INFO_PANEL_SCREEN_MARGIN
	)

	var center_y: float = node_rect.position.y + node_rect.size.y / 2.0
	var target_top: float = clamp(
		center_y - _INFO_PANEL_SIZE.y / 2.0,
		_INFO_PANEL_SCREEN_MARGIN,
		viewport_size.y - _INFO_PANEL_SIZE.y - _INFO_PANEL_SCREEN_MARGIN
	)

	_info_panel.position = Vector2(target_left, target_top)


# ============================================================
# ÖFFNEN / SCHLIESSEN
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	# Schließen per Escape hat Vorrang vor allem anderen unten -
	# funktioniert nur, solange der Baum gerade offen ist (siehe
	# HINWEIS oben, PauseMenu lässt Escape dafür bewusst durch).
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
		return

	if not event.is_action_pressed(&"open_skill_tree"):
		return

	get_viewport().set_input_as_handled()

	_toggle()


func _toggle() -> void:
	if _is_open:
		_close()
		return

	if get_node_or_null("/root/RunState") == null:
		return

	if not RunState.has_chosen_skill_path():
		return

	if (
		get_node_or_null("/root/PauseMenu") != null
		and PauseMenu.is_open()
	):
		return

	if get_tree().paused:
		return

	_open()


func _open() -> void:
	_is_open = true

	_refresh_content()

	get_tree().paused = true
	_root.visible = true

	# Ohne das hier bleibt der Mauszeiger versteckt (das Spiel
	# blendet ihn normalerweise aus) - dann lässt sich kein Skill
	# per Maus anklicken. Genau wie PauseMenu.open_pause_menu().
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close() -> void:
	_is_open = false

	get_tree().paused = false
	_root.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func is_open() -> bool:
	return _is_open


# ============================================================
# INHALT
# ============================================================

func _refresh_content() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	if get_node_or_null("/root/SettingsManager") == null:
		return

	var path_key: StringName = RunState.chosen_skill_path

	_title_label.text = SettingsManager.t(String(path_key))
	_title_label.add_theme_color_override(
		"font_color",
		RunState.get_skill_path_color()
	)

	_points_label.text = (
		SettingsManager.t("skilltree.points_label")
		% RunState.skill_points
	)

	_clear_skill_info()

	_rebuild_skill_buttons(path_key)


# Feste Pixelposition (Mittelpunkt) eines Skill-Knotens innerhalb
# von _tree_canvas, aus "tier" (Reihe, wächst nach unten) und
# "branch" (Ast, siehe BRANCH_X_OFFSETS) berechnet.
func _node_center(skill: Dictionary) -> Vector2:
	var tier: int = int(skill.get("tier", 0))
	var branch: int = int(skill.get("branch", -1))

	var x: float = (
		TREE_CANVAS_SIZE.x / 2.0
		+ float(BRANCH_X_OFFSETS.get(branch, 0.0))
	)
	var y: float = (
		TREE_TOP_MARGIN
		+ float(tier) * TIER_HEIGHT
		+ NODE_SIZE.y / 2.0
	)

	return Vector2(x, y)


# Baut den kompletten Baum neu auf - ein Button pro Skill an einer
# festen Pixelposition (siehe _node_center()) statt in Container-
# Zeilen, damit _draw_tree_connections() Linien zwischen den echten
# Knoten-Mittelpunkten zeichnen kann. Komplett neu aufbauen statt
# einzelne Buttons live nachzupflegen ist einfacher/weniger
# fehleranfällig und muss eh nur beim Öffnen bzw. nach jedem
# Freischalten laufen (selten).
func _rebuild_skill_buttons(path_key: StringName) -> void:
	_current_tree_path = path_key

	for child in _tree_canvas.get_children():
		child.queue_free()

	_skill_buttons.clear()
	_node_positions.clear()

	var skills: Array[Dictionary] = SkillTreeData.get_skills_for_path(
		path_key
	)

	for skill in skills:
		var skill_id: StringName = skill.get("id", &"")
		_node_positions[skill_id] = _node_center(skill)

	for skill in skills:
		var skill_id: StringName = skill.get("id", &"")
		var center: Vector2 = _node_positions[skill_id]

		var button := Button.new()
		button.position = center - NODE_SIZE / 2.0
		button.size = NODE_SIZE
		button.toggle_mode = false
		button.clip_text = false
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		_apply_skill_button_state(button, skill)

		button.pressed.connect(
			_on_skill_button_pressed.bind(skill_id)
		)

		_tree_canvas.add_child(button)
		_skill_buttons[skill_id] = button

	_tree_canvas.queue_redraw()


# Zeichnet eine Linie von jedem Skill zu jeder seiner Voraussetzungen
# (siehe Game/skill_tree_data.gd -> "prerequisites") - in der Pfad-
# Farbe, wenn BEIDE Enden bereits freigeschaltet sind (Nutzer-Wunsch:
# "die Strecke zu ihm soll rot werden... wegen dem passenden Weg"),
# sonst gedämpft/grau. Läuft über das "draw"-Signal von _tree_canvas
# (siehe _build_ui()) statt über ein eigenes Skript, damit dieses
# Menü weiterhin komplett ohne .tscn auskommt.
func _draw_tree_connections() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	var path_color: Color = RunState.get_skill_path_color()

	for skill in SkillTreeData.get_skills_for_path(_current_tree_path):
		var skill_id: StringName = skill.get("id", &"")
		var prerequisites: Array = skill.get("prerequisites", [])

		if prerequisites.is_empty():
			continue

		if not _node_positions.has(skill_id):
			continue

		var to_pos: Vector2 = _node_positions[skill_id]
		var child_unlocked: bool = RunState.has_unlocked_skill(skill_id)

		for prerequisite_id in prerequisites:
			if not _node_positions.has(prerequisite_id):
				continue

			var from_pos: Vector2 = _node_positions[prerequisite_id]

			var prerequisite_unlocked: bool = RunState.has_unlocked_skill(
				prerequisite_id
			)

			var line_color: Color = (
				path_color
				if (child_unlocked and prerequisite_unlocked)
				else MUTED_LINE_COLOR
			)

			_tree_canvas.draw_line(
				from_pos,
				to_pos,
				line_color,
				LINE_WIDTH
			)


func _apply_skill_button_state(
	button: Button,
	skill: Dictionary
) -> void:
	var skill_id: StringName = skill.get("id", &"")
	var cost: int = int(skill.get("cost", 1))
	var skill_name: String = SettingsManager.t(
		String(skill.get("name_key", ""))
	)

	var unlocked: bool = RunState.has_unlocked_skill(skill_id)
	var prereq_met: bool = RunState.skill_prerequisites_met(skill_id)

	if not prereq_met:
		# Absichtlich KEINE Info-Textbox für verdeckte Skills (Nutzer-
		# Wunsch: "bei allem außer bei den hidden") - kein
		# mouse_entered-Signal wird hier verbunden. Eigenes "Locked"-
		# Icon (Nutzer-Wunsch, siehe SkillTreeData.get_locked_icon_
		# texture()) statt dem übrigen Skill-Icon-Satz - dasselbe für
		# JEDEN verdeckten Skill dieses Pfads.
		var locked_icon: Texture2D = SkillTreeData.get_locked_icon_texture(
			_current_tree_path
		)

		button.disabled = true
		button.modulate = Color(1.0, 1.0, 1.0, 0.5)

		if locked_icon != null:
			button.text = ""
			_clear_button_stylebox_overrides(button)
			_add_skill_icon(button, locked_icon, true, false)
		else:
			button.text = SettingsManager.t("skilltree.locked_skill")

		return

	# Icon aus dem Krieger-Icon-Atlas (siehe Game/skill_tree_data.gd)
	# - null, solange für diesen Pfad/Skill noch keins hinterlegt ist
	# (aktuell z.B. Arkana/Auferstehung), dann bleibt der jeweilige
	# Zweig unten beim bisherigen reinen Text-Button.
	var icon_texture: Texture2D = SkillTreeData.get_skill_icon_texture(
		_current_tree_path, skill_id
	)

	# Kein "[A]"/"[P]"-Kürzel mehr direkt auf dem Button - Typ,
	# Kosten und Beschreibung stehen stattdessen komplett in der
	# Info-Textbox oben (siehe _show_skill_info()), angezeigt per
	# mouse_entered/mouse_exited statt über Godots eingebautes
	# Button.tooltip_text (das erschien beim Testen nur bei bereits
	# freigeschalteten/deaktivierten Buttons zuverlässig).
	if unlocked:
		# Nur bereits freigeschaltete AKTIVE Skills lassen sich in den
		# Skill-Slot legen (Nutzer-Wunsch: im Skill-Baum anklicken,
		# siehe RunState.equip_active_skill()/_on_skill_button_pressed()
		# unten) - passive Skills brauchen das nicht und bleiben wie
		# bisher rein informativ/deaktiviert.
		var is_active: bool = skill.get("type", &"passive") == &"active"
		var is_equipped: bool = (
			is_active
			and RunState.equipped_active_skill == skill_id
		)

		button.mouse_entered.connect(
			_show_skill_info.bind(skill, skill_name, cost, true, button)
		)
		button.mouse_exited.connect(_clear_skill_info)
		button.disabled = not is_active
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)

		if icon_texture != null:
			# Icon trägt jetzt die ganze Darstellung (Nutzer-Wunsch:
			# "die Felder durch die Icons ersetzen") - Name/Typ/
			# Kosten/Status stehen komplett in der Info-Textbox oben
			# (siehe _show_skill_info()), kein zusätzlicher Text mehr
			# direkt auf dem Knoten. In Originalfarbe, weil bereits
			# freigeschaltet; zusätzlich mit gelbem Rahmen ums Icon,
			# falls gerade ausgerüstet.
			button.text = ""
			_clear_button_stylebox_overrides(button)
			_add_skill_icon(button, icon_texture, true, is_equipped)
		else:
			if is_equipped:
				button.text = "%s\n✓ [%s]" % [
					skill_name,
					SettingsManager.t("skilltree.equipped_tag")
				]
			else:
				button.text = "%s\n✓" % skill_name

			# Nutzer-Wunsch (Referenzbild): freigeschaltete Skills
			# bekommen einen Rahmen in der Pfad-Farbe statt der
			# vorherigen grünen Einfärbung. Der aktuell ausgerüstete
			# aktive Skill bekommt stattdessen einen goldenen Rahmen,
			# damit er sich klar von den übrigen freigeschalteten
			# Skills abhebt. (Nur noch Fallback für Pfade/Skills OHNE
			# eigenes Icon - siehe oben.)
			var border_color: Color = (
				Color(1.0, 0.85, 0.3, 1.0) if is_equipped
				else RunState.get_skill_path_color()
			)

			var unlocked_style: StyleBoxFlat = _make_unlocked_stylebox(
				border_color
			)

			button.add_theme_stylebox_override(
				"disabled", unlocked_style
			)

			if is_active:
				# disabled=false Buttons benutzen nicht den "disabled"-
				# Stylebox - dieselbe Optik muss deshalb zusätzlich auf
				# "normal"/"hover"/"pressed" gesetzt werden, sonst sähe
				# ein anklickbarer aktiver Skill wie ein Standard-
				# Button aus, statt wie die übrigen freigeschalteten
				# Skills.
				button.add_theme_stylebox_override(
					"normal", unlocked_style
				)
				button.add_theme_stylebox_override(
					"hover", unlocked_style
				)
				button.add_theme_stylebox_override(
					"pressed", unlocked_style
				)

		return

	var affordable: bool = RunState.skill_points >= cost

	button.mouse_entered.connect(
		_show_skill_info.bind(skill, skill_name, cost, false, button)
	)
	button.mouse_exited.connect(_clear_skill_info)
	button.disabled = not affordable
	button.modulate = (
		Color(1.0, 1.0, 1.0, 1.0) if affordable
		else Color(1.0, 1.0, 1.0, 0.75)
	)

	if icon_texture != null:
		# Noch nicht freigeschaltet, aber Voraussetzungen erfüllt -
		# Icon in Graustufen (Nutzer-Wunsch), Kosten/Name weiterhin
		# nur in der Info-Textbox beim Hovern (siehe oben).
		button.text = ""
		_clear_button_stylebox_overrides(button)
		_add_skill_icon(button, icon_texture, false, false)
	else:
		button.text = "%s\n(%d)" % [skill_name, cost]


# Rahmen in Pfad-Farbe für bereits freigeschaltete Skills (siehe
# _apply_skill_button_state() oben) - dunkler Innenraum, damit der
# farbige Rand auf jedem Pfad (Rot/Blau/Lila-Pink) klar erkennbar
# bleibt.
func _make_unlocked_stylebox(path_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.09, 0.95)
	style.border_color = path_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	return style


func _build_skill_icon_locked_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _SKILL_ICON_LOCKED_SHADER_CODE

	var material := ShaderMaterial.new()
	material.shader = shader

	return material


# Blendet die Standard-Button-Optik komplett aus, sobald ein Skill
# über sein Icon dargestellt wird (Nutzer-Wunsch: Icon soll die GANZE
# Darstellung sein, kein zusätzlicher Rahmen/Hintergrund mehr auf dem
# gesamten Knoten) - exakt dasselbe Muster wie bei den flachen
# Hauptmenü-Buttons (siehe Game/main_menu.gd -> _add_menu_button_
# row()).
func _clear_button_stylebox_overrides(button: Button) -> void:
	var empty_style := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty_style)
	button.add_theme_stylebox_override("hover", empty_style)
	button.add_theme_stylebox_override("pressed", empty_style)
	button.add_theme_stylebox_override("focus", empty_style)
	button.add_theme_stylebox_override("disabled", empty_style)


# Fügt das Icon (icon_texture, siehe SkillTreeData.get_skill_icon_
# texture()/get_locked_icon_texture()) als Kind von "button" ein: in
# Graustufen, solange der Skill noch nicht freigeschaltet ist
# (is_unlocked=false), in Originalfarbe sobald doch (für das
# "Locked"-Icon der verdeckten Skills wird is_unlocked=true über-
# geben, siehe _apply_skill_button_state() oben - das Icon ist ja
# schon extra für diesen Zustand gezeichnet, braucht also keine
# zusätzliche Entsättigung). Ist er zusätzlich der aktuell
# ausgerüstete aktive Skill (is_equipped=true), bekommt er einen
# engen gelben Rahmen NUR um das Icon selbst (Nutzer-Wunsch: "einfach
# um dass icon rum einen gelben rand") - der Rahmen wird um die FESTE
# Icon-Position herum gebaut, statt das Icon je nach Zustand zu
# verschieben, damit es beim Ausrüsten/Abrüsten nicht "springt".
# Mittig im Knoten (statt oben, wie zu der Zeit, als daneben noch
# Text stand) - der Knoten zeigt jetzt NUR noch das Icon.
func _add_skill_icon(
	button: Button,
	icon_texture: Texture2D,
	is_unlocked: bool,
	is_equipped: bool
) -> void:
	var icon_left: float = -_SKILL_ICON_SIZE.x / 2.0
	var icon_right: float = _SKILL_ICON_SIZE.x / 2.0
	var icon_top: float = -_SKILL_ICON_SIZE.y / 2.0
	var icon_bottom: float = _SKILL_ICON_SIZE.y / 2.0

	if is_equipped:
		var border := StyleBoxFlat.new()
		border.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		border.border_color = _SKILL_ICON_EQUIPPED_BORDER_COLOR
		border.set_border_width_all(_SKILL_ICON_EQUIPPED_BORDER_WIDTH)
		border.set_corner_radius_all(4)

		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_theme_stylebox_override("panel", border)
		frame.anchor_left = 0.5
		frame.anchor_right = 0.5
		frame.anchor_top = 0.5
		frame.anchor_bottom = 0.5
		frame.offset_left = (
			icon_left - _SKILL_ICON_EQUIPPED_BORDER_PADDING
		)
		frame.offset_right = (
			icon_right + _SKILL_ICON_EQUIPPED_BORDER_PADDING
		)
		frame.offset_top = (
			icon_top - _SKILL_ICON_EQUIPPED_BORDER_PADDING
		)
		frame.offset_bottom = (
			icon_bottom + _SKILL_ICON_EQUIPPED_BORDER_PADDING
		)
		button.add_child(frame)

	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.anchor_left = 0.5
	icon.anchor_right = 0.5
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = icon_left
	icon.offset_right = icon_right
	icon.offset_top = icon_top
	icon.offset_bottom = icon_bottom

	if not is_unlocked:
		icon.material = _build_skill_icon_locked_material()

	button.add_child(icon)


# Zeigt die volle Info (Name, Typ, Kosten, Beschreibung) eines
# Skills in der Textbox oben an, sobald die Maus über seinem Button
# steht (siehe _apply_skill_button_state() oben) - funktioniert
# unabhängig davon, ob der Button gerade deaktiviert ist, weil
# mouse_entered/mouse_exited (anders als Godots eingebautes
# Tooltip-Popup) auf jedem Control gleich feuern.
#
# "node_button" ist der gehoverte Skill-Knoten selbst (Nutzer-Wunsch:
# Textbox soll RECHTS NEBEN dem Icon erscheinen, siehe _position_info_
# panel_beside()) - zusätzlich wird hier rechts in der Textbox nochmal
# eine größere Kopie desselben Icons gezeigt (Nutzer-Wunsch: "nochmal
# dass icon... in gröser"), in Graustufen/Farbe genau wie am Knoten
# selbst.
func _show_skill_info(
	skill: Dictionary,
	skill_name: String,
	cost: int,
	is_unlocked: bool,
	node_button: Control
) -> void:
	_position_info_panel_beside(node_button)
	_info_panel.visible = true

	var skill_id: StringName = skill.get("id", &"")
	var icon_texture: Texture2D = SkillTreeData.get_skill_icon_texture(
		_current_tree_path, skill_id
	)

	if icon_texture != null:
		_info_icon.texture = icon_texture
		_info_icon.material = (
			null if is_unlocked
			else _build_skill_icon_locked_material()
		)
		_info_icon.visible = true
	else:
		_info_icon.visible = false

	var skill_type: StringName = skill.get("type", &"passive")

	var type_text: String = SettingsManager.t(
		"skilltree.tooltip_type_active"
		if skill_type == &"active"
		else "skilltree.tooltip_type_passive"
	)

	var desc_text: String = SettingsManager.t(
		String(skill.get("desc_key", ""))
	)

	var status_line: String = (
		SettingsManager.t("skilltree.tooltip_unlocked")
		if is_unlocked
		else SettingsManager.t("skilltree.tooltip_cost") % cost
	)

	# Zusätzlicher Hinweis nur bei bereits freigeschalteten AKTIVEN
	# Skills (siehe _apply_skill_button_state() - nur die sind
	# überhaupt anklickbar, um sie in den Skill-Slot zu legen).
	if is_unlocked and skill_type == &"active":
		status_line += "\n" + SettingsManager.t("skilltree.equip_hint")

	_info_label.text = "%s (%s)\n%s\n\n%s" % [
		skill_name,
		type_text,
		status_line,
		desc_text
	]


# Blendet die Info-Textbox komplett aus (Nutzer-Wunsch: kein
# "Hover over a skill for details"-Platzhaltertext mehr, solange
# nichts gehovert wird) - beim Öffnen des Baums (siehe _refresh_
# content()) und sobald die Maus einen Skill-Button wieder verlässt
# (siehe _apply_skill_button_state() oben).
func _clear_skill_info() -> void:
	_info_panel.visible = false
	_info_icon.visible = false


func _on_skill_button_pressed(skill_id: StringName) -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	if RunState.has_unlocked_skill(skill_id):
		# Bereits gekauft - ein Klick rüstet den Skill stattdessen in
		# den Skill-Slot aus (siehe _apply_skill_button_state() oben:
		# nur bereits freigeschaltete AKTIVE Skills sind hier überhaupt
		# anklickbar, passive Skills kommen nie hier an).
		RunState.equip_active_skill(skill_id)
		_refresh_content()
		return

	if RunState.unlock_skill(skill_id):
		_refresh_content()
