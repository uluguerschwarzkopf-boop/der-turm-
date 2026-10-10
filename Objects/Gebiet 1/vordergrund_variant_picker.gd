@tool
extends Parallax2D

# ============================================================
# Varianten-Auswahl für Vordergrund-Elemente (z.B. Ranken)
# ============================================================
# Viele Vordergrund-Elemente haben in ihrem Kind-AnimatedSprite2D
# mehrere "Animationen" hinterlegt, die eigentlich unterschiedliche
# optische VARIANTEN sind (z.B. "Ranke 1" / "Rnake 2"), keine echten
# Bewegungs-Animationen. Damit man beim Platzieren einer Instanz
# direkt am Root auswählen kann, welche Variante gezeigt wird - ohne
# vorher "Editierbare Kinder" aktivieren zu müssen, nur um an das
# AnimatedSprite2D-Kind ranzukommen - baut dieses Script im Inspector
# ein Dropdown ("Variant"), das automatisch alle im Kind hinterlegten
# Varianten auflistet.
#
# Muss auf dem Parallax2D-Root sitzen, das Kind muss "AnimatedSprite2D"
# heißen. Ändert nichts an Parallax-/Kamera-Logik (siehe scroll_scale
# direkt am selben Root-Node) und auch nichts am Idle-Schwank-Script
# des Kindes.

var variant: String = ""

@onready var _sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


func _get_property_list() -> Array:
	var names: PackedStringArray = _get_variant_names()
	var hint_string: String = ""
	if names.size() > 0:
		hint_string = ",".join(names)

	return [{
		"name": "variant",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": hint_string,
	}]


func _get_variant_names() -> PackedStringArray:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return PackedStringArray()
	return sprite.sprite_frames.get_animation_names()


func _set(property: StringName, value: Variant) -> bool:
	if property == &"variant":
		variant = value
		_apply_variant()
		return true
	return false


func _get(property: StringName) -> Variant:
	if property == &"variant":
		return variant
	return null


func _ready() -> void:
	_sprite = get_node_or_null("AnimatedSprite2D")
	_apply_variant()
	notify_property_list_changed()


func _apply_variant() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("AnimatedSprite2D")
	if _sprite == null or _sprite.sprite_frames == null:
		return
	if variant == "" or not _sprite.sprite_frames.has_animation(variant):
		return
	_sprite.play(variant)
