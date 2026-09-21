extends Area2D

@export var player_group: StringName = &"player"

@export_group("Beam")
@export var damage: int = 1
@export var beam_duration: float = 5.0
@export var damage_tick_time: float = 0.35
@export var beam_length: float = 900.0
@export var beam_height: float = 32.0
@export var segment_width: float = 32.0
@export var visual_offset: Vector2 = Vector2(40, -10)

@export_group("Animations")
@export var anim_start: StringName = &"Start"
@export var anim_segment: StringName = &"Segment"
@export var anim_end: StringName = &"End"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shape: CollisionShape2D = $CollisionShape2D

var active: bool = false
var ending: bool = false
var started: bool = false
var damage_timer: float = 0.0
var beam_sprites: Array[AnimatedSprite2D] = []


func _ready() -> void:
	visible = true
	monitoring = true
	monitorable = true

	_force_animation_loops()
	_set_hitbox_enabled(false)

	sprite.visible = true
	sprite.z_index = 200
	sprite.position = visual_offset
	beam_sprites = [sprite]

	await get_tree().process_frame

	if not started:
		start()


func setup(_new_direction: float = -1.0, new_damage: int = -1) -> void:
	if new_damage >= 0:
		damage = new_damage

	if is_node_ready():
		start()


func start() -> void:
	if started:
		return

	started = true

	_build_beam_segments()
	_setup_hitbox()

	active = true
	damage_timer = 0.0
	_set_hitbox_enabled(true)

	await get_tree().create_timer(beam_duration).timeout

	if is_instance_valid(self):
		_start_end()


func _physics_process(delta: float) -> void:
	if not active or ending:
		return

	damage_timer -= delta

	if damage_timer <= 0.0:
		damage_timer = damage_tick_time
		_damage_player_inside()


func _force_animation_loops() -> void:
	if sprite.sprite_frames == null:
		return

	if sprite.sprite_frames.has_animation(anim_start):
		sprite.sprite_frames.set_animation_loop(anim_start, false)

	if sprite.sprite_frames.has_animation(anim_segment):
		sprite.sprite_frames.set_animation_loop(anim_segment, true)

	if sprite.sprite_frames.has_animation(anim_end):
		sprite.sprite_frames.set_animation_loop(anim_end, false)


func _build_beam_segments() -> void:
	for i in range(1, beam_sprites.size()):
		if is_instance_valid(beam_sprites[i]):
			beam_sprites[i].queue_free()

	beam_sprites.clear()
	beam_sprites.append(sprite)

	var count: int = max(1, int(ceil(beam_length / segment_width)))

	for i in range(count):
		var current_sprite: AnimatedSprite2D

		if i == 0:
			current_sprite = sprite
		else:
			current_sprite = sprite.duplicate() as AnimatedSprite2D
			add_child(current_sprite)
			beam_sprites.append(current_sprite)

		current_sprite.visible = true
		current_sprite.z_index = 200
		current_sprite.position = visual_offset + Vector2(-segment_width * i, 0)

		if i == 0:
			if current_sprite.sprite_frames.has_animation(anim_start):
				current_sprite.play(anim_start)
		else:
			if current_sprite.sprite_frames.has_animation(anim_segment):
				current_sprite.play(anim_segment)

		if i == 0:
			current_sprite.animation_finished.connect(func():
				if current_sprite.animation == anim_start:
					if current_sprite.sprite_frames.has_animation(anim_segment):
						current_sprite.play(anim_segment)
			)


func _setup_hitbox() -> void:
	if shape == null:
		return

	if shape.shape is RectangleShape2D:
		var rect := shape.shape as RectangleShape2D
		rect.size = Vector2(beam_length, beam_height)

	shape.position = visual_offset + Vector2(-beam_length * 0.5, 0)


func _set_hitbox_enabled(enabled: bool) -> void:
	if shape != null:
		shape.disabled = not enabled


func _start_end() -> void:
	if ending:
		return

	ending = true
	active = false
	_set_hitbox_enabled(false)

	for beam_sprite in beam_sprites:
		if beam_sprite != null and is_instance_valid(beam_sprite):
			if beam_sprite.sprite_frames.has_animation(anim_end):
				beam_sprite.play(anim_end)
			else:
				beam_sprite.visible = false

	await get_tree().create_timer(0.35).timeout

	if is_instance_valid(self):
		queue_free()


func _damage_player_inside() -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group(player_group):
			if body.has_method("take_damage"):
				body.take_damage(damage, global_position)
