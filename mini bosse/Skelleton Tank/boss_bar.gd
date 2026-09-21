extends CanvasLayer

@export var boss_name: String = "Skeleton Tank"

var boss = null
var bar: ProgressBar = null
var name_label: Label = null


func _ready() -> void:
	bar = find_child("ProgressBar", true, false) as ProgressBar
	name_label = find_child("Label", true, false) as Label

	visible = false


func set_boss(target) -> void:
	boss = target

	if boss == null:
		return

	if boss.has_signal("boss_started"):
		boss.boss_started.connect(_on_boss_started)

	bar.max_value = boss.max_health
	bar.value = boss.hp

	if name_label:
		name_label.text = boss_name


func _on_boss_started() -> void:
	visible = true


func _process(_delta: float) -> void:
	if boss == null:
		return

	if not visible:
		return

	bar.value = boss.hp

	if boss.dead:
		visible = false
