extends Node2D

@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var background: AnimatedSprite2D = $Sprite2D


func _ready() -> void:
	if background:
		background.play("default")
