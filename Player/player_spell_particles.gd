extends Node2D


# ============================================================
# ZAUBER-PARTIKEL
# ============================================================

# Zentrale Stelle für kurze Partikel-Effekte bei Zauber-
# Treffern (z.B. Eis-Funken, Lichtkugel-Glitzern) - statt den
# betroffenen Gegner einzufärben. Andere Scripte rufen einfach
# spawn_ice_particles(target) bzw. spawn_lightorb_particles(target)
# auf dieser Node auf (zu finden über
# owner_player.get_node_or_null("Scripts/PlayerSpellParticles")).


@export_group("Eis-Partikel")

@export var ice_particle_color: Color = Color(
	0.4,
	0.8,
	1.0,
	0.9
)

@export_range(1, 40, 1)
var ice_particle_amount: int = 12

@export var ice_particle_lifetime: float = 0.6
@export var ice_particle_speed: float = 40.0


@export_group("Lichtkugel-Partikel")

@export var lightorb_particle_color: Color = Color(
	1.0,
	0.92,
	0.55,
	0.85
)

@export_range(1, 40, 1)
var lightorb_particle_amount: int = 8

@export var lightorb_particle_lifetime: float = 0.5
@export var lightorb_particle_speed: float = 24.0


# ============================================================
# ÖFFENTLICHE FUNKTIONEN
# ============================================================

func spawn_ice_particles(target: Node2D) -> void:
	_spawn_burst(
		target,
		ice_particle_color,
		ice_particle_amount,
		ice_particle_lifetime,
		ice_particle_speed
	)


func spawn_lightorb_particles(target: Node2D) -> void:
	_spawn_burst(
		target,
		lightorb_particle_color,
		lightorb_particle_amount,
		lightorb_particle_lifetime,
		lightorb_particle_speed
	)


# ============================================================
# PARTIKEL ERZEUGEN
# ============================================================

func _spawn_burst(
	target: Node2D,
	burst_color: Color,
	amount: int,
	lifetime: float,
	speed: float
) -> void:
	if target == null or not is_instance_valid(target):
		return

	var tree := get_tree()

	if tree == null:
		return

	var spawn_parent: Node = tree.current_scene

	if spawn_parent == null:
		return

	var particles := CPUParticles2D.new()

	particles.texture = _get_particle_texture()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 0.9
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = speed * 0.5
	particles.initial_velocity_max = speed
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.1
	particles.color = burst_color
	particles.z_index = 500

	spawn_parent.add_child(particles)

	particles.global_position = target.global_position
	particles.emitting = true

	await tree.create_timer(lifetime + 0.3).timeout

	if is_instance_valid(particles):
		particles.queue_free()


# ============================================================
# GEMEINSAME PARTIKEL-TEXTUR (WEICHER PUNKT)
# ============================================================

var _particle_texture: Texture2D = null


func _get_particle_texture() -> Texture2D:
	if _particle_texture != null:
		return _particle_texture

	var size: int = 16
	var image := Image.create(
		size,
		size,
		false,
		Image.FORMAT_RGBA8
	)

	var center := Vector2(
		size / 2.0,
		size / 2.0
	)

	var radius: float = size / 2.0

	for y in range(size):
		for x in range(size):
			var pixel_center := Vector2(
				x + 0.5,
				y + 0.5
			)

			var distance: float = pixel_center.distance_to(center)
			var alpha: float = clampf(
				1.0 - distance / radius,
				0.0,
				1.0
			)

			image.set_pixel(
				x,
				y,
				Color(1.0, 1.0, 1.0, alpha)
			)

	_particle_texture = ImageTexture.create_from_image(image)

	return _particle_texture
