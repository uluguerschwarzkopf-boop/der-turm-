extends Node

# Nutzer-Wunsch: Jeder Gegner bekommt ein ganz subtiles eigenes Licht, damit
# er sich vom dunklen Raum abhebt. Dieses Skript hängt am Node "Enemies" und
# gibt jedem Kind automatisch ein PointLight2D - auch Gegnern, die später
# dazukommen (z. B. der Mutant aus der Käfig-Cutscene).
# So muss man nicht jede Gegner-Szene einzeln anfassen.

@export_group("Gegner-Licht")
@export var light_enabled: bool = true
## Helligkeit. Subtil halten (0.3 bis 0.6).
@export var light_energy: float = 0.4
@export var light_color: Color = Color(0.8, 0.86, 1.0)
## Durchmesser des Lichts in Pixeln.
@export var light_size: float = 80.0
## Position relativ zu den Füßen des Gegners (negativ = höher).
@export var light_offset: Vector2 = Vector2(0, -14)

var _texture: Texture2D = null


func _ready() -> void:
	_texture = _make_texture()
	for child in get_children():
		_add_light(child)
	child_entered_tree.connect(_add_light)


func _add_light(node: Node) -> void:
	if not light_enabled or not (node is Node2D):
		return
	if node.get_node_or_null("Gegner Licht") != null:
		return
	var light := PointLight2D.new()
	light.name = "Gegner Licht"
	light.texture = _texture
	light.texture_scale = light_size / 64.0
	light.energy = light_energy
	light.color = light_color
	light.position = light_offset
	# add_child direkt in child_entered_tree ist nicht erlaubt, daher verzögert.
	node.add_child.call_deferred(light)


func _make_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1), Color(0.3, 0.3, 0.3), Color(0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex
