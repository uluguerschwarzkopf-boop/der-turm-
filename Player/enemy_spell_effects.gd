extends Node


# ============================================================
# HINWEIS
# ============================================================

# Dieses Script hängt an jedem Gegner (Node-Name im Szenen-
# baum: "enemy_spell_effects"). Es speichert absichtlich KEINE
# eigenen Zahlen mehr (Dauer, Farbe, Stärke) - alle Werte
# kommen von außen, normalerweise aus player_spell_effects.gd.
# So lässt sich alles an einer zentralen Stelle im Inspector
# einstellen, statt in vielen einzelnen Zauber-Scripts.
#
# Prinzipiell könnte dasselbe Script auch an den Spieler
# gehängt werden, falls ein Boss ihm später Effekte geben soll.


# ============================================================
# STATUS: PARALYSE (BLITZ)
# ============================================================

var enemy: Node = null

var paralyzed: bool = false
var paralyze_generation: int = 0

var _paralyze_previous_physics_process: bool = true
var _paralyze_previous_process: bool = true

var _paralyze_pause_animations: bool = true
var _paralyze_disable_physics: bool = true
var _paralyze_disable_process: bool = true


# ============================================================
# STATUS: EINFRIEREN (EIS)
# ============================================================

var frozen: bool = false
var freeze_generation: int = 0


# ============================================================
# STATUS: FESTHALTEN (RANKEN)
# ============================================================

var rooted: bool = false
var root_generation: int = 0


# ============================================================
# GESCHWINDIGKEITS-MODIFIKATOREN
# ============================================================

# key -> Multiplikator (0.0 = steht komplett, 1.0 = normale
# Geschwindigkeit). Mehrere Quellen können gleichzeitig aktiv
# sein (z.B. Einfrieren + Lichtkugel-Aura zusammen) - es zählt
# immer die stärkste (kleinste) Verlangsamung.
var _speed_modifiers: Dictionary = {}


# ============================================================
# SICHTBARE EFFEKTE (FARB-SHADER)
# ============================================================

var _affected_sprites: Array[CanvasItem] = []
var _original_materials: Dictionary = {}
var _active_tint_key: String = ""

var _paused_animated_sprites: Array[AnimatedSprite2D] = []


# ============================================================
# START
# ============================================================

func _ready() -> void:
	enemy = get_parent()

	if enemy == null:
		push_warning(
			"EnemySpellEffects besitzt keinen Gegner als Parent."
		)


# ============================================================
# PARALYSE (BLITZ)
# ============================================================

func apply_paralyze(
	duration: float,
	tint_color: Color,
	tint_strength: float,
	pause_animations: bool = true,
	disable_physics: bool = true,
	disable_process: bool = true
) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	if _enemy_is_dead():
		return

	paralyze_generation += 1

	var this_generation: int = paralyze_generation
	var safe_duration: float = max(duration, 0.05)

	_paralyze_pause_animations = pause_animations
	_paralyze_disable_physics = disable_physics
	_paralyze_disable_process = disable_process

	if not paralyzed:
		_start_paralyze(tint_color, tint_strength)
	else:
		# Erneuter Treffer während die Paralyse schon läuft:
		# Farbe ggf. aktualisieren, Dauer wird unten neu gestartet.
		_apply_tint("paralyze", tint_color, tint_strength)

	await get_tree().create_timer(safe_duration).timeout

	if not is_inside_tree():
		return

	if enemy == null or not is_instance_valid(enemy):
		return

	if _enemy_is_dead():
		_end_paralyze()
		return

	# Ein weiterer Treffer hat die Dauer neu gestartet.
	if this_generation != paralyze_generation:
		return

	_end_paralyze()


func _start_paralyze(
	tint_color: Color,
	tint_strength: float
) -> void:
	if paralyzed:
		return

	paralyzed = true

	if enemy is CharacterBody2D:
		enemy.velocity.x = 0

	_paralyze_previous_physics_process = enemy.is_physics_processing()
	_paralyze_previous_process = enemy.is_processing()

	if _paralyze_disable_physics:
		enemy.set_physics_process(false)

	if _paralyze_disable_process:
		enemy.set_process(false)

	_apply_tint("paralyze", tint_color, tint_strength)

	if _paralyze_pause_animations:
		_pause_animations()


func _end_paralyze() -> void:
	if not paralyzed:
		return

	paralyzed = false

	_clear_tint("paralyze")
	_resume_animations()

	if enemy != null and is_instance_valid(enemy):
		if _paralyze_disable_physics:
			enemy.set_physics_process(
				_paralyze_previous_physics_process
			)

		if _paralyze_disable_process:
			enemy.set_process(
				_paralyze_previous_process
			)


func is_paralyzed() -> bool:
	return paralyzed


# ============================================================
# EINFRIEREN (EIS)
# ============================================================

# Anders als Paralyse wird der Gegner NICHT komplett gestoppt,
# sondern nur verlangsamt (slow_multiplier) und blau eingefärbt.
func apply_freeze(
	duration: float,
	slow_multiplier: float
) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	if _enemy_is_dead():
		return

	freeze_generation += 1

	var this_generation: int = freeze_generation
	var safe_duration: float = max(duration, 0.05)

	frozen = true

	_speed_modifiers["freeze"] = clampf(slow_multiplier, 0.0, 1.0)

	await get_tree().create_timer(safe_duration).timeout

	if not is_inside_tree():
		return

	if enemy == null or not is_instance_valid(enemy):
		return

	if _enemy_is_dead():
		_end_freeze()
		return

	if this_generation != freeze_generation:
		return

	_end_freeze()


func _end_freeze() -> void:
	if not frozen:
		return

	frozen = false

	_speed_modifiers.erase("freeze")


func is_frozen() -> bool:
	return frozen


# ============================================================
# PARRY-BETÄUBUNG (SCHWERT-PARADE DES SPIELERS)
# ============================================================

# Nutzer-Wunsch (Parry-Skill, siehe Player/player.gd
# _try_start_parry()): trifft ein Gegner den Spieler, während dessen
# "Parry"-Animation läuft, nimmt der Spieler keinen Schaden UND
# dieser Gegner wird komplett eingefroren (wie Paralyse oben -
# Physik/Process aus, alle AnimatedSprite2D-Kinder auf ihrem
# aktuellen Frame pausiert). ANDERS als Paralyse gibt es hier aber
# eine zusätzliche Abbruchbedingung (Nutzer-Wunsch: "wenn er Schaden
# bekommt dann ist er wieder normal"): bekommt der Gegner WÄHREND der
# Betäubung selbst Schaden, endet sie sofort, statt die volle Dauer
# abzuwarten. Duck-typing auf "hp" (genau wie schon "dead" bei
# _enemy_is_dead() oben) statt einer festen Klasse, damit das für
# jeden Gegnertyp funktioniert, der dieses Feld besitzt - fehlt "hp",
# läuft einfach nur der normale Timer bis zum Ende durch.
var parry_stun_generation: int = 0
var _parry_stunned: bool = false


func apply_parry_stun(duration: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	if _enemy_is_dead():
		return

	parry_stun_generation += 1

	var this_generation: int = parry_stun_generation
	var safe_duration: float = max(duration, 0.05)

	var starting_hp: Variant = null

	if "hp" in enemy:
		starting_hp = enemy.hp

	if not _parry_stunned:
		_start_parry_stun()

	var elapsed: float = 0.0
	var poll_step: float = 0.05

	while elapsed < safe_duration:
		if not is_instance_valid(enemy):
			return

		if this_generation != parry_stun_generation:
			return

		if _enemy_is_dead():
			_end_parry_stun()
			return

		if starting_hp != null and "hp" in enemy:
			if int(enemy.hp) != int(starting_hp):
				break

		if not is_inside_tree():
			return

		await get_tree().create_timer(
			min(poll_step, safe_duration - elapsed)
		).timeout

		elapsed += poll_step

	if this_generation != parry_stun_generation:
		return

	_end_parry_stun()


# Nutzer-Wunsch: der Gegner soll beim Parry IMMER auf Frame 1 seiner
# gerade laufenden Animation einfrieren (Godot zählt Frames ab 0,
# siehe skeleton.gd attack_damage_frame-Kommentar) - NICHT auf dem
# Frame, auf dem er zufällig gerade steht, wenn der Treffer passiert
# (anders als bei Paralyse/Root oben, die bewusst den aktuellen Frame
# halten). Siehe PARRY_FROZEN_FRAME/_pause_animations() weiter unten.
const PARRY_FROZEN_FRAME: int = 1


func _start_parry_stun() -> void:
	_parry_stunned = true

	if enemy is CharacterBody2D:
		enemy.velocity.x = 0

	enemy.set_physics_process(false)
	enemy.set_process(false)

	_pause_animations(PARRY_FROZEN_FRAME)


func _end_parry_stun() -> void:
	if not _parry_stunned:
		return

	_parry_stunned = false

	if enemy != null and is_instance_valid(enemy):
		enemy.set_physics_process(true)
		enemy.set_process(true)

		# Nutzer-Wunsch: die unterbrochene Angriffsanimation soll NICHT
		# einfach zu Ende laufen, sondern der Gegner direkt zu dem
		# übergehen, was als Nächstes ansteht (laufen, erneut
		# angreifen, ...) - siehe skeleton.gd interrupt_current_action().
		# Optional (has_method-Check), damit Gegnertypen ohne diese
		# Methode einfach beim bisherigen Verhalten (Animation läuft ab
		# ihrem eingefrorenen Frame normal weiter) bleiben.
		if enemy.has_method("interrupt_current_action"):
			enemy.interrupt_current_action()

	_resume_animations()


func is_parry_stunned() -> bool:
	return _parry_stunned


# ============================================================
# FESTHALTEN (RANKEN)
# ============================================================

# Blockiert nur die Bewegung (velocity.x), nicht Angriffe.
# Die aufrufende Seite (z.B. skeleton.gd) muss is_rooted()
# selbst prüfen, bevor sie in den WALK-Zustand wechselt.
#
# Zusätzlich wird die aktuelle Animation auf ihrem aktuellen
# Frame eingefroren (wie eine Pause-Taste) und läuft nach Ende
# der Wurzel-Zeit an genau dieser Stelle weiter. Falls der
# Gegner genau jetzt einen Schaden-Frame hat (z.B. mitten im
# Angriff), wird NICHT sofort eingefroren, sondern erst wenn
# die nächste Animation beginnt - siehe _try_hold_root_animation().
func apply_root(duration: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	if _enemy_is_dead():
		return

	root_generation += 1

	var this_generation: int = root_generation
	var safe_duration: float = max(duration, 0.05)

	rooted = true

	# Sofort versuchen zu halten: fängt den EXAKTEN Frame ab,
	# auf dem der Gegner in diesem Moment gerade ist (z.B. mitten
	# im Laufen), bevor seine eigene Logik im nächsten Tick sonst
	# auf Idle umschalten würde.
	_try_hold_root_animation()

	await get_tree().create_timer(safe_duration).timeout

	if not is_inside_tree():
		return

	if this_generation != root_generation:
		return

	_end_root()


# Wird von der Ranken-Animation selbst aufgerufen (roots_hold.gd),
# sobald sie verschwindet - dann muss nicht auf den Sicherheits-
# Timeout gewartet werden.
func cancel_root() -> void:
	root_generation += 1
	_end_root()


func _end_root() -> void:
	rooted = false
	_release_root_animation_hold()


func is_rooted() -> bool:
	return rooted


# ------------------------------------------------------------
# Animation auf dem aktuellen Frame festhalten
# ------------------------------------------------------------

var _root_held_sprite: AnimatedSprite2D = null


func _process(_delta: float) -> void:
	if not rooted:
		return

	# Läuft absichtlich JEDEN Frame weiter (nicht nur bis zum
	# ersten Halten): falls z.B. ein Angriff dazwischenkommt und
	# danach die Idle-Animation neu beginnt, wird der neue Frame
	# genauso sofort wieder festgehalten (selbstheilend).
	_try_hold_root_animation()


func _try_hold_root_animation() -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	# Der Gegner kann selbst sagen, ob es gerade sicher ist
	# (z.B. nicht mitten in einem Angriffs-/Schaden-Frame).
	# Ohne diese Funktion gilt es immer als sicher.
	if enemy.has_method("is_animation_freeze_safe"):
		if not enemy.is_animation_freeze_safe():
			return

	var target_sprite: AnimatedSprite2D = _find_primary_sprite(enemy)

	if target_sprite == null:
		return

	# pause() ist auch dann harmlos, wenn schon pausiert -
	# deshalb kein is_playing()-Gate nötig. So wird jeder neue
	# Frame (z.B. nach einem Angriff) zuverlässig sofort wieder
	# eingefroren, statt für immer auf dem alten Stand zu bleiben.
	target_sprite.pause()
	_root_held_sprite = target_sprite


func _release_root_animation_hold() -> void:
	if _root_held_sprite != null and is_instance_valid(_root_held_sprite):
		_root_held_sprite.play()

	_root_held_sprite = null


func _find_primary_sprite(node: Node) -> AnimatedSprite2D:
	if "sprite" in node:
		var direct_sprite: Variant = node.sprite

		if direct_sprite is AnimatedSprite2D:
			return direct_sprite

	return _find_first_animated_sprite(node)


func _find_first_animated_sprite(node: Node) -> AnimatedSprite2D:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D

		var found: AnimatedSprite2D = _find_first_animated_sprite(child)

		if found != null:
			return found

	return null


# ============================================================
# VERLANGSAMEN OHNE FESTE DAUER (Z.B. LICHTKUGEL-AURA)
# ============================================================

# source_id ist frei wählbar (z.B. "lightorb"), damit mehrere
# unabhängige Quellen sich nicht gegenseitig überschreiben.
# Bleibt aktiv, bis remove_slow_source() mit derselben
# source_id aufgerufen wird (z.B. beim Verlassen der Aura).
func apply_slow_source(
	source_id: String,
	multiplier: float
) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	_speed_modifiers[source_id] = clampf(multiplier, 0.0, 1.0)


func remove_slow_source(source_id: String) -> void:
	_speed_modifiers.erase(source_id)


# Wird von der Bewegungslogik des Gegners (z.B. skeleton.gd)
# mit move_speed multipliziert.
func get_speed_multiplier() -> float:
	var result: float = 1.0

	for modifier_value in _speed_modifiers.values():
		result = min(result, float(modifier_value))

	return result


# ============================================================
# ALLE EFFEKTE ABBRECHEN (Z.B. BEIM TOD DES GEGNERS)
# ============================================================

func cancel_all_effects() -> void:
	paralyze_generation += 1
	freeze_generation += 1
	root_generation += 1
	parry_stun_generation += 1

	if paralyzed:
		_end_paralyze()

	if frozen:
		_end_freeze()

	if _parry_stunned:
		_end_parry_stun()

	rooted = false
	_release_root_animation_hold()

	_speed_modifiers.clear()
	_clear_all_tints()


# ============================================================
# FARB-SHADER (GENERISCH, MEHRERE EFFEKTE MÖGLICH)
# ============================================================

func _apply_tint(
	key: String,
	tint_color: Color,
	tint_strength: float
) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	if _affected_sprites.is_empty():
		_collect_canvas_items(enemy)

		for canvas_item in _affected_sprites:
			if canvas_item != null and is_instance_valid(canvas_item):
				_original_materials[canvas_item] = canvas_item.material

	_active_tint_key = key

	for canvas_item in _affected_sprites:
		if canvas_item == null or not is_instance_valid(canvas_item):
			continue

		var material := ShaderMaterial.new()
		material.shader = _create_tint_shader()

		material.set_shader_parameter(
			"tint_color",
			tint_color
		)

		material.set_shader_parameter(
			"tint_strength",
			tint_strength
		)

		canvas_item.material = material


# Setzt die Farbe nur zurück, wenn gerade kein anderer Effekt
# (Paralyse/Einfrieren) noch eine eigene Farbe braucht.
func _clear_tint(key: String) -> void:
	if key != _active_tint_key:
		return

	# Einfrieren benutzt seit dem Partikel-Umbau keine eigene
	# Farbe mehr - nur Paralyse hält den Tint noch aktiv.
	if paralyzed:
		return

	_clear_all_tints()


func _clear_all_tints() -> void:
	for canvas_item in _original_materials.keys():
		if canvas_item == null or not is_instance_valid(canvas_item):
			continue

		canvas_item.material = _original_materials[canvas_item]

	_affected_sprites.clear()
	_original_materials.clear()
	_active_tint_key = ""


func _collect_canvas_items(node: Node) -> void:
	for child in node.get_children():
		if (
			child is Sprite2D
			or child is AnimatedSprite2D
			or child is Polygon2D
		):
			_affected_sprites.append(child as CanvasItem)

		_collect_canvas_items(child)


func _create_tint_shader() -> Shader:
	var shader := Shader.new()

	shader.code = """
shader_type canvas_item;

uniform vec4 tint_color : source_color = vec4(
	1.0,
	0.78,
	0.05,
	1.0
);

uniform float tint_strength : hint_range(
	0.0,
	1.0
) = 0.55;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	if (source.a <= 0.0) {
		COLOR = source;
		return;
	}

	float luminance = dot(
		source.rgb,
		vec3(0.299, 0.587, 0.114)
	);

	vec3 tinted = mix(
		source.rgb * tint_color.rgb,
		tint_color.rgb * max(luminance, 0.25),
		0.45
	);

	vec3 result = mix(
		source.rgb,
		tinted,
		tint_strength
	);

	COLOR = vec4(
		result,
		source.a
	);
}
"""

	return shader


# ============================================================
# ANIMATIONEN (NUR FÜR PARALYSE)
# ============================================================

# force_frame >= 0 (siehe PARRY_FROZEN_FRAME oben, NUR vom Parry-
# Stun benutzt) erzwingt zusätzlich diesen Frame-Index auf jedem
# pausierten AnimatedSprite2D, statt ihn einfach auf dem Frame zu
# halten, auf dem er gerade zufällig steht (Standard -1 = wie bisher
# bei Paralyse: aktueller Frame bleibt einfach stehen).
func _pause_animations(force_frame: int = -1) -> void:
	_paused_animated_sprites.clear()
	_collect_and_pause_animated_sprites(enemy, force_frame)


func _collect_and_pause_animated_sprites(
	node: Node,
	force_frame: int = -1
) -> void:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			if child.is_playing():
				child.pause()
				_paused_animated_sprites.append(child)

				if force_frame >= 0:
					_apply_forced_frame(child, force_frame)

		_collect_and_pause_animated_sprites(child, force_frame)


# Klemmt target_frame sicher auf die tatsächliche Frame-Anzahl der
# gerade laufenden Animation, damit ein z.B. sehr kurzer Angriff mit
# weniger als 2 Frames nicht auf einen ungültigen Frame-Index gesetzt
# wird.
func _apply_forced_frame(
	sprite: AnimatedSprite2D,
	target_frame: int
) -> void:
	if sprite.sprite_frames == null:
		return

	if sprite.animation == &"":
		return

	var frame_count: int = sprite.sprite_frames.get_frame_count(
		sprite.animation
	)

	if frame_count <= 0:
		return

	sprite.frame = clampi(target_frame, 0, frame_count - 1)


func _resume_animations() -> void:
	for animated_sprite in _paused_animated_sprites:
		if (
			animated_sprite != null
			and is_instance_valid(animated_sprite)
		):
			animated_sprite.play()

	_paused_animated_sprites.clear()


# ============================================================
# TOD PRÜFEN
# ============================================================

func _enemy_is_dead() -> bool:
	if enemy == null:
		return true

	if "dead" in enemy:
		return bool(enemy.dead)

	return false
