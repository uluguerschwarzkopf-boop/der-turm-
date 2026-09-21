extends Control

signal selected(button)

@export var slot_size: Vector2 = Vector2(48, 48)
@export var icon_position: Vector2 = Vector2(24, 17)
@export var icon_scale: Vector2 = Vector2(2.0, 2.0)
@export var cost_label_position: Vector2 = Vector2(5, 30)

@export var normal_border_color: Color = Color(0.08, 0.08, 0.08, 1.0)
@export var selected_border_color: Color = Color(1.0, 0.72, 0.1, 1.0)
@export var sold_color: Color = Color(0.35, 0.35, 0.35, 1.0)

@onready var panel: Panel = $Panel
@onready var icon: AnimatedSprite2D = $AnimatedSprite2D
@onready var cost_label: Label = $CostLabel
@onready var click_button: Button = $ClickButton

var item_data: Dictionary = {}
var is_selected: bool = false
var is_sold: bool = false


func _ready() -> void:
	custom_minimum_size = slot_size
	size = slot_size

	panel.position = Vector2.ZERO
	panel.size = slot_size

	icon.position = icon_position
	icon.scale = icon_scale

	cost_label.position = cost_label_position

	click_button.position = Vector2.ZERO
	click_button.size = slot_size
	click_button.flat = true
	click_button.text = ""

	click_button.pressed.connect(_on_click_pressed)

	_apply_style()


func setup_item(data: Dictionary, sold: bool) -> void:
	item_data = data
	is_sold = sold
	is_selected = false
	visible = true

	var anim_name: StringName = StringName(str(item_data.get("icon_anim", "potion")))

	if is_sold:
		var sold_anim: StringName = StringName(str(anim_name) + "_sold")
		if icon.sprite_frames.has_animation(sold_anim):
			icon.play(sold_anim)
		elif icon.sprite_frames.has_animation(anim_name):
			icon.play(anim_name)
		icon.modulate = sold_color
	else:
		if icon.sprite_frames.has_animation(anim_name):
			icon.play(anim_name)
		icon.modulate = Color.WHITE

	cost_label.text = str(item_data.get("cost", 0)) + "G"
	_apply_style()


func apply_font(font: Font, size: int) -> void:
	if font != null:
		cost_label.add_theme_font_override("font", font)

	if size > 0:
		cost_label.add_theme_font_size_override("font_size", size)


func clear_item() -> void:
	item_data = {}
	is_selected = false
	is_sold = false
	visible = false


func set_selected(value: bool) -> void:
	is_selected = value
	_apply_style()


func mark_sold() -> void:
	is_sold = true

	var anim_name: StringName = StringName(str(item_data.get("icon_anim", "potion")))
	var sold_anim: StringName = StringName(str(anim_name) + "_sold")

	if icon.sprite_frames.has_animation(sold_anim):
		icon.play(sold_anim)

	icon.modulate = sold_color
	_apply_style()


func _on_click_pressed() -> void:
	if item_data.is_empty():
		return

	selected.emit(self)


func _apply_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.22, 0.22, 1.0)
	style.border_color = selected_border_color if is_selected else normal_border_color
	style.set_border_width_all(4 if is_selected else 2)
	panel.add_theme_stylebox_override("panel", style)
