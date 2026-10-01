extends CharacterBody2D

# Fliegender Mob (Gebiet 2). Nutzer-Wunsch: gleicher Aufwach-
# Mechanismus wie beim Schatten Mutant (siehe Mobs/Gebiet 2/schatten
# mutant/schatten_mutant.gd): SLEEP zeigt "Hängen" in Dauerschleife,
# bis der Spieler (oder PlayerSummon) in die WakeArea kommt - dann
# spielt "schlüpfen" einmal, danach ist sie wach.
#
# Anders als der Schatten Mutant fliegt sie danach aber frei in x
# UND y direkt auf ihr Ziel zu (keine Schwerkraft, kein Boden-Check).
# Berührt sie dabei den Spieler/das Summon, macht sie Schaden und
# fliegt danach kurz in die Gegenrichtung weg (RETREAT), bevor sie
# wieder zurück zum Ziel fliegt (CHASE) - so gibt's keinen
# Dauerschaden bei direktem Kontakt.
#
# Sprites sind nach RECHTS gezeichnet (genau wie beim Schatten
# Mutant, anders als beim normalen Skelett) - deshalb NICHT spiegeln
# beim Blick nach rechts, SPIEGELN beim Blick nach links (siehe
# _update_facing()).


enum State {
	SLEEP,
	AWAKE,
	CHASE,
	RETREAT,
	HURT,
	DEATH
}


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("Allgemein")

@export var max_health: int = 2
@export var damage: int = 1
@export var move_speed: float = 60.0


# ============================================================
# RÜCKZUG NACH TREFFER
# ============================================================

@export_group("Rückzug nach Treffer")

# Nutzer-Wunsch: nach einem Treffer fliegt sie kurz in die
# Gegenrichtung weg, bevor sie wieder zum Ziel zurückfliegt.
@export var retreat_speed: float = 90.0
@export var retreat_time: float = 0.6


# ============================================================
# TREFFER
# ============================================================

@export_group("Treffer")

@export var hurt_time: float = 0.3

# Trefferblitz: so lange bleibt sie voll hell ...
@export var attack_hit_flash_time: float = 0.05
# ... und blendet dann so lange weich aus.
@export var hit_flash_fade_time: float = 0.16
# Farbe des Blitzes: kaltes, leicht milchiges Weiß.
@export var hit_flash_color: Color = Color(0.82, 0.9, 1.0)
# Gleicht die Abdunklung durch den dunklen Raum (CanvasModulate) aus.
# Ohne das wäre der Blitz nur ein dunkles Grau. Höher = greller.
@export var hit_flash_boost: float = 5.0

# Verhindert mehrfachen Schaden durch dieselbe aktive Hitbox.
@export var damage_hit_lock_time: float = 0.12


# ============================================================
# TOD
# ============================================================

@export_group("Tod")

@export var death_delete_time: float = 1.0


# ============================================================
# GRUPPEN
# ============================================================

@export_group("Gruppen")

@export var player_group: StringName = &"player"
@export var summon_group: StringName = &"player_summon"
@export var player_attack_group: StringName = &"player_attack"


# ============================================================
# ANIMATIONEN
# ============================================================

@export_group("Animationen")

@export var anim_sleep: StringName = &"Hängen"
@export var anim_awake: StringName = &"schlüpfen"
@export var anim_fly: StringName = &"Fliegen"
@export var anim_hurt: StringName = &"Hittet"
@export var anim_death: StringName = &"Tot"


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionPolygon2D = $CollisionPolygon2D

# Verursacht Schaden am Spieler oder PlayerSummon bei Berührung.
@onready var attack_hitbox: Area2D = $AttackHitbox

# Empfängt Angriffe des Spielers.
@onready var hurtbox: Area2D = $Hurtbox

# Weckt die Fledermaus durch Spieler oder PlayerSummon einmalig auf.
@onready var wake_area: Area2D = $WakeArea

# Nutzer-Wunsch: statt stur geradeaus aufs Ziel zuzufliegen, sucht
# sie sich per Godot-Pfadsuche (NavigationAgent2D) einen Weg um
# Hindernisse/Plattformen herum - genau wie das "Pathing" in Spielen
# wie Hollow Knight. Dafür braucht JEDER Raum, in dem sie vorkommt,
# einmalig eine eigene NavigationRegion2D mit gebackenem
# NavigationPolygon (siehe Hinweis unten bei _process_chase()) - ohne
# das fällt sie automatisch auf die alte gerade Linie zurück.
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

# Optional: Node "enemy_spell_effects" (Freeze/Root/Slow durch
# Spieler-Zauber). Kann null sein, falls die Gegner-Szene den Node
# (noch) nicht besitzt - dann wirken einfach keine Effekte.
@onready var spell_effects: Node = get_node_or_null(
	"enemy_spell_effects"
)


# ============================================================
# STATUS
# ============================================================

var state: State = State.SLEEP
var player: Node2D = null
var current_target: Node2D = null

var hp: int = 0
var facing_right: bool = false

var awakened: bool = false

var can_take_damage: bool = false
var invincible: bool = false
var damage_hit_locked: bool = false

var dead: bool = false

var flash_generation: int = 0
var hit_flash_material: ShaderMaterial = null
var _flash_tween: Tween = null

# Feste Richtung + Restzeit für den Rückzug nach einem Treffer
# (siehe _start_retreat_after_hit() / _process_retreat()).
var _retreat_direction: Vector2 = Vector2.ZERO
var _retreat_time_left: float = 0.0


# ============================================================
# START
# ============================================================

func _ready() -> void:
	hp = max_health

	add_to_group("enemy")

	_setup_hit_flash_shader()

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D

	if not wake_area.body_entered.is_connected(
		_on_wake_area_body_entered
	):
		wake_area.body_entered.connect(
			_on_wake_area_body_entered
		)

	if not wake_area.area_entered.is_connected(
		_on_wake_area_area_entered
	):
		wake_area.area_entered.connect(
			_on_wake_area_area_entered
		)

	if not hurtbox.area_entered.is_connected(
		_on_hurtbox_area_entered
	):
		hurtbox.area_entered.connect(
			_on_hurtbox_area_entered
		)

	if not sprite.animation_finished.is_connected(
		_on_animation_finished
	):
		sprite.animation_finished.connect(
			_on_animation_finished
		)

	wake_area.monitoring = true
	wake_area.monitorable = true

	hurtbox.monitoring = true
	hurtbox.monitorable = true

	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true

	_set_animation_loop(anim_awake, false)
	_set_animation_loop(anim_hurt, false)
	_set_animation_loop(anim_death, false)

	_set_animation_loop(anim_sleep, true)
	_set_animation_loop(anim_fly, true)

	state = State.SLEEP
	awakened = false

	can_take_damage = false

	if _has_animation(anim_sleep):
		sprite.play(anim_sleep)
	else:
		awakened = true
		can_take_damage = true
		_enter_chase()

	# Prüft, ob Spieler oder PlayerSummon beim Szenenstart bereits
	# innerhalb der WakeArea stehen.
	await get_tree().physics_frame

	_check_initial_wake_overlap()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	if dead:
		return

	_find_player_if_missing()
	_refresh_target()
	_check_player_attack_overlap()
	_check_contact_damage()

	match state:
		State.SLEEP:
			velocity = Vector2.ZERO

		State.AWAKE:
			velocity = Vector2.ZERO

		State.CHASE:
			_process_chase()

		State.RETREAT:
			_process_retreat(delta)

		State.HURT:
			velocity = Vector2.ZERO

		State.DEATH:
			velocity = Vector2.ZERO

	move_and_slide()


# ============================================================
# ZIELE SUCHEN
# ============================================================

func _find_player_if_missing() -> void:
	if player != null and is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group(
		player_group
	) as Node2D


func _refresh_target() -> void:
	var nearest_target: Node2D = null
	var nearest_distance: float = INF

	if _node_is_available_target(player):
		nearest_target = player
		nearest_distance = global_position.distance_to(
			player.global_position
		)

	for summon_node: Node in get_tree().get_nodes_in_group(
		summon_group
	):
		if not summon_node is Node2D:
			continue

		var summon := summon_node as Node2D

		if not _node_is_available_target(summon):
			continue

		var summon_distance: float = global_position.distance_to(
			summon.global_position
		)

		if summon_distance < nearest_distance:
			nearest_distance = summon_distance
			nearest_target = summon

	current_target = nearest_target


func _node_is_available_target(node: Node2D) -> bool:
	if node == null:
		return false

	if not is_instance_valid(node):
		return false

	if not node.visible:
		return false

	if "dead" in node and bool(node.dead):
		return false

	return true


func _target_is_available() -> bool:
	return _node_is_available_target(current_target)


func _is_player_or_summon(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	return (
		node.is_in_group(player_group)
		or node.is_in_group(summon_group)
	)


func _get_player_or_summon_from_area(area: Area2D) -> Node:
	if _is_player_or_summon(area):
		return area

	var parent: Node = area.get_parent()

	if _is_player_or_summon(parent):
		return parent

	return null


# ============================================================
# VERFOLGUNG (FLIEGEN)
# ============================================================

func _enter_chase() -> void:
	if dead:
		return

	state = State.CHASE

	_play_animation(anim_fly)


func _process_chase() -> void:
	if _is_rooted():
		velocity = Vector2.ZERO
		return

	if not _target_is_available():
		velocity = Vector2.ZERO
		_play_animation(anim_fly)
		return

	var to_next: Vector2 = _next_chase_step()

	if to_next.length() > 0.5:
		var direction: Vector2 = to_next.normalized()

		velocity = direction * move_speed * _get_speed_multiplier()

		_update_facing(direction.x)
	else:
		velocity = Vector2.ZERO

	_play_animation(anim_fly)


# Liefert den Vektor zum nächsten Schritt Richtung Ziel - über die
# Godot-Pfadsuche (NavigationAgent2D), falls im aktuellen Raum eine
# NavigationRegion2D mit gebackenem NavigationPolygon liegt (dann
# fliegt sie in mehreren Etappen um Plattformen/Wände herum, genau
# wie gewünscht). GIBT ES noch keine NavigationRegion2D im Raum,
# liefert die Pfadsuche keinen brauchbaren Weg (naechster Punkt liegt
# praktisch auf ihrer eigenen Position) - dann fällt das hier
# automatisch auf die alte gerade Linie direkt zum Ziel zurück, damit
# sie in noch nicht eingerichteten Räumen nicht einfach stehen bleibt.
#
# EINMALIGES SETUP PRO RAUM (im Godot-Editor, nicht per Code):
#   1. In der Raum-Szene eine "NavigationRegion2D"-Node hinzufügen.
#   2. Im Inspector ein neues "NavigationPolygon" zuweisen.
#   3. Oben in der 2D-Ansicht auf "Bake NavigationPolygon" klicken -
#      Godot erkennt die Kollisionen von TileMap/Plattformen
#      automatisch und schneidet sie aus der begehbaren Fläche raus.
func _next_chase_step() -> Vector2:
	nav_agent.target_position = current_target.global_position

	var next_point: Vector2 = nav_agent.get_next_path_position()
	var to_next: Vector2 = next_point - global_position

	if to_next.length() < 1.0:
		return current_target.global_position - global_position

	return to_next


# ============================================================
# RÜCKZUG NACH TREFFER
# ============================================================

func _start_retreat_after_hit() -> void:
	if dead:
		return

	state = State.RETREAT

	var away: Vector2 = Vector2.ZERO

	if _target_is_available():
		away = global_position - current_target.global_position

	if away.length() < 0.5:
		away = Vector2(-1.0 if facing_right else 1.0, 0.0)
	else:
		away = away.normalized()

	_retreat_direction = away
	_retreat_time_left = max(retreat_time, 0.01)

	_play_animation(anim_fly)


func _process_retreat(delta: float) -> void:
	if _is_rooted():
		velocity = Vector2.ZERO
		return

	velocity = (
		_retreat_direction * retreat_speed * _get_speed_multiplier()
	)

	# Nutzer-Wunsch: sie soll sich beim Rückzug auch in die
	# Flugrichtung drehen, nicht nur beim Verfolgen.
	_update_facing(_retreat_direction.x)

	_retreat_time_left -= delta

	if _retreat_time_left <= 0.0:
		_enter_chase()


# ============================================================
# SCHADEN AN SPIELER/SUMMON BEI BERÜHRUNG
# ============================================================

func _check_contact_damage() -> void:
	if dead:
		return

	if state != State.CHASE:
		return

	for body: Node in attack_hitbox.get_overlapping_bodies():
		if not _is_player_or_summon(body):
			continue

		_deal_contact_damage(body)
		return

	for area: Area2D in attack_hitbox.get_overlapping_areas():
		var target: Node = _get_player_or_summon_from_area(area)

		if target == null:
			continue

		_deal_contact_damage(target)
		return


func _deal_contact_damage(target: Node) -> void:
	if target.has_method("take_damage"):
		target.take_damage(
			damage,
			global_position
		)

	_start_retreat_after_hit()


# ============================================================
# SPIELERANGRIFFE ERKENNEN (SCHADEN AN DER FLEDERMAUS)
# ============================================================

func _on_hurtbox_area_entered(area: Area2D) -> void:
	_try_take_player_attack_damage(area)


func _check_player_attack_overlap() -> void:
	if dead:
		return

	if hurtbox == null:
		return

	for area: Area2D in hurtbox.get_overlapping_areas():
		_try_take_player_attack_damage(area)


func _try_take_player_attack_damage(area: Area2D) -> void:
	if dead:
		return

	if damage_hit_locked:
		return

	if not can_take_damage:
		return

	if invincible:
		return

	if not area.is_in_group(player_attack_group):
		return

	if not area.has_meta("active"):
		return

	if area.get_meta("active") != true:
		return

	var attack_damage: int = 1

	if area.has_meta("damage"):
		attack_damage = int(
			area.get_meta("damage")
		)

	damage_hit_locked = true

	take_damage(attack_damage)

	_release_damage_hit_lock_later()


func _release_damage_hit_lock_later() -> void:
	var tree := get_tree()

	if tree == null:
		damage_hit_locked = false
		return

	await tree.create_timer(
		max(damage_hit_lock_time, 0.01)
	).timeout

	if is_inside_tree():
		damage_hit_locked = false


# ============================================================
# SCHADEN
# ============================================================

func take_damage(
	amount: int,
	_from_position: Vector2 = Vector2.ZERO
) -> void:
	if dead:
		return

	if amount <= 0:
		return

	if not can_take_damage:
		return

	if invincible:
		return

	hp -= amount

	EnemySoundManager.play(&"skelette", &"hit", global_position)

	if hp <= 0:
		_die()
		return

	# Trefferblitz bei jedem Treffer.
	_flash_white()

	# Die "Hittet"-Animation unterbricht nur, solange sie gerade
	# fliegt (CHASE/RETREAT) - nicht während Aufwachen oder Tod.
	if state == State.CHASE or state == State.RETREAT:
		_start_hurt()


func _start_hurt() -> void:
	if dead:
		return

	state = State.HURT
	invincible = true

	velocity = Vector2.ZERO

	if _has_animation(anim_hurt):
		_play_animation_force(anim_hurt)

	var tree := get_tree()

	if tree == null:
		_finish_hurt()
		return

	await tree.create_timer(
		max(hurt_time, 0.01)
	).timeout

	if dead:
		return

	_finish_hurt()


func _finish_hurt() -> void:
	if dead:
		return

	invincible = false
	can_take_damage = true

	_enter_chase()


# ============================================================
# AUFWACHEN
# ============================================================

func _check_initial_wake_overlap() -> void:
	if state != State.SLEEP:
		return

	for body: Node in wake_area.get_overlapping_bodies():
		if _is_player_or_summon(body):
			_wake_up_for_target(body as Node2D)
			return

	for area: Area2D in wake_area.get_overlapping_areas():
		var wake_target: Node = _get_player_or_summon_from_area(
			area
		)

		if wake_target is Node2D:
			_wake_up_for_target(wake_target as Node2D)
			return


func _on_wake_area_body_entered(body: Node) -> void:
	if not _is_player_or_summon(body):
		return

	_wake_up_for_target(body as Node2D)


func _on_wake_area_area_entered(area: Area2D) -> void:
	var wake_target: Node = _get_player_or_summon_from_area(area)

	if not wake_target is Node2D:
		return

	_wake_up_for_target(wake_target as Node2D)


func _wake_up_for_target(wake_target: Node2D) -> void:
	if wake_target == null:
		return

	if wake_target.is_in_group(player_group):
		player = wake_target

	current_target = wake_target

	if awakened:
		return

	if state != State.SLEEP:
		return

	state = State.AWAKE

	# Ab jetzt dauerhaft aktiviert - kann während der Schlüpf-
	# Animation aber noch keinen Schaden nehmen (gleiches Muster
	# wie beim Schatten Mutant während seiner Aufwach-Animation).
	awakened = true

	can_take_damage = false

	var direction: Vector2 = (
		wake_target.global_position - global_position
	)

	if abs(direction.x) > 0.5:
		_update_facing(direction.x)

	if _has_animation(anim_awake):
		_play_animation_force(anim_awake)
	else:
		can_take_damage = true
		_enter_chase()


# ============================================================
# ANIMATIONSENDE
# ============================================================

func _on_animation_finished() -> void:
	if dead and state != State.DEATH:
		return

	if (
		state == State.AWAKE
		and sprite.animation == anim_awake
	):
		can_take_damage = true

		_enter_chase()
		return

	if (
		state == State.DEATH
		and sprite.animation == anim_death
	):
		queue_free()


# ============================================================
# KOMPLETT WEISSER TREFFERBLITZ
# ============================================================

func _setup_hit_flash_shader() -> void:
	if sprite == null:
		return

	var flash_shader := Shader.new()

	flash_shader.code = """
shader_type canvas_item;

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color = vec3(0.82, 0.9, 1.0);
uniform float flash_boost = 5.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	vec3 final_color = mix(
		source.rgb,
		flash_color * flash_boost,
		flash_amount
	);

	COLOR = vec4(
		final_color,
		source.a
	);
}
"""

	hit_flash_material = ShaderMaterial.new()
	hit_flash_material.shader = flash_shader

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		0.0
	)
	hit_flash_material.set_shader_parameter(
		"flash_color",
		Vector3(hit_flash_color.r, hit_flash_color.g, hit_flash_color.b)
	)
	hit_flash_material.set_shader_parameter(
		"flash_boost",
		hit_flash_boost
	)

	sprite.material = hit_flash_material


func _flash_white() -> void:
	if hit_flash_material == null:
		return

	flash_generation += 1

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	_set_flash_amount(1.0)

	_flash_tween = create_tween()
	_flash_tween.tween_interval(max(attack_hit_flash_time, 0.01))
	_flash_tween.tween_method(
		_set_flash_amount,
		1.0,
		0.0,
		max(hit_flash_fade_time, 0.01)
	)


func _set_flash_amount(value: float) -> void:
	if hit_flash_material == null:
		return

	hit_flash_material.set_shader_parameter(
		"flash_amount",
		value
	)


func _reset_hit_flash() -> void:
	flash_generation += 1

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	if hit_flash_material != null:
		hit_flash_material.set_shader_parameter(
			"flash_amount",
			0.0
		)


# ============================================================
# TOD
# ============================================================

func _die() -> void:
	if dead:
		return

	dead = true
	state = State.DEATH

	EnemySoundManager.play(&"skelette", &"death", global_position)

	# Zählt für die Statistik UND lässt (falls schon ein Skill-Pfad
	# gewählt wurde) einen kleinen Pixel von hier zum XP-Ring im HUD
	# fliegen (siehe RunState.add_enemy_kill()).
	RunState.add_enemy_kill(1, global_position)

	can_take_damage = false
	invincible = false
	damage_hit_locked = true

	velocity = Vector2.ZERO

	_reset_hit_flash()

	wake_area.monitoring = false
	hurtbox.monitoring = false
	attack_hitbox.monitoring = false

	if body_shape != null:
		body_shape.set_deferred(
			"disabled",
			true
		)

	if _has_animation(anim_death):
		_play_animation_force(anim_death)
	else:
		queue_free()
		return

	var tree := get_tree()

	if tree == null:
		return

	await tree.create_timer(
		max(death_delete_time, 0.01)
	).timeout

	if is_instance_valid(self):
		queue_free()


# ============================================================
# ZAUBER-EFFEKTE (FREEZE / ROOT / SLOW)
# ============================================================

func _is_rooted() -> bool:
	return spell_effects != null and spell_effects.is_rooted()


func _get_speed_multiplier() -> float:
	if spell_effects == null:
		return 1.0

	return spell_effects.get_speed_multiplier()


# Wird von enemy_spell_effects.gd abgefragt (z.B. beim Festhalten
# durch Ranken), um zu wissen, ob die Animation gerade gefahrlos
# eingefroren werden darf.
func is_animation_freeze_safe() -> bool:
	return state == State.CHASE or state == State.RETREAT


# ============================================================
# BLICKRICHTUNG
# ============================================================

# x_direction: die x-Komponente der aktuellen Flugrichtung. Sehr
# kleine Werte (fast senkrechter Flug) werden ignoriert, damit die
# Blickrichtung nicht bei jedem Frame hin- und herflackert.
func _update_facing(x_direction: float) -> void:
	if abs(x_direction) < 0.05:
		return

	# WICHTIG: KEIN "schon facing_right, also nichts zu tun"-Abbruch
	# hier - facing_right startet als false, was zufällig mit "schaut
	# nach links" übereinstimmt, obwohl sprite.flip_h anfangs noch
	# gar nicht gesetzt wurde. Ein Abbruch bei Gleichstand hat genau
	# deshalb das allererste Spiegeln nach links verschluckt. Deshalb
	# hier IMMER flip_h/Hitbox neu setzen, genau wie beim Schatten
	# Mutant (siehe schatten_mutant.gd _set_facing()).
	facing_right = x_direction > 0.0

	# Sprites sind nach rechts gezeichnet - deshalb NICHT spiegeln
	# beim Blick nach rechts, SPIEGELN beim Blick nach links.
	sprite.flip_h = not facing_right

	attack_hitbox.scale.x = (
		1.0 if facing_right else -1.0
	)


# ============================================================
# ANIMATIONSHILFEN
# ============================================================

func _has_animation(animation_name: StringName) -> bool:
	if sprite == null:
		return false

	if sprite.sprite_frames == null:
		return false

	return sprite.sprite_frames.has_animation(animation_name)


func _play_animation(animation_name: StringName) -> void:
	if not _has_animation(animation_name):
		return

	if _is_rooted():
		return

	if sprite.animation != animation_name:
		sprite.play(animation_name)


func _play_animation_force(animation_name: StringName) -> void:
	if not _has_animation(animation_name):
		return

	sprite.play(animation_name)
	sprite.frame = 0


func _set_animation_loop(
	animation_name: StringName,
	should_loop: bool
) -> void:
	if not _has_animation(animation_name):
		return

	sprite.sprite_frames.set_animation_loop(
		animation_name,
		should_loop
	)
