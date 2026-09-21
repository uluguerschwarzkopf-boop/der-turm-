extends Control


# ============================================================
# ZAUBER-ICONS
# ============================================================

@export_group("Spell UI - Icons")

# Gemeinsames SpriteFrames mit diesen Animationen:
#
# fireball
# lightning
# ice
# roots
# necromancy
# lightorb
@export var spell_icon_frames: SpriteFrames


# ============================================================
# ZAUBER-SLOTS: POSITION UND GRÖSSE
# ============================================================

@export_group("Spell UI - Layout")

# Position relativ zur unteren rechten Bildschirmecke.
#
# X kleiner/negativer = weiter nach links
# X größer = weiter nach rechts
#
# Y kleiner/negativer = weiter nach oben
# Y größer = weiter nach unten
@export var spell_ui_offset_from_bottom_right: Vector2 = Vector2(
	-255,
	-70
)

@export var spell_slot_size: Vector2 = Vector2(40, 40)
@export var spell_slot_spacing: float = 46.0

@export var spell_icon_position: Vector2 = Vector2(20, 20)
@export var spell_icon_scale: Vector2 = Vector2(1.0, 1.0)

@export var spell_number_position: Vector2 = Vector2(4, 1)
@export var spell_number_size: Vector2 = Vector2(18, 18)


# ============================================================
# ZAUBER-SLOTS: AUSSEHEN
# ============================================================

@export_group("Spell UI - Aussehen")

@export var spell_slot_background_color: Color = Color(
	0.08,
	0.08,
	0.08,
	0.82
)

@export var spell_slot_border_color: Color = Color(
	0.75,
	0.75,
	0.75,
	1.0
)

@export var spell_slot_border_width: int = 2
@export var spell_number_color: Color = Color.WHITE


# ============================================================
# ECHOS (BOSS-BELOHNUNGEN)
# ============================================================

@export_group("Echos")

# Abstand zwischen dem letzten Herz und dem Echo-Bereich (Node2D
# "Echos" in HUD/Echos) - der Echo-Bereich sitzt direkt rechts
# neben den Herzen, auf derselben Höhe.
#
# Nutzer-Rückmeldung: das Echo-Icon (mit seinem nach unten-links
# hängenden Funken) saß mit seiner LINKEN Hälfte noch über der
# rechten Kante der Vigor-Leiste darunter (VIGOR_BAR_SIZE.x = 192,
# siehe unten) - der Wert wurde deshalb erhöht, um das Icon weiter
# NACH RECHTS zu schieben (weiter WEG von der Vigor-Leiste). Ein
# kleinerer Wert würde das Icon dagegen näher an die Herzen und
# damit noch weiter in die Vigor-Leiste hinein schieben.
@export var echos_gap_after_hearts: float = 60.0

# Grundgröße des Echo-Icons (wie heart.scale = Vector2(3, 3) bei
# den Herzen) - fest im Code, NICHT die einstellbare UI-Größe.
# Die einstellbare Größe kommt jetzt genau wie bei Herzen/Tränken/
# Bogen/Zaubern über SettingsManager.get_hud_scale(&"echo_der_
# flamme") (siehe _setup_echos_ui() unten) und ist in den
# Einstellungen unter "UI-Größe" regelbar, sobald das Echo
# freigeschaltet ist (siehe main_menu.gd -> _refresh_hud_scale_
# list()).
const ECHO_ICON_BASE_SCALE: float = 3.0


# ============================================================
# BESTEHENDE HUD-NODES
# ============================================================

@onready var hearts_node: Node2D = $Hearts
@onready var potions_node: Node2D = $Potions

@onready var potion_icon: AnimatedSprite2D = (
	$Potions/PotionIcon
)

@onready var potion_label: Label = (
	$Potions/PotionLabel
)

@onready var bow_ui: Node2D = get_node_or_null(
	"BowUI"
)

@onready var bow_circle: AnimatedSprite2D = get_node_or_null(
	"BowUI/BowCircle"
)

@onready var bow_icon: AnimatedSprite2D = get_node_or_null(
	"BowUI/BowIcon"
)

@onready var arrow_circle: AnimatedSprite2D = get_node_or_null(
	"BowUI/ArrowCircle"
)

@onready var arrow_icon: AnimatedSprite2D = get_node_or_null(
	"BowUI/ArrowIcon"
)

@onready var arrow_label: Label = get_node_or_null(
	"BowUI/ArrowLabel"
)

@onready var echos_node: Node2D = get_node_or_null(
	"Echos"
)

@onready var gold_ui: Control = get_node_or_null(
	"GoldUI"
)

@onready var echo_der_flamme_icon: AnimatedSprite2D = (
	get_node_or_null("Echos/EchoDerFlamme")
)

# WICHTIG (siehe Chat-Verlauf): Der XP-Ring wurde bisher rein über
# Anker-Werte (anchor_left/anchor_right = 1.0) in der .tscn
# positioniert - das hat aus ungeklärtem Grund NICHT funktioniert,
# obwohl der Node nachweislich in der Szene ankam (bewiesen über
# eine testweise eingebaute, logikfreie pinke Fläche an derselben
# Stelle mit denselben Ankern, die ebenfalls unsichtbar blieb).
# Erst als dieselbe Fläche stattdessen per Code aus screen_size
# positioniert wurde (genau wie Hearts/Potions/BowUI unten), ist
# sie erschienen. Der Ring bekommt seine Position deshalb jetzt
# genauso per Code, siehe _setup_positions().
@onready var skill_ring: Control = get_node_or_null(
	"SkillRing"
)

# _setup_bow_ui() hat den Maßstab bisher immer auf Vector2.ONE
# gesetzt (unabhängig vom in der .tscn eingestellten Wert) - das
# bleibt die Basis, auf die der UI-Größe-Regler aus den
# Einstellungen multipliziert, damit sich am bisherigen Aussehen
# bei 100% nichts ändert.
var _bow_ui_base_scale: Vector2 = Vector2.ONE


# ============================================================
# SPIELER-SYSTEME
# ============================================================

var health: Node = null
var inventory: Node = null
var bow: Node = null
var spells: Node = null

var heart_sprites: Array[AnimatedSprite2D] = []


# ============================================================
# ZAUBER-UI-NODES
# ============================================================

var spell_ui: Control = null

var spell_panels: Array[Panel] = []
var spell_icons: Array[AnimatedSprite2D] = []
var spell_number_labels: Array[Label] = []


# ============================================================
# AKTIVER SKILL: SKILL-SLOT (über dem Bogen) + VIGOR-LEISTE
# (unter den Herzen), PFAD DER STÄRKE
# ============================================================

# Skill-Slot und Vigor-Leiste sind zwei EIGENSTÄNDIGE HUD-Gruppen
# (Nutzer-Wunsch: Skill-Slot einzeln über dem Bogen-Slot, Vigor-
# Leiste unter den Herzen, Gold darunter) - beide komplett per Code
# gebaut, genau wie BowUI/Zauber-Slots oben, kein eigener .tscn-Node
# nötig. Nur sichtbar, solange der "Pfad der Stärke" gewählt ist
# (siehe _process() unten) - Vigor/aktive Skills sind aktuell nur
# für diesen Pfad definiert (siehe Game/skill_tree_data.gd, Arcana/
# Resurrection sind noch leer).
# Nutzer-Rückmeldung: bei 100% (Grundgröße) waren Skill-Slot und
# Vigor-Leiste zu klein, bei 200% hat es gepasst - die GRUNDGRÖSSE
# (100%) wurde deshalb verdoppelt, statt den UI-Größe-Regler
# irgendwie zu verbiegen (der bleibt normal bei 75%-200%, genau wie
# bei jeder anderen HUD-Gruppe). "100%" zeigt jetzt also genau das,
# was vorher "200%" war - die alte, zu kleine 100%-Ansicht ist damit
# nicht mehr erreichbar.
const ACTIVE_SKILL_SLOT_SIZE: Vector2 = Vector2(80.0, 80.0)
const VIGOR_BAR_SIZE: Vector2 = Vector2(192.0, 20.0)

# Testweise von Hand abgestimmte Abstände (siehe Kommentare an den
# jeweiligen Verwendungsstellen unten) - bei Bedarf einfach hier
# anpassen, genau wie bei echos_gap_after_hearts oben.
const VIGOR_GAP_BELOW_HEARTS: float = 10.0
const GOLD_GAP_BELOW_VIGOR: float = 10.0

# Mit der oben verdoppelten ACTIVE_SKILL_SLOT_SIZE musste dieser
# Wert um genau denselben Betrag wachsen (95 + 40 = 135), damit die
# UNTERE Kante des Kästchens (die sich jetzt automatisch tiefer
# Richtung Bogen ausdehnt, siehe _update_skill_slot_position() unten)
# denselben Abstand zum Bogen-Kreis behält wie vorher - sonst hätte
# das größere Kästchen den Bogen-Kreis wieder berührt.
const SKILL_SLOT_GAP_ABOVE_BOW: float = 135.0

# CoinIcon (Player/gold_ui.gd) ist ZENTRIERT (AnimatedSprite2D-
# Standard "centered = true") - der Münz-Grafik selbst ist QUADRATISCH
# 16x16 groß, mit coin_scale = (3.5, 3.5) in der .tscn (siehe
# canvas_layer.tscn), also 56x56 auf dem Bildschirm, 28px von der
# Mitte zum Rand (in JEDE Richtung, da quadratisch - dieselbe
# Konstante gilt deshalb für x UND y). Ohne diese Konstante würde
# nur die MITTE der Münze ausgerichtet statt ihres sichtbaren Randes:
# vertikal ragte sie sonst in die Vigor-Leiste hinein, horizontal saß
# sie sichtbar zu weit links (nicht bündig mit Herzen/Vigor-Leiste).
const GOLD_COIN_HALF_SIZE_100: float = 28.0

var _skill_slot_ui: Control = null
var _skill_slot_panel: Panel = null
var _skill_slot_label: Label = null
var _skill_slot_icon: TextureRect = null
var _skill_slot_key_label: Label = null

var _vigor_bar_ui: Control = null
var _vigor_bar_bg: Panel = null
var _vigor_fill: ColorRect = null


# ============================================================
# START
# ============================================================

func _ready() -> void:
	# Ohne das hier bleibt _process() (siehe unten,
	# _refresh_active_skill_ui_visibility()) bei pausiertem Spiel
	# stehen - z.B. während die Einstellungen vom Pause-Menü aus
	# offen sind. Ein Neuaufbau von Skill-Slot/Vigor-Leiste über den
	# UI-Größe-Regler dort setzt deren visible zunächst auf false
	# (siehe _setup_skill_slot_ui()/_setup_vigor_bar_ui()) - ohne
	# laufendes _process() bleiben sie dann bis zum Verlassen der
	# Einstellungen unsichtbar. Genau dasselbe Muster/derselbe Fix
	# wie beim XP-Ring, siehe Player/UI/skill_ring_hud.gd.
	process_mode = Node.PROCESS_MODE_ALWAYS

	set_anchors_preset(Control.PRESET_FULL_RECT)

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player == null:
		push_error("HUD: Kein Player gefunden.")
		return

	health = player.get_node_or_null(
		"Scripts/PlayerHealth"
	)

	inventory = player.get_node_or_null(
		"Scripts/PlayerInventory"
	)

	bow = player.get_node_or_null(
		"Scripts/PlayerBow"
	)

	spells = player.get_node_or_null(
		"Scripts/PlayerSpells"
	)

	if health == null:
		push_error("HUD: PlayerHealth fehlt.")
		return

	if inventory == null:
		push_error("HUD: PlayerInventory fehlt.")
		return

	for child in hearts_node.get_children():
		if child is AnimatedSprite2D:
			heart_sprites.append(child)

	# Vitality (Pfad der Stärke, siehe Game/skill_tree_data.gd) kann
	# ein zusätzliches Herz freischalten - im .tscn gibt es aber fest
	# nur 3 Herz-Nodes (siehe Player/UI/canvas_layer.tscn). Ein
	# viertes wird deshalb bei Bedarf hier per Code dazugebaut, genau
	# wie schon der Skill-Baum (skill_tree_menu.gd) komplett ohne
	# eigene .tscn-Nodes auskommt.
	_ensure_heart_slot_count(
		health.get_max_health() if health != null else heart_sprites.size()
	)

	_setup_positions()
	_setup_bow_ui()
	_setup_spell_ui()
	_setup_echos_ui()
	_setup_skill_slot_ui()
	_setup_vigor_bar_ui()
	_update_gold_position()

	_connect_health_signals()
	_connect_inventory_signals()
	_connect_bow_signals()
	_connect_spell_signals()
	_connect_active_skill_signals()

	_set_all_heart_static()

	_update_potions(
		inventory.current_potions
	)

	if bow != null:
		_on_bow_changed(
			bow.bow_unlocked
		)

		_on_arrows_changed(
			bow.current_arrows,
			bow.max_arrows
		)

	# Zeigt sofort die bereits im RunState gespeicherten Zauber.
	if spells != null and "spell_slots" in spells:
		_on_spells_changed(
			spells.spell_slots
		)
	else:
		clear_all_spell_icons()

	if not get_viewport().size_changed.is_connected(
		_on_viewport_size_changed
	):
		get_viewport().size_changed.connect(
			_on_viewport_size_changed
		)

	if get_node_or_null("/root/SettingsManager") != null:
		if not SettingsManager.hud_scale_changed.is_connected(
			_on_hud_scale_changed
		):
			SettingsManager.hud_scale_changed.connect(
				_on_hud_scale_changed
			)


# ============================================================
# SIGNALE VERBINDEN
# ============================================================

func _connect_health_signals() -> void:
	if not health.health_changed.is_connected(
		_on_health_changed
	):
		health.health_changed.connect(
			_on_health_changed
		)

	if not health.armor_changed.is_connected(
		_on_armor_changed
	):
		health.armor_changed.connect(
			_on_armor_changed
		)

	if not health.armor_broken.is_connected(
		_on_armor_broken
	):
		health.armor_broken.connect(
			_on_armor_broken
		)


func _connect_inventory_signals() -> void:
	if not inventory.potions_changed.is_connected(
		_on_potions_changed
	):
		inventory.potions_changed.connect(
			_on_potions_changed
		)

	if not inventory.potion_used.is_connected(
		_on_potion_used
	):
		inventory.potion_used.connect(
			_on_potion_used
		)


func _connect_bow_signals() -> void:
	if bow == null:
		return

	if not bow.bow_changed.is_connected(
		_on_bow_changed
	):
		bow.bow_changed.connect(
			_on_bow_changed
		)

	if not bow.arrows_changed.is_connected(
		_on_arrows_changed
	):
		bow.arrows_changed.connect(
			_on_arrows_changed
		)


func _connect_spell_signals() -> void:
	if spells == null:
		push_warning(
			"HUD: PlayerSpells wurde nicht gefunden."
		)
		return

	if not spells.spells_changed.is_connected(
		_on_spells_changed
	):
		spells.spells_changed.connect(
			_on_spells_changed
		)


func _connect_active_skill_signals() -> void:
	if get_node_or_null("/root/RunState") != null:
		if not RunState.vigor_changed.is_connected(
			_on_vigor_changed
		):
			RunState.vigor_changed.connect(_on_vigor_changed)

		if not RunState.equipped_active_skill_changed.is_connected(
			_on_equipped_active_skill_changed
		):
			RunState.equipped_active_skill_changed.connect(
				_on_equipped_active_skill_changed
			)

		_on_vigor_changed(RunState.current_vigor, RunState.VIGOR_MAX)
		_on_equipped_active_skill_changed(RunState.equipped_active_skill)

	if get_node_or_null("/root/SettingsManager") != null:
		if not SettingsManager.controls_changed.is_connected(
			_on_controls_changed
		):
			SettingsManager.controls_changed.connect(
				_on_controls_changed
			)

	_refresh_skill_key_label()


# ============================================================
# BESTEHENDE HUD-POSITIONEN
# ============================================================

func _setup_positions() -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	var hearts_scale: float = _get_hud_scale(&"hearts")

	hearts_node.position = Vector2(
		_corner_margin(28.0, hearts_scale),
		_corner_margin(28.0, hearts_scale)
	)
	hearts_node.scale = Vector2(hearts_scale, hearts_scale)

	for i in heart_sprites.size():
		var heart := heart_sprites[i]

		heart.visible = true
		heart.centered = true
		heart.scale = Vector2(3, 3)
		heart.position = Vector2(i * 48, 0)

	var potions_scale: float = _get_hud_scale(&"potions")

	potions_node.position = Vector2(
		_corner_margin(28.0, potions_scale),
		screen_size.y - _corner_margin(42.0, potions_scale)
	)
	potions_node.scale = Vector2(potions_scale, potions_scale)

	potion_icon.visible = true
	potion_icon.centered = true
	potion_icon.scale = Vector2(3, 3)
	potion_icon.position = Vector2.ZERO

	potion_label.visible = true
	potion_label.position = Vector2(44, -8)

	# XP-Ring oben rechts - Position per Code, aus demselben Grund
	# wie oben beim skill_ring-Feld erklärt: Anker allein haben bei
	# diesem Node nicht funktioniert, Code-Positionierung (wie bei
	# jedem anderen HUD-Element hier) schon.
	#
	# Skaliert (wie Herzen/Bogen) um den eigenen Mittelpunkt statt um
	# die obere linke Ecke - pivot_offset liegt deshalb auf (45, 45),
	# der Mitte der 90x90-Box, in der _draw() den Ring zeichnet.
	# Ursprünglich (100%) sitzt diese Mitte bei screen.x - 65 / 69 -
	# über _corner_margin() wandert sie bei größerer UI-Größe weiter
	# nach innen, damit der Ring nicht über den Bildschirmrand
	# hinauswächst (exakt dasselbe Prinzip wie bei _setup_bow_ui()).
	var skill_ring_scale: float = _get_hud_scale(&"skill_ring")

	if skill_ring != null:
		skill_ring.size = Vector2(90.0, 90.0)
		skill_ring.pivot_offset = Vector2(45.0, 45.0)

		var skill_ring_center: Vector2 = Vector2(
			screen_size.x - _corner_margin(65.0, skill_ring_scale),
			_corner_margin(69.0, skill_ring_scale)
		)

		skill_ring.position = (
			skill_ring_center - Vector2(45.0, 45.0)
		)
		skill_ring.scale = Vector2(
			skill_ring_scale,
			skill_ring_scale
		)


# ============================================================
# BOGEN-UI
# ============================================================

func _setup_bow_ui() -> void:
	if bow_ui == null:
		return

	var screen := get_viewport_rect().size

	var bow_scale: float = _get_hud_scale(&"bow")

	bow_ui.position = Vector2(
		screen.x - _corner_margin(85.0, bow_scale),
		screen.y - _corner_margin(70.0, bow_scale)
	)
	bow_ui.scale = _bow_ui_base_scale * bow_scale

	if bow_circle != null:
		bow_circle.visible = true
		bow_circle.centered = true
		bow_circle.scale = Vector2.ONE
		bow_circle.position = Vector2.ZERO

		_play_anim_safe(
			bow_circle,
			"default"
		)

	if bow_icon != null:
		bow_icon.centered = true
		bow_icon.scale = Vector2.ONE
		bow_icon.position = Vector2.ZERO
		bow_icon.visible = false

		_play_anim_safe(
			bow_icon,
			"default"
		)

	if arrow_circle != null:
		arrow_circle.visible = true
		arrow_circle.centered = true
		arrow_circle.scale = Vector2.ONE
		arrow_circle.position = Vector2(28, 24)

		_play_anim_safe(
			arrow_circle,
			"default"
		)

	if arrow_icon != null:
		arrow_icon.centered = true
		arrow_icon.scale = Vector2(0.55, 0.55)
		arrow_icon.position = Vector2(28, 24)
		arrow_icon.visible = false

		_play_anim_safe(
			arrow_icon,
			"default"
		)

	if arrow_label != null:
		arrow_label.position = Vector2(39, 32)
		arrow_label.visible = false
		arrow_label.text = "0"


# ============================================================
# ZAUBER-UI ERSTELLEN
# ============================================================

func _setup_spell_ui() -> void:
	if spell_ui != null and is_instance_valid(spell_ui):
		spell_ui.queue_free()

	spell_panels.clear()
	spell_icons.clear()
	spell_number_labels.clear()

	spell_ui = Control.new()
	spell_ui.name = "SpellUI"
	spell_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(spell_ui)

	var total_width: float = (
		spell_slot_size.x
		+ spell_slot_spacing * 2.0
	)

	spell_ui.size = Vector2(
		total_width,
		spell_slot_size.y
	)

	# Skaliert um die eigene Mitte statt um die obere linke Ecke,
	# damit die Zauber-Slots beim Größerstellen nicht Richtung
	# Bildschirmrand wandern.
	spell_ui.pivot_offset = spell_ui.size / 2.0

	var spells_scale: float = _get_hud_scale(&"spells")
	spell_ui.scale = Vector2(spells_scale, spells_scale)

	_update_spell_ui_position()

	for i in range(3):
		_create_spell_slot(i)


func _create_spell_slot(slot_index: int) -> void:
	var panel := Panel.new()

	panel.name = "SpellSlot" + str(
		slot_index + 1
	)

	panel.position = Vector2(
		slot_index * spell_slot_spacing,
		0
	)

	panel.size = spell_slot_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	spell_ui.add_child(panel)

	var style := StyleBoxFlat.new()

	style.bg_color = spell_slot_background_color
	style.border_color = spell_slot_border_color

	style.set_border_width_all(
		spell_slot_border_width
	)

	panel.add_theme_stylebox_override(
		"panel",
		style
	)

	var icon := AnimatedSprite2D.new()

	icon.name = "SpellIcon"
	icon.position = spell_icon_position
	icon.scale = spell_icon_scale
	icon.centered = true
	icon.visible = false

	if spell_icon_frames != null:
		icon.sprite_frames = spell_icon_frames

	panel.add_child(icon)

	var number_label := Label.new()

	number_label.name = "SpellNumber"
	number_label.text = str(slot_index + 1)
	number_label.position = spell_number_position
	number_label.size = spell_number_size
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	number_label.add_theme_color_override(
		"font_color",
		spell_number_color
	)

	panel.add_child(number_label)

	spell_panels.append(panel)
	spell_icons.append(icon)
	spell_number_labels.append(number_label)


func _update_spell_ui_position() -> void:
	if spell_ui == null:
		return

	var screen_size := get_viewport_rect().size
	var spells_scale: float = _get_hud_scale(&"spells")

	spell_ui.position = screen_size + Vector2(
		-_corner_margin(
			abs(spell_ui_offset_from_bottom_right.x),
			spells_scale
		),
		-_corner_margin(
			abs(spell_ui_offset_from_bottom_right.y),
			spells_scale
		)
	)


# ============================================================
# SKILL-SLOT ERSTELLEN (EIGENSTÄNDIG, ÜBER DEM BOGEN-SLOT)
# ============================================================

func _setup_skill_slot_ui() -> void:
	if _skill_slot_ui != null and is_instance_valid(_skill_slot_ui):
		_skill_slot_ui.queue_free()

	_skill_slot_ui = Control.new()
	_skill_slot_ui.name = "SkillSlotUI"
	_skill_slot_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_slot_ui.visible = false

	add_child(_skill_slot_ui)

	_skill_slot_ui.size = ACTIVE_SKILL_SLOT_SIZE

	# Skaliert um die eigene Mitte, genau wie SpellUI oben - sonst
	# würde der Slot beim Größerstellen Richtung Bildschirmrand
	# wandern statt an Ort und Stelle zu wachsen.
	_skill_slot_ui.pivot_offset = _skill_slot_ui.size / 2.0

	var skill_slot_scale: float = _get_hud_scale(&"skill_slot")
	_skill_slot_ui.scale = Vector2(skill_slot_scale, skill_slot_scale)

	_skill_slot_panel = Panel.new()
	_skill_slot_panel.name = "SkillSlot"
	_skill_slot_panel.position = Vector2.ZERO
	_skill_slot_panel.size = ACTIVE_SKILL_SLOT_SIZE
	_skill_slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = spell_slot_background_color
	slot_style.border_color = spell_slot_border_color
	slot_style.set_border_width_all(spell_slot_border_width)
	_skill_slot_panel.add_theme_stylebox_override("panel", slot_style)

	_skill_slot_ui.add_child(_skill_slot_panel)

	_skill_slot_label = Label.new()
	_skill_slot_label.name = "SkillLabel"
	_skill_slot_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skill_slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_slot_label.clip_text = true
	_skill_slot_label.add_theme_font_size_override("font_size", 9)
	_skill_slot_panel.add_child(_skill_slot_label)

	# Nutzer-Wunsch: das Icon des ausgerüsteten Skills (dasselbe wie
	# im Skill-Baum, siehe Game/skill_tree_data.gd -> get_skill_icon_
	# texture()) soll HIER im aktiven Skill-Slot erscheinen, statt nur
	# der Name als Text - siehe _refresh_skill_slot_label() unten.
	# Kleiner Rand zum Kästchenrand, damit der farbige Rahmen von
	# slot_style oben sichtbar bleibt.
	_skill_slot_icon = TextureRect.new()
	_skill_slot_icon.name = "SkillIcon"
	_skill_slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skill_slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skill_slot_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_skill_slot_icon.offset_left = 6.0
	_skill_slot_icon.offset_right = -6.0
	_skill_slot_icon.offset_top = 6.0
	_skill_slot_icon.offset_bottom = -6.0
	_skill_slot_icon.visible = false
	_skill_slot_panel.add_child(_skill_slot_icon)

	_skill_slot_key_label = Label.new()
	_skill_slot_key_label.name = "SkillKeyLabel"

	# Oben links IM Kästchen statt darüber - genau wie die
	# Zauber-Nummer bei den Zauber-Slots (siehe spell_number_position/
	# _create_spell_slot() oben, dasselbe Prinzip wiederverwendet).
	_skill_slot_key_label.position = spell_number_position
	_skill_slot_key_label.size = spell_number_size

	_skill_slot_key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_slot_key_label.add_theme_font_size_override("font_size", 12)
	_skill_slot_key_label.add_theme_color_override(
		"font_color",
		Color(0.95, 0.9, 0.65, 1.0)
	)
	_skill_slot_panel.add_child(_skill_slot_key_label)

	_update_skill_slot_position()

	if get_node_or_null("/root/RunState") != null:
		_on_equipped_active_skill_changed(RunState.equipped_active_skill)

	_refresh_skill_key_label()


func _update_skill_slot_position() -> void:
	if _skill_slot_ui == null:
		return

	if bow_ui == null:
		return

	var skill_slot_scale: float = _get_hud_scale(&"skill_slot")

	# Horizontal auf die Mitte des Bogen-Kreises ausgerichtet (siehe
	# _setup_bow_ui() - bow_ui.position ist dessen Mittelpunkt) und
	# darüber platziert, mit etwas Abstand zum Bogen-Kreis (siehe
	# SKILL_SLOT_GAP_ABOVE_BOW oben, von Hand abgestimmt).
	#
	# WICHTIG: Die x-Verschiebung um die halbe Kästchenbreite NICHT
	# mit skill_slot_scale multiplizieren - pivot_offset (siehe unten,
	# = Kästchengröße/2) sorgt schon von sich aus dafür, dass das
	# Kästchen bei jeder Größe um denselben Mittelpunkt herum wächst,
	# solange position.x + Größe/2 (UNSKALIERT) konstant bleibt. Mit
	# einer zusätzlichen Skalierung hier würde sich das Kästchen bei
	# größerer UI-Größe zusätzlich nach links verschieben, statt sauber
	# um den Bogen-Mittelpunkt zu wachsen (Symptom: wandert bei hohem
	# Prozentwert Richtung/über den Bildschirmrand - derselbe Fehler,
	# der bei der Vigor-Leiste unten gerade behoben wurde).
	_skill_slot_ui.position = Vector2(
		bow_ui.position.x - ACTIVE_SKILL_SLOT_SIZE.x / 2.0,
		bow_ui.position.y
		- _corner_margin(SKILL_SLOT_GAP_ABOVE_BOW, skill_slot_scale)
	)


# ============================================================
# VIGOR-LEISTE ERSTELLEN (EIGENSTÄNDIG, UNTER DEN HERZEN)
# ============================================================

func _setup_vigor_bar_ui() -> void:
	if _vigor_bar_ui != null and is_instance_valid(_vigor_bar_ui):
		_vigor_bar_ui.queue_free()

	_vigor_bar_ui = Control.new()
	_vigor_bar_ui.name = "VigorBarUI"
	_vigor_bar_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vigor_bar_ui.visible = false

	add_child(_vigor_bar_ui)

	_vigor_bar_ui.size = VIGOR_BAR_SIZE

	# BEWUSST kein pivot_offset (bleibt (0,0), Standard) - anders als
	# bei zentrumsverankerten Gruppen wie SpellUI/SkillSlotUI soll die
	# Vigor-Leiste an ihrer LINKEN Kante an den Herzen ausgerichtet
	# bleiben (siehe _update_vigor_bar_position()) und nur nach
	# rechts/unten wachsen. Mit pivot_offset = Größe/2 (wie ursprünglich
	# hier gesetzt) wächst eine Control-Node dagegen um ihre MITTE -
	# bei hoher UI-Größe (getestet: 200%) wanderte die linke Kante der
	# Leiste dadurch weit nach LINKS, bis sie aus dem Bildschirmrand
	# herauslief. Ohne pivot_offset bleibt position.x (=hearts_node.
	# position.x) exakt die linke Kante, unabhängig vom Skalierungswert.
	var vigor_scale: float = _get_hud_scale(&"vigor")
	_vigor_bar_ui.scale = Vector2(vigor_scale, vigor_scale)

	_vigor_bar_bg = Panel.new()
	_vigor_bar_bg.name = "VigorBar"
	_vigor_bar_bg.position = Vector2.ZERO
	_vigor_bar_bg.size = VIGOR_BAR_SIZE
	_vigor_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vigor_bg_style := StyleBoxFlat.new()
	vigor_bg_style.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	vigor_bg_style.border_color = Color(0.75, 0.75, 0.75, 0.9)
	vigor_bg_style.set_border_width_all(1)
	_vigor_bar_bg.add_theme_stylebox_override("panel", vigor_bg_style)

	_vigor_bar_ui.add_child(_vigor_bar_bg)

	_vigor_fill = ColorRect.new()
	_vigor_fill.name = "VigorFill"
	_vigor_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vigor_fill.color = Color(0.85, 0.25, 0.2, 1.0)
	_vigor_fill.position = Vector2(1.0, 1.0)
	_vigor_fill.size = Vector2(0.0, VIGOR_BAR_SIZE.y - 2.0)
	_vigor_bar_bg.add_child(_vigor_fill)

	_update_vigor_bar_position()

	if get_node_or_null("/root/RunState") != null:
		_on_vigor_changed(RunState.current_vigor, RunState.VIGOR_MAX)


func _update_vigor_bar_position() -> void:
	if _vigor_bar_ui == null:
		return

	if hearts_node == null:
		return

	# Direkt unter der Herzreihe: hearts_node.position ist NICHT die
	# linke Kante der Herzen, sondern die Position/Mitte des ERSTEN
	# Herzes (heart.position = Vector2(0,0) lokal, UND centered=true,
	# siehe _setup_positions()) - die sichtbare linke Kante der
	# Herzreihe liegt deshalb 24 Einheiten (halbe Herzbreite, 48/2)
	# weiter LINKS als hearts_node.position.x. Ohne diesen Ausgleich
	# säße die Vigor-Leiste sichtbar zu weit rechts, nicht bündig mit
	# den Herzen (siehe Nutzer-Rückmeldung "sollte ein wenig nach
	# links"). Mit hearts_scale ergibt das jeweils die halbe Breite/
	# Höhe der Herzreihe auf dem Bildschirm - genau dasselbe Prinzip
	# wie bei echos_node oben, das ebenfalls relativ zu den Herzen
	# sitzt.
	var hearts_scale: float = _get_hud_scale(&"hearts")

	_vigor_bar_ui.position = Vector2(
		hearts_node.position.x - 24.0 * hearts_scale,
		hearts_node.position.y
		+ 24.0 * hearts_scale
		+ VIGOR_GAP_BELOW_HEARTS * hearts_scale
	)


# ============================================================
# GOLD-ANZEIGE (GoldUI, Player/gold_ui.gd) UNTER DER VIGOR-LEISTE
# ============================================================

# GoldUI positioniert sich normalerweise komplett selbst (siehe
# gold_ui.gd -> _apply_hud_scale(), fester ui_position-Eck-Abstand).
# Da Gold jetzt aber unter der (an die Herzen gekoppelten, dynamisch
# positionierten) Vigor-Leiste hängen soll, übernimmt das HUD hier
# die Positionierung - siehe gold_ui.gd -> set_external_position(),
# das die eigene ui_position-Berechnung dafür deaktiviert.
func _update_gold_position() -> void:
	if gold_ui == null:
		return

	if hearts_node == null or _vigor_bar_ui == null:
		return

	var hearts_scale: float = _get_hud_scale(&"hearts")
	var vigor_scale: float = _get_hud_scale(&"vigor")
	var gold_scale: float = _get_hud_scale(&"gold")

	# GoldUI zeichnet CoinIcon/GoldLabel NICHT bei (0,0) der eigenen
	# Control-Node, sondern intern versetzt (siehe gold_ui.gd export
	# coin_position, in der .tscn auf (20, 55) gesetzt - historisch so
	# gewählt, als GoldUI noch fest oben links am Bildschirmrand saß).
	# Ohne diesen Versatz hier herauszurechnen, würde die SICHTBARE
	# Münze viel weiter unten als der eigentliche Ziel-Abstand
	# GOLD_GAP_BELOW_VIGOR erscheinen ("viel zu viel Abstand").
	var coin_offset: Vector2 = gold_ui.coin_position * gold_scale

	# Herzreihe links bündig (siehe _update_vigor_bar_position() oben -
	# hearts_node.position.x ist die MITTE des ersten Herzes, die
	# sichtbare linke Kante liegt 24 Einheiten weiter links).
	var hearts_left_edge: float = hearts_node.position.x - 24.0 * hearts_scale

	# CoinIcon ist ZENTRIERT (siehe GOLD_COIN_HALF_SIZE_100 oben) - der
	# Ziel-Wert soll aber jeweils der sichtbare RAND der Münze sein,
	# nicht ihre Mitte:
	#   - x: die sichtbare LINKE Kante der Münze soll bündig mit der
	#     linken Kante von Herzen/Vigor-Leiste sein (Nutzer-Wunsch:
	#     "gleichen Abstand zum Rand ... alles gleich in der Reihe") -
	#     deshalb die Mitte um den halben Münz-Durchmesser nach RECHTS
	#     verschoben.
	#   - y: der sichtbare OBERE Rand der Münze soll GOLD_GAP_BELOW_
	#     VIGOR Abstand zur Vigor-Leiste haben - deshalb die Mitte um
	#     denselben Betrag nach UNTEN verschoben (ohne das ragte die
	#     Münze in die Vigor-Leiste hinein).
	gold_ui.set_external_position(Vector2(
		hearts_left_edge + GOLD_COIN_HALF_SIZE_100 * gold_scale
		- coin_offset.x,
		_vigor_bar_ui.position.y
		+ VIGOR_BAR_SIZE.y * vigor_scale
		+ GOLD_GAP_BELOW_VIGOR * hearts_scale
		+ GOLD_COIN_HALF_SIZE_100 * gold_scale
		- coin_offset.y
	))


func _on_viewport_size_changed() -> void:
	_setup_positions()
	_setup_bow_ui()
	_update_spell_ui_position()
	_setup_echos_ui()
	_update_skill_slot_position()
	_update_vigor_bar_position()
	_update_gold_position()


# ============================================================
# UI-GRÖSSE (EINSTELLUNGEN)
# ============================================================

func _get_hud_scale(category: StringName) -> float:
	if get_node_or_null("/root/SettingsManager") == null:
		return 1.0

	return SettingsManager.get_hud_scale(category)


# Wandelt einen bei 100% von Hand eingestellten Eck-Abstand in
# den tatsächlich zu verwendenden Abstand beim aktuellen
# UI-Größe-Faktor um (siehe SettingsManager.get_corner_margin -
# bei 100% unverändert, darüber/darunter stärker nach innen/
# außen verschoben). Ohne SettingsManager bleibt der Abstand
# unverändert (Faktor 1.0 = ursprüngliche Position).
func _corner_margin(base_margin: float, scale_factor: float) -> float:
	if get_node_or_null("/root/SettingsManager") == null:
		return base_margin

	return SettingsManager.get_corner_margin(
		base_margin,
		scale_factor
	)


func _on_hud_scale_changed(
	category: StringName,
	_scale: float
) -> void:
	match category:
		&"hearts":
			_setup_positions()
			_update_vigor_bar_position()
			_update_gold_position()

		&"potions", &"skill_ring":
			_setup_positions()

		&"bow":
			_setup_bow_ui()
			_reapply_bow_state()
			_update_skill_slot_position()

		&"spells":
			_setup_spell_ui()
			_reapply_spell_state()

		&"echo_der_flamme":
			_setup_echos_ui()

		&"skill_slot":
			_setup_skill_slot_ui()

		&"vigor":
			_setup_vigor_bar_ui()
			_update_gold_position()

		&"gold":
			_update_gold_position()


# _setup_bow_ui() versteckt Bogen-/Pfeil-Icons beim Neuaufbau
# (z.B. bei einer UI-Größe-Änderung) grundsätzlich erstmal wieder,
# genau wie beim allerersten _ready(). Deshalb muss danach wie
# beim Start der aktuelle Freischalt-/Pfeil-Status erneut ange-
# wendet werden - sonst verschwindet ein bereits freigeschalteter
# Bogen nach dem Verstellen des Reglers.
func _reapply_bow_state() -> void:
	if bow == null:
		return

	_on_bow_changed(bow.bow_unlocked)

	_on_arrows_changed(
		bow.current_arrows,
		bow.max_arrows
	)


# Dasselbe Prinzip wie bei _reapply_bow_state(): _setup_spell_ui()
# baut alle Zauber-Slots komplett neu (und damit unsichtbar) auf -
# der aktuell ausgerüstete Zauber muss danach erneut angezeigt
# werden.
func _reapply_spell_state() -> void:
	if spells != null and "spell_slots" in spells:
		_on_spells_changed(spells.spell_slots)
	else:
		clear_all_spell_icons()


# ============================================================
# PLAYER SPELLS → HUD
# ============================================================

func _on_spells_changed(
	new_spell_slots: Array
) -> void:
	for slot_index in range(spell_icons.size()):
		if slot_index >= new_spell_slots.size():
			clear_spell_icon(slot_index)
			continue

		var spell_id: String = str(
			new_spell_slots[slot_index]
		)

		if spell_id.is_empty():
			clear_spell_icon(slot_index)
			continue

		show_spell_icon(
			slot_index,
			spell_id
		)


func show_spell_icon(
	slot_index: int,
	spell_id: String
) -> void:
	if slot_index < 0:
		return

	if slot_index >= spell_icons.size():
		return

	var icon := spell_icons[slot_index]

	if icon == null:
		return

	if icon.sprite_frames == null:
		push_warning(
			"HUD: Spell Icon Frames wurden nicht gesetzt."
		)
		return

	if not icon.sprite_frames.has_animation(
		spell_id
	):
		push_warning(
			"HUD: Zauber-Icon fehlt: "
			+ spell_id
		)

		icon.visible = false
		return

	icon.visible = true
	icon.play(spell_id)
	icon.frame = 0
	icon.pause()


func clear_spell_icon(slot_index: int) -> void:
	if slot_index < 0:
		return

	if slot_index >= spell_icons.size():
		return

	var icon := spell_icons[slot_index]

	if icon == null:
		return

	icon.stop()
	icon.visible = false


func clear_all_spell_icons() -> void:
	for i in range(spell_icons.size()):
		clear_spell_icon(i)


# ============================================================
# LEBEN UND RÜSTUNG
# ============================================================

func _on_health_changed(
	_current_health: int,
	max_health: int,
	_old_health: int
) -> void:
	_ensure_heart_slot_count(max_health)
	_set_all_heart_static()


# Kleiner Korrektur-Versatz NACH OBEN (in Bildschirm-Pixeln, NICHT
# in den lokalen Sprite-Einheiten von heart.offset), damit ein
# gerüstetes Herz exakt auf derselben Höhe wie ein ungerüstetes Herz
# sitzt - die gerüsteten Animationen ("armor_*"/"Iron heart *") sind
# in ihrer eigenen Grafik minimal tiefer gezeichnet als "full"/
# "empty". BEWUSST NUR dieser 1-Pixel-Korrekturwert per Code, sonst
# NICHTS - das Herz bleibt ansonsten exakt so positioniert, wie es
# schon im AnimatedSprite2D/den Animationen selbst hinterlegt ist
# (kein erzwungenes Zurücksetzen von offset auf einen anderen Wert
# als das, was ohne dieses Skript ohnehin gelten würde).
#
# WICHTIG (Ursache der bisherigen "viel zu hoch"-Fehlversuche):
# heart.offset wirkt im LOKALEN Sprite-Raum, VOR heart.scale =
# Vector2(3, 3) (siehe _setup_positions()) - ein roher Offset-Wert
# von z.B. -4.0 verschiebt das Herz deshalb um -12 Bildschirm-Pixel,
# nicht um -4. _apply_heart_armor_offset() unten rechnet diesen
# Bildschirm-Pixel-Wert deshalb erst durch heart.scale.y, bevor er
# auf heart.offset.y angewendet wird.
@export var armor_heart_y_offset_px: float = 1.0


# Rüstungs-Animationsnamen je Rüstungsart (siehe player_health.gd,
# ARMOR_TYPE_SHIELD/ARMOR_TYPE_IRON). Beide Sätze liegen in derselben
# Herz-SpriteFrames-Ressource (Player/UI/canvas_layer.tscn):
# "shield" nutzt die schon lange bestehenden "armor_*"-Animationen,
# "iron" die vom Nutzer neu hinzugefügten "Iron heart *"-Animationen.
# Unbekannte/leere Rüstungsart fällt defensiv auf "shield" zurück.
const _ARMOR_ANIM_NAMES: Dictionary = {
	"shield": {
		"get_on": "armor_get_on",
		"equip": "armor_equip",
		"break": "armor_break",
	},
	"iron": {
		"get_on": "Iron heart get on",
		"equip": "Iron heart equip",
		"break": "Iron heart break",
	},
}


func _armor_anim_name(
	armor_type: StringName,
	phase: String
) -> String:
	var key: String = String(armor_type)

	if not _ARMOR_ANIM_NAMES.has(key):
		key = "shield"

	return _ARMOR_ANIM_NAMES[key][phase]


# Wendet die 1-Pixel-Korrektur (siehe armor_heart_y_offset_px oben)
# an, oder nimmt sie zurück - is_armored true, solange das Herz eine
# der "Rüstung dran"-Animationen zeigt (get_on/equip/break),
# andernfalls false. Rechnet den Bildschirm-Pixel-Wert korrekt durch
# heart.scale.y (siehe Kommentar oben), statt ihn roh auf offset.y zu
# schreiben.
func _apply_heart_armor_offset(
	heart: AnimatedSprite2D,
	is_armored: bool
) -> void:
	if heart == null:
		return

	if not is_armored:
		heart.offset.y = 0.0
		return

	if is_zero_approx(heart.scale.y):
		return

	heart.offset.y = -armor_heart_y_offset_px / heart.scale.y


func _on_armor_changed(
	current_armor: int,
	_max_armor: int,
	old_armor: int
) -> void:
	if current_armor > old_armor:
		var index := current_armor - 1

		_set_all_heart_static(index)

		if (
			index >= 0
			and index < heart_sprites.size()
			and health != null
		):
			var heart := heart_sprites[index]

			var armor_type: StringName = &""

			if index < health.armor_types.size():
				armor_type = health.armor_types[index]

			_apply_heart_armor_offset(heart, true)

			_play_anim_safe(
				heart,
				_armor_anim_name(armor_type, "get_on")
			)

			await heart.animation_finished

			_set_static_anim(
				heart,
				_armor_anim_name(armor_type, "equip")
			)

		return


func _on_armor_broken(
	armor_index: int,
	armor_type: StringName
) -> void:
	_set_all_heart_static(
		armor_index
	)

	if (
		armor_index >= 0
		and armor_index < heart_sprites.size()
	):
		var heart := heart_sprites[
			armor_index
		]

		_apply_heart_armor_offset(heart, true)

		_play_anim_safe(
			heart,
			_armor_anim_name(armor_type, "break")
		)

		await heart.animation_finished

		_apply_heart_armor_offset(heart, false)

		_set_static_anim(
			heart,
			"full"
		)

	_set_all_heart_static(
		armor_index
	)


# Baut bei Bedarf weitere Herz-Icons dazu, falls target_count über
# der Anzahl der im .tscn fest angelegten Herzen liegt (aktuell 3,
# siehe Player/UI/canvas_layer.tscn) - z.B. durch den Vitality-Skill
# ("+1 maximales Herz", Pfad der Stärke, siehe Game/skill_tree_data.
# gd). Übernimmt SpriteFrames vom ersten vorhandenen Herz als
# Vorlage, damit ein neues Herz genau gleich aussieht, und ruft am
# Ende _setup_positions() auf, damit auch das neue Herz an der
# richtigen Stelle in der Reihe landet.
func _ensure_heart_slot_count(target_count: int) -> void:
	if hearts_node == null:
		return

	if target_count <= heart_sprites.size():
		return

	var reference: AnimatedSprite2D = (
		heart_sprites[0] if not heart_sprites.is_empty() else null
	)

	while heart_sprites.size() < target_count:
		var heart := AnimatedSprite2D.new()

		heart.name = "Heart" + str(heart_sprites.size() + 1)
		heart.centered = true
		heart.scale = Vector2(3, 3)

		if reference != null:
			heart.sprite_frames = reference.sprite_frames

		hearts_node.add_child(heart)
		heart_sprites.append(heart)

	_setup_positions()


func _set_all_heart_static(
	skip_index: int = -1
) -> void:
	for i in heart_sprites.size():
		if i == skip_index:
			continue

		var heart := heart_sprites[i]

		if (
			health != null
			and i < health.armor_types.size()
			and health.armor_types[i] != &""
		):
			_apply_heart_armor_offset(heart, true)

			_set_static_anim(
				heart,
				_armor_anim_name(health.armor_types[i], "equip")
			)

		elif i < health.current_health:
			_apply_heart_armor_offset(heart, false)

			_set_static_anim(
				heart,
				"full"
			)

		else:
			_apply_heart_armor_offset(heart, false)

			_set_static_anim(
				heart,
				"empty"
			)


func _set_static_anim(
	sprite: AnimatedSprite2D,
	anim_name: String
) -> void:
	if sprite == null:
		return

	if sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(
		anim_name
	):
		return

	sprite.play(anim_name)
	sprite.frame = 0
	sprite.pause()


# ============================================================
# AKTIVER SKILL (SKILL-SLOT + VIGOR-LEISTE)
# ============================================================

# Nur sichtbar, solange der "Pfad der Stärke" gewählt ist - Vigor
# und der Skill-Slot sind aktuell nur für diesen Pfad definiert
# (siehe Game/skill_tree_data.gd, Arcana/Resurrection sind noch
# leer). Direktes Auslesen jeden Frame statt über ein Signal, GENAU
# wie beim XP-Ring (siehe Player/UI/skill_ring_hud.gd, HINWEIS dort:
# eine frühere signal-/gruppenbasierte Fassung ist an einer stillen
# Timing-Lücke gescheitert) - hier bewusst dasselbe bewährte Muster.
func _process(_delta: float) -> void:
	_refresh_active_skill_ui_visibility()


func _refresh_active_skill_ui_visibility() -> void:
	if _skill_slot_ui == null or _vigor_bar_ui == null:
		return

	var should_show: bool = (
		get_node_or_null("/root/RunState") != null
		and RunState.has_chosen_skill_path()
		and RunState.chosen_skill_path == &"skill_path.strength"
	)

	if should_show != _skill_slot_ui.visible:
		_skill_slot_ui.visible = should_show

	if should_show != _vigor_bar_ui.visible:
		_vigor_bar_ui.visible = should_show


func _on_vigor_changed(current: int, max_vigor: int) -> void:
	if _vigor_fill == null:
		return

	var max_width: float = VIGOR_BAR_SIZE.x - 2.0
	var ratio: float = 0.0

	if max_vigor > 0:
		ratio = clamp(float(current) / float(max_vigor), 0.0, 1.0)

	_vigor_fill.size = Vector2(
		max_width * ratio,
		VIGOR_BAR_SIZE.y - 2.0
	)


func _on_equipped_active_skill_changed(skill_id: StringName) -> void:
	_refresh_skill_slot_label(skill_id)


# Nutzer-Wunsch: das Icon des ausgerüsteten Skills trägt jetzt die
# Darstellung im Slot, genau wie am Knoten im Skill-Baum selbst
# (siehe Game/skill_tree_menu.gd) - der Name-Text bleibt nur noch als
# Rückfalloption, falls für den Pfad/Skill (noch) kein Icon hinterlegt
# ist (siehe Game/skill_tree_data.gd -> get_skill_icon_texture()).
func _refresh_skill_slot_label(skill_id: StringName) -> void:
	if _skill_slot_label == null:
		return

	if skill_id == &"":
		_skill_slot_label.text = ""

		if _skill_slot_icon != null:
			_skill_slot_icon.visible = false

		return

	if (
		get_node_or_null("/root/RunState") == null
		or get_node_or_null("/root/SettingsManager") == null
	):
		return

	var skill: Dictionary = SkillTreeData.get_skill(
		RunState.chosen_skill_path,
		skill_id
	)

	if skill.is_empty():
		_skill_slot_label.text = ""

		if _skill_slot_icon != null:
			_skill_slot_icon.visible = false

		return

	var icon_texture: Texture2D = SkillTreeData.get_skill_icon_texture(
		RunState.chosen_skill_path,
		skill_id
	)

	if icon_texture != null and _skill_slot_icon != null:
		_skill_slot_icon.texture = icon_texture
		_skill_slot_icon.visible = true
		_skill_slot_label.text = ""
	else:
		if _skill_slot_icon != null:
			_skill_slot_icon.visible = false

		_skill_slot_label.text = SettingsManager.t(
			String(skill.get("name_key", ""))
		)


# Zeigt die aktuell gebundene Taste für "use_skill" (Standard "E")
# im Skill-Slot an - wird beim Start UND nach jedem Rebind in den
# Einstellungen neu geholt (siehe _on_controls_changed()), damit die
# Anzeige nach einem Tastenwechsel weiter stimmt.
#
# WICHTIG: bewusst SettingsManager.get_binding_text() statt direkt
# InputEventKey.as_text() - unsere Tasten-Belegungen (siehe project.
# godot) setzen nur physical_keycode, keinen normalen keycode, und
# as_text() hängt dafür ein zusätzliches " (Physical)" an (z.B. wurde
# "E" so zu "E (Physical)"). get_binding_text() nutzt stattdessen
# as_text_physical_keycode() (siehe Game/settings_manager.gd), das
# nur den reinen Tasten-Buchstaben liefert - genau wie an den
# Zauber-Slots, wo auch nur die reine Zahl steht, nichts weiter.
func _refresh_skill_key_label() -> void:
	if _skill_slot_key_label == null:
		return

	if get_node_or_null("/root/SettingsManager") == null:
		_skill_slot_key_label.text = ""
		return

	_skill_slot_key_label.text = SettingsManager.get_binding_text(&"use_skill")


func _on_controls_changed(action_name: StringName) -> void:
	if action_name == &"use_skill":
		_refresh_skill_key_label()


# ============================================================
# TRÄNKE
# ============================================================

func _on_potions_changed(
	current_potions: int,
	_max_potions: int
) -> void:
	_update_potions(
		current_potions
	)


func _update_potions(
	current_potions: int
) -> void:
	potion_label.text = (
		"x"
		+ str(current_potions)
	)

	if current_potions > 0:
		_set_static_anim(
			potion_icon,
			"full"
		)
	else:
		_set_static_anim(
			potion_icon,
			"empty"
		)


func _on_potion_used() -> void:
	_play_anim_safe(
		potion_icon,
		"use"
	)

	await potion_icon.animation_finished

	_update_potions(
		inventory.current_potions
	)


# ============================================================
# BOGEN UND PFEILE
# ============================================================

func _on_bow_changed(
	unlocked: bool
) -> void:
	if bow_icon != null:
		bow_icon.visible = unlocked

	if arrow_icon != null:
		arrow_icon.visible = unlocked

	if arrow_label != null:
		arrow_label.visible = unlocked


func _on_arrows_changed(
	current_arrows: int,
	_max_arrows: int
) -> void:
	if arrow_label != null:
		arrow_label.text = str(
			current_arrows
		)

	if bow != null:
		if arrow_icon != null:
			arrow_icon.visible = (
				bow.bow_unlocked
			)

		if arrow_label != null:
			arrow_label.visible = (
				bow.bow_unlocked
			)


# ============================================================
# HILFSFUNKTIONEN
# ============================================================

func _play_anim_safe(
	sprite: AnimatedSprite2D,
	anim_name: String
) -> void:
	if sprite == null:
		return

	if sprite.sprite_frames == null:
		return

	if sprite.sprite_frames.has_animation(
		anim_name
	):
		sprite.play(anim_name)


# ============================================================
# ECHOS (BOSS-BELOHNUNGEN)
# ============================================================

func _setup_echos_ui() -> void:
	if echos_node == null:
		return

	var hearts_scale: float = _get_hud_scale(&"hearts")

	# Rechts neben den Herzen platzieren: hearts_node.position ist die
	# obere linke Ecke der Herzreihe (siehe _setup_positions()), und
	# jedes Herz sitzt dort lokal i*48 auseinander - zusammen mit
	# hearts_scale ergibt das die tatsächliche Breite der Herzreihe
	# auf dem Bildschirm. echos_node.position.y = hearts_node.
	# position.y richtet den Echo-Bereich auf dieselbe Höhe wie das
	# Zentrum der Herzen aus (heart.position.y ist dort ebenfalls 0).
	var hearts_row_width: float = (
		float(max(heart_sprites.size(), 1) - 1) * 48.0 + 48.0
	) * hearts_scale

	echos_node.position = Vector2(
		hearts_node.position.x
		+ hearts_row_width
		+ _corner_margin(echos_gap_after_hearts, hearts_scale),
		hearts_node.position.y
	)

	var echo_scale: float = _get_hud_scale(&"echo_der_flamme")

	echos_node.scale = Vector2(echo_scale, echo_scale)

	if echo_der_flamme_icon != null:
		echo_der_flamme_icon.centered = true
		echo_der_flamme_icon.position = Vector2.ZERO
		echo_der_flamme_icon.scale = Vector2(
			ECHO_ICON_BASE_SCALE,
			ECHO_ICON_BASE_SCALE
		)

	_refresh_echo_visibility()


# Zeigt jedes bereits freigeschaltete Echo an - AUSSER genau das
# eine, das gerade frisch enthüllt werden soll
# (RunState.pending_echo_reveal ist dann noch gesetzt). Das
# erscheint erst über reveal_echo(), nachdem Spieler-Animation
# und Banner fertig abgespielt wurden (siehe
# Levels/room_manager.gd -> _play_echo_reveal_sequence()) - nicht
# schon beim bloßen Neuaufbau des HUDs (z.B. nach Laden eines
# Spielstands, in dem dieses Echo bereits enthalten ist, aber
# gerade frisch enthüllt werden soll).
func _refresh_echo_visibility() -> void:
	if echo_der_flamme_icon == null:
		return

	var should_show: bool = false

	if get_node_or_null("/root/RunState") != null:
		should_show = (
			RunState.has_echo(&"echo_der_flamme")
			and RunState.pending_echo_reveal != &"echo_der_flamme"
		)

	echo_der_flamme_icon.visible = should_show

	if should_show:
		_play_anim_safe(echo_der_flamme_icon, "default")


# Wird von RoomManager aufgerufen, NACHDEM die Spieler-Animation
# und die Banner-Einblende für dieses Echo bereits fertig
# abgespielt wurden - blendet das dauerhafte Icon jetzt final ein
# und startet dessen Loop-Animation.
func reveal_echo(_echo_id: StringName) -> void:
	if echo_der_flamme_icon == null:
		return

	echo_der_flamme_icon.visible = true
	_play_anim_safe(echo_der_flamme_icon, "default")


# Der XP-Ring oben rechts (Player/UI/skill_ring_hud.gd, Kind-Node
# "SkillRing" hier im HUD) braucht bewusst KEINE Anbindung mehr von
# hier aus - er liest RunState (chosen_skill_path/skill_ring_
# revealed/skill_path_xp/skill_points, siehe run_state.gd) jeden
# Frame komplett selbst aus. Grund: eine frühere Fassung über HUD-
# Signale + "hud"-Gruppen-Suche aus skill_statue.gd hat den Ring
# nicht zuverlässig sichtbar gemacht - die jetzige, selbst lesende
# Fassung kann an dieser Verbindung nicht mehr scheitern.


func hide_for_cutscene() -> void:
	visible = false


func show_after_cutscene() -> void:
	visible = true
