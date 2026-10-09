extends Area2D

# Pfeil vom Skellet Archer (Gebiet 2).
# Basiert auf Mobs/Gebiet 1/Skellete/Archer/arrow.gd (gleiches
# Verhalten: fliegt gerade horizontal, trifft Spieler und
# beschworene Skelette, verschwindet an Wänden). Der alte Pfeil
# bleibt unverändert, damit der Gebiet-1-Archer nicht kaputtgeht.
#
# Unterschied zum alten Pfeil: Körper anderer Gegner werden
# ignoriert (der Pfeil fliegt durch sie hindurch), statt sie zu
# treffen oder an ihnen zu zerbrechen.


# ============================================================
# FLUG
# ============================================================

@export_group("Flug")

# Pixel pro Sekunde.
@export var speed: float = 420.0

# Nach so vielen Sekunden verschwindet der Pfeil von selbst.
@export var lifetime: float = 3.0


# ============================================================
# SCHADEN
# ============================================================

@export_group("Schaden")

@export var damage: int = 1


# ============================================================
# GRAFIK
# ============================================================

@export_group("Grafik")

# Nutzer-Angabe: Pfeil.png ist nach RECHTS gezeichnet (anders als
# der alte Archer-Pfeil, der nach links zeigt). Falls die Grafik
# getauscht wird, hier umschalten statt Code anzufassen.
@export var sprite_faces_right: bool = true


# ============================================================
# GRUPPEN
# ============================================================

@export_group("Gruppen")

@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"
@export var enemy_group: StringName = &"enemy"
@export var enemy_hurtbox_group: StringName = &"enemy_hurtbox"


var direction: float = 1.0
var shooter: Node = null

var has_hit: bool = false

# Wird von der Lichtkugel-Aura gesetzt, solange der Pfeil sie
# durchfliegt (1.0 = normale Geschwindigkeit).
var speed_multiplier: float = 1.0


func _ready() -> void:
	monitoring = true
	monitorable = true

	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	await get_tree().create_timer(
		max(lifetime, 0.01)
	).timeout

	if is_instance_valid(self):
		queue_free()


# Wird vom Skellet Archer direkt nach dem Spawnen aufgerufen.
func setup(
	new_direction: float,
	new_shooter: Node = null
) -> void:
	direction = 1.0 if new_direction >= 0.0 else -1.0
	shooter = new_shooter

	# Grafik zeigt in Flugrichtung: nur spiegeln, wenn die
	# Flugrichtung nicht zur Zeichenrichtung passt.
	var flies_right: bool = direction > 0.0

	if flies_right == sprite_faces_right:
		scale.x = abs(scale.x)
	else:
		scale.x = -abs(scale.x)


func _physics_process(delta: float) -> void:
	if has_hit:
		return

	global_position.x += direction * speed * speed_multiplier * delta


# Wird von light_orb_player.gd aufgerufen, solange der Pfeil
# innerhalb der Aura fliegt.
func set_speed_multiplier(multiplier: float) -> void:
	speed_multiplier = clampf(multiplier, 0.0, 1.0)


func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	if body == null:
		return

	if _is_shooter_or_child(body):
		return

	# Spieler (oder beschworenes Skelett mit Körper-Kollision).
	if body.is_in_group(player_group) or body.is_in_group(summon_group):
		var target: Node = _find_damage_target(body)

		if target != null:
			_hit_target(target)
			return

	# Andere Gegner: durchfliegen.
	if body.is_in_group(enemy_group):
		return

	# Alles andere (Wände, Boden, TileMaps): Pfeil zerbricht.
	_destroy_arrow()


func _on_area_entered(area: Area2D) -> void:
	if has_hit:
		return

	if area == null:
		return

	if _is_shooter_or_child(area):
		return

	# Beschworenes Skelett: hat collision_layer = 0 am Körper,
	# deshalb nur über seine echte Hurtbox treffbar.
	if _is_summon_hurtbox(area):
		var summon_target: Node = _find_damage_target(area)

		if summon_target != null:
			_hit_target(summon_target)

		return

	# Gleiche Hurtbox-Gruppe wie beim alten Pfeil
	# (z.B. Feuerritter Phase 2).
	if area.is_in_group(enemy_hurtbox_group):
		var enemy_target: Node = _find_damage_target(area)

		if enemy_target != null:
			_hit_target(enemy_target)
			return

		_destroy_arrow()
		return

	# Andere Areas wie WakeArea oder AttackHitbox
	# werden vollständig ignoriert.


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

	if target == null or not is_instance_valid(target):
		return

	if not target.has_method("take_damage"):
		return

	has_hit = true

	# set_deferred: wir sind hier mitten in einem Physik-Signal.
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	target.take_damage(
		damage,
		global_position
	)

	queue_free()


func _destroy_arrow() -> void:
	if has_hit:
		return

	has_hit = true

	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

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
