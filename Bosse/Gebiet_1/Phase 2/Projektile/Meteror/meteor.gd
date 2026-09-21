extends Area2D

@export var player_group: StringName = &"player"

@export var damage: int = 2
@export var fall_speed: float = 260.0
@export var lifetime: float = 5.0

@export_group("Spawn")
@export var spawn_height_above_player: float = 180.0
@export var auto_start: bool = true

@export_group("Impact Damage Frames")
@export var impact_damage_frame_start: int = 4
@export var impact_damage_frame_end: int = 5

@export_group("Animations")
@export var anim_spawn: StringName = &"spawn"
@export var anim_loop: StringName = &"loop"
@export var anim_impact: StringName = &"impact"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var impact_area: Area2D = $ImpactArea
@onready var ground_cast: RayCast2D = $GroundCast

var target: Node2D = null
var falling: bool = false
var dying: bool = false
var damage_done: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = false

	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)

	impact_area.monitoring = true
	impact_area.monitorable = true
	impact_area.body_entered.connect(_on_impact_area_body_entered)

	ground_cast.enabled = true

	if auto_start:
		start()

	await get_tree().create_timer(lifetime).timeout

	if is_instance_valid(self):
		queue_free()


func setup(new_target: Node2D, new_damage: int) -> void:
	target = new_target
	damage = new_damage
	start()


func start() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group(player_group) as Node2D

	if target != null and is_instance_valid(target):
		global_position = target.global_position + Vector2(0, -spawn_height_above_player)

		# GroundCast soll NUR echten Boden erkennen, nicht den Spieler -
		# sonst "landet" der Meteor auf dem Kopf des Spielers und bleibt
		# dort haengen, statt durchzufallen (Nutzer-Wunsch: der Meteor
		# soll durch den Spieler durchgehen, ihm aber trotzdem Schaden
		# machen - siehe _on_impact_area_body_entered() unten).
		if target is CollisionObject2D:
			ground_cast.add_exception(target as CollisionObject2D)

	falling = false
	dying = false
	damage_done = false

	if sprite.sprite_frames.has_animation(anim_spawn):
		sprite.play(anim_spawn)
	else:
		_start_fall()


func _physics_process(delta: float) -> void:
	if not falling:
		return

	if dying:
		return

	global_position.y += fall_speed * delta

	if ground_cast.is_colliding():
		_start_impact()


func _on_animation_finished() -> void:
	if sprite.animation == anim_spawn:
		_start_fall()
		return

	if sprite.animation == anim_impact:
		queue_free()


func _on_frame_changed() -> void:
	if sprite.animation != anim_impact:
		return

	var f: int = sprite.frame

	if not damage_done and f >= impact_damage_frame_start and f <= impact_damage_frame_end:
		damage_done = true
		_damage_player()


func _start_fall() -> void:
	falling = true

	if sprite.sprite_frames.has_animation(anim_loop):
		sprite.play(anim_loop)


func _start_impact() -> void:
	if dying:
		return

	dying = true
	falling = false

	# damage_done NICHT hier zuruecksetzen: wurde der Spieler schon beim
	# Durchfallen getroffen (_on_impact_area_body_entered()), soll der
	# Boden-Einschlag direkt danach nicht nochmal Schaden machen.
	if sprite.sprite_frames.has_animation(anim_impact):
		sprite.play(anim_impact)
	else:
		_damage_player()
		queue_free()


func _damage_player() -> void:
	for body in impact_area.get_overlapping_bodies():
		if body.is_in_group(player_group):
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position)
			return


# Schaden soll schon beim Durchfallen durch den Spieler ausgeloest werden
# (Nutzer-Wunsch: der Meteor geht durch den Spieler durch, macht ihm aber
# trotzdem Schaden) - nicht erst beim Boden-Impact. damage_done sorgt
# dafuer, dass trotzdem nur einmal Schaden ausgeteilt wird, auch wenn der
# normale Impact-Frame-Schaden (_on_frame_changed() -> _damage_player())
# spaeter noch fuer andere Spieler in der Nähe des Einschlags durchlaeuft.
func _on_impact_area_body_entered(body: Node) -> void:
	if damage_done:
		return

	if not body.is_in_group(player_group):
		return

	if not body.has_method("take_damage"):
		return

	damage_done = true
	body.take_damage(damage, global_position)
