extends Area2D


@export_group("Reward")

@export_enum(
	"fireball",
	"lightning",
	"ice",
	"roots",
	"necromancy",
	"lightorb"
)
var spell_id: String = "necromancy"


@export_group("Groups")

@export var player_group: StringName = &"player"
@export var player_attack_group: StringName = &"player_attack"


@export_group("Feedback")

@export var destroy_after_reward: bool = true
@export var hit_lock_time: float = 0.15


var hit_locked: bool = false
var opened: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = true

	if not area_entered.is_connected(
		_on_area_entered
	):
		area_entered.connect(
			_on_area_entered
		)


func _on_area_entered(area: Area2D) -> void:
	if opened:
		return

	if hit_locked:
		return

	if not area.is_in_group(player_attack_group):
		return

	if not area.has_meta("active"):
		return

	if area.get_meta("active") != true:
		return

	hit_locked = true

	var success: bool = _give_spell()

	if success:
		opened = true

		if destroy_after_reward:
			queue_free()

		return

	await get_tree().create_timer(
		max(hit_lock_time, 0.01)
	).timeout

	if is_inside_tree():
		hit_locked = false


func _give_spell() -> bool:
	var player: Node = get_tree().get_first_node_in_group(
		player_group
	)

	if player == null:
		push_warning(
			"DebugSpellChest: Player not found."
		)
		return false

	if not player.has_method("add_spell"):
		push_warning(
			"DebugSpellChest: Player has no add_spell method."
		)
		return false

	var success: bool = player.add_spell(spell_id)

	if success:
		print(
			"DebugSpellChest: Added spell ",
			spell_id
		)
	else:
		print(
			"DebugSpellChest: Could not add spell. "
			+ "The spell slots may be full."
		)

	return success
