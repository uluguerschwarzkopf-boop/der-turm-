extends Node2D

# Nutzer-Wunsch: Stirbt der Krieger (z. B. auf einer Plattform), faellt sein
# Kopf mit Schwerkraft herunter und rollt ein kleines Stueck weg.
#
# Wird von krieger_skellet.gd beim Tod erzeugt (alle Werte kommen von dort,
# einstellbar im Inspektor des Kriegers unter "Kopf beim Tod").
#
# Eigene kleine Physik per Raycast statt RigidBody2D: So prallt der Kopf nur
# an Tiles ab, nie an Spieler oder Gegnern (die liegen auf derselben
# Physik-Ebene), und er kann niemandem den Weg versperren.

var texture: Texture2D
var flip_h: bool = false
var velocity: Vector2 = Vector2.ZERO
var gravity: float = 320.0
var bounce: float = 0.3
var roll_friction: float = 40.0
var spin: float = 6.0
var radius: float = 3.5
var floor_mask: int = 1

var _sprite: Sprite2D
var _grounded: bool = false
var _resting: bool = false


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.flip_h = flip_h
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if _resting:
		return
	if _grounded:
		_roll(delta)
	else:
		_fly(delta)


func _fly(delta: float) -> void:
	velocity.y += gravity * delta
	var motion: Vector2 = velocity * delta
	var from: Vector2 = global_position
	# Strahl um den Kopfradius verlaengern, damit der Kopf nicht ins Tile sinkt.
	var to: Vector2 = from + motion + motion.normalized() * radius
	var hit: Dictionary = _ray(from, to)
	if hit.is_empty():
		global_position += motion
		_sprite.rotation += spin * signf(velocity.x) * delta
		return
	var normal: Vector2 = hit["normal"]
	var point: Vector2 = hit["position"]
	if normal.y < -0.5:
		# Boden: aufsetzen, bei viel Tempo einmal leicht abprallen.
		global_position = Vector2(point.x, point.y - radius)
		if velocity.y > 60.0:
			velocity.y = -velocity.y * bounce
			velocity.x *= 0.8
		else:
			velocity.y = 0.0
			_grounded = true
	elif absf(normal.x) > 0.5:
		# Wand: zurueckprallen und weiterfallen.
		global_position = point + normal * radius
		velocity.x = -velocity.x * 0.3
	else:
		# Decke
		global_position = point + normal * radius
		velocity.y = 0.0


func _roll(delta: float) -> void:
	# Kein Boden mehr unter dem Kopf (z. B. ueber die Plattformkante gerollt)?
	if _ray(global_position, global_position + Vector2(0.0, radius + 2.0)).is_empty():
		_grounded = false
		return
	velocity.x = move_toward(velocity.x, 0.0, roll_friction * delta)
	var step: float = velocity.x * delta
	if absf(step) > 0.0:
		var ahead: Vector2 = global_position + Vector2(signf(step) * (radius + absf(step)), 0.0)
		if not _ray(global_position, ahead).is_empty():
			velocity.x = -velocity.x * 0.3
			step = 0.0
	global_position.x += step
	# Rollen: Drehung passend zur zurueckgelegten Strecke.
	_sprite.rotation += step / radius
	if absf(velocity.x) < 0.5:
		_settle()


func _settle() -> void:
	_resting = true
	set_physics_process(false)
	# Zum Liegen auf die naechste Vierteldrehung kippen, damit der Pixel-Schaedel
	# nicht schraeg (verpixelt) liegen bleibt.
	var target: float = roundf(_sprite.rotation / (PI * 0.5)) * PI * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(_sprite, "rotation", target, 0.15)


# Raycast nur gegen die Welt: Spieler/Gegner (CharacterBody2D) werden ignoriert.
func _ray(from: Vector2, to: Vector2) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, floor_mask)
	var exclude: Array[RID] = []
	for i in 4:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return hit
		if hit["collider"] is CharacterBody2D:
			exclude.append(hit["rid"])
			continue
		return hit
	return {}
