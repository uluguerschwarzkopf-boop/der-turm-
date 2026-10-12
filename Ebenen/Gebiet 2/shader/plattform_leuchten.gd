extends Node

# Nutzer-Wunsch: Die Oberkante der Tiles leuchtet, wenn der Spieler darüber
# läuft. Dieses Skript meldet dem Plattform-Shader (plattform_lebendig.gdshader)
# jeden Frame, wo die Füße des Spielers sind, und blendet das Leuchten weich
# ein, solange er auf dem Boden steht (im Sprung blendet es aus).

@export_group("Leuchten")
## Das Material mit plattform_lebendig.gdshader (liegt auf den Tiles).
@export var material: ShaderMaterial
@export var player_group: StringName = &"player"
## Verschiebung vom Spieler-Ursprung zu den Füßen (Pixel).
@export var feet_offset: Vector2 = Vector2.ZERO
## Wie schnell das Leuchten ein- und ausblendet (höher = schneller).
@export var fade_speed: float = 6.0
## An = leuchtet nur, wenn der Spieler auf dem Boden steht.
@export var only_on_floor: bool = true

var _amount: float = 0.0


func _process(delta: float) -> void:
	if material == null:
		return
	var player: Node2D = get_tree().get_first_node_in_group(player_group) as Node2D
	var target: float = 0.0
	if player != null:
		material.set_shader_parameter("player_feet", player.global_position + feet_offset)
		target = 1.0
		if only_on_floor and player is CharacterBody2D and not (player as CharacterBody2D).is_on_floor():
			target = 0.0
	_amount = move_toward(_amount, target, fade_speed * delta)
	material.set_shader_parameter("glow_amount", _amount)
