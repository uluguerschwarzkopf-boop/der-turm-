extends CharacterBody2D


# ============================================================
# EINSTELLUNGEN
# ============================================================

@export var speed: float = 160.0
@export var jump_velocity: float = -330.0
@export var gravity: float = 900.0
@export var roll_speed: float = 350.0
@export var roll_time: float = 0.25

# Wie lange die Kollision mit einer Plattform beim Durchfallen
# ausgeschaltet bleibt (siehe start_roll()-Nachbarschaft weiter
# unten bei "PLATTFORMEN"). Muss nur lang genug sein, dass der
# Spieler klar unter der Plattform landet.
@export var drop_through_disable_time: float = 0.35

@export var heal_amount: int = 1
@export var drink_heal_delay: float = 0.35
@export var drink_total_time: float = 0.75
@export var hurt_flash_time: float = 0.12


@export_group("Footstep Timing (NICHT die Audiodatei!)")

# ACHTUNG: hier NICHT die Fußschritt-Audiodatei reinziehen - das ist
# nur eine ZEIT (in Sekunden), kein Audio-Slot!
#
# Solange der Spieler läuft (in der "run"-Animation ist), wird alle
# footstep_interval Sekunden ein "footstep"-Sound abgespielt (siehe
# _physics_process() weiter unten) - unabhängig davon, wie viele
# Frames die "run"-Animation hat.
#
# Die eigentliche Audiodatei gehört NICHT hierher, sondern in die
# Sound-Bank auf dem SEPARATEN "SoundManager"-Node: im Szenenbaum
# links Player -> Scripts (Pfeil davor aufklappen) -> SoundManager
# anklicken - DORT im Inspector ist das Array "Sound Bank", da wird
# die Audiodatei reingezogen (siehe Player/player_sound_manager.gd).
@export var footstep_interval: float = 0.32

var _footstep_timer: float = 0.0


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = (
	get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
)

@onready var combat: Node = get_node_or_null(
	"Scripts/PlayerCombat"
)

@onready var health: Node = get_node_or_null(
	"Scripts/PlayerHealth"
)

@onready var inventory: Node = get_node_or_null(
	"Scripts/PlayerInventory"
)

@onready var bow: Node = get_node_or_null(
	"Scripts/PlayerBow"
)

@onready var spells: Node = get_node_or_null(
	"Scripts/PlayerSpells"
)

# Sound-Bank (Nutzer-Wunsch) - siehe Player/player_sound_manager.gd für
# die komplette Erklärung, wie man dort im Inspector Sounds einträgt.
@onready var sound_manager: Node = get_node_or_null(
	"Scripts/SoundManager"
)

# Für den Bildschirm-Ruckler beim Parry (siehe _shake_camera() weiter
# unten) - derselbe Camera2D-Node, der den Spieler sowieso schon
# verfolgt.
@onready var camera: Camera2D = get_node_or_null(
	"Camera2D"
) as Camera2D


# ============================================================
# STATUS
# ============================================================

var facing_right: bool = true
var is_rolling: bool = false
var roll_timer: float = 0.0
var roll_direction: float = 1.0

# Double Roll (Pfad der Stärke, siehe Game/skill_tree_data.gd, id
# &"double_roll": "2 Rollen-Ladungen statt einer") - wie viele
# Rollen INNERHALB der gerade laufenden Rollen-Kette noch übrig
# sind. Wird bei jedem frischen Rollenstart (siehe start_roll())
# neu gesetzt, nicht über Zeit aufgeladen: ohne den Skill bleibt es
# bei genau einer Rolle pro Kette (0 übrig, sobald sie läuft) -
# exakt das bisherige Verhalten. Mit dem Skill bleibt während der
# ersten Rolle noch eine zweite übrig, mit der man mitten in der
# Rolle nochmal rollen kann (Richtungswechsel oder mehr Strecke,
# siehe Nutzer-Wunsch).
var _rolls_remaining_in_chain: int = 0

var is_drinking: bool = false
var dead: bool = false
var control_locked: bool = false

# Charge Attack (Pfad der Stärke, erster aktiver Skill) - siehe
# _try_start_charge_attack()/_release_charge_attack() weiter unten.
# Taste gedrückt halten = laden, loslassen = Animation abbrechen -
# ABER ab dem "Commit"-Frame (siehe CHARGE_ATTACK_COMMIT_FRAME) ist
# kein Abbrechen mehr möglich, der Treffer auf CHARGE_ATTACK_HIT_FRAME
# läuft dann immer durch.
var _charge_attack_active: bool = false
var _charge_attack_committed: bool = false

# Abklingzeit (siehe CHARGE_ATTACK_COOLDOWN) - läuft in _physics_
# process() runter, unabhängig davon ob gerade geladen wird oder
# nicht (Cooldown startet mit der Aktivierung, siehe
# _try_start_charge_attack()).
var _charge_attack_cooldown_remaining: float = 0.0

# Ground Slam (Pfad der Stärke) - siehe _try_start_ground_slam()
# weiter unten. Nur in der Luft aktivierbar, kein Abbrechen danach:
# fällt "falling" auf der Stelle nach unten (GROUND_SLAM_FALL_ANIM),
# spielt beim Aufkommen dann "hitting" die Aufprall-Animation
# (GROUND_SLAM_HIT_ANIM) mit dem Schaden auf GROUND_SLAM_HIT_FRAME.
var _ground_slam_falling: bool = false
var _ground_slam_hitting: bool = false

# Iron Skin (Pfad der Stärke) - siehe _try_start_iron_skin() weiter
# unten. Noch ohne Spiel-Effekt (Nutzer-Wunsch), nur die Animation
# spielt ab; solange sie läuft, friert die Bewegung ein (wie Charge
# Attack), damit die normale Bewegungs-/Sprunglogik sie nicht sofort
# mit "idle"/"run"/... überschreibt.
var _iron_skin_active: bool = false

# Dash Slash (Pfad der Stärke) - siehe _try_start_dash_slash() weiter
# unten. Wie Ground Slam/Iron Skin nicht abbrechbar: dasht mit fester
# Geschwindigkeit (dash_slash_speed, siehe dort) in der beim Start
# gespeicherten Blickrichtung (_dash_slash_direction), bis die
# "Dash Slash"-Animation fertig ist.
var _dash_slash_active: bool = false
var _dash_slash_direction: float = 1.0

# Parry (Pfad der Stärke) - siehe _try_start_parry() weiter unten.
# Wie Iron Skin nur horizontal eingefroren, damit die Bewegungs-/
# Sprunglogik die "Parry"-Animation nicht überschreibt. Solange aktiv,
# fängt take_damage() weiter unten JEDEN Schaden ab (siehe dort) -
# kein Schaden, Parry-Effekt, Bildschirm-Ruckler und der zuschlagende
# Gegner wird kurz eingefroren.
var _parry_active: bool = false

# Schutz gegen sich überlappende Bildschirm-Ruckler (siehe
# _shake_camera() weiter unten) - z.B. wenn kurz hintereinander zwei
# Treffer geparried werden.
var _shake_generation: int = 0

# Einmalig in _ready() festgehaltener Ruhe-Wert von camera.offset
# (siehe Player/player.tscn, Camera2D.offset = (0, -50)) - _shake_
# camera() schüttelt UM diesen Wert herum, statt ihn zu überschreiben,
# und setzt am Ende auch wieder GENAU auf ihn zurück. Wird bewusst
# einmalig beim Start gespeichert (nicht bei jedem Ruckler live aus
# camera.offset gelesen), damit ein zweiter, schnell hintereinander
# ausgelöster Ruckler nicht versehentlich einen bereits mitten im
# Schütteln befindlichen Zwischenwert als neue "Ruhe-Position"
# übernimmt.
var _camera_rest_offset: Vector2 = Vector2.ZERO


# Fasst alle Status-Sperren aktiver Skills zusammen, die andere
# Aktionen (Angriff, Rolle, Bogen, Tränke, Zauber-Slots) blockieren
# sollen - siehe _input() oben.
func _is_active_skill_busy() -> bool:
	return (
		_charge_attack_active
		or _ground_slam_falling
		or _ground_slam_hitting
		or _iron_skin_active
		or _dash_slash_active
		or _parry_active
		or _backstep_active
	)

var scene_is_changing: bool = false


# ============================================================
# START
# ============================================================

func _ready() -> void:
	scene_is_changing = false

	set_physics_process(true)
	set_process_input(true)

	if health != null:
		if health.has_signal("hurt"):
			if not health.hurt.is_connected(_on_hurt):
				health.hurt.connect(_on_hurt)

		if health.has_signal("died"):
			if not health.died.is_connected(_on_died):
				health.died.connect(_on_died)

		dead = health.current_health <= 0

	if spells == null:
		push_warning(
			"Player: PlayerSpells fehlt unter Scripts/PlayerSpells."
		)

	if sprite != null:
		sprite.play("idle")

	if camera != null:
		_camera_rest_offset = camera.offset


func _exit_tree() -> void:
	scene_is_changing = true
	is_rolling = false
	is_drinking = false


# Fußschritt-Sounds (Nutzer-Wunsch): solange der Spieler in der
# "run"-Animation ist, wird alle footstep_interval Sekunden ein
# "footstep"-Sound aus der Sound-Bank abgespielt (siehe
# Player/player_sound_manager.gd) - siehe Aufruf in _physics_process()
# weiter unten. Läuft der Spieler nicht (mehr), wird der Timer sofort
# zurückgesetzt, damit nach dem nächsten Losrennen gleich wieder ein
# Schritt-Sound kommt, statt erst nach dem vollen Intervall.
func _update_footstep_sound(delta: float) -> void:
	if sprite == null or sprite.animation != "run":
		_footstep_timer = 0.0
		return

	_footstep_timer -= delta

	if _footstep_timer <= 0.0:
		_footstep_timer = footstep_interval
		_play_sound(&"footstep")


# Sound-Bank (Nutzer-Wunsch) - siehe Player/player_sound_manager.gd.
# Bewusst defensiv (kein Fehler, wenn SoundManager fehlt oder die id
# noch keine Audiodatei im Inspector hat).
func _play_sound(id: StringName) -> void:
	if sound_manager != null and sound_manager.has_method("play"):
		sound_manager.play(id)


# ============================================================
# EINGABEN
# ============================================================

func _input(event: InputEvent) -> void:
	if dead or control_locked or scene_is_changing:
		return

	# Alle Aktionen laufen über die InputMap (is_action_pressed),
	# statt über feste Tasten-/Maustastencodes, damit die
	# Tastenbelegung aus den Einstellungen tatsächlich wirkt.

	if event.is_action_pressed(&"attack "):
		if (
			combat != null
			and not is_rolling
			and not is_drinking
			and not _is_active_skill_busy()
		):
			combat.attack()

	if event.is_action_pressed(&"shoot_bow"):
		if (
			bow != null
			and not is_rolling
			and not is_drinking
			and not _is_active_skill_busy()
		):
			bow.shoot(facing_right)

	if event.is_action_pressed(&"roll "):
		if not is_drinking and not _is_active_skill_busy():
			start_roll()

	if event.is_action_pressed(&"use_potion"):
		if not _is_active_skill_busy():
			start_drink()

	if event.is_action_pressed(&"spell_slot_1"):
		if not _is_active_skill_busy():
			use_spell(0)

	if event.is_action_pressed(&"spell_slot_2"):
		if not _is_active_skill_busy():
			use_spell(1)

	if event.is_action_pressed(&"spell_slot_3"):
		if not _is_active_skill_busy():
			use_spell(2)

	if event.is_action_pressed(&"drop_through"):
		_try_drop_through_platform()

	if event.is_action_pressed(&"use_skill"):
		_use_equipped_skill()

	if event.is_action_released(&"use_skill"):
		_release_charge_attack()


# ============================================================
# PHYSIK
# ============================================================

func _physics_process(delta: float) -> void:
	if scene_is_changing:
		return

	if _charge_attack_cooldown_remaining > 0.0:
		_charge_attack_cooldown_remaining = max(
			_charge_attack_cooldown_remaining - delta, 0.0
		)

	if dead:
		velocity.x = 0
		_apply_gravity(delta)
		move_and_slide()
		return

	# Fußschritt-Sounds (Nutzer-Wunsch) - läuft JEDEN Physik-Frame,
	# unabhängig von Rollen/Trinken/Skills weiter unten: die Funktion
	# selbst prüft, ob sprite.animation gerade "run" ist, und tut sonst
	# nichts (Timer wird dann zurückgesetzt).
	_update_footstep_sound(delta)

	# Auch während eines Zaubers bleibt die Schwerkraft aktiv.
	# Nur die horizontale Steuerung wird blockiert.
	if control_locked:
		velocity.x = 0
		_apply_gravity(delta)
		move_and_slide()
		return

	_apply_gravity(delta)

	if is_rolling:
		roll_timer -= delta
		velocity.x = roll_direction * roll_speed

		if roll_timer <= 0.0:
			is_rolling = false

			# Zurücksetzen falls start_roll() für eine 2. Rolle die
			# Abspielgeschwindigkeit angepasst hat (siehe dort) - sonst
			# würden auch alle folgenden Animationen (Laufen, Idle...)
			# zu schnell/langsam abgespielt werden.
			if sprite != null:
				sprite.speed_scale = 1.0

		move_and_slide()
		return

	if is_drinking:
		velocity.x = 0
		move_and_slide()
		return

	# Charge Attack friert die Bewegung ein (wie ein normaler Angriff)
	# UND verhindert, dass die Bewegungs-/Sprung-Logik weiter unten
	# jeden Frame sprite.play("idle"/"run"/...) aufruft und damit die
	# Charge-Attack-Animation überschreibt.
	if _charge_attack_active:
		velocity.x = 0
		move_and_slide()
		return

	# Ground Slam: FALLEND - Bewegung horizontal eingefroren, die
	# Vertikalgeschwindigkeit wird NICHT überschrieben, sondern läuft
	# ganz normal über die _apply_gravity()-Schwerkraft weiter (siehe
	# Aufruf oben) - genau wie bei einem normalen Sprung. War der
	# Spieler beim Aktivieren noch am Aufsteigen, steigt er also erst
	# ganz normal bis zum höchsten Punkt weiter, bevor die Schwerkraft
	# ihn von dort aus mit normalem Sprung-Falltempo runterzieht
	# (Nutzer-Wunsch: "erst runter wenn man ganz oben ist, dann normale
	# Fallgeschwindigkeit").
	if _ground_slam_falling:
		velocity.x = 0

		move_and_slide()

		if is_on_floor():
			_land_ground_slam()

		return

	# Ground Slam: TRIFFT GERADE AUF - komplett eingefroren, bis die
	# Aufprall-Animation fertig ist (siehe _on_ground_slam_animation_
	# finished()).
	if _ground_slam_hitting:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Iron Skin: wie Charge Attack nur horizontal eingefroren, damit
	# die Bewegungs-/Sprunglogik weiter unten die Animation nicht
	# sofort überschreibt.
	if _iron_skin_active:
		velocity.x = 0
		move_and_slide()
		return

	# Dash Slash: dasht mit fester Geschwindigkeit in die beim Start
	# gespeicherte Blickrichtung (siehe _dash_slash_direction) - aber
	# NUR bis einschließlich dash_slash_hit_frame - 1 (Nutzer-Wunsch:
	# "ab frame 7 bleibt der Spieler auf der Stelle, weil da kein Dash
	# mehr ist") - ab dash_slash_hit_frame (siehe _on_dash_slash_frame_
	# changed() weiter unten, wo dort genau auf diesem Frame der
	# Schwertschlag ausgelöst wird) bleibt der Spieler für den Rest der
	# Animation stehen. move_and_slide() sorgt beim eigentlichen Dash
	# ganz normal dafür, dass eine Wand ihn wie jede andere Bewegung
	# stoppt.
	if _dash_slash_active:
		if sprite != null and sprite.frame < dash_slash_hit_frame:
			velocity.x = _dash_slash_direction * dash_slash_speed
		else:
			velocity.x = 0

		move_and_slide()
		return

	# Backstep: dasht wie Dash Slash mit fester Geschwindigkeit, bis der
	# Spieler wirklich hinter der Kollisions-Hitbox des Ziels
	# angekommen ist (siehe _backstep_landing_x / _try_start_backstep()
	# für den Grund und add_collision_exception_with(), warum der
	# Gegner dabei NICHT im Weg steht) - Nutzer-Wunsch: "wenn man schon
	# durch ihn durch ist, wird der Dash abgebrochen". backstep_
	# pass_frame ist dabei nur noch ein Sicherheitsnetz, falls die
	# Position aus irgendeinem Grund nie erreicht wird (z.B. eine Wand
	# im Weg). Sobald angekommen, wird exakt auf die Landeposition
	# geschnappt und der Spieler steht still, während die restliche
	# Animation (inkl. Treffer-Frame für die eigene Hitbox) fertig
	# abläuft.
	if _backstep_active:
		if not _backstep_passed:
			var reached_by_position: bool = (
				(
					_backstep_direction > 0.0
					and global_position.x >= _backstep_landing_x
				)
				or (
					_backstep_direction < 0.0
					and global_position.x <= _backstep_landing_x
				)
			)
			var reached_by_frame_failsafe: bool = (
				sprite != null and sprite.frame >= backstep_pass_frame
			)

			if reached_by_position or reached_by_frame_failsafe:
				_backstep_passed = true

				# Nur bei "echtem" Ankommen exakt auf die Landeposition
				# schnappen - beim Sicherheitsnetz (z.B. eine Wand hat
				# den Dash vorher gestoppt) würde das den Spieler durch
				# die Wand teleportieren, das wollen wir nicht.
				if reached_by_position:
					global_position.x = _backstep_landing_x

				if health != null:
					health.invincible = false
			else:
				velocity.x = _backstep_direction * backstep_speed

		if _backstep_passed:
			velocity.x = 0

		move_and_slide()
		return

	# Parry: wie Iron Skin nur horizontal eingefroren, damit die
	# Bewegungs-/Sprunglogik weiter unten die "Parry"-Animation nicht
	# sofort überschreibt.
	if _parry_active:
		velocity.x = 0
		move_and_slide()
		return

	if combat != null and combat.attacking:
		if (
			combat.can_cancel_second_hit()
			and _wants_to_interrupt_attack()
		):
			combat.cancel_attack()
			# Kein return: fällt in die normale Bewegungs-/
			# Sprunglogik weiter unten durch.
		else:
			velocity.x = 0
			move_and_slide()
			return

	if bow != null and "shooting" in bow and bow.shooting:
		velocity.x = 0
		move_and_slide()
		return

	var dir: float = Input.get_axis(
		"move_left",
		"move_right"
	)

	if dir != 0:
		velocity.x = dir * speed
		facing_right = dir > 0

		if sprite != null:
			sprite.flip_h = not facing_right

			if is_on_floor():
				sprite.play("run")
	else:
		velocity.x = 0

		if sprite != null and is_on_floor():
			sprite.play("idle")

	if (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	):
		velocity.y = jump_velocity

		if sprite != null:
			sprite.play("jump")

	if sprite != null and not is_on_floor():
		if velocity.y < 0:
			sprite.play("jump")
		else:
			sprite.play("fall")

	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		if velocity.y > 0:
			velocity.y = 0


# Wird während combat.attacking geprüft, um zu entscheiden,
# ob der Spieler den zweiten Schlag (Doppelschlag) durch
# Bewegen oder Springen unterbrechen möchte.
func _wants_to_interrupt_attack() -> bool:
	var dir: float = Input.get_axis(
		"move_left",
		"move_right"
	)

	if dir != 0.0:
		return true

	if (
		Input.is_action_just_pressed("jump")
		and is_on_floor()
	):
		return true

	return false


# ============================================================
# ROLLE
# ============================================================

func start_roll() -> void:
	if scene_is_changing:
		return

	if is_drinking or control_locked:
		return

	if combat != null and combat.attacking:
		return

	if is_rolling:
		# Mitten in einer laufenden Rolle nochmal rollen geht NUR mit
		# Double Roll (siehe _rolls_remaining_in_chain oben) - ohne
		# den Skill bleibt es beim bisherigen Verhalten: eine laufende
		# Rolle muss immer erst zu Ende laufen.
		if _rolls_remaining_in_chain <= 0:
			return

		_rolls_remaining_in_chain -= 1

		_apply_roll_direction_from_input()

		roll_timer = roll_time

		_spawn_roll_dust()

		# sprite.play("roll") würde hier NICHTS tun, wenn "roll" schon
		# die gerade laufende Animation ist (Godot startet dieselbe
		# Animation dann nicht neu, sondern spielt sie einfach weiter,
		# wo sie gerade steht) - genau das hat dazu geführt, dass die
		# zweite Rolle bei Double Roll optisch gar nicht wie eine neue
		# Rolle aussah, nur wie ein stummes Rutschen. stop() erzwingt
		# den Neustart.
		#
		# Startet danach bewusst bei Frame 2 statt bei Frame 0 (Nutzer-
		# Wunsch): die ersten Frames der "roll"-Animation zeigen den
		# Spieler noch am Boden ankauernd - Frame 2 zeigt ihn laut
		# Nutzer bereits mitten in der Rolle/in der Luft, was zur
		# zweiten (angehängten) Rolle optisch viel besser passt als
		# nochmal von der Ankauer-Pose anzufangen.
		if sprite != null:
			sprite.stop()
			sprite.play("roll")

			if (
				sprite.sprite_frames != null
				and sprite.sprite_frames.get_frame_count("roll") > 2
			):
				sprite.frame = 2

				# Nutzer-Problem: weil die 2. Rolle bei Frame 2 statt 0
				# startet (siehe oben), hat die Animation WENIGER Frames
				# zu zeigen als roll_timer Zeit hat - sie erreicht ihren
				# letzten Frame VOR Ablauf von roll_timer und bleibt dann
				# für den Rest der Zeit sichtbar auf diesem letzten
				# Frame "eingefroren" stehen. Fix: Abspielgeschwindigkeit
				# (speed_scale) so anpassen, dass genau die verbleibenden
				# Frames (ab Frame 2) exakt über roll_time verteilt
				# werden - dann kommt der letzte Frame GENAU dann, wenn
				# die Rolle auch bewegungstechnisch zu Ende ist, ohne
				# sichtbares Einfrieren. Wird direkt nach dem Ende dieser
				# Rolle wieder auf 1.0 zurückgesetzt (siehe
				# _physics_process() bei roll_timer <= 0.0).
				var native_fps: float = (
					sprite.sprite_frames.get_animation_speed("roll")
				)
				var remaining_frames: int = (
					sprite.sprite_frames.get_frame_count("roll") - 2
				)

				if native_fps > 0.0 and roll_time > 0.0:
					sprite.speed_scale = (
						(float(remaining_frames) / roll_time)
						/ native_fps
					)

		return

	# Rollen geht sonst nur am Boden, nicht in der Luft
	# (verhindert den "Roll-Schwung" beim Springen).
	if not is_on_floor():
		return

	is_rolling = true
	roll_timer = roll_time
	roll_direction = 1.0 if facing_right else -1.0
	_rolls_remaining_in_chain = _max_roll_chain() - 1

	if sprite != null:
		# Falls von einer vorigen 2. Rolle noch eine angepasste
		# speed_scale übrig wäre (siehe HINWEIS unten bei roll_timer
		# <= 0.0) - hier zur Sicherheit nochmal explizit zurücksetzen,
		# damit die 1. Rolle (Frame 0 bis Ende) immer mit normaler
		# Geschwindigkeit startet.
		sprite.speed_scale = 1.0
		sprite.play("roll")


# Wie viele Rollen insgesamt in einer Kette möglich sind, bevor man
# wieder ganz von vorn anfangen muss (siehe start_roll()) - 1 ohne
# Double Roll (bisheriges Verhalten), 2 mit dem Skill.
func _max_roll_chain() -> int:
	if get_node_or_null("/root/RunState") != null:
		if RunState.has_unlocked_skill(&"double_roll"):
			return 2

	return 1


# Wird nur beim Double-Roll-Nachrollen mitten in einer laufenden
# Rolle aufgerufen - übernimmt, falls der Spieler gerade eine
# Richtung gedrückt hält, diese als neue Rollrichtung (siehe
# Nutzer-Wunsch: "damit du auch Richtung wechseln kannst in der
# Rolle"). Ohne gedrückte Richtung bleibt die bisherige
# roll_direction unverändert - man rollt dann einfach geradeaus
# weiter, statt zwangsweise umzudrehen.
func _apply_roll_direction_from_input() -> void:
	var input_dir: float = Input.get_axis(
		"move_left",
		"move_right"
	)

	if input_dir == 0.0:
		return

	roll_direction = 1.0 if input_dir > 0.0 else -1.0
	facing_right = input_dir > 0.0

	if sprite != null:
		sprite.flip_h = not facing_right


# ============================================================
# ROLL-STAUB-EFFEKT (PIXEL-ART-PARTIKEL)
# ============================================================

# Kleiner Staub-Effekt NUR beim Doppelroller (2. Rolle einer
# laufenden Kette, siehe Aufruf oben im Double-Roll-Zweig von
# start_roll() - die 1. Rolle bekommt bewusst KEINEN Staub) - ein
# kurzer CPUParticles2D-Ausstoß, der GEGEN die Rollrichtung fliegt
# (wie aufgewirbelter Staub, den man hinter sich lässt), dabei über
# die Lebenszeit dunkler wird und gleichzeitig ausblendet (siehe
# _get_roll_dust_gradient() unten) - genau wie vom Nutzer beschrieben:
# "wird immer dunkler und geht weiter weg bis es weg ist komplett".
func _spawn_roll_dust() -> void:
	var tree := get_tree()

	if tree == null:
		return

	var spawn_parent: Node = tree.current_scene

	if spawn_parent == null:
		return

	var particles := CPUParticles2D.new()

	particles.texture = _get_roll_dust_texture()
	# NEAREST statt der Godot-Standardfilterung, sonst würde die
	# kleine Pixel-Art-Textur beim Hochskalieren (scale_amount unten)
	# weichgezeichnet/verwaschen aussehen statt knackig-pixelig.
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 8
	particles.lifetime = 0.5
	particles.explosiveness = 0.85
	particles.z_index = -1

	# GEGEN die Rollrichtung (roll_direction: 1.0 = rechts, -1.0 =
	# links), mit leichtem Aufwärts-Bias, damit es wie vom Boden
	# aufgewirbelter Staub aussieht statt flach am Boden zu kleben.
	particles.direction = Vector2(-roll_direction, -0.35).normalized()
	particles.spread = 22.0

	particles.gravity = Vector2(0.0, 60.0)
	particles.initial_velocity_min = 18.0
	particles.initial_velocity_max = 42.0

	# Bremst die Partikel über die Zeit ab, statt dass sie gerade
	# weiterfliegen - wirkt dadurch mehr wie Staub, der sich legt,
	# statt wie Geschosse.
	particles.damping_min = 40.0
	particles.damping_max = 70.0

	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.0

	particles.color_ramp = _get_roll_dust_gradient()

	spawn_parent.add_child(particles)

	particles.global_position = global_position
	particles.emitting = true

	await tree.create_timer(particles.lifetime + 0.3).timeout

	if is_instance_valid(particles):
		particles.queue_free()


var _roll_dust_texture: Texture2D = null


# Kleine, HARTKANTIGE (nicht weich verlaufende) quadratische Textur -
# bewusst anders als _get_particle_texture() in Player/player_spell_
# particles.gd (die einen weichen Kreis erzeugt): Staub soll wie
# Pixel-Art aussehen, nicht wie ein Glow-/Funken-Effekt.
func _get_roll_dust_texture() -> Texture2D:
	if _roll_dust_texture != null:
		return _roll_dust_texture

	var size: int = 4
	var image := Image.create(
		size,
		size,
		false,
		Image.FORMAT_RGBA8
	)

	image.fill(Color(1.0, 1.0, 1.0, 1.0))

	_roll_dust_texture = ImageTexture.create_from_image(image)

	return _roll_dust_texture


var _roll_dust_gradient: Gradient = null


# Startet bei einem hellen, halbtransparenten Grauton (Nutzer-Wunsch:
# grauer statt bräunlich) und endet bei einem DEUTLICH dunkleren Grau
# mit Alpha 0 (komplett unsichtbar) - ergibt zusammen mit der
# Lebenszeit oben genau den gewünschten "wird dunkler und
# verschwindet dabei"-Effekt.
func _get_roll_dust_gradient() -> Gradient:
	if _roll_dust_gradient != null:
		return _roll_dust_gradient

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.72, 0.72, 0.72, 0.85),
		Color(0.18, 0.18, 0.18, 0.0),
	])

	_roll_dust_gradient = gradient

	return _roll_dust_gradient


# ============================================================
# AKTIVER SKILL (SKILL-SLOT, PFAD DER STÄRKE) - GRUNDGERÜST
# ============================================================

# TESTWERT, NICHT FINAL (wie RunState.VIGOR_MAX/VIGOR_PER_MELEE_HIT) -
# die echten Vigor-Kosten pro Skill stehen noch nicht fest (siehe
# z.B. skill.charged_strike.desc: "Vigor-Kosten noch nicht final").
# Bis dahin kostet JEDER ausgerüstete aktive Skill hier einheitlich
# diesen Platzhalterwert.
const PLACEHOLDER_SKILL_VIGOR_COST: int = 30


# Ausgelöst über die Taste "use_skill" (siehe _input() oben, Standard
# Taste E, unter Einstellungen -> Steuerung änderbar). Der Skill
# selbst kommt aus RunState.equipped_active_skill - zugewiesen durch
# Anklicken eines bereits freigeschalteten aktiven Skills im
# Skill-Baum (siehe Game/skill_tree_menu.gd). Ist gar kein aktiver
# Skill ausgerüstet, ist equipped_active_skill "" und hier passiert
# nichts - ein Skill lässt sich also nur benutzen, wenn er auch
# tatsächlich im Slot ausgerüstet ist.
#
# Charge Attack (erster aktiver Skill, Pfad der Stärke) ist bereits
# vollständig umgesetzt (siehe _try_start_charge_attack() unten).
# Alle anderen aktiven Skills warten noch auf ihre endgültigen Werte
# (siehe Game/skill_tree_data.gd) - für die bleibt es bei Vigor-
# Verbrauch plus Debug-Ausgabe als Platzhalter.
func _use_equipped_skill() -> void:
	if dead or control_locked or scene_is_changing:
		return

	if get_node_or_null("/root/RunState") == null:
		return

	var skill_id: StringName = RunState.equipped_active_skill

	if skill_id == &"":
		return

	if skill_id == CHARGE_ATTACK_SKILL_ID:
		_try_start_charge_attack()
		return

	if skill_id == GROUND_SLAM_SKILL_ID:
		_try_start_ground_slam()
		return

	if skill_id == IRON_SKIN_SKILL_ID:
		_try_start_iron_skin()
		return

	if skill_id == DASH_SLASH_SKILL_ID:
		_try_start_dash_slash()
		return

	if skill_id == BACKSTEP_SKILL_ID:
		_try_start_backstep()
		return

	if skill_id == PARRY_SKILL_ID:
		_try_start_parry()
		return

	if not RunState.spend_vigor(PLACEHOLDER_SKILL_VIGOR_COST):
		return

	print(
		"Aktiver Skill ausgelöst (Platzhalter, noch ohne Effekt): ",
		skill_id
	)


# ============================================================
# CHARGE ATTACK (PFAD DER STÄRKE, ERSTER AKTIVER SKILL)
# ============================================================

# Skill-Taste ("use_skill") gedrückt HALTEN spielt die "Charge
# Attack"-Animation ab. Lässt man sie VOR dem Commit-Frame wieder
# los, bricht die Animation sofort ab (kein Schaden). Ab dem Commit-
# Frame ist kein Abbrechen mehr möglich - die Animation läuft dann
# garantiert bis zum Ende durch und trifft auf dem Hit-Frame mit der
# GLEICHEN Hitbox wie die normalen Nahkampf-Angriffe (siehe
# Player/player_combat.gd activate_hitbox_with_damage()), nur mit
# eigenem, festem Schaden statt des normalen Angriffsschadens.
const CHARGE_ATTACK_SKILL_ID: StringName = &"charged_strike"
const CHARGE_ATTACK_ANIM: StringName = &"Charge Attack"
const CHARGE_ATTACK_COMMIT_FRAME: int = 24
const CHARGE_ATTACK_HIT_FRAME: int = 25
const CHARGE_ATTACK_DAMAGE: int = 3

# Eigener Vigor-Preis (NICHT der generische PLACEHOLDER_SKILL_VIGOR_
# COST oben, der ist nur für die noch nicht umgesetzten Skills) und
# eine Abklingzeit, damit der Skill nicht im Sekundentakt spammbar
# ist. Beides Testwerte, noch nicht final (Nutzer-Wunsch).
const CHARGE_ATTACK_VIGOR_COST: int = 40
const CHARGE_ATTACK_COOLDOWN: float = 5.0


func _try_start_charge_attack() -> void:
	if _charge_attack_active:
		return

	if is_rolling or is_drinking:
		return

	if _ground_slam_falling or _ground_slam_hitting:
		return

	if combat != null and combat.attacking:
		return

	if _charge_attack_cooldown_remaining > 0.0:
		print(
			"Charge Attack: noch ",
			"%.1f" % _charge_attack_cooldown_remaining,
			"s Abklingzeit übrig."
		)
		return

	if sprite == null:
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(CHARGE_ATTACK_ANIM)
	):
		push_warning(
			"Charge Attack: Animation '" + String(CHARGE_ATTACK_ANIM)
			+ "' fehlt auf dem Player-Sprite."
		)
		return

	# Nutzer-Wunsch: Vigor wird erst beim COMMIT-Frame abgezogen
	# (siehe _on_charge_attack_frame_changed()), nicht schon hier beim
	# Start - wer die Taste vor dem Commit-Frame wieder loslässt und
	# abbricht, soll gar keine Vigor bezahlen. Hier nur PRÜFEN, ob
	# überhaupt genug da ist, damit der Skill nicht startet, wenn er
	# sich eh nicht "leisten" lässt.
	if RunState.current_vigor < CHARGE_ATTACK_VIGOR_COST:
		# Kein Testwert-Meckern per push_warning, damit das beim
		# normalen Spielen nicht ständig aufploppt - aber ein print()
		# fürs Debuggen, sonst sieht es beim Testen so aus, als würde
		# beim Tastendruck einfach GAR NICHTS passieren.
		print(
			"Charge Attack: nicht genug Vigor (",
			RunState.current_vigor, "/", CHARGE_ATTACK_VIGOR_COST,
			" nötig) - erst ein paar Nahkampf-Treffer landen."
		)
		return

	_charge_attack_cooldown_remaining = CHARGE_ATTACK_COOLDOWN

	_charge_attack_active = true
	_charge_attack_committed = false

	if not sprite.frame_changed.is_connected(
		_on_charge_attack_frame_changed
	):
		sprite.frame_changed.connect(_on_charge_attack_frame_changed)

	if not sprite.animation_finished.is_connected(
		_on_charge_attack_animation_finished
	):
		sprite.animation_finished.connect(
			_on_charge_attack_animation_finished
		)

	sprite.play(CHARGE_ATTACK_ANIM)


# Loslassen der Skill-Taste - bricht NUR ab, solange der Commit-Frame
# noch nicht erreicht wurde (siehe _on_charge_attack_frame_changed()).
func _release_charge_attack() -> void:
	if not _charge_attack_active:
		return

	if _charge_attack_committed:
		return

	_end_charge_attack()


func _on_charge_attack_frame_changed() -> void:
	if not _charge_attack_active:
		return

	if sprite == null or sprite.animation != CHARGE_ATTACK_ANIM:
		return

	if (
		sprite.frame >= CHARGE_ATTACK_COMMIT_FRAME
		and not _charge_attack_committed
	):
		_charge_attack_committed = true

		# Erst JETZT tatsächlich Vigor abziehen (siehe Kommentar in
		# _try_start_charge_attack()) - der Angriff läuft ab hier so
		# oder so durch, "kostet" also erst ab dem Punkt, wo er nicht
		# mehr abgebrochen werden kann.
		if get_node_or_null("/root/RunState") != null:
			RunState.spend_vigor(CHARGE_ATTACK_VIGOR_COST)

	if sprite.frame == CHARGE_ATTACK_HIT_FRAME and combat != null:
		combat.activate_hitbox_with_damage(CHARGE_ATTACK_DAMAGE)
		_play_sound(&"skill_charged_strike")


func _on_charge_attack_animation_finished() -> void:
	if sprite == null or sprite.animation != CHARGE_ATTACK_ANIM:
		return

	_end_charge_attack()


func _end_charge_attack() -> void:
	_charge_attack_active = false
	_charge_attack_committed = false

	if sprite == null:
		return

	if sprite.frame_changed.is_connected(_on_charge_attack_frame_changed):
		sprite.frame_changed.disconnect(_on_charge_attack_frame_changed)

	if sprite.animation_finished.is_connected(
		_on_charge_attack_animation_finished
	):
		sprite.animation_finished.disconnect(
			_on_charge_attack_animation_finished
		)

	if not dead:
		sprite.play("idle")


# ============================================================
# GROUND SLAM (PFAD DER STÄRKE)
# ============================================================

# Nur in der Luft aktivierbar. Sobald ausgelöst, gibt es (anders als
# Charge Attack) KEIN Abbrechen mehr: Spieler fällt auf der Stelle
# (horizontal eingefroren) mit fester Geschwindigkeit nach unten
# (GROUND_SLAM_FALL_ANIM), bis der Boden erreicht ist. Dann spielt
# die Aufprall-Animation (GROUND_SLAM_HIT_ANIM) und aktiviert auf
# GROUND_SLAM_HIT_FRAME die eigene "Ground slam Hitbox" (siehe
# Player/player_combat.gd activate_ground_slam_hitbox()) mit eigenem
# Schaden.
const GROUND_SLAM_SKILL_ID: StringName = &"ground_slam"
const GROUND_SLAM_FALL_ANIM: StringName = &"ground slam fall"
const GROUND_SLAM_HIT_ANIM: StringName = &"ground slam hit"
const GROUND_SLAM_HIT_FRAME: int = 2
const GROUND_SLAM_DAMAGE: int = 2

# Testwerte, noch nicht final (Nutzer-Wunsch) - wie bei Charge Attack
# eigener Vigor-Preis, getrennt vom generischen PLACEHOLDER_SKILL_
# VIGOR_COST. Anders als Charge Attack gibt es hier kein "erst beim
# Commit abziehen", weil Ground Slam nicht abbrechbar ist - die Vigor
# wird also direkt beim erfolgreichen Auslösen abgezogen.
const GROUND_SLAM_VIGOR_COST: int = 60

# Nutzer-Wunsch: beim Aktivieren erst NOCH HÖHER springen (extra
# Aufwärts-Schub, NUR während Ground Slam - normale Sprünge bleiben
# unverändert) und danach erst wie gewohnt fallen. Negativ, weil "nach
# oben" in Godot 2D negative Y-Geschwindigkeit ist - wird unten auf
# die aktuelle velocity.y AUFADDIERT, nicht ersetzt, damit ein bereits
# vorhandener Sprung-Schwung nicht verloren geht.
const GROUND_SLAM_JUMP_BOOST: float = -110.0


func _try_start_ground_slam() -> void:
	if _ground_slam_falling or _ground_slam_hitting:
		return

	if _charge_attack_active:
		return

	if is_rolling or is_drinking:
		return

	if combat != null and combat.attacking:
		return

	# Nutzer-Wunsch: nur in der Luft aktivierbar.
	if is_on_floor():
		print("Ground Slam: nur in der Luft aktivierbar.")
		return

	if sprite == null:
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(GROUND_SLAM_FALL_ANIM)
		or not sprite.sprite_frames.has_animation(GROUND_SLAM_HIT_ANIM)
	):
		push_warning(
			"Ground Slam: Animation(en) fehlen auf dem Player-Sprite."
		)
		return

	if RunState.current_vigor < GROUND_SLAM_VIGOR_COST:
		print(
			"Ground Slam: nicht genug Vigor (",
			RunState.current_vigor, "/", GROUND_SLAM_VIGOR_COST,
			" nötig)."
		)
		return

	RunState.spend_vigor(GROUND_SLAM_VIGOR_COST)

	_ground_slam_falling = true
	_ground_slam_hitting = false

	# Extra Aufwärts-Schub NUR für Ground Slam (Nutzer-Wunsch: "noch
	# höher springen, dann erst runter droppen") - danach übernimmt
	# wie gehabt die normale Schwerkraft (siehe _apply_gravity()-
	# Aufruf oben in _physics_process()) den Rest: erst bis zum neuen,
	# höheren Scheitelpunkt weiter steigen, dann normal fallen.
	velocity.y += GROUND_SLAM_JUMP_BOOST
	velocity.x = 0

	sprite.play(GROUND_SLAM_FALL_ANIM)


# Wird aufgerufen, sobald der Spieler während des Sturzes den Boden
# erreicht (siehe _physics_process() oben).
func _land_ground_slam() -> void:
	_ground_slam_falling = false
	_ground_slam_hitting = true

	velocity = Vector2.ZERO

	if sprite == null:
		return

	if not sprite.frame_changed.is_connected(
		_on_ground_slam_frame_changed
	):
		sprite.frame_changed.connect(_on_ground_slam_frame_changed)

	if not sprite.animation_finished.is_connected(
		_on_ground_slam_animation_finished
	):
		sprite.animation_finished.connect(
			_on_ground_slam_animation_finished
		)

	sprite.play(GROUND_SLAM_HIT_ANIM)


func _on_ground_slam_frame_changed() -> void:
	if not _ground_slam_hitting:
		return

	if sprite == null or sprite.animation != GROUND_SLAM_HIT_ANIM:
		return

	if sprite.frame == GROUND_SLAM_HIT_FRAME and combat != null:
		combat.activate_ground_slam_hitbox(GROUND_SLAM_DAMAGE)
		_play_sound(&"skill_ground_slam")


func _on_ground_slam_animation_finished() -> void:
	if sprite == null or sprite.animation != GROUND_SLAM_HIT_ANIM:
		return

	_end_ground_slam()


func _end_ground_slam() -> void:
	_ground_slam_falling = false
	_ground_slam_hitting = false

	if sprite == null:
		return

	if sprite.frame_changed.is_connected(_on_ground_slam_frame_changed):
		sprite.frame_changed.disconnect(_on_ground_slam_frame_changed)

	if sprite.animation_finished.is_connected(
		_on_ground_slam_animation_finished
	):
		sprite.animation_finished.disconnect(
			_on_ground_slam_animation_finished
		)

	if not dead:
		sprite.play("idle")


# ============================================================
# IRON SKIN (PFAD DER STÄRKE, VIERTER AKTIVER SKILL)
# ============================================================

# Nutzer-Wunsch: Iron Skin verleiht 1 Herz Iron-Rüstung - verhält
# sich mechanisch genau wie die normale Schild-Rüstung aus dem Shop
# (siehe add_armor() oben, Händler/.../shop_overlay.gd), nur mit
# eigener Optik ("Iron heart *"-Animationen statt "armor_*", siehe
# player_health.gd/hud.gd). Volle Leben nötig, und jedes Herz kann
# immer nur EINE Rüstung gleichzeitig tragen (egal welcher Art) -
# das prüft add_armor() zentral.
const IRON_SKIN_SKILL_ID: StringName = &"iron_skin"
const IRON_SKIN_ANIM: StringName = &"Iron Skin"
const IRON_SKIN_VIGOR_COST: int = 50
const IRON_SKIN_ARMOR_TYPE: StringName = &"iron"


func _try_start_iron_skin() -> void:
	if dead or control_locked or scene_is_changing:
		return

	if _is_active_skill_busy():
		return

	if is_rolling or is_drinking:
		return

	if combat != null and combat.attacking:
		return

	if RunState.current_vigor < IRON_SKIN_VIGOR_COST:
		print(
			"Iron Skin: nicht genug Vigor (",
			RunState.current_vigor,
			"/",
			IRON_SKIN_VIGOR_COST,
			" nötig)."
		)
		return

	# Rüstung ZUERST vergeben, bevor Vigor verbraucht wird - schlägt
	# das fehl (nicht volle Leben, oder schon jedes Herz mit einer
	# Rüstung belegt), löst der Skill gar nicht erst aus, genau wie
	# ein Schild-Kauf im Shop bei vollen Herzen einfach nicht klappt.
	if not add_armor(1, IRON_SKIN_ARMOR_TYPE):
		print(
			"Iron Skin: keine Rüstung möglich (nicht volle Leben "
			+ "oder kein freies Herz)."
		)
		return

	RunState.spend_vigor(IRON_SKIN_VIGOR_COST)

	print("Iron Skin ausgelöst - 1 Iron-Rüstung vergeben.")

	if (
		sprite == null
		or sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(IRON_SKIN_ANIM)
	):
		push_warning(
			"Iron Skin: Animation '" + String(IRON_SKIN_ANIM)
			+ "' fehlt auf dem Player-Sprite."
		)
		return

	_iron_skin_active = true

	if not sprite.animation_finished.is_connected(
		_on_iron_skin_animation_finished
	):
		sprite.animation_finished.connect(
			_on_iron_skin_animation_finished
		)

	sprite.play(IRON_SKIN_ANIM)
	_play_sound(&"skill_iron_skin")


func _on_iron_skin_animation_finished() -> void:
	if sprite == null or sprite.animation != IRON_SKIN_ANIM:
		return

	_iron_skin_active = false

	if sprite.animation_finished.is_connected(
		_on_iron_skin_animation_finished
	):
		sprite.animation_finished.disconnect(
			_on_iron_skin_animation_finished
		)

	if not dead:
		sprite.play("idle")


# ============================================================
# DASH SLASH (PFAD DER STÄRKE, MOBILITÄTS-ZWEIG)
# ============================================================

# Nutzer-Wunsch: Dash-Angriff nach vorne - der Spieler dasht während
# der ganzen "Dash Slash"-Animation (siehe Player/player.tscn,
# SpriteFrames "Dash Slash" - 11 Frames, Index 0-10) mit fester
# Geschwindigkeit in Blickrichtung, auf DASH_SLASH_HIT_FRAME löst der
# Schwertschlag aus und aktiviert dieselbe Hitbox wie die normalen
# Nahkampf-Angriffe (siehe Player/player_combat.gd
# activate_hitbox_with_damage()) - genau wie schon bei Charge Attack.
# Kann NICHT abgebrochen werden, sobald gestartet - läuft immer bis
# zum Ende der Animation durch, genau wie Ground Slam/Iron Skin.
const DASH_SLASH_SKILL_ID: StringName = &"dash_slash"
const DASH_SLASH_ANIM: StringName = &"Dash Slash"

# Nutzer-Wunsch: Schaden UND Dash-Werte (Geschwindigkeit, Vigor-
# Kosten, Treffer-Frame) sollen im Godot-Inspector einstellbar sein -
# deshalb hier bewusst @export statt const (anders als bei den
# bisherigen aktiven Skills oben, deren Werte laut Vorlage zwar auch
# noch nicht final sind, aber nicht als Inspector-Werte gewünscht
# wurden).
@export_group("Aktiver Skill - Dash Slash")
@export var dash_slash_speed: float = 500.0
@export var dash_slash_damage: int = 2
@export var dash_slash_vigor_cost: int = 60
@export var dash_slash_hit_frame: int = 7


func _try_start_dash_slash() -> void:
	if dead or control_locked or scene_is_changing:
		return

	if _is_active_skill_busy():
		return

	if is_rolling or is_drinking:
		return

	if combat != null and combat.attacking:
		return

	if sprite == null:
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(DASH_SLASH_ANIM)
	):
		push_warning(
			"Dash Slash: Animation '" + String(DASH_SLASH_ANIM)
			+ "' fehlt auf dem Player-Sprite."
		)
		return

	if RunState.current_vigor < dash_slash_vigor_cost:
		print(
			"Dash Slash: nicht genug Vigor (",
			RunState.current_vigor,
			"/",
			dash_slash_vigor_cost,
			" nötig)."
		)
		return

	RunState.spend_vigor(dash_slash_vigor_cost)

	_dash_slash_active = true
	_dash_slash_direction = 1.0 if facing_right else -1.0

	if not sprite.frame_changed.is_connected(
		_on_dash_slash_frame_changed
	):
		sprite.frame_changed.connect(_on_dash_slash_frame_changed)

	if not sprite.animation_finished.is_connected(
		_on_dash_slash_animation_finished
	):
		sprite.animation_finished.connect(
			_on_dash_slash_animation_finished
		)

	sprite.play(DASH_SLASH_ANIM)


func _on_dash_slash_frame_changed() -> void:
	if not _dash_slash_active:
		return

	if sprite == null or sprite.animation != DASH_SLASH_ANIM:
		return

	if sprite.frame == dash_slash_hit_frame and combat != null:
		combat.activate_hitbox_with_damage(dash_slash_damage)
		_play_sound(&"skill_dash_slash")


func _on_dash_slash_animation_finished() -> void:
	if sprite == null or sprite.animation != DASH_SLASH_ANIM:
		return

	_end_dash_slash()


func _end_dash_slash() -> void:
	_dash_slash_active = false

	if sprite == null:
		return

	if sprite.frame_changed.is_connected(_on_dash_slash_frame_changed):
		sprite.frame_changed.disconnect(_on_dash_slash_frame_changed)

	if sprite.animation_finished.is_connected(
		_on_dash_slash_animation_finished
	):
		sprite.animation_finished.disconnect(
			_on_dash_slash_animation_finished
		)

	if not dead:
		sprite.play("idle")


# ============================================================
# BACKSTEP (PFAD DER STÄRKE, MOBILITÄTS-ZWEIG)
# ============================================================

# Nutzer-Wunsch: geht nur bei GENAU EINEM Gegner in Reichweite (siehe
# combat.find_backstep_target()) und nur, wenn hinter dem Ziel fester
# Boden ist (siehe _has_floor_behind_target() weiter unten, sonst
# würde der Spieler danach runterfallen). Läuft dann in Blickrichtung
# durch den Gegner HINDURCH (siehe add_collision_exception_with()
# unten - nur für dieses eine Ziel, Wände/Boden bleiben ganz normal
# solide) bis er wirklich HINTER der Kollisions-Hitbox des Gegners
# angekommen ist (siehe _get_backstep_landing_position() - berechnet
# aus der tatsächlichen Breite des Gegners, nicht aus einem festen
# Rate-Wert). Der Dash wird also nicht mehr nach einer festen Anzahl
# Frames abgebrochen, sondern genau dann, wenn der Spieler diese
# Position erreicht (bzw. spätestens bei backstep_pass_frame als
# Sicherheitsnetz, falls z.B. eine Wand im Weg ist) - ab da steht der
# Spieler und die restliche Animation läuft normal weiter. Während des
# gesamten Dashs (bis zum Ankommen) ist der Spieler unsterblich (siehe
# health.invincible). Auf backstep_hit_frame löst die eigene Backstep-
# Hitbox den Schaden aus (siehe Player/player_combat.gd
# activate_backstep_hitbox()).
const BACKSTEP_SKILL_ID: StringName = &"backstep"
const BACKSTEP_ANIM: StringName = &"backstep"

@export_group("Aktiver Skill - Backstep")
@export var backstep_speed: float = 500.0
@export var backstep_damage: int = 2
@export var backstep_vigor_cost: int = 70

# Sicherheitsnetz: spätestens auf diesem Frame wird der Dash auf
# jeden Fall beendet, auch falls die Landeposition (siehe unten) aus
# irgendeinem Grund nie erreicht wird (z.B. eine Wand blockiert).
@export var backstep_pass_frame: int = 9
@export var backstep_hit_frame: int = 14

# Zusätzlicher Sicherheitsabstand (in Pixeln) HINTER der tatsächlichen
# Kollisions-Hitbox des Gegners (siehe _get_target_half_width() unten)
# - die eigentliche Breite des Gegners wird automatisch ermittelt,
# das hier ist nur noch der Puffer obendrauf, damit der Spieler nicht
# direkt an der Kante klebt.
@export var backstep_land_offset: float = 8.0

var _backstep_active: bool = false
var _backstep_direction: float = 1.0
var _backstep_target: Node = null

# Die X-Position, an der der Dash enden soll - genau hinter der
# Kollisions-Hitbox des Ziels (siehe _get_backstep_landing_position()).
# Wird beim Start berechnet und dann jeden Physik-Frame geprüft.
var _backstep_landing_x: float = 0.0

# true, sobald der Spieler diese Position erreicht (oder das
# Sicherheitsnetz backstep_pass_frame gegriffen) hat - ab dann steht
# der Spieler still, auch wenn die Animation noch weiterläuft.
var _backstep_passed: bool = false


func _try_start_backstep() -> void:
	if dead or control_locked or scene_is_changing:
		return

	if _is_active_skill_busy():
		return

	if is_rolling or is_drinking:
		return

	if combat != null and combat.attacking:
		return

	if sprite == null:
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(BACKSTEP_ANIM)
	):
		push_warning(
			"Backstep: Animation '" + String(BACKSTEP_ANIM)
			+ "' fehlt auf dem Player-Sprite."
		)
		return

	if combat == null or not combat.has_method("find_backstep_target"):
		return

	# Nutzer-Wunsch: "geht nur bei einzelnden Gegnern" - bei keinem
	# oder mehreren gleichzeitig in Reichweite (z.B. hintereinander
	# aufgereiht) startet der Skill gar nicht erst.
	var target: Variant = combat.find_backstep_target()

	if target == null or not (target is Node2D):
		print("Backstep: kein einzelner Gegner in Reichweite.")
		return

	if get_node_or_null("/root/RunState") == null:
		return

	if RunState.current_vigor < backstep_vigor_cost:
		print(
			"Backstep: nicht genug Vigor (",
			RunState.current_vigor,
			"/",
			backstep_vigor_cost,
			" nötig)."
		)
		return

	var dash_direction: float = 1.0 if facing_right else -1.0

	# Nutzer-Wunsch: kein Boden hinter dem Ziel (Loch) -> keine
	# Aktivierung, sonst würde der Spieler nach dem Backstep
	# runterfallen.
	if not _has_floor_behind_target(target as Node2D, dash_direction):
		print("Backstep: kein fester Boden hinter dem Ziel.")
		return

	RunState.spend_vigor(backstep_vigor_cost)

	_backstep_active = true
	_backstep_direction = dash_direction
	_backstep_target = target
	_backstep_passed = false
	_backstep_landing_x = _get_backstep_landing_position(
		target as Node2D,
		dash_direction
	).x

	# Nutzer-Wunsch: "während dem Dash bist du unsterblich" - siehe
	# _on_backstep_frame_changed() weiter unten, wo das ab
	# backstep_pass_frame wieder ausgeschaltet wird.
	if health != null:
		health.invincible = true

	# Nutzer-Wunsch: der Spieler wird zum "Geist" für GENAU dieses eine
	# Ziel, damit er beim Dash durch den Gegner hindurchgehen kann,
	# statt daran abgeblockt zu werden - betrifft NUR die Kollision mit
	# diesem einen Gegner, Wände/Boden bleiben über move_and_slide()
	# ganz normal solide (siehe _end_backstep() weiter unten, wo das
	# wieder aufgehoben wird).
	add_collision_exception_with(target)

	if not sprite.frame_changed.is_connected(_on_backstep_frame_changed):
		sprite.frame_changed.connect(_on_backstep_frame_changed)

	if not sprite.animation_finished.is_connected(
		_on_backstep_animation_finished
	):
		sprite.animation_finished.connect(
			_on_backstep_animation_finished
		)

	sprite.play(BACKSTEP_ANIM)


# Liefert die tatsächliche halbe Breite der Kollisions-Hitbox des
# Ziels (der CharacterBody2D-eigene CollisionShape2D, NICHT Hurtbox/
# AttackHitbox/WakeArea - das sind eigene Area2D-Kinder und zählen
# hier nicht mit) - erkennt Rechteck/Kapsel/Kreis-Formen automatisch,
# damit größere Gegner (Mini-Boss, Boss) automatisch einen weiteren
# Landepunkt bekommen als z.B. ein normales Skelett. Fällt auf einen
# Standardwert zurück, wenn die Form nicht erkannt wird.
func _get_target_half_width(target: Node2D) -> float:
	const FALLBACK_HALF_WIDTH: float = 16.0

	if not (target is CollisionObject2D):
		return FALLBACK_HALF_WIDTH

	var body := target as CollisionObject2D
	var best: float = -1.0

	for owner_id in body.get_shape_owners():
		var shape_count: int = body.shape_owner_get_shape_count(owner_id)

		for i in range(shape_count):
			var shape: Shape2D = body.shape_owner_get_shape(owner_id, i)

			if shape == null:
				continue

			var width: float = -1.0

			if shape is RectangleShape2D:
				width = (shape as RectangleShape2D).size.x / 2.0
			elif shape is CapsuleShape2D:
				width = (shape as CapsuleShape2D).radius
			elif shape is CircleShape2D:
				width = (shape as CircleShape2D).radius

			if width > best:
				best = width

	if best > 0.0:
		return best

	return FALLBACK_HALF_WIDTH


# Nutzer-Wunsch: "immer genau hinter den Mob... hinter die Gegner-
# Hitbox" - die Landeposition liegt jetzt genau hinter der ECHTEN
# Kollisions-Hitbox des Ziels (siehe _get_target_half_width() oben),
# plus einem kleinen Sicherheitsabstand (backstep_land_offset), statt
# eines pauschalen Rate-Werts. Wird sowohl vom Bodencheck
# (_has_floor_behind_target()) als auch vom eigentlichen Dash
# (_try_start_backstep()/_physics_process()) benutzt, damit beide
# über denselben Punkt reden.
func _get_backstep_landing_position(
	target: Node2D,
	direction: float
) -> Vector2:
	var offset: float = _get_target_half_width(target) + backstep_land_offset

	return target.global_position + Vector2(direction * offset, 0)


# Prüft per Raycast, ob ETWAS Festes unter der Landeposition hinter
# dem Ziel ist (siehe _get_backstep_landing_position() oben) - kein
# Fund heißt Loch/Abgrund, dann startet der Skill gar nicht erst
# (siehe _try_start_backstep()).
func _has_floor_behind_target(
	target: Node2D,
	direction: float
) -> bool:
	var landing_position: Vector2 = _get_backstep_landing_position(
		target,
		direction
	)

	var tree := get_tree()

	if tree == null:
		return true

	var space_state := get_world_2d().direct_space_state

	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(
		landing_position + Vector2(0, -16),
		landing_position + Vector2(0, 16)
	)

	# exclude erwartet RIDs, keine Nodes.
	query.exclude = [self.get_rid(), target.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)

	return not result.is_empty()


func _on_backstep_frame_changed() -> void:
	if not _backstep_active:
		return

	if sprite == null or sprite.animation != BACKSTEP_ANIM:
		return

	# Der Dash-Stopp und das Ende der Unsterblichkeit hängen jetzt an
	# der tatsächlichen Position (siehe _physics_process()), nicht mehr
	# an einem festen Frame - backstep_pass_frame ist dort nur noch das
	# Sicherheitsnetz. Hier bleibt nur noch der Treffer-Frame für die
	# eigene Hitbox übrig.
	if sprite.frame == backstep_hit_frame and combat != null:
		combat.activate_backstep_hitbox(backstep_damage)
		_play_sound(&"skill_backstep")


func _on_backstep_animation_finished() -> void:
	if sprite == null or sprite.animation != BACKSTEP_ANIM:
		return

	_end_backstep()


func _end_backstep() -> void:
	_backstep_active = false
	_backstep_passed = false

	if health != null:
		health.invincible = false

	if _backstep_target != null and is_instance_valid(_backstep_target):
		remove_collision_exception_with(_backstep_target)

	_backstep_target = null

	if sprite != null:
		if sprite.frame_changed.is_connected(_on_backstep_frame_changed):
			sprite.frame_changed.disconnect(_on_backstep_frame_changed)

		if sprite.animation_finished.is_connected(
			_on_backstep_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_backstep_animation_finished
			)

	if not dead:
		sprite.play("idle")


# ============================================================
# PARRY (PFAD DER STÄRKE, VERTEIDIGUNGS-ZWEIG)
# ============================================================

# Nutzer-Wunsch: solange die "Parry"-Animation läuft, ist der Spieler
# horizontal eingefroren (wie Iron Skin) - trifft währenddessen ein
# Gegner zu (also würde take_damage() weiter oben eigentlich Schaden
# verursachen), passiert stattdessen: KEIN Schaden, einmalig die neue
# "Parry effekt"-Szene an der Spielerposition, ein kurzer/schwacher
# Bildschirm-Ruckler, und der zuschlagende Gegner wird
# parry_freeze_duration Sekunden lang auf seinem aktuellen Frame
# eingefroren (siehe Player/enemy_spell_effects.gd
# apply_parry_stun()) - bekommt er währenddessen selbst Schaden, endet
# die Einfrierung sofort wieder (siehe dort). Läuft die Animation
# einfach zu Ende, ohne dass der Spieler getroffen wird, passiert
# nichts weiter (kein Fehlschlag-Malus) - genau wie bei den anderen
# aktiven Skills oben.
const PARRY_SKILL_ID: StringName = &"parry"
const PARRY_ANIM: StringName = &"Parry"

const PARRY_EFFECT_SCENE: PackedScene = preload(
	"res://Player/Skills/Krieger Skill Tree/parry_effekt.tscn"
)

# Nutzer-Wunsch: Parry ist kostenlos (0 Vigor) UND alle Werte
# (Bildschirm-Ruckler, Einfrier-Dauer des Gegners) sollen im
# Godot-Inspector einstellbar sein - genau wie schon bei Dash Slash
# oben deshalb bewusst @export statt const.
@export_group("Aktiver Skill - Parry")
@export var parry_vigor_cost: int = 25
@export var parry_freeze_duration: float = 2.0
@export var parry_shake_strength: float = 2.0
@export var parry_shake_duration: float = 0.15


func _try_start_parry() -> void:
	if dead or control_locked or scene_is_changing:
		return

	if _is_active_skill_busy():
		return

	if is_rolling or is_drinking:
		return

	if combat != null and combat.attacking:
		return

	if sprite == null:
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(PARRY_ANIM)
	):
		push_warning(
			"Parry: Animation '" + String(PARRY_ANIM)
			+ "' fehlt auf dem Player-Sprite."
		)
		return

	if RunState.current_vigor < parry_vigor_cost:
		print(
			"Parry: nicht genug Vigor (",
			RunState.current_vigor,
			"/",
			parry_vigor_cost,
			" nötig)."
		)
		return

	RunState.spend_vigor(parry_vigor_cost)

	_parry_active = true

	if not sprite.animation_finished.is_connected(
		_on_parry_animation_finished
	):
		sprite.animation_finished.connect(
			_on_parry_animation_finished
		)

	sprite.play(PARRY_ANIM)
	_play_sound(&"skill_parry")


func _on_parry_animation_finished() -> void:
	if sprite == null or sprite.animation != PARRY_ANIM:
		return

	_end_parry()


func _end_parry() -> void:
	_parry_active = false

	if sprite == null:
		return

	if sprite.animation_finished.is_connected(
		_on_parry_animation_finished
	):
		sprite.animation_finished.disconnect(
			_on_parry_animation_finished
		)

	if not dead:
		sprite.play("idle")


# Wird von take_damage() aufgerufen, sobald ein Treffer während des
# Parry-Fensters ankäme - der Schaden selbst ist an dieser Stelle
# schon abgewendet (siehe take_damage() oben), hier nur noch die
# Auswirkungen: Effekt-Szene, Bildschirm-Ruckler, Gegner einfrieren.
# Bricht die laufende "Parry"-Animation NICHT ab - sie darf normal zu
# Ende laufen (und könnte theoretisch noch einen zweiten Treffer
# parrieren).
func _trigger_parry(from_position: Vector2) -> void:
	print("Parry! Kein Schaden genommen.")

	_spawn_parry_effect()
	_shake_camera(parry_shake_strength, parry_shake_duration)

	var attacking_enemy: Node = _find_attacking_enemy(from_position)

	if attacking_enemy == null:
		return

	var effects: Node = attacking_enemy.get_node_or_null(
		"enemy_spell_effects"
	)

	if effects != null and effects.has_method("apply_parry_stun"):
		effects.apply_parry_stun(parry_freeze_duration)


# Sucht in der Gruppe "enemy" (siehe Mobs/.../skeleton.gd ->
# add_to_group("enemy")) den Gegner, dessen global_position zu
# from_position passt - Angriffe rufen take_damage(damage,
# global_position) im selben Funktionsaufruf auf, in dem sie ihre
# eigene global_position gerade gelesen haben (siehe skeleton.gd
# _damage_target_if_inside()), die Position stimmt also exakt (bis
# auf minimale Toleranz) überein. So lässt sich der zuschlagende
# Gegner identifizieren, OHNE jedes einzelne Gegner-Script um eine
# eigene Selbst-Referenz im take_damage()-Aufruf erweitern zu müssen.
func _find_attacking_enemy(from_position: Vector2) -> Node:
	var closest: Node = null
	var closest_distance: float = INF

	for candidate in get_tree().get_nodes_in_group(&"enemy"):
		if not (candidate is Node2D):
			continue

		var distance: float = (
			(candidate as Node2D).global_position - from_position
		).length()

		if distance < closest_distance:
			closest_distance = distance
			closest = candidate

	if closest_distance > 8.0:
		return null

	return closest


# Instanziert die vom Nutzer gebaute "Parry effekt"-Szene (eigenes
# AnimatedSprite2D, siehe Player/Skills/Krieger Skill Tree/
# parry_effekt.tscn) einmalig an der Spielerposition - genau dasselbe
# Muster wie schon _spawn_roll_dust() oben (in tree.current_scene
# einhängen, abspielen, danach wieder entfernen).
func _spawn_parry_effect() -> void:
	var tree := get_tree()

	if tree == null:
		return

	var spawn_parent: Node = tree.current_scene

	if spawn_parent == null:
		return

	var effect: Node = PARRY_EFFECT_SCENE.instantiate()

	if effect == null:
		return

	spawn_parent.add_child(effect)

	if effect is Node2D:
		(effect as Node2D).global_position = global_position

	if effect is AnimatedSprite2D:
		var effect_sprite := effect as AnimatedSprite2D

		effect_sprite.play("default")
		effect_sprite.frame = 0

		await effect_sprite.animation_finished

	if is_instance_valid(effect):
		effect.queue_free()


# Kurzer/schwacher Bildschirm-Ruckler (Nutzer-Wunsch) über die
# Camera2D des Spielers - camera.offset bekommt für parry_shake_
# duration Sekunden einen zufälligen, über die Zeit abklingenden
# Versatz und wird danach wieder auf Vector2.ZERO zurückgesetzt.
# _shake_generation verhindert, dass sich zwei schnell
# hintereinander ausgelöste Ruckler gegenseitig ins Gehege kommen -
# nur der JEWEILS NEUESTE setzt camera.offset am Ende zurück.
func _shake_camera(strength: float, duration: float) -> void:
	if camera == null:
		return

	if strength <= 0.0 or duration <= 0.0:
		return

	_shake_generation += 1

	var this_generation: int = _shake_generation

	# GEFUNDENER FEHLER (Nutzer-Rückmeldung: "Kamera wird außerhalb
	# ihres Randes platziert"): camera.offset trägt schon einen festen
	# Basis-Wert (siehe Player/player.tscn, Camera2D.offset = (0, -50),
	# damit die Kamera etwas über dem Spieler zentriert ist). Diesen
	# Wert hier einfach mit dem Ruckler-Versatz zu ÜBERSCHREIBEN hat
	# ihn für die Dauer des Rucklers auf ~0 gesetzt und am Ende sogar
	# fälschlich auf Vector2.ZERO statt zurück auf den Basis-Wert -
	# das sah wie ein einmaliger, harter Kamera-Sprung aus, der den
	# sichtbaren Bereich weit über den eigentlichen Raum hinausschob.
	# Der Ruckler-Versatz wird deshalb jetzt UM _camera_rest_offset
	# (einmalig in _ready() festgehalten, siehe dort) herum addiert,
	# statt camera.offset live zu überschreiben, und am Ende auch
	# wieder exakt auf diesen Ruhe-Wert zurückgesetzt.
	var elapsed: float = 0.0
	var step: float = 0.02

	while elapsed < duration:
		if not is_instance_valid(camera):
			return

		if this_generation != _shake_generation:
			return

		var remaining_ratio: float = 1.0 - (elapsed / duration)

		camera.offset = _camera_rest_offset + Vector2(
			randf_range(-strength, strength) * remaining_ratio,
			randf_range(-strength, strength) * remaining_ratio
		)

		if not await _wait_safely(min(step, duration - elapsed)):
			return

		elapsed += step

	if this_generation != _shake_generation:
		return

	if is_instance_valid(camera):
		camera.offset = _camera_rest_offset


# ============================================================
# PLATTFORMEN (DURCHFALLEN)
# ============================================================

# Findet heraus, ob der Spieler gerade auf einer Einweg-Plattform
# steht (Gruppe "one_way_platforms", siehe Objects/platform.tscn
# und Objects/dark_platform.tscn), und schaltet für diese eine
# Plattform kurz die Kollision aus, damit der Spieler durchfällt.
# Normaler Boden (TileMap) ist NICHT in dieser Gruppe und bleibt
# davon komplett unberührt.
func _try_drop_through_platform() -> void:
	if scene_is_changing:
		return

	if not is_on_floor():
		return

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if collider == null:
			continue

		if not (collider is Node):
			continue

		if not (collider as Node).is_in_group(&"one_way_platforms"):
			continue

		_drop_through_body(collider as Node)
		return


func _drop_through_body(body: Node) -> void:
	var shapes: Array[CollisionShape2D] = []

	for child in body.get_children():
		if child is CollisionShape2D:
			shapes.append(child)

	if shapes.is_empty():
		return

	for shape in shapes:
		shape.disabled = true

	await _wait_safely(drop_through_disable_time)

	for shape in shapes:
		if is_instance_valid(shape):
			shape.disabled = false


# ============================================================
# TRANK
# ============================================================

func start_drink() -> void:
	if scene_is_changing:
		return

	if is_drinking or is_rolling or control_locked:
		return

	if combat != null and combat.attacking:
		return

	if health == null or inventory == null:
		return

	if health.current_health >= health.get_max_health():
		return

	if inventory.current_potions <= 0:
		return

	is_drinking = true
	velocity.x = 0

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation("drink")
	):
		sprite.play("drink")

	if not await _wait_safely(drink_heal_delay):
		is_drinking = false
		return

	if scene_is_changing:
		is_drinking = false
		return

	if inventory != null and inventory.use_potion():
		if health != null:
			health.heal(heal_amount)

	var remaining_time: float = max(
		drink_total_time - drink_heal_delay,
		0.05
	)

	if not await _wait_safely(remaining_time):
		is_drinking = false
		return

	is_drinking = false

	if sprite != null and is_instance_valid(sprite):
		sprite.play("idle")


# ============================================================
# SCHADEN
# ============================================================

func take_damage(
	amount: int,
	from_position: Vector2 = Vector2.ZERO
) -> void:
	# control_locked wird hier absichtlich NICHT geprüft.
	# Dadurch kann der Spieler auch beim Zaubern Schaden nehmen.
	if dead or scene_is_changing:
		return

	# Parry (Nutzer-Wunsch): während der "Parry"-Animation läuft, wird
	# JEDER Schaden hier abgefangen, BEVOR er health.take_damage()
	# erreicht - kein Schaden, stattdessen _trigger_parry() (Effekt,
	# Bildschirm-Ruckler, Gegner einfrieren). Siehe _try_start_parry()
	# weiter unten.
	if _parry_active:
		_trigger_parry(from_position)
		return

	if health != null:
		health.take_damage(amount)


# ============================================================
# SHOP UND INVENTAR
# ============================================================

func add_potion(amount: int = 1) -> bool:
	if inventory == null:
		inventory = get_node_or_null(
			"Scripts/PlayerInventory"
		)

	if (
		inventory != null
		and inventory.has_method("add_potion")
	):
		return inventory.add_potion(amount)

	return false


func add_armor(
	amount: int = 1,
	armor_type: StringName = &"shield"
) -> bool:
	if health == null:
		health = get_node_or_null(
			"Scripts/PlayerHealth"
		)

	if (
		health != null
		and health.has_method("add_armor")
	):
		return health.add_armor(amount, armor_type)

	return false


func unlock_bow() -> bool:
	if bow == null:
		bow = get_node_or_null(
			"Scripts/PlayerBow"
		)

	if (
		bow != null
		and bow.has_method("unlock_bow")
	):
		return bow.unlock_bow()

	return false


func add_arrows(amount: int = 5) -> bool:
	if bow == null:
		bow = get_node_or_null(
			"Scripts/PlayerBow"
		)

	if (
		bow != null
		and bow.has_method("add_arrows")
	):
		return bow.add_arrows(amount)

	return false


# ============================================================
# ZAUBERSYSTEM
# ============================================================

func add_spell(spell_id: String) -> bool:
	if spells == null:
		spells = get_node_or_null(
			"Scripts/PlayerSpells"
		)

	if spells == null:
		push_warning(
			"Player: PlayerSpells wurde nicht gefunden."
		)
		return false

	if not spells.has_method("add_spell"):
		push_warning(
			"Player: PlayerSpells besitzt keine add_spell()-Funktion."
		)
		return false

	return spells.add_spell(spell_id)


func can_add_spell() -> bool:
	if spells == null:
		spells = get_node_or_null(
			"Scripts/PlayerSpells"
		)

	if spells == null:
		return false

	if not spells.has_method("can_add_spell"):
		return false

	return spells.can_add_spell()


func use_spell(slot_index: int) -> bool:
	if dead or control_locked or scene_is_changing:
		return false

	# Zaubern ist nur auf dem Boden möglich.
	if not is_on_floor():
		return false

	if is_rolling or is_drinking:
		return false

	if combat != null and combat.attacking:
		return false

	if bow != null and "shooting" in bow and bow.shooting:
		return false

	if spells == null:
		spells = get_node_or_null(
			"Scripts/PlayerSpells"
		)

	if spells == null:
		return false

	if not spells.has_method("use_spell"):
		return false

	return spells.use_spell(slot_index)


func lock_control() -> void:
	control_locked = true

	# Nur horizontale Bewegung stoppen.
	# Die vertikale Geschwindigkeit wird nicht gelöscht.
	velocity.x = 0


func unlock_control() -> void:
	if scene_is_changing:
		return

	control_locked = false


# Für Cutscenes/Dialoge (z.B. die Leere-Narration beim Betreten des
# Bossraums, siehe void_narration.gd): friert den Spieler sichtbar
# auf "idle" ein. Funktioniert nur zusammen mit lock_control() davor -
# solange control_locked true ist, kehrt _physics_process() vorzeitig
# zurück und ruft selbst kein sprite.play(...) mehr auf (siehe
# Kommentar bei play_echo_reveal_animation() weiter unten für den
# genau umgekehrten Fehlerfall), das einmalige sprite.play("idle")
# hier bleibt also für die ganze gesperrte Zeit stehen - egal, welche
# Animation (Laufen/Springen/Angriff/...) gerade lief, als die
# Sperre einsetzte.
func force_idle() -> void:
	if sprite == null:
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation("idle")
	):
		return

	sprite.play("idle")


# ============================================================
# RAUMWECHSEL
# ============================================================

func revive_for_room() -> void:
	scene_is_changing = false
	is_rolling = false
	is_drinking = false
	control_locked = false
	velocity = Vector2.ZERO

	# Siehe HINWEIS bei roll_timer <= 0.0 in _physics_process() -
	# falls hier mitten in einer angepassten 2. Rolle unterbrochen
	# wurde, muss die Geschwindigkeit zurückgesetzt werden.
	if sprite != null:
		sprite.speed_scale = 1.0

	if health == null:
		health = get_node_or_null(
			"Scripts/PlayerHealth"
		)

	if health != null:
		if health.has_method("restore_from_run_state"):
			health.restore_from_run_state()

		dead = health.current_health <= 0
	else:
		dead = false

	if spells == null:
		spells = get_node_or_null(
			"Scripts/PlayerSpells"
		)

	if sprite == null:
		sprite = get_node_or_null(
			"AnimatedSprite2D"
		) as AnimatedSprite2D

	if sprite != null:
		sprite.modulate = Color.WHITE
		sprite.visible = true

		if not dead:
			sprite.play("idle")

	visible = true


# ============================================================
# TREFFERANZEIGE
# ============================================================

func _on_hurt() -> void:
	if scene_is_changing:
		return

	_flash_hurt()


func _flash_hurt() -> void:
	if sprite == null:
		return

	# Das Sprite wird auch während einer Zauberanimation rot.
	sprite.modulate = Color(
		3.0,
		0.35,
		0.35,
		1.0
	)

	if not await _wait_safely(hurt_flash_time):
		return

	if (
		is_instance_valid(sprite)
		and not scene_is_changing
	):
		sprite.modulate = Color.WHITE


func _on_died() -> void:
	dead = true
	is_rolling = false
	is_drinking = false
	control_locked = false
	velocity = Vector2.ZERO

	# Sicherheitsnetz: falls der Tod mitten in einer Charge-Attack-
	# Ladung passiert (Skill ist nicht gegen Treffer abgesichert),
	# sollen die Frame-Verbindungen nicht ewig hängen bleiben.
	_charge_attack_active = false
	_charge_attack_committed = false

	if sprite != null:
		if sprite.frame_changed.is_connected(
			_on_charge_attack_frame_changed
		):
			sprite.frame_changed.disconnect(
				_on_charge_attack_frame_changed
			)

		if sprite.animation_finished.is_connected(
			_on_charge_attack_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_charge_attack_animation_finished
			)

	# Gleiches Sicherheitsnetz für Ground Slam.
	_ground_slam_falling = false
	_ground_slam_hitting = false

	if sprite != null:
		if sprite.frame_changed.is_connected(
			_on_ground_slam_frame_changed
		):
			sprite.frame_changed.disconnect(
				_on_ground_slam_frame_changed
			)

		if sprite.animation_finished.is_connected(
			_on_ground_slam_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_ground_slam_animation_finished
			)

	# Gleiches Sicherheitsnetz für Iron Skin.
	_iron_skin_active = false

	if sprite != null:
		if sprite.animation_finished.is_connected(
			_on_iron_skin_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_iron_skin_animation_finished
			)

	# Gleiches Sicherheitsnetz für Dash Slash.
	_dash_slash_active = false

	if sprite != null:
		if sprite.frame_changed.is_connected(_on_dash_slash_frame_changed):
			sprite.frame_changed.disconnect(_on_dash_slash_frame_changed)

		if sprite.animation_finished.is_connected(
			_on_dash_slash_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_dash_slash_animation_finished
			)

	# Gleiches Sicherheitsnetz für Parry.
	_parry_active = false

	if sprite != null:
		if sprite.animation_finished.is_connected(
			_on_parry_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_parry_animation_finished
			)

	# Gleiches Sicherheitsnetz für Backstep - inklusive Aufheben der
	# Kollisions-Ausnahme (siehe _try_start_backstep()), falls der Tod
	# mitten im Dash passiert.
	_backstep_active = false
	_backstep_passed = false

	if health != null:
		health.invincible = false

	if _backstep_target != null and is_instance_valid(_backstep_target):
		remove_collision_exception_with(_backstep_target)

	_backstep_target = null

	if sprite != null:
		if sprite.frame_changed.is_connected(_on_backstep_frame_changed):
			sprite.frame_changed.disconnect(_on_backstep_frame_changed)

		if sprite.animation_finished.is_connected(
			_on_backstep_animation_finished
		):
			sprite.animation_finished.disconnect(
				_on_backstep_animation_finished
			)

	# Siehe HINWEIS bei roll_timer <= 0.0 in _physics_process() -
	# falls hier mitten in einer angepassten 2. Rolle unterbrochen
	# wurde, muss die Geschwindigkeit zurückgesetzt werden.
	if sprite != null:
		sprite.speed_scale = 1.0

	if (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation("death")
	):
		sprite.play("death")


# ============================================================
# ECHO-ENTHÜLLUNG (BOSS-BELOHNUNG)
# ============================================================

# Spielt einmalig eine Enthüllungs-Animation ab (z.B. "Echo der
# Flamme", siehe AnimatedSprite2D-SpriteFrames auf diesem Node)
# und wartet, bis sie fertig ist. Wird von RoomManager aufgerufen,
# während der Spieler noch control_locked ist - _physics_process()
# kehrt dabei ganz am Anfang zurück (siehe control_locked-Zweig)
# und überschreibt die Animation währenddessen also nicht.
func play_echo_reveal_animation(anim_name: StringName) -> void:
	if sprite == null:
		print("ECHO: player.sprite ist null - Abbruch.")
		return

	if (
		sprite.sprite_frames == null
		or not sprite.sprite_frames.has_animation(anim_name)
	):
		push_warning(
			"Player: Echo-Animation fehlt: " + String(anim_name)
		)
		return

	# DER EIGENTLICHE FEHLER: enter_room() ruft lock_control() auf,
	# aber revive_for_room() (eine Zeile später, siehe oben) setzt
	# control_locked danach wieder auf false zurück. Dadurch lief
	# _physics_process() waehrend der ganzen Enthuellungs-Sequenz
	# ganz normal weiter, und da kein Bewegungs-Input anliegt, hat
	# sie jeden Frame sprite.play("idle") aufgerufen - das hat diese
	# Animation hier binnen eines einzigen Frames wieder ueber-
	# schrieben, komplett unsichtbar. Banner und HUD-Icon kamen
	# trotzdem, weil "idle" (loop=true) beim ersten Durchlauf sein
	# eigenes animation_finished ausgeloest hat, auf das unten
	# gewartet wurde - nicht auf das Ende dieser Animation.
	#
	# Deshalb hier zur Sicherheit selbst nochmal sperren: passend zum
	# Kommentar in room_manager.gd (_play_echo_reveal_sequence()),
	# der genau das schon voraussetzt. Aufgehoben wird das ganz normal
	# am Ende von _enter_at_return_spawn() ueber unlock_control().
	control_locked = true

	# Ganz sicher gehen, dass nichts von vorher (Hurt-Flash-Tint,
	# eine Zauber-Pause vom Gegner, ein angehaltenes Sprite) die
	# neue Animation unsichtbar oder eingefroren aussehen lässt.
	sprite.visible = true
	sprite.modulate = Color.WHITE
	sprite.speed_scale = 1.0
	sprite.stop()
	sprite.play(anim_name)

	await sprite.animation_finished


# ============================================================
# SICHERE TIMER
# ============================================================

func _can_continue_async_action() -> bool:
	if scene_is_changing:
		return false

	if not is_inside_tree():
		return false

	if get_tree() == null:
		return false

	return true


func _wait_safely(wait_time: float) -> bool:
	if not _can_continue_async_action():
		return false

	var tree := get_tree()

	if tree == null:
		return false

	await tree.create_timer(
		max(wait_time, 0.001)
	).timeout

	return _can_continue_async_action()
