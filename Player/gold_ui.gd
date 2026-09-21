extends Control

@export var ui_position: Vector2 = Vector2(8, 34)

@export var coin_position: Vector2 = Vector2(0, 0)
@export var coin_scale: Vector2 = Vector2(2.0, 2.0)

@export var label_position: Vector2 = Vector2(22, 2)
@export var label_scale: Vector2 = Vector2(1.0, 1.0)

@export var normal_color: Color = Color.WHITE
@export var blink_color: Color = Color.YELLOW
@export var blink_time: float = 0.04
@export var coin_animation_name: StringName = &"default"

@onready var coin_icon: AnimatedSprite2D = $CoinIcon
@onready var gold_label: Label = $GoldLabel

var displayed_gold: int = 0
var counting: bool = false

# Jede neue Goldänderung bekommt eine neue Nummer.
# Alte laufende Zählvorgänge brechen dadurch sauber ab.
var count_version: int = 0

# Wird true, sobald diese GoldUI aus dem SceneTree entfernt wird.
var shutting_down: bool = false

# Wird true, sobald das HUD (Player/hud.gd) diese GoldUI per
# set_external_position() unter die Vigor-Leiste gehängt hat - dann
# rechnet _apply_hud_scale() die Position NICHT mehr selbst aus
# ui_position, sondern lässt die vom HUD gesetzte Position stehen
# (nur der Maßstab wird hier weiterhin normal angewendet).
var _use_external_position: bool = false


func _ready() -> void:
	_apply_hud_scale()

	if get_node_or_null("/root/SettingsManager") != null:
		if not SettingsManager.hud_scale_changed.is_connected(
			_on_hud_scale_changed
		):
			SettingsManager.hud_scale_changed.connect(
				_on_hud_scale_changed
			)

	coin_icon.position = coin_position
	coin_icon.scale = coin_scale

	if (
		coin_icon.sprite_frames != null
		and coin_icon.sprite_frames.has_animation(coin_animation_name)
	):
		coin_icon.play(coin_animation_name)

	coin_icon.modulate = normal_color

	gold_label.position = label_position
	gold_label.scale = label_scale

	displayed_gold = GoldSystem.get_gold()
	gold_label.text = str(displayed_gold)

	if not GoldSystem.gold_changed.is_connected(_on_gold_changed):
		GoldSystem.gold_changed.connect(_on_gold_changed)


func _apply_hud_scale() -> void:
	var gold_scale: float = 1.0

	if get_node_or_null("/root/SettingsManager") != null:
		gold_scale = SettingsManager.get_hud_scale(&"gold")

	if not _use_external_position:
		position = Vector2(
			_corner_margin(ui_position.x, gold_scale),
			_corner_margin(ui_position.y, gold_scale)
		)

	scale = Vector2(gold_scale, gold_scale)


# Vom HUD (Player/hud.gd) aufgerufen, um Gold unter der Vigor-Leiste
# zu verankern (Nutzer-Wunsch: "die münzen unter die vigor leiste
# ziehen") statt am festen ui_position-Eck-Abstand. Ab hier rechnet
# _apply_hud_scale() die Position nicht mehr selbst aus - nur der
# Maßstab bleibt weiterhin normal einstellbar.
func set_external_position(new_position: Vector2) -> void:
	_use_external_position = true
	position = new_position


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
	_new_scale: float
) -> void:
	if category != &"gold":
		return

	_apply_hud_scale()


func _exit_tree() -> void:
	shutting_down = true
	count_version += 1
	counting = false

	if GoldSystem.gold_changed.is_connected(_on_gold_changed):
		GoldSystem.gold_changed.disconnect(_on_gold_changed)

	if get_node_or_null("/root/SettingsManager") != null:
		if SettingsManager.hud_scale_changed.is_connected(
			_on_hud_scale_changed
		):
			SettingsManager.hud_scale_changed.disconnect(
				_on_hud_scale_changed
			)


func _on_gold_changed(new_amount: int, added_amount: int) -> void:
	if shutting_down:
		return

	count_version += 1
	var my_version: int = count_version

	if added_amount > 0:
		await _count_up_to(new_amount, my_version)
	else:
		_set_gold_immediately(new_amount)


func _count_up_to(target_amount: int, my_version: int) -> void:
	if shutting_down:
		return

	if counting:
		_set_gold_immediately(target_amount)
		return

	counting = true

	while displayed_gold < target_amount:
		if not _can_continue_counting(my_version):
			counting = false
			return

		displayed_gold += 1
		gold_label.text = str(displayed_gold)

		coin_icon.modulate = blink_color

		if not await _wait_safely(blink_time, my_version):
			counting = false
			return

		if not _can_continue_counting(my_version):
			counting = false
			return

		coin_icon.modulate = normal_color

		if not await _wait_safely(blink_time, my_version):
			counting = false
			return

	if is_instance_valid(coin_icon):
		coin_icon.modulate = normal_color

	counting = false


func _set_gold_immediately(amount: int) -> void:
	displayed_gold = max(amount, 0)

	if is_instance_valid(gold_label):
		gold_label.text = str(displayed_gold)

	if is_instance_valid(coin_icon):
		coin_icon.modulate = normal_color

	counting = false


func _can_continue_counting(my_version: int) -> bool:
	if shutting_down:
		return false

	if my_version != count_version:
		return false

	if not is_inside_tree():
		return false

	if not is_instance_valid(gold_label):
		return false

	if not is_instance_valid(coin_icon):
		return false

	return true


func _wait_safely(time: float, my_version: int) -> bool:
	if not _can_continue_counting(my_version):
		return false

	var tree := get_tree()

	if tree == null:
		return false

	await tree.create_timer(max(time, 0.001)).timeout

	return _can_continue_counting(my_version)
