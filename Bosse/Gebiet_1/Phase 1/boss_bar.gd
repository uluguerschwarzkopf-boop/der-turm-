extends CanvasLayer

@export var boss_group: StringName = &"boss"
@export var boss_name: String = "Ash Knight"

var boss = null
var label: Label = null
var bar: ProgressBar = null
var border: AnimatedSprite2D = null


func _ready() -> void:
	visible = false

	label = find_child("Label", true, false) as Label
	bar = find_child("ProgressBar", true, false) as ProgressBar
	border = find_child("Border", true, false) as AnimatedSprite2D

	if label == null or bar == null or border == null:
		push_warning("BossBar: Label, ProgressBar oder Border fehlt.")
		return

	if not border.animation_finished.is_connected(_on_border_animation_finished):
		border.animation_finished.connect(_on_border_animation_finished)

	await get_tree().process_frame

	boss = get_tree().get_first_node_in_group(boss_group)

	if boss == null:
		push_warning("Boss nicht gefunden.")
		return

	if boss.has_signal("boss_started"):
		boss.boss_started.connect(_on_boss_started)

	if boss.has_signal("phase_1_finished"):
		boss.phase_1_finished.connect(_on_boss_finished)

	if boss.has_signal("summon_started"):
		boss.summon_started.connect(_on_summon_started)

	if boss.has_signal("summon_ended"):
		boss.summon_ended.connect(_on_summon_ended)

	label.text = boss_name
	bar.max_value = boss.max_health
	bar.value = boss.hp

	border.play("Normal")


func _process(_delta: float) -> void:
	if boss == null:
		return

	if not visible:
		return

	bar.value = boss.hp


func _on_boss_started() -> void:
	visible = true


func _on_boss_finished() -> void:
	queue_free()


func _on_summon_started() -> void:
	border.play("Fire_Start")


func _on_summon_ended() -> void:
	border.play("Fire_End")


func _on_border_animation_finished() -> void:
	if border.animation == "Fire_Start":
		border.play("Fire_Loop")
	elif border.animation == "Fire_End":
		border.play("Normal")
