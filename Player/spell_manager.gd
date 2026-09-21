extends Node


# ============================================================
# SIGNALE
# ============================================================

signal cast_started(spell_id: String)
signal spell_spawned(spell_id: String)
signal cast_finished(spell_id: String)
signal cast_failed(message: String)


# ============================================================
# CAST-EINSTELLUNGEN
# ============================================================

@export_group("Cast Einstellungen")

# Godot zählt Frames ab 0.
# Sichtbarer Frame 8 bedeutet hier also Wert 7.
@export_range(0, 100, 1)
var spell_spawn_frame: int = 7

# Sicherheitsdauer, falls eine Animation nicht korrekt endet.
@export var maximum_cast_time: float = 3.0

# Sperrt während des Zauberns Bewegung und Eingaben.
# Schaden kann der Spieler trotzdem erhalten.
@export var lock_player_during_cast: bool = true

# Zaubern ist nur möglich, wenn der Spieler am Boden steht.
@export var cast_only_on_floor: bool = true


# ============================================================
# ZAUBERSZENEN
# ============================================================

@export_group("Zauberszenen")

@export var fireball_scene: PackedScene
@export var lightning_scene: PackedScene
@export var ice_scene: PackedScene
@export var roots_scene: PackedScene
@export var necromancy_scene: PackedScene
@export var lightorb_scene: PackedScene


# ============================================================
# SPIELERANIMATIONEN
# ============================================================

@export_group("Spieleranimationen")

@export var fireball_animation: StringName = &"spell_fireball"
@export var lightning_animation: StringName = &"spell_lightning"
@export var ice_animation: StringName = &"spell_ice"
@export var roots_animation: StringName = &"spell_roots"
@export var necromancy_animation: StringName = &"spell_necromancy"
@export var lightorb_animation: StringName = &"spell_lightorb"


# ============================================================
# NODES
# ============================================================

var player: CharacterBody2D = null
var player_sprite: AnimatedSprite2D = null
var spell_spawn: Marker2D = null
var player_summons: Node = null


# ============================================================
# CAST-STATUS
# ============================================================

var casting: bool = false
var current_spell_id: String = ""

# Verhindert, dass alte await-Abläufe einen neueren Cast verändern.
var cast_generation: int = 0


# ============================================================
# START
# ============================================================

func _ready() -> void:
	_find_required_nodes()


func _find_required_nodes() -> void:
	# Aufbau:
	#
	# Player
	# └── Scripts
	#     └── SpellManager
	#
	# Deshalb liegt der Player zwei Ebenen über diesem Node.
	var possible_player: Node = get_parent().get_parent()

	if possible_player is CharacterBody2D:
		player = possible_player as CharacterBody2D
	else:
		push_error(
			"SpellManager: Player wurde nicht gefunden. "
			+ "SpellManager muss unter Player/Scripts liegen."
		)
		return

	player_sprite = player.get_node_or_null(
		"AnimatedSprite2D"
	) as AnimatedSprite2D

	spell_spawn = player.get_node_or_null(
		"SpellSpawn"
	) as Marker2D

	player_summons = player.get_node_or_null(
		"Scripts/PlayerSummons"
	)

	if player_sprite == null:
		push_error(
			"SpellManager: AnimatedSprite2D fehlt am Player."
		)

	if spell_spawn == null:
		push_error(
			"SpellManager: SpellSpawn fehlt am Player."
		)

	if player_summons == null:
		push_warning(
			"SpellManager: PlayerSummons fehlt unter Player/Scripts."
		)


# ============================================================
# ZAUBER STARTEN
# ============================================================

func cast_spell(spell_id: String) -> bool:
	var normalized_spell_id: String = (
		spell_id.strip_edges().to_lower()
	)

	if casting:
		cast_failed.emit(
			"Es wird bereits ein Zauber gewirkt."
		)
		return false

	if player == null or not is_instance_valid(player):
		cast_failed.emit(
			"Player wurde nicht gefunden."
		)
		return false

	if player_sprite == null or not is_instance_valid(player_sprite):
		cast_failed.emit(
			"Spieleranimation wurde nicht gefunden."
		)
		return false

	# Necromancy benötigt keinen normalen SpellSpawn.
	if normalized_spell_id != "necromancy":
		if spell_spawn == null or not is_instance_valid(spell_spawn):
			cast_failed.emit(
				"SpellSpawn wurde nicht gefunden."
			)
			return false

	# Vor dem Start prüfen, ob überhaupt noch ein Summon frei ist.
	# Dadurch bleibt der Zauber im Slot, wenn bereits die maximale
	# Anzahl an Beschwörungen aktiv ist.
	if normalized_spell_id == "necromancy":
		if player_summons == null or not is_instance_valid(player_summons):
			cast_failed.emit(
				"PlayerSummons wurde nicht gefunden."
			)
			return false

		if not player_summons.has_method("can_summon"):
			cast_failed.emit(
				"PlayerSummons besitzt keine can_summon-Funktion."
			)
			return false

		if not bool(player_summons.can_summon()):
			cast_failed.emit(
				"Maximum number of summons reached."
			)
			return false

	if _player_cannot_cast():
		cast_failed.emit(
			"Der Spieler kann gerade keinen Zauber wirken."
		)
		return false

	var animation_name: StringName = (
		_get_animation_name(normalized_spell_id)
	)

	if animation_name == &"":
		cast_failed.emit(
			"Unbekannter Zauber: "
			+ normalized_spell_id
		)
		return false

	if player_sprite.sprite_frames == null:
		cast_failed.emit(
			"Beim Spieler fehlen SpriteFrames."
		)
		return false

	if not player_sprite.sprite_frames.has_animation(
		animation_name
	):
		cast_failed.emit(
			"Spieleranimation fehlt: "
			+ str(animation_name)
		)
		return false

	var spell_scene: PackedScene = (
		_get_spell_scene(normalized_spell_id)
	)

	# Necromancy wird über PlayerSummons erzeugt und benötigt
	# deshalb keine eigene Projektil-/Zauberszene.
	if normalized_spell_id != "necromancy":
		if spell_scene == null:
			cast_failed.emit(
				"Zauberszene fehlt: "
				+ normalized_spell_id
			)
			return false

	casting = true
	current_spell_id = normalized_spell_id

	cast_generation += 1

	var this_cast_generation: int = cast_generation

	if lock_player_during_cast:
		if player.has_method("lock_control"):
			player.lock_control()

	# Nur horizontale Bewegung stoppen.
	# Die vertikale Geschwindigkeit wird nicht gelöscht.
	player.velocity.x = 0

	cast_started.emit(normalized_spell_id)

	_run_cast_sequence(
		normalized_spell_id,
		animation_name,
		spell_scene,
		this_cast_generation
	)

	return true


# ============================================================
# CAST-ABLAUF
# ============================================================

func _run_cast_sequence(
	spell_id: String,
	animation_name: StringName,
	spell_scene: PackedScene,
	this_cast_generation: int
) -> void:
	if not _can_continue_cast(this_cast_generation):
		return

	player_sprite.stop()
	player_sprite.frame = 0
	player_sprite.play(animation_name)

	var elapsed_time: float = 0.0
	var spell_was_spawned: bool = false

	while elapsed_time < maximum_cast_time:
		if not _can_continue_cast(this_cast_generation):
			return

		# Der Zauber erscheint am eingestellten Frame.
		if (
			not spell_was_spawned
			and player_sprite.animation == animation_name
			and player_sprite.frame >= spell_spawn_frame
		):
			spell_was_spawned = _spawn_spell(
				spell_id,
				spell_scene
			)

			if not spell_was_spawned:
				_finish_cast(
					spell_id,
					this_cast_generation
				)
				return

		# Die Animation wurde durch etwas anderes ersetzt.
		if player_sprite.animation != animation_name:
			break

		# Nicht geloopte Animation ist zu Ende.
		if not player_sprite.is_playing():
			break

		var tree := get_tree()

		if tree == null:
			cancel_cast()
			return

		await tree.process_frame

		elapsed_time += get_process_delta_time()

	# Sicherheitslösung:
	# Falls der Spawn-Frame übersprungen wurde,
	# wird der Zauber spätestens nach der Animation erzeugt.
	if (
		not spell_was_spawned
		and _can_continue_cast(this_cast_generation)
	):
		spell_was_spawned = _spawn_spell(
			spell_id,
			spell_scene
		)

	_finish_cast(
		spell_id,
		this_cast_generation
	)


# ============================================================
# ZAUBER ERZEUGEN
# ============================================================

func _spawn_spell(
	spell_id: String,
	spell_scene: PackedScene
) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	# Necromancy erzeugt keinen normalen Spell-Node.
	# Stattdessen wird das Skelett über PlayerSummons erstellt.
	if spell_id == "necromancy":
		if player_summons == null or not is_instance_valid(player_summons):
			return false

		if not player_summons.has_method("summon"):
			return false

		var summon_success: bool = bool(
			player_summons.summon()
		)

		if not summon_success:
			cast_failed.emit(
				"Summon could not be created."
			)
			return false

		spell_spawned.emit(spell_id)

		print(
			"SpellManager: ",
			spell_id,
			" summon was created."
		)

		return true

	if spell_scene == null:
		return false

	if spell_spawn == null or not is_instance_valid(spell_spawn):
		return false

	var spell_instance: Node = spell_scene.instantiate()

	if spell_instance == null:
		push_error(
			"SpellManager: Zauber konnte nicht erstellt werden: "
			+ spell_id
		)
		return false

	var spawn_parent: Node = get_tree().current_scene

	if spawn_parent == null:
		spell_instance.queue_free()
		return false

	spawn_parent.add_child(spell_instance)

	if spell_instance is Node2D:
		var spawn_position: Vector2 = (
			spell_spawn.global_position
		)

		# Falls SpellSpawn nur auf einer Seite platziert ist,
		# wird der Abstand abhängig von der Blickrichtung gespiegelt.
		var local_offset_x: float = abs(
			spell_spawn.position.x
		)

		if _is_player_facing_right():
			spawn_position.x = (
				player.global_position.x
				+ local_offset_x
			)
		else:
			spawn_position.x = (
				player.global_position.x
				- local_offset_x
			)

		spell_instance.global_position = spawn_position

	var cast_direction: Vector2 = Vector2.RIGHT

	if not _is_player_facing_right():
		cast_direction = Vector2.LEFT

	if spell_instance.has_method("setup"):
		spell_instance.setup(
			cast_direction,
			player
		)

	spell_spawned.emit(spell_id)

	print(
		"SpellManager: ",
		spell_id,
		" wurde erzeugt."
	)

	return true


# ============================================================
# CAST BEENDEN
# ============================================================

func _finish_cast(
	spell_id: String,
	this_cast_generation: int
) -> void:
	if this_cast_generation != cast_generation:
		return

	casting = false
	current_spell_id = ""

	if (
		lock_player_during_cast
		and player != null
		and is_instance_valid(player)
		and player.has_method("unlock_control")
	):
		player.unlock_control()

	_play_player_idle()

	cast_finished.emit(spell_id)


func cancel_cast() -> void:
	cast_generation += 1

	casting = false
	current_spell_id = ""

	if (
		player != null
		and is_instance_valid(player)
		and player.has_method("unlock_control")
	):
		player.unlock_control()

	_play_player_idle()


func _play_player_idle() -> void:
	if player_sprite == null:
		return

	if not is_instance_valid(player_sprite):
		return

	if player_sprite.sprite_frames == null:
		return

	if player_sprite.sprite_frames.has_animation(&"idle"):
		player_sprite.play(&"idle")


# ============================================================
# ZAUBERSZENEN
# ============================================================

func _get_spell_scene(spell_id: String) -> PackedScene:
	match spell_id:
		"fireball":
			return fireball_scene

		"lightning":
			return lightning_scene

		"ice":
			return ice_scene

		"roots":
			return roots_scene

		"necromancy":
			return necromancy_scene

		"lightorb":
			return lightorb_scene

	return null


# ============================================================
# ANIMATIONSNAMEN
# ============================================================

func _get_animation_name(
	spell_id: String
) -> StringName:
	match spell_id:
		"fireball":
			return fireball_animation

		"lightning":
			return lightning_animation

		"ice":
			return ice_animation

		"roots":
			return roots_animation

		"necromancy":
			return necromancy_animation

		"lightorb":
			return lightorb_animation

	return &""


# ============================================================
# PRÜFEN, OB DER SPIELER ZAUBERN DARF
# ============================================================

func _player_cannot_cast() -> bool:
	if player == null:
		return true

	if not is_instance_valid(player):
		return true

	# Zaubern nur am Boden.
	if cast_only_on_floor:
		if not player.is_on_floor():
			return true

	if "dead" in player:
		if player.dead:
			return true

	if "scene_is_changing" in player:
		if player.scene_is_changing:
			return true

	if "is_rolling" in player:
		if player.is_rolling:
			return true

	if "is_drinking" in player:
		if player.is_drinking:
			return true

	var combat: Node = player.get_node_or_null(
		"Scripts/PlayerCombat"
	)

	if combat != null:
		if "attacking" in combat:
			if combat.attacking:
				return true

	var bow: Node = player.get_node_or_null(
		"Scripts/PlayerBow"
	)

	if bow != null:
		if "shooting" in bow:
			if bow.shooting:
				return true

	return false


func _is_player_facing_right() -> bool:
	if player == null:
		return true

	if "facing_right" in player:
		return bool(player.facing_right)

	return true


func _can_continue_cast(
	this_cast_generation: int
) -> bool:
	if this_cast_generation != cast_generation:
		return false

	if not casting:
		return false

	if not is_inside_tree():
		return false

	if get_tree() == null:
		return false

	if player == null or not is_instance_valid(player):
		return false

	if (
		player_sprite == null
		or not is_instance_valid(player_sprite)
	):
		return false

	return true
