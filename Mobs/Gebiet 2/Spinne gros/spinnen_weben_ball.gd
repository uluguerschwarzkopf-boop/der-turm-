extends Area2D

# Projektil der Spinne Gros (Fernkampf-Angriff, siehe
# Mobs/Gebiet 2/Spinne gros/spinne_gros.gd -> _shoot_web_ball()).
# Basiert auf Mobs/Gebiet 1/Skellete/Archer/arrow.gd (gleiche
# geradeaus-Flugbahn + Treffer-Erkennung), spielt beim Einschlag aber
# zusätzlich einmal die "Hit"-Animation ab, bevor er verschwindet,
# statt sofort zu löschen.

@export var speed: float = 160.0
@export var damage: int = 1
@export var lifetime: float = 4.0

@export var enemy_hurtbox_group: StringName = &"enemy_hurtbox"
@export var summon_group: StringName = &"player_summon"
@export var player_group: StringName = &"player"

# Nutzer-Wunsch: trifft der Ball den SPIELER (nicht ein beschworenes
# Skelett o.ä.), wird er zusätzlich für diese Zeit (Sekunden)
# eingesponnen - siehe Player/player.gd -> start_web_wrap(). Wird von
# der Spinne Gros beim Abschießen überschrieben (siehe spinne_gros.gd
# -> _shoot_web_ball(), web_wrap_duration dort), das hier ist nur der
# Standardwert, falls der Ball mal ohne eigene Vorgabe benutzt wird.
@export var web_wrap_duration: float = 2.0

@export_group("Animationen")

@export var anim_fly: StringName = &"Fly"
@export var anim_hit: StringName = &"Hit"


@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var direction: float = 1.0
var shooter: Node = null

var has_hit: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = true

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_fly)
	):
		sprite.play(anim_fly)

	if not area_entered.is_connected(
		_on_area_entered
	):
		area_entered.connect(
			_on_area_entered
		)

	if not body_entered.is_connected(
		_on_body_entered
	):
		body_entered.connect(
			_on_body_entered
		)

	await get_tree().create_timer(
		max(lifetime, 0.01)
	).timeout

	if is_instance_valid(self) and not has_hit:
		queue_free()


func setup(
	new_direction: float,
	new_shooter: Node = null
) -> void:
	direction = new_direction
	shooter = new_shooter

	# Nutzer-Korrektur: der Spinnenwebenball ist nach RECHTS gezeichnet
	# (anders als der Pfeil beim Skelett-Archer, der nach links
	# gezeichnet ist) - deshalb hier NICHT spiegeln wenn er nach rechts
	# fliegt, SPIEGELN wenn er nach links fliegt.
	if direction > 0.0:
		scale.x = abs(scale.x)
	else:
		scale.x = -abs(scale.x)


func _physics_process(delta: float) -> void:
	if has_hit:
		return

	global_position.x += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	if body == null:
		return

	if _is_shooter_or_child(body):
		return

	var target: Node = _find_damage_target(body)

	if target != null:
		_hit_target(target)
		return

	_impact()


func _on_area_entered(area: Area2D) -> void:
	if has_hit:
		return

	if area == null:
		return

	if _is_shooter_or_child(area):
		return

	# Beschworenes Skelett:
	# Nur die echte Hurtbox darf Schaden auslösen.
	if _is_summon_hurtbox(area):
		var summon_target: Node = _find_damage_target(area)

		if summon_target != null:
			_hit_target(summon_target)

		return

	# Bestehende Spieler-Hurtbox-Erkennung.
	if area.is_in_group(enemy_hurtbox_group):
		var player_target: Node = _find_damage_target(area)

		if player_target != null:
			_hit_target(player_target)
			return

		_impact()
		return

	# Andere Areas wie DetectionArea oder AttackHitbox werden
	# vollständig ignoriert.


func _is_summon_hurtbox(area: Area2D) -> bool:
	if area.name != &"Hurtbox":
		return false

	var current: Node = area.get_parent()

	while current != null:
		if current.is_in_group(summon_group):
			return true

		current = current.get_parent()

	return false


func _hit_target(target: Node) -> void:
	if has_hit:
		return

	if target == null:
		return

	if not is_instance_valid(target):
		return

	if target.has_method("take_damage"):
		target.take_damage(
			damage,
			global_position
		)

	# Nutzer-Wunsch: trifft der Ball den SPIELER, wird er zusätzlich
	# eingesponnen (siehe Player/player.gd -> start_web_wrap()) - bei
	# anderen Zielen (z.B. einem beschworenen Skelett) passiert das
	# nicht, da die dortigen Skripte start_web_wrap() gar nicht haben.
	if (
		target.is_in_group(player_group)
		and target.has_method("start_web_wrap")
	):
		target.start_web_wrap(web_wrap_duration)

	_impact()


# Stoppt die Flugbahn, spielt (falls vorhanden) einmal die "Hit"-
# Animation ab und entfernt den Ball erst danach - statt wie der
# Pfeil sofort zu verschwinden.
func _impact() -> void:
	if has_hit:
		return

	has_hit = true

	monitoring = false
	monitorable = false

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_hit)
	):
		sprite.play(anim_hit)
		sprite.frame = 0

		await sprite.animation_finished

	if is_instance_valid(self):
		queue_free()


func _find_damage_target(node: Node) -> Node:
	var current: Node = node

	while current != null:
		if current.has_method("take_damage"):
			return current

		current = current.get_parent()

	return null


func _is_shooter_or_child(node: Node) -> bool:
	if shooter == null:
		return false

	if not is_instance_valid(shooter):
		return false

	var current: Node = node

	while current != null:
		if current == shooter:
			return true

		current = current.get_parent()

	return false
