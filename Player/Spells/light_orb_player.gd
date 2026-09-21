extends Node2D


# ============================================================
# DAUER
# ============================================================

@export_group("Dauer")

# Wie lange die Lichtkugel nach der Spawn-Animation aktiv bleibt.
@export var active_duration: float = 10.0

# Sicherheitsdauer, falls eine Animation nicht korrekt endet.
@export var maximum_lifetime: float = 15.0


# ============================================================
# FOLGEBEWEGUNG
# ============================================================

@export_group("Folgebewegung")

# Horizontaler Abstand hinter dem Spieler.
# Der Code wechselt automatisch die Seite.
@export var horizontal_offset: float = 20.0

# Höhe über dem Spieler.
# Negative Y-Werte liegen in Godot oberhalb.
@export var vertical_offset: float = -22.0

# Wie schnell sich die Kugel zur Zielposition bewegt.
# Höher = schnelleres Folgen.
@export var follow_speed: float = 6.0

# Verhindert extrem schnelle Bewegungen bei großen Abständen.
# 0 bedeutet: keine Geschwindigkeitsbegrenzung.
@export var maximum_follow_speed: float = 180.0

# Wenn aktiviert, schwebt der Orb immer hinter dem Spieler.
@export var switch_side_with_player_direction: bool = true


# ============================================================
# SCHWEBEBEWEGUNG
# ============================================================

@export_group("Schweben")

# Höhe der Auf-und-ab-Bewegung.
@export var bob_height: float = 3.0

# Geschwindigkeit der Auf-und-ab-Bewegung.
@export var bob_speed: float = 2.5

# Kleine horizontale Bewegung zusätzlich zum Folgen.
@export var horizontal_bob_amount: float = 1.0

@export var horizontal_bob_speed: float = 1.6


# ============================================================
# LICHT
# ============================================================

@export_group("Licht")

@export var light_enabled: bool = true

@export var light_color: Color = Color(
	1.0,
	0.95,
	0.45,
	1.0
)

@export var light_energy: float = 1.0

# Wird nur angewendet, wenn dein PointLight2D eine Textur besitzt.
@export var light_texture_scale: float = 1.0

# Licht blendet während Spawn und Verschwinden weich ein/aus.
@export var animate_light_energy: bool = true


# ============================================================
# VERLANGSAMEN
# ============================================================

@export_group("Verlangsamen")

@export var enemy_group: StringName = &"enemy"

# Hier enemy_spell_effects.gd hineinziehen.
@export var enemy_spell_effects_script: Script


# ============================================================
# SICHTBARER WIRKBEREICH
# ============================================================

@export_group("Sichtbarer Wirkbereich")

# Zeichnet einen weichen gelben Kreis um den Wirkbereich der
# Lichtkugel-Aura (Radius kommt von Area2D/CollisionShape2D).
@export var show_effect_radius: bool = true

# Sehr geringe Sättigung/Deckkraft - nur ein leichter gelber
# Schimmer in der Fläche zwischen Mitte und Rand.
@export var effect_radius_fill_color: Color = Color(
	1.0,
	0.92,
	0.55,
	0.05
)

@export var effect_radius_ring_color: Color = Color(
	1.0,
	0.85,
	0.35,
	0.35
)

@export var effect_radius_ring_width: float = 2.5


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var spawn_animation: StringName = &"Spawn"
@export var float_animation: StringName = &"Float"
@export var disappear_animation: StringName = &"Disappear"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
)

@onready var point_light: PointLight2D = (
	get_node_or_null("PointLight2D") as PointLight2D
)

@onready var effect_area: Area2D = (
	get_node_or_null("Area2D") as Area2D
)

@onready var effect_shape: CollisionShape2D = (
	get_node_or_null(
		"Area2D/CollisionShape2D"
	) as CollisionShape2D
)


# ============================================================
# STATUS
# ============================================================

var owner_player: Node2D = null

var active: bool = false
var disappearing: bool = false
var finished: bool = false
var sequence_started: bool = false

var elapsed_bob_time: float = 0.0

var starting_light_energy: float = 1.0

var generation: int = 0

# instance_id -> Node, damit wir beim Verschwinden des Orbs
# alle noch verlangsamten Gegner sicher wieder freigeben können.
var _slowed_enemies: Dictionary = {}

# instance_id -> Area2D (z.B. Pfeile), die gerade durch die
# Aura verlangsamt werden.
var _slowed_projectiles: Dictionary = {}


# ============================================================
# START
# ============================================================

func _ready() -> void:
	if sprite != null:
		if not sprite.animation_finished.is_connected(
			_on_animation_finished
		):
			sprite.animation_finished.connect(
				_on_animation_finished
			)

	if point_light != null:
		starting_light_energy = light_energy

		point_light.enabled = light_enabled
		point_light.color = light_color
		point_light.texture_scale = light_texture_scale

		if animate_light_energy:
			point_light.energy = 0.0
		else:
			point_light.energy = light_energy

	if effect_area != null:
		effect_area.monitoring = true
		effect_area.monitorable = true

		if not effect_area.body_entered.is_connected(
			_on_effect_area_body_entered
		):
			effect_area.body_entered.connect(
				_on_effect_area_body_entered
			)

		if not effect_area.body_exited.is_connected(
			_on_effect_area_body_exited
		):
			effect_area.body_exited.connect(
				_on_effect_area_body_exited
			)

		# Projektile (z.B. Pfeile) sind selbst Area2D-Nodes,
		# deshalb zusätzlich Area-Area-Overlap abhören.
		if not effect_area.area_entered.is_connected(
			_on_effect_area_area_entered
		):
			effect_area.area_entered.connect(
				_on_effect_area_area_entered
			)

		if not effect_area.area_exited.is_connected(
			_on_effect_area_area_exited
		):
			effect_area.area_exited.connect(
				_on_effect_area_area_exited
			)

	if effect_shape != null:
		effect_shape.disabled = false

	queue_redraw()

	_start_safety_timer()

	# setup() wird direkt nach dem Erzeugen durch den
	# SpellManager aufgerufen.
	call_deferred("_start_sequence")


# ============================================================
# SETUP DURCH DEN SPELLMANAGER
# ============================================================

func setup(
	_direction: Vector2,
	new_owner_player: Node = null
) -> void:
	if new_owner_player is Node2D:
		owner_player = new_owner_player as Node2D

		# Der Orb startet an der aktuellen Spielerposition,
		# damit er nicht aus der Spawnposition heraus springt.
		global_position = _get_target_position()


# ============================================================
# SEQUENZ STARTEN
# ============================================================

func _start_sequence() -> void:
	if sequence_started or finished:
		return

	sequence_started = true
	generation += 1

	var this_generation: int = generation

	if owner_player == null:
		push_warning(
			"LightOrb: Kein Player in setup() übergeben."
		)
		_finish()
		return

	if sprite == null:
		_start_active_phase(this_generation)
		return

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			spawn_animation
		)
	):
		sprite.play(spawn_animation)

		if animate_light_energy:
			_fade_light_to(
				light_energy,
				_get_animation_duration(spawn_animation)
			)

		return

	_start_active_phase(this_generation)


# ============================================================
# FOLGEN UND SCHWEBEN
# ============================================================

func _process(delta: float) -> void:
	if finished:
		return

	if owner_player == null:
		return

	if not is_instance_valid(owner_player):
		_start_disappear()
		return

	elapsed_bob_time += delta

	var target_position: Vector2 = _get_target_position()

	var bob_offset := Vector2(
		sin(
			elapsed_bob_time
			* horizontal_bob_speed
		) * horizontal_bob_amount,
		sin(
			elapsed_bob_time
			* bob_speed
		) * bob_height
	)

	target_position += bob_offset

	if follow_speed <= 0.0:
		global_position = target_position
		return

	# Exponentielle Glättung:
	# bleibt auch bei unterschiedlichen FPS weich.
	var follow_weight: float = (
		1.0
		- exp(-follow_speed * delta)
	)

	var desired_position: Vector2 = global_position.lerp(
		target_position,
		follow_weight
	)

	if maximum_follow_speed > 0.0:
		var movement: Vector2 = (
			desired_position - global_position
		)

		var max_distance: float = (
			maximum_follow_speed * delta
		)

		if movement.length() > max_distance:
			movement = movement.normalized() * max_distance

		global_position += movement
	else:
		global_position = desired_position


func _get_target_position() -> Vector2:
	if owner_player == null:
		return global_position

	var side_sign: float = -1.0

	if switch_side_with_player_direction:
		var player_faces_right: bool = true

		if "facing_right" in owner_player:
			player_faces_right = bool(
				owner_player.facing_right
			)

		# Blick nach rechts:
		# Orb schwebt links hinter dem Spieler.
		if player_faces_right:
			side_sign = -1.0
		else:
			side_sign = 1.0

	var offset := Vector2(
		abs(horizontal_offset) * side_sign,
		vertical_offset
	)

	return owner_player.global_position + offset


# ============================================================
# AKTIVE PHASE
# ============================================================

func _start_active_phase(
	this_generation: int
) -> void:
	if finished or disappearing:
		return

	if this_generation != generation:
		return

	active = true

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			float_animation
		)
	):
		sprite.play(float_animation)

	var tree := get_tree()

	if tree == null:
		_finish()
		return

	await tree.create_timer(
		max(active_duration, 0.01)
	).timeout

	if not is_inside_tree():
		return

	if finished or disappearing:
		return

	if this_generation != generation:
		return

	_start_disappear()


# ============================================================
# VERSCHWINDEN
# ============================================================

func _start_disappear() -> void:
	if disappearing or finished:
		return

	disappearing = true
	active = false

	generation += 1

	_clear_all_slows()

	if effect_area != null:
		effect_area.monitoring = false
		effect_area.monitorable = false

	if effect_shape != null:
		effect_shape.set_deferred(
			"disabled",
			true
		)

	if animate_light_energy:
		var fade_duration: float = (
			_get_animation_duration(
				disappear_animation
			)
		)

		_fade_light_to(
			0.0,
			max(fade_duration, 0.1)
		)

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			disappear_animation
		)
	):
		sprite.play(disappear_animation)
		return

	_finish()


func _on_animation_finished() -> void:
	if sprite == null:
		return

	if sprite.animation == spawn_animation:
		_start_active_phase(generation)
		return

	if sprite.animation == disappear_animation:
		_finish()


# ============================================================
# LICHT ÜBERBLENDEN
# ============================================================

func _fade_light_to(
	target_energy: float,
	duration: float
) -> void:
	if point_light == null:
		return

	if not animate_light_energy:
		point_light.energy = target_energy
		return

	var tween := create_tween()

	tween.tween_property(
		point_light,
		"energy",
		target_energy,
		max(duration, 0.01)
	)


func _get_animation_duration(
	animation_name: StringName
) -> float:
	if sprite == null:
		return 0.1

	if sprite.sprite_frames == null:
		return 0.1

	if not sprite.sprite_frames.has_animation(
		animation_name
	):
		return 0.1

	var frame_count: int = (
		sprite.sprite_frames.get_frame_count(
			animation_name
		)
	)

	var animation_speed: float = (
		sprite.sprite_frames.get_animation_speed(
			animation_name
		)
	)

	if animation_speed <= 0.0:
		return 0.1

	return float(frame_count) / animation_speed


# ============================================================
# ENDE
# ============================================================

func _finish() -> void:
	if finished:
		return

	finished = true
	active = false
	disappearing = true

	generation += 1

	queue_free()


# ============================================================
# VERLANGSAMEN
# ============================================================

func _on_effect_area_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return

	if not body.is_in_group(enemy_group):
		return

	_apply_slow_to_enemy(body)


func _on_effect_area_body_exited(body: Node) -> void:
	if body == null:
		return

	_remove_slow_from_enemy(body)


func _apply_slow_to_enemy(enemy: Node) -> void:
	var effects: Node = enemy.get_node_or_null(
		"enemy_spell_effects"
	)

	if effects == null:
		if enemy_spell_effects_script == null:
			push_warning(
				"LightOrb: EnemySpellEffects-Script fehlt im Inspector."
			)
			return

		effects = Node.new()
		effects.name = "enemy_spell_effects"
		effects.set_script(enemy_spell_effects_script)

		enemy.add_child(effects)

	if not effects.has_method("apply_slow_source"):
		return

	var multiplier: float = 0.5
	var config: Node = _get_player_spell_effects()

	if config != null:
		multiplier = config.lightorb_enemy_slow_multiplier

	effects.apply_slow_source("lightorb", multiplier)

	_slowed_enemies[enemy.get_instance_id()] = enemy


func _remove_slow_from_enemy(enemy: Node) -> void:
	_slowed_enemies.erase(enemy.get_instance_id())

	if not is_instance_valid(enemy):
		return

	var effects: Node = enemy.get_node_or_null(
		"enemy_spell_effects"
	)

	if effects != null and effects.has_method("remove_slow_source"):
		effects.remove_slow_source("lightorb")


# Sicherheitsnetz: falls beim Deaktivieren der Area kein
# body_exited mehr für aktuell überlappende Gegner kommt,
# werden hier trotzdem alle noch verlangsamten Gegner befreit.
func _clear_all_slows() -> void:
	for enemy_id in _slowed_enemies.keys():
		var enemy: Node = _slowed_enemies[enemy_id]

		if enemy == null or not is_instance_valid(enemy):
			continue

		var effects: Node = enemy.get_node_or_null(
			"enemy_spell_effects"
		)

		if effects != null and effects.has_method("remove_slow_source"):
			effects.remove_slow_source("lightorb")

	_slowed_enemies.clear()

	for projectile_id in _slowed_projectiles.keys():
		var projectile: Area2D = _slowed_projectiles[projectile_id]

		if projectile == null or not is_instance_valid(projectile):
			continue

		if projectile.has_method("set_speed_multiplier"):
			projectile.set_speed_multiplier(1.0)

	_slowed_projectiles.clear()


# ============================================================
# PROJEKTILE VERLANGSAMEN
# ============================================================

func _on_effect_area_area_entered(area: Area2D) -> void:
	if area == null or not is_instance_valid(area):
		return

	if not area.has_method("set_speed_multiplier"):
		return

	var multiplier: float = 0.35
	var config: Node = _get_player_spell_effects()

	if config != null:
		multiplier = config.lightorb_projectile_slow_multiplier

	area.set_speed_multiplier(multiplier)

	_slowed_projectiles[area.get_instance_id()] = area


func _on_effect_area_area_exited(area: Area2D) -> void:
	if area == null:
		return

	_slowed_projectiles.erase(area.get_instance_id())

	if not is_instance_valid(area):
		return

	if area.has_method("set_speed_multiplier"):
		area.set_speed_multiplier(1.0)


func _get_player_spell_effects() -> Node:
	if owner_player == null or not is_instance_valid(owner_player):
		return null

	return owner_player.get_node_or_null(
		"Scripts/PlayerSpellEffects"
	)


# ============================================================
# SICHTBARER WIRKBEREICH
# ============================================================

func _draw() -> void:
	if not show_effect_radius:
		return

	var radius: float = _get_effect_radius()

	if radius <= 0.0:
		return

	draw_circle(
		Vector2.ZERO,
		radius,
		effect_radius_fill_color
	)

	draw_arc(
		Vector2.ZERO,
		radius,
		0.0,
		TAU,
		64,
		effect_radius_ring_color,
		effect_radius_ring_width,
		true
	)


func _get_effect_radius() -> float:
	if effect_shape == null:
		return 0.0

	var circle_shape := effect_shape.shape as CircleShape2D

	if circle_shape == null:
		return 0.0

	return circle_shape.radius


# ============================================================
# SICHERHEITSTIMER
# ============================================================

func _start_safety_timer() -> void:
	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(maximum_lifetime, 0.1)
	).timeout

	if is_instance_valid(self):
		_finish()
