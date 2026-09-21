extends Node2D

@onready var boss = $SkeletonTank
@onready var boss_bar = $BossBar


func _ready() -> void:
	boss_bar.set_boss(boss)
