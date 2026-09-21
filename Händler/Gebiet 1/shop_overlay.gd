extends Control


@export var player_group: StringName = &"player"


# ============================================================
# LAYOUT
# ============================================================

@export_group("Layout")

@export var panel_size: Vector2 = Vector2(430, 250)
@export var grid_position: Vector2 = Vector2(20, 55)
@export var info_panel_position: Vector2 = Vector2(235, 55)
@export var info_panel_size: Vector2 = Vector2(175, 170)


# Skaliert das komplette Shop-Fenster (Panel + alles darin) als
# Ganzes hoch/runter, statt jede Innen-Position einzeln neu
# ausrechnen zu müssen - bleibt dabei über pivot_offset exakt in
# der Bildschirmmitte zentriert. Wird normalerweise NICHT direkt
# hier verändert, sondern vom Händler beim Öffnen per
# set_panel_scale() gesetzt (siehe Händler/Gebiet 1/händler_1.gd,
# Export-Gruppe "Shop-Fenster-Größe") - so ist die Fenstergröße
# im Inspector des Händlers einstellbar.
@export_group("Größe")

@export var panel_scale: float = 1.0


# ============================================================
# ITEM PRICES
# ============================================================

@export_group("Item Prices")

@export var potion_cost: int = 15
@export var shield_cost: int = 25
@export var arrows_cost: int = 10
@export var bow_cost: int = 40
@export var fireball_cost: int = 30
@export var lightning_cost: int = 35
@export var ice_cost: int = 35
@export var necromancy_cost: int = 45
@export var roots_cost: int = 30
@export var lightorb_cost: int = 40


# Namen und Beschreibungen kommen jetzt aus SettingsManager.t()
# (siehe unten bei "shop.item.*" in Game/settings_manager.gd) und
# wechseln dadurch automatisch mit der Sprache mit. Nur der Preis
# bleibt hier pro Gegenstand im Inspector einstellbar (siehe
# "Item Prices" oben).


# ============================================================
# SCHRIFT
# ============================================================

@export_group("Font")

@export var shop_font: Font = null
@export var shop_font_size: int = 16


# ============================================================
# NODES
# ============================================================

@onready var shop_panel: Panel = $ShopPanel
@onready var title_label: Label = $ShopPanel/TitleLabel
@onready var item_grid: GridContainer = $ShopPanel/ItemGrid

@onready var info_panel: Panel = $ShopPanel/InfoPanel
@onready var info_icon: AnimatedSprite2D = $ShopPanel/InfoPanel/InfoIcon
@onready var item_name_label: Label = $ShopPanel/InfoPanel/ItemNameLabel
@onready var cost_label: Label = $ShopPanel/InfoPanel/CostLabel
@onready var description_label: Label = $ShopPanel/InfoPanel/DescriptionLabel
@onready var buy_button: Button = $ShopPanel/InfoPanel/BuyButton
@onready var close_button: Button = $ShopPanel/CloseButton

# Wird erst zur Laufzeit gebaut (siehe _setup_description_scroll),
# damit die Beschreibung scrollen kann statt über den Kaufen-
# Button hinauszulaufen, wenn der Text zu lang ist.
var description_scroll: ScrollContainer = null


# ============================================================
# STATUS
# ============================================================

var player: Node = null
var current_selected_button: Control = null
var current_item: Dictionary = {}


# ============================================================
# START
# ============================================================

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 999

	_setup_description_scroll()
	_setup_layout()
	_refresh_static_texts()
	_apply_font()

	if not buy_button.pressed.is_connected(
		_on_buy_pressed
	):
		buy_button.pressed.connect(
			_on_buy_pressed
		)

	if not close_button.pressed.is_connected(
		close_shop
	):
		close_button.pressed.connect(
			close_shop
		)

	for child in item_grid.get_children():
		if child.has_signal("selected"):
			if not child.selected.is_connected(
				_on_item_selected
			):
				child.selected.connect(
					_on_item_selected
				)

		if child.has_method("apply_font"):
			child.apply_font(shop_font, shop_font_size)

		if child.has_method("clear_item"):
			child.clear_item()

	_clear_info()

	if get_node_or_null("/root/SettingsManager") != null:
		if not SettingsManager.language_changed.is_connected(
			_on_language_changed
		):
			SettingsManager.language_changed.connect(
				_on_language_changed
			)

	# BUGFIX (Shop-Checkpoint): Dieser Node (ShopOverlay) ist entgegen
	# dem früheren Kommentar hier NICHT nur Teil von shop_room_1.tscn,
	# sondern Teil von Player/UI/canvas_layer.tscn (dem HUD), und DAS
	# HUD steckt in JEDEM Raum drin (siehe canvas_layer.tscn -> HUD ->
	# ShopOverlay, eingebettet in level_01/02/03/4/5/6/7,
	# skill_tree_room, beide Bossräume, mini_boss_room UND
	# shop_room_1). _ready() hier feuert also bei JEDEM Raumwechsel,
	# nicht nur im Shop - dadurch wurde der Checkpoint bisher bei
	# jedem Betreten irgendeines Raums auf GENAU DIESEN Raum
	# überschrieben, statt fest auf dem Shop stehen zu bleiben (Bug,
	# den der Nutzer gemeldet hat: Tod-Neustart landete immer im
	# zuletzt betretenen Raum statt im Shop).
	#
	# Fix: nur speichern, wenn die GERADE geladene Szene wirklich der
	# Shop-Raum ist (RunState.SHOP_ROOM_PATH, siehe Game/run_state.gd).
	if get_node_or_null("/root/RunState") != null:
		var current_scene: Node = get_tree().current_scene

		if (
			current_scene != null
			and current_scene.scene_file_path == RunState.SHOP_ROOM_PATH
		):
			RunState.save_shop_checkpoint()


# ============================================================
# BESCHREIBUNG SCROLLBAR MACHEN
# ============================================================

# Reparentet das DescriptionLabel einmalig in einen
# ScrollContainer, statt es direkt im InfoPanel zu belassen -
# so kann langer Beschreibungstext nach unten gescrollt werden
# (Mausrad oder die automatisch erscheinende Scrollbar per Maus),
# statt über den Kaufen-Button hinauszulaufen.
func _setup_description_scroll() -> void:
	if description_scroll != null:
		return

	description_scroll = ScrollContainer.new()
	description_scroll.name = "DescriptionScroll"

	description_scroll.horizontal_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED
	)

	description_scroll.vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_AUTO
	)

	var label_parent: Node = description_label.get_parent()
	var label_index: int = description_label.get_index()

	label_parent.remove_child(description_label)
	label_parent.add_child(description_scroll)
	label_parent.move_child(description_scroll, label_index)

	description_scroll.add_child(description_label)


# ============================================================
# LAYOUT
# ============================================================

# Wird vom Händler aufgerufen, BEVOR open_shop() das Layout neu
# aufbaut (siehe Händler/Gebiet 1/händler_1.gd) - dadurch übernimmt
# _setup_layout() gleich den neuen Wert.
func set_panel_scale(new_scale: float) -> void:
	panel_scale = new_scale


func _setup_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	position = Vector2.ZERO
	size = get_viewport_rect().size

	shop_panel.size = panel_size
	shop_panel.position = (
		get_viewport_rect().size - panel_size
	) / 2.0

	shop_panel.pivot_offset = panel_size / 2.0
	shop_panel.scale = Vector2.ONE * panel_scale

	title_label.position = Vector2(20, 12)

	item_grid.position = grid_position
	item_grid.columns = 2

	info_panel.position = info_panel_position
	info_panel.size = info_panel_size

	info_icon.position = Vector2(12, 10)
	info_icon.scale = Vector2(1, 1)

	item_name_label.position = Vector2(55, 10)
	cost_label.position = Vector2(55, 34)

	# Der Beschreibungstext steht jetzt in einem ScrollContainer
	# (siehe _setup_description_scroll), damit er bei langen
	# Texten nicht mehr über den Kaufen-Button hinausläuft,
	# sondern per Mausrad oder an der Scrollbar per Maus nach
	# unten geschoben werden kann. Die Höhe endet knapp über dem
	# Kaufen-Button bei y=132.
	description_scroll.position = Vector2(12, 62)
	description_scroll.size = Vector2(151, 66)

	description_label.custom_minimum_size = Vector2(134, 0)
	description_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)

	buy_button.position = Vector2(42, 132)
	buy_button.size = Vector2(90, 28)

	close_button.position = Vector2(
		panel_size.x - 42,
		10
	)

	close_button.size = Vector2(32, 28)
	close_button.text = "X"


# ============================================================
# SCHRIFT (INSPECTOR)
# ============================================================

func _apply_font() -> void:
	var controls: Array[Control] = [
		title_label,
		item_name_label,
		cost_label,
		description_label,
		buy_button,
		close_button
	]

	for control in controls:
		if control == null:
			continue

		if shop_font != null:
			control.add_theme_font_override(
				"font",
				shop_font
			)

		if shop_font_size > 0:
			control.add_theme_font_size_override(
				"font_size",
				shop_font_size
			)


# ============================================================
# ÜBERSETZUNG
# ============================================================

# Kleiner Helfer, damit dieses Script auch ohne SettingsManager
# (z.B. isoliert getestet) nicht abstürzt, sondern auf den
# englischen Standardtext zurückfällt.
func _t(key: String, fallback: String) -> String:
	if get_node_or_null("/root/SettingsManager") == null:
		return fallback

	return SettingsManager.t(key)


func _refresh_static_texts() -> void:
	title_label.text = _t("shop.title", "Merchant")

	# Zeigt zusätzlich die Plus-Taste als Kauf-Kurzbefehl an (z.B.
	# "Kaufen (+)"/"Buy (+)") - siehe _unhandled_key_input() weiter
	# unten, das den eigentlichen Tastendruck abfängt.
	buy_button.text = _t("shop.buy_button", "Buy") + " (+)"

	if current_item.is_empty():
		_clear_info()


func _on_language_changed(_language: String) -> void:
	_refresh_static_texts()
	_display_saved_shop_offer()

	var previous_item_id: String = str(
		current_item.get("id", "")
	)

	if previous_item_id.is_empty():
		_clear_info()
		return

	var catalog: Dictionary = _get_item_catalog()

	if catalog.has(previous_item_id):
		current_item = (
			catalog[previous_item_id] as Dictionary
		).duplicate(true)

		_update_info_panel()
	else:
		_clear_info()


# ============================================================
# OPEN / CLOSE
# ============================================================

func open_shop() -> void:
	player = get_tree().get_first_node_in_group(
		player_group
	)

	if player and player.has_method("lock_control"):
		player.lock_control()

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_setup_layout()

	visible = true
	show()

	# The offer is generated only once per run.
	_ensure_shop_offer_exists()
	_display_saved_shop_offer()

	_clear_info()


func close_shop() -> void:
	visible = false
	hide()

	if (
		current_selected_button
		and current_selected_button.has_method(
			"set_selected"
		)
	):
		current_selected_button.set_selected(false)

	current_selected_button = null
	current_item = {}

	if player and player.has_method("unlock_control"):
		player.unlock_control()

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _process(_delta: float) -> void:
	if (
		visible
		and Input.is_action_just_pressed("ui_cancel")
	):
		close_shop()


# Plus-Taste kauft den aktuell ausgewählten Gegenstand - als
# zusätzlicher Kurzbefehl neben dem normalen Maus-Klick auf den
# Kaufen-Button. Läuft über _unhandled_key_input() statt einer
# eigenen Input-Map-Aktion, damit KEINE Änderung an den Projekt-
# einstellungen/Tastenbelegungen nötig ist - fängt sowohl die
# "+"-Taste auf der Haupttastatur (layoutunabhängig über das
# tatsächlich getippte Zeichen) als auch das Nummernblock-Plus ab.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return

	if not (event is InputEventKey):
		return

	var key_event: InputEventKey = event

	if not key_event.pressed or key_event.echo:
		return

	var is_plus_key: bool = (
		key_event.unicode == 43  # "+"-Zeichen, egal welches Tastatur-Layout
		or key_event.physical_keycode == KEY_KP_ADD  # Nummernblock "+"
		or key_event.keycode == KEY_PLUS
	)

	if not is_plus_key:
		return

	get_viewport().set_input_as_handled()
	_on_buy_pressed()


# ============================================================
# ITEM CATALOG
# ============================================================

func _get_item_catalog() -> Dictionary:
	# Der Bogen-Text nennt die aktuell zugewiesene Taste dynamisch,
	# statt fest "right click" zu schreiben - sonst wäre die
	# Beschreibung falsch, sobald "shoot_bow" umbelegt wird.
	var bow_binding: String = "?"

	if get_node_or_null("/root/SettingsManager") != null:
		bow_binding = SettingsManager.get_binding_text(&"shoot_bow")

	return {
		"potion": {
			"id": "potion",
			"name": _t("shop.item.potion.name", "Healing Potion"),
			"cost": potion_cost,
			"desc": _t(
				"shop.item.potion.desc",
				"Adds a potion to your inventory. Drink it to heal."
			),
			"icon_anim": "potion",
			"consumable": true
		},
		"shield": {
			"id": "shield",
			"name": _t("shop.item.shield.name", "Armor"),
			"cost": shield_cost,
			"desc": _t(
				"shop.item.shield.desc",
				"+1 armor point. Absorbs the next hit before it reaches your hearts."
			),
			"icon_anim": "shield",
			"consumable": true
		},
		"arrows": {
			"id": "arrows",
			"name": _t("shop.item.arrows.name", "Arrows"),
			"cost": arrows_cost,
			"desc": _t(
				"shop.item.arrows.desc",
				"+5 arrows for your bow."
			),
			"icon_anim": "arrows",
			"consumable": true
		},
		"bow": {
			"id": "bow",
			"name": _t("shop.item.bow.name", "Bow"),
			"cost": bow_cost,
			"desc": String(
				_t(
					"shop.item.bow.desc",
					"Secondary weapon. Shoot with %s."
				)
			) % [bow_binding],
			"icon_anim": "bow",
			"consumable": false
		},
		"fireball": {
			"id": "fireball",
			"name": _t("shop.item.fireball.name", "Fireball"),
			"cost": fireball_cost,
			"desc": _t(
				"shop.item.fireball.desc",
				"Single-use spell. Launches a large fireball."
			),
			"icon_anim": "fireball",
			"consumable": true
		},
		"lightning": {
			"id": "lightning",
			"name": _t("shop.item.lightning.name", "Lightning"),
			"cost": lightning_cost,
			"desc": _t(
				"shop.item.lightning.desc",
				"Single-use spell. Fires a fast lightning bolt."
			),
			"icon_anim": "lightning",
			"consumable": true
		},
		"ice": {
			"id": "ice",
			"name": _t("shop.item.ice.name", "Ice Wave"),
			"cost": ice_cost,
			"desc": _t(
				"shop.item.ice.desc",
				"Single-use spell. Summons an ice wave."
			),
			"icon_anim": "ice",
			"consumable": true
		},
		"necromancy": {
			"id": "necromancy",
			"name": _t("shop.item.necromancy.name", "Necromancy"),
			"cost": necromancy_cost,
			"desc": _t(
				"shop.item.necromancy.desc",
				"Single-use spell. Summons an allied skeleton."
			),
			"icon_anim": "necromancy",
			"consumable": true
		},
		"roots": {
			"id": "roots",
			"name": _t("shop.item.roots.name", "Roots"),
			"cost": roots_cost,
			"desc": _t(
				"shop.item.roots.desc",
				"Single-use spell. Sends roots across the ground."
			),
			"icon_anim": "roots",
			"consumable": true
		},
		"lightorb": {
			"id": "lightorb",
			"name": _t("shop.item.lightorb.name", "Light Orb"),
			"cost": lightorb_cost,
			"desc": _t(
				"shop.item.lightorb.desc",
				"Single-use spell. Summons a floating light orb."
			),
			"icon_anim": "lightorb",
			"consumable": true
		}
	}


# ============================================================
# CREATE ONE OFFER PER RUN
# ============================================================

func _ensure_shop_offer_exists() -> void:
	if get_node_or_null("/root/RunState") == null:
		push_error(
			"ShopOverlay: RunState Autoload was not found."
		)
		return

	if RunState.has_shop_offer():
		return

	var random_pool: Array[String] = [
		"arrows",
		"bow",
		"fireball",
		"lightning",
		"ice",
		"necromancy",
		"roots",
		"lightorb"
	]

	random_pool.shuffle()

	var generated_offer: Array[String] = [
		"potion",
		"shield"
	]

	while (
		generated_offer.size() < 6
		and not random_pool.is_empty()
	):
		generated_offer.append(
			random_pool.pop_front()
		)

	RunState.set_shop_offer(generated_offer)


# ============================================================
# DISPLAY SAVED OFFER
# ============================================================

func _display_saved_shop_offer() -> void:
	var slots: Array = item_grid.get_children()
	var catalog: Dictionary = _get_item_catalog()

	var saved_ids: Array[String] = []

	if get_node_or_null("/root/RunState") != null:
		saved_ids = RunState.get_shop_offer()

	for i in range(slots.size()):
		var slot = slots[i]

		if i >= saved_ids.size():
			if slot.has_method("clear_item"):
				slot.clear_item()

			continue

		var item_id: String = saved_ids[i]

		if not catalog.has(item_id):
			if slot.has_method("clear_item"):
				slot.clear_item()

			continue

		var item: Dictionary = (
			catalog[item_id] as Dictionary
		).duplicate(true)

		var sold: bool = _is_item_sold(item)

		if slot.has_method("setup_item"):
			slot.setup_item(item, sold)


# ============================================================
# SELECTION / INFO PANEL
# ============================================================

func _on_item_selected(button: Control) -> void:
	if (
		current_selected_button
		and current_selected_button.has_method(
			"set_selected"
		)
	):
		current_selected_button.set_selected(false)

	current_selected_button = button

	if current_selected_button.has_method("set_selected"):
		current_selected_button.set_selected(true)

	current_item = button.item_data

	_update_info_panel()


func _update_info_panel() -> void:
	if current_item.is_empty():
		_clear_info()
		return

	var icon_anim: StringName = StringName(
		str(
			current_item.get(
				"icon_anim",
				"potion"
			)
		)
	)

	if (
		info_icon.sprite_frames
		and info_icon.sprite_frames.has_animation(
			icon_anim
		)
	):
		info_icon.play(icon_anim)

	info_icon.visible = true

	item_name_label.text = str(
		current_item.get(
			"name",
			"Item"
		)
	)

	cost_label.text = String(
		_t("shop.cost_label", "Cost: %d Gold")
	) % [int(current_item.get("cost", 0))]

	description_label.text = str(
		current_item.get(
			"desc",
			""
		)
	)

	buy_button.disabled = _is_item_sold(
		current_item
	)


func _clear_info() -> void:
	info_icon.visible = false
	item_name_label.text = _t("shop.no_item", "No item")
	cost_label.text = _t("shop.cost_placeholder", "Cost: -")
	description_label.text = _t("shop.select_item", "Select an item.")
	buy_button.disabled = true


# ============================================================
# BUY
# ============================================================

func _on_buy_pressed() -> void:
	if current_item.is_empty():
		return

	if _is_item_sold(current_item):
		description_label.text = _t("shop.already_sold", "Already sold.")
		return

	var cost: int = int(
		current_item.get(
			"cost",
			0
		)
	)

	if not GoldSystem.spend_gold(cost):
		description_label.text = _t("shop.not_enough_gold", "Not enough gold.")
		return

	var success: bool = _apply_item(current_item)

	if not success:
		GoldSystem.add_gold(cost)
		description_label.text = _t("shop.cannot_purchase", "Cannot be purchased.")
		return

	if not bool(
		current_item.get(
			"consumable",
			false
		)
	):
		var item_id: String = str(
			current_item.get(
				"id",
				""
			)
		)

		if get_node_or_null("/root/RunState") != null:
			RunState.mark_unique_shop_item_bought(
				item_id
			)

		if (
			current_selected_button
			and current_selected_button.has_method(
				"mark_sold"
			)
		):
			current_selected_button.mark_sold()

		description_label.text = _t("shop.purchased", "Purchased!")
		buy_button.disabled = true
	else:
		description_label.text = _t("shop.purchased", "Purchased!")
		buy_button.disabled = false


# ============================================================
# APPLY ITEM
# ============================================================

func _apply_item(item: Dictionary) -> bool:
	var id: String = str(
		item.get(
			"id",
			""
		)
	)

	if player == null:
		return false

	if id == "potion":
		if player.has_method("add_potion"):
			return player.add_potion(1)

		return false

	if id == "shield":
		if player.has_method("add_armor"):
			return player.add_armor(1)

		return false

	if id == "arrows":
		if player.has_method("add_arrows"):
			return player.add_arrows(5)

		return false

	if id == "bow":
		if player.has_method("unlock_bow"):
			return player.unlock_bow()

		return false

	if id == "fireball":
		if player.has_method("add_spell"):
			return player.add_spell("fireball")

		return false

	if id == "lightning":
		if player.has_method("add_spell"):
			return player.add_spell("lightning")

		return false

	if id == "ice":
		if player.has_method("add_spell"):
			return player.add_spell("ice")

		return false

	if id == "necromancy":
		if player.has_method("add_spell"):
			return player.add_spell(
				"necromancy"
			)

		return false

	if id == "roots":
		if player.has_method("add_spell"):
			return player.add_spell("roots")

		return false

	if id == "lightorb":
		if player.has_method("add_spell"):
			return player.add_spell("lightorb")

		return false

	return false


# ============================================================
# SOLD STATUS
# ============================================================

func _is_item_sold(item: Dictionary) -> bool:
	if bool(
		item.get(
			"consumable",
			false
		)
	):
		return false

	var item_id: String = str(
		item.get(
			"id",
			""
		)
	)

	if get_node_or_null("/root/RunState") == null:
		return false

	return RunState.is_unique_shop_item_bought(
		item_id
	)
