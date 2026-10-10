extends Area2D


enum ChestType {
	BRONZE,
	SILVER,
	GOLD
}


# ============================================================
# SIGNALE
# ============================================================

signal chest_opened
signal loot_given


# ============================================================
# ALLGEMEIN
# ============================================================

@export_group("General")

@export var chest_type: ChestType = ChestType.BRONZE
@export var auto_detect_chest_type: bool = true

@export var player_group: StringName = &"player"
@export var player_attack_group: StringName = &"player_attack"

@export var anim_closed: StringName = &"Closed"
@export var anim_opening: StringName = &"Opening"
@export var anim_opened: StringName = &"Opened"


# ============================================================
# BRONZE LOOT
# ============================================================

@export_group("Bronze Chest")

@export var bronze_gold_min: int = 5
@export var bronze_gold_max: int = 15

@export var bronze_potion_amount: int = 1

@export_range(0.0, 100.0, 1.0)
var bronze_gold_weight: float = 60.0

@export_range(0.0, 100.0, 1.0)
var bronze_potion_weight: float = 25.0

@export_range(0.0, 100.0, 1.0)
var bronze_gold_and_potion_weight: float = 15.0


# ============================================================
# SILVER LOOT
# ============================================================

@export_group("Silver Chest")

@export var silver_gold_min: int = 15
@export var silver_gold_max: int = 30

@export var silver_potion_amount: int = 1

@export var silver_arrow_min: int = 5
@export var silver_arrow_max: int = 12

@export_range(0.0, 100.0, 1.0)
var silver_gold_weight: float = 35.0

@export_range(0.0, 100.0, 1.0)
var silver_potion_weight: float = 25.0

@export_range(0.0, 100.0, 1.0)
var silver_arrows_weight: float = 25.0

@export_range(0.0, 100.0, 1.0)
var silver_bow_weight: float = 15.0


# ============================================================
# GOLD LOOT
# ============================================================

@export_group("Gold Chest")

@export var gold_chest_gold_min: int = 10
@export var gold_chest_gold_max: int = 20

@export var gold_chest_spells: Array[String] = [
	"fireball",
	"lightning",
	"ice",
	"roots",
	"necromancy",
	"lightorb"
]


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox

# Kann null sein, falls eine Kisten-Szene (noch) kein ChestLight-Node
# besitzt - siehe _stop_chest_light().
@onready var chest_light: PointLight2D = get_node_or_null("ChestLight")


# ============================================================
# STATUS
# ============================================================

var opened: bool = false
var opening: bool = false
var loot_was_given: bool = false


# ============================================================
# START
# ============================================================

func _ready() -> void:
	randomize()

	if hurtbox != null:
		hurtbox.monitoring = true
		hurtbox.monitorable = true

	if (
		hurtbox != null
		and not hurtbox.area_entered.is_connected(
			_on_hurtbox_area_entered
		)
	):
		hurtbox.area_entered.connect(
			_on_hurtbox_area_entered
		)

	if (
		sprite != null
		and not sprite.animation_finished.is_connected(
			_on_animation_finished
		)
	):
		sprite.animation_finished.connect(
			_on_animation_finished
		)

	_detect_chest_type()
	_setup_animation_loops()

	opened = false
	opening = false
	loot_was_given = false

	_play_animation(anim_closed)

	_setup_sparkle_particles()
	_setup_chest_shine()
	_apply_chest_light_shape()


# ============================================================
# KISTENTYP ERKENNEN
# ============================================================

func _detect_chest_type() -> void:
	if not auto_detect_chest_type:
		return

	var source_text: String = (
		scene_file_path
		+ " "
		+ name
	).to_lower()

	if "gold_chest" in source_text or "goldchest" in source_text:
		chest_type = ChestType.GOLD
		return

	if "silver_chest" in source_text or "silverchest" in source_text:
		chest_type = ChestType.SILVER
		return

	if "bronze_chest" in source_text or "bronzechest" in source_text:
		chest_type = ChestType.BRONZE
		return


# ============================================================
# ANGRIFF ERKENNEN
# ============================================================

func _on_hurtbox_area_entered(
	area: Area2D
) -> void:
	if opened or opening:
		return

	if area == null:
		return

	if not area.is_in_group(player_attack_group):
		return

	if not area.has_meta("active"):
		return

	if area.get_meta("active") != true:
		return

	# Nur echte Angriffe des Spielers dürfen die Kiste öffnen.
	# Summons benutzen ebenfalls player_attack,
	# deshalb prüfen wir zusätzlich die Elternstruktur.
	if not _attack_belongs_to_player(area):
		return

	_try_open_chest()


func _attack_belongs_to_player(
	area: Area2D
) -> bool:
	var current: Node = area

	while current != null:
		if current.is_in_group(player_group):
			return true

		current = current.get_parent()

	return false


# ============================================================
# KISTE ÖFFNEN
# ============================================================

func _try_open_chest() -> void:
	if opened or opening:
		return

	# Eine Goldkiste garantiert einen Zauber.
	# Wenn kein Slot frei ist, bleibt sie geschlossen.
	if chest_type == ChestType.GOLD:
		var player_spells: Node = _find_player_spells()

		if player_spells == null:
			push_warning(
				"Chest: PlayerSpells wurde nicht gefunden."
			)
			return

		if (
			player_spells.has_method("can_add_spell")
			and not player_spells.can_add_spell()
		):
			return

	opening = true

	_stop_sparkle_particles()
	_stop_chest_shine()
	_stop_chest_light()

	if hurtbox != null:
		hurtbox.set_deferred(
			"monitoring",
			false
		)

	if _has_animation(anim_opening):
		_play_animation_force(anim_opening)
	else:
		_finish_opening()


func _finish_opening() -> void:
	if opened:
		return

	opening = false
	opened = true

	_give_loot()

	_play_animation(anim_opened)

	chest_opened.emit()


# ============================================================
# ANIMATIONSENDE
# ============================================================

func _on_animation_finished() -> void:
	if not opening:
		return

	if sprite.animation != anim_opening:
		return

	_finish_opening()


# ============================================================
# LOOT
# ============================================================

func _give_loot() -> void:
	if loot_was_given:
		return

	loot_was_given = true

	match chest_type:
		ChestType.BRONZE:
			print(
				"Chest Type: BRONZE | Gold ",
				bronze_gold_min,
				"-",
				bronze_gold_max
			)
			_give_bronze_loot()

		ChestType.SILVER:
			print(
				"Chest Type: SILVER | Gold ",
				silver_gold_min,
				"-",
				silver_gold_max
			)
			_give_silver_loot()

		ChestType.GOLD:
			print(
				"Chest Type: GOLD | Gold ",
				gold_chest_gold_min,
				"-",
				gold_chest_gold_max
			)
			_give_gold_loot()

	loot_given.emit()


# ============================================================
# BRONZE
# ============================================================

func _give_bronze_loot() -> void:
	var potion_system: Node = _find_potion_system()

	var gold_weight: float = max(
		bronze_gold_weight,
		0.0
	)

	var potion_weight: float = max(
		bronze_potion_weight,
		0.0
	)

	var combination_weight: float = max(
		bronze_gold_and_potion_weight,
		0.0
	)

	var total_weight: float = (
		gold_weight
		+ potion_weight
		+ combination_weight
	)

	if total_weight <= 0.0:
		_give_gold(
			bronze_gold_min,
			bronze_gold_max
		)
		return

	var roll: float = randf_range(
		0.0,
		total_weight
	)

	if roll < gold_weight:
		print("Bronze Chest Loot: GOLD")
		_give_gold(
			bronze_gold_min,
			bronze_gold_max
		)
		return

	roll -= gold_weight

	if roll < potion_weight:
		print("Bronze Chest Loot: POTION")

		if not _give_potion(
			potion_system,
			bronze_potion_amount
		):
			_give_gold(
				bronze_gold_min,
				bronze_gold_max
			)

		return

	print("Bronze Chest Loot: GOLD + POTION")

	_give_gold(
		bronze_gold_min,
		bronze_gold_max
	)

	_give_potion(
		potion_system,
		bronze_potion_amount
	)


# ============================================================
# SILBER
# ============================================================

func _give_silver_loot() -> void:
	var potion_system: Node = _find_potion_system()
	var player_bow: Node = _find_player_bow()

	var gold_weight: float = max(
		silver_gold_weight,
		0.0
	)

	var potion_weight: float = max(
		silver_potion_weight,
		0.0
	)

	var arrows_weight: float = max(
		silver_arrows_weight,
		0.0
	)

	var bow_weight: float = max(
		silver_bow_weight,
		0.0
	)

	var total_weight: float = (
		gold_weight
		+ potion_weight
		+ arrows_weight
		+ bow_weight
	)

	if total_weight <= 0.0:
		_give_gold(
			silver_gold_min,
			silver_gold_max
		)
		return

	var roll: float = randf_range(
		0.0,
		total_weight
	)

	if roll < gold_weight:
		print("Silver Chest Loot: GOLD")
		_give_gold(
			silver_gold_min,
			silver_gold_max
		)
		return

	roll -= gold_weight

	if roll < potion_weight:
		print("Silver Chest Loot: POTION")

		if not _give_potion(
			potion_system,
			silver_potion_amount
		):
			_give_gold(
				silver_gold_min,
				silver_gold_max
			)

		return

	roll -= potion_weight

	if roll < arrows_weight:
		print("Silver Chest Loot: ARROWS")

		if not _give_arrows(player_bow):
			_give_gold(
				silver_gold_min,
				silver_gold_max
			)

		return

	print("Silver Chest Loot: BOW")

	if not _give_bow(player_bow):
		# Bow already owned/unavailable:
		# first try arrows, otherwise give silver gold.
		if not _give_arrows(player_bow):
			_give_gold(
				silver_gold_min,
				silver_gold_max
			)


# ============================================================
# GOLD
# ============================================================

func _give_gold_loot() -> void:
	var player_spells: Node = _find_player_spells()

	if player_spells == null:
		push_warning(
			"Chest: PlayerSpells wurde nicht gefunden."
		)
		return

	var valid_spells: Array[String] = []

	for spell_id: String in gold_chest_spells:
		var normalized_id: String = (
			spell_id.strip_edges().to_lower()
		)

		if normalized_id.is_empty():
			continue

		if (
			player_spells.has_method("is_valid_spell")
			and not player_spells.is_valid_spell(
				normalized_id
			)
		):
			continue

		valid_spells.append(
			normalized_id
		)

	if valid_spells.is_empty():
		push_warning(
			"Chest: Gold Chest besitzt keine gültigen Zauber."
		)
		return

	var spell_id: String = valid_spells.pick_random()

	var spell_added: bool = false

	if player_spells.has_method("add_spell"):
		spell_added = player_spells.add_spell(
			spell_id
		)

	if not spell_added:
		return

	print("Gold Chest Spell: ", spell_id)

	_give_gold(
		gold_chest_gold_min,
		gold_chest_gold_max
	)


# ============================================================
# GOLD VERGEBEN
# ============================================================

func _give_gold(
	minimum: int,
	maximum: int
) -> void:
	if get_node_or_null("/root/GoldSystem") == null:
		push_warning(
			"Chest: GoldSystem wurde nicht gefunden."
		)
		return

	var min_value: int = min(
		minimum,
		maximum
	)

	var max_value: int = max(
		minimum,
		maximum
	)

	var amount: int = randi_range(
		max(min_value, 0),
		max(max_value, 0)
	)

	if amount <= 0:
		return

	GoldSystem.add_gold(amount)
	print("Chest Gold Given: ", amount)


# ============================================================
# TRÄNKE
# ============================================================

func _give_potion(
	potion_system: Node,
	amount: int
) -> bool:
	if potion_system == null:
		return false

	if amount <= 0:
		return false

	if not potion_system.has_method("add_potion"):
		return false

	return potion_system.add_potion(amount)


func _can_receive_potion(
	potion_system: Node
) -> bool:
	if potion_system == null:
		return false

	if not "current_potions" in potion_system:
		return false

	if not "max_potions" in potion_system:
		return false

	return (
		int(potion_system.current_potions)
		< int(potion_system.max_potions)
	)


# ============================================================
# PFEILE
# ============================================================

func _give_arrows(
	player_bow: Node
) -> bool:
	if player_bow == null:
		return false

	if not player_bow.has_method("add_arrows"):
		return false

	var min_value: int = min(
		silver_arrow_min,
		silver_arrow_max
	)

	var max_value: int = max(
		silver_arrow_min,
		silver_arrow_max
	)

	var amount: int = randi_range(
		max(min_value, 1),
		max(max_value, 1)
	)

	return player_bow.add_arrows(amount)


func _can_receive_arrows(
	player_bow: Node
) -> bool:
	if player_bow == null:
		return false

	if not "current_arrows" in player_bow:
		return false

	if not "max_arrows" in player_bow:
		return false

	return (
		int(player_bow.current_arrows)
		< int(player_bow.max_arrows)
	)


# ============================================================
# BOGEN
# ============================================================

func _give_bow(
	player_bow: Node
) -> bool:
	if player_bow == null:
		return false

	if not player_bow.has_method("unlock_bow"):
		return false

	return player_bow.unlock_bow()


func _can_receive_bow(
	player_bow: Node
) -> bool:
	if player_bow == null:
		return false

	if not "bow_unlocked" in player_bow:
		return false

	return not bool(
		player_bow.bow_unlocked
	)


# ============================================================
# PLAYER-SYSTEME FINDEN
# ============================================================

func _find_player() -> Node:
	return get_tree().get_first_node_in_group(
		player_group
	)


func _find_potion_system() -> Node:
	var player: Node = _find_player()

	if player == null:
		return null

	return _find_node_with_method(
		player,
		"add_potion"
	)


func _find_player_bow() -> Node:
	var player: Node = _find_player()

	if player == null:
		return null

	return _find_node_with_method(
		player,
		"add_arrows"
	)


func _find_player_spells() -> Node:
	var player: Node = _find_player()

	if player == null:
		return null

	return _find_node_with_method(
		player,
		"add_spell"
	)


func _find_node_with_method(
	root: Node,
	method_name: StringName
) -> Node:
	if root == null:
		return null

	if root.has_method(method_name):
		return root

	for child: Node in root.get_children():
		var found: Node = _find_node_with_method(
			child,
			method_name
		)

		if found != null:
			return found

	return null


# ============================================================
# LEUCHTENDER SCHEIN (TEST)
# ============================================================

# Kleiner, dezenter Glanzstreifen, der in Abständen einmal diagonal
# über die Kiste läuft - in der jeweiligen Kisten-Farbe (siehe
# _get_sparkle_color(), dieselben Farben wie beim Glitzern oben).
# Bewusst schwach gehalten (siehe shine_alpha) - nur ein kleines
# Extra, kein auffälliger Dauer-Glow. Nutzt das bereits vorhandene
# chest_shine.gdshader. Wird beim Öffnen automatisch ausgeschaltet,
# siehe _stop_chest_shine().

@export_group("Leuchtender Schein")

@export var shine_enabled: bool = true

@export_range(0.0, 1.0, 0.01)
var shine_alpha: float = 0.35

@export_range(0.02, 1.0, 0.01)
var shine_width: float = 0.14

@export var shine_interval: float = 3.2
@export var shine_duration: float = 0.6

const _CHEST_SHINE_SHADER: Shader = preload(
	"res://Objects/Chests/chest_shine.gdshader"
)

var _shine_material: ShaderMaterial = null


func _setup_chest_shine() -> void:
	if not shine_enabled:
		return

	if sprite == null:
		return

	if _shine_material != null:
		return

	var material := ShaderMaterial.new()
	material.shader = _CHEST_SHINE_SHADER

	var color: Color = _get_sparkle_color()
	color.a = shine_alpha

	material.set_shader_parameter("shine_color", color)
	material.set_shader_parameter("shine_width", shine_width)
	material.set_shader_parameter("shine_interval", shine_interval)
	material.set_shader_parameter("shine_duration", shine_duration)
	material.set_shader_parameter("shine_enabled", true)

	sprite.material = material

	_shine_material = material


func _stop_chest_shine() -> void:
	if _shine_material == null:
		return

	_shine_material.set_shader_parameter("shine_enabled", false)


# Nutzer-Wunsch: der Lichtkegel über der Kiste (siehe ChestLight-Node
# in den *_chest.tscn Dateien) soll ausgehen, sobald die Kiste
# geöffnet wurde - genau wie das Glitzern und der Glanzstreifen.
func _stop_chest_light() -> void:
	if chest_light == null:
		return

	chest_light.enabled = false


# TESTWEISE: rundes Licht statt des trichterförmigen Fenster-Lichts
# aus der Szene. Einfach chest_light_circular im Inspektor (oder den
# Default hier unten) wieder auf false stellen, um sofort zur
# ursprünglichen Textur aus der *_chest.tscn zurückzukehren - Position,
# Skalierung, Energie und Farbe (alles vom Nutzer schon angepasst)
# bleiben davon komplett unberührt, es wird NUR die Textur getauscht.
@export var chest_light_circular: bool = true

var _original_chest_light_texture: Texture2D = null
var _circular_chest_light_texture: Texture2D = null


func _apply_chest_light_shape() -> void:
	if chest_light == null:
		return

	if _original_chest_light_texture == null:
		_original_chest_light_texture = chest_light.texture

	if not chest_light_circular:
		chest_light.texture = _original_chest_light_texture
		return

	if _circular_chest_light_texture == null:
		_circular_chest_light_texture = _build_circular_light_texture()

	chest_light.texture = _circular_chest_light_texture


func _build_circular_light_texture() -> Texture2D:
	var gradient := Gradient.new()

	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0)
	])

	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	return texture


# ============================================================
# GLITZER-PARTIKEL
# ============================================================

# Dezentes Glitzern über der Kiste - ein paar kleine, weiche
# Partikel in der jeweiligen Kisten-Farbe (Bronze/Silber/Gold),
# die langsam nach oben aufsteigen und wieder verblassen, damit
# die Kiste im Raum ein wenig auffälliger wirkt (siehe Terraria-
# Münzen). Bewusst minimal gehalten (wenige, kleine Partikel).
# Wird beim Öffnen automatisch gestoppt, siehe
# _stop_sparkle_particles().

@export_group("Glitzer-Partikel")

@export var sparkle_enabled: bool = true

@export_range(1, 10, 1)
var sparkle_amount: int = 2

# Nutzer-Wunsch: max. 2 Sterne gleichzeitig sichtbar (siehe
# sparkle_amount oben) UND langsamer spawnen - länger lebende
# Partikel spawnen automatisch seltener nach (bei gleichbleibendem
# sparkle_amount), ohne dass mehr gleichzeitig auf der Kiste zu
# sehen sind.
@export var sparkle_lifetime: float = 2.6
@export var sparkle_drift_speed: float = 3.5

# Nutzer-Wunsch: die Sterne sollen nicht mehr so hoch steigen. Vorher
# hat eine starke negative "Schwerkraft" (-4) die Partikel die ganze
# Lebenszeit über immer weiter nach oben beschleunigt statt sie
# abzubremsen - dadurch sind sie am Ende ihrer Lebenszeit sehr hoch
# geflogen. Jetzt deutlich schwächer, damit sie nur noch ein kleines
# Stück aufsteigen, bevor sie verblassen.
@export var sparkle_rise_accel: float = 1.2

var _sparkle_particles: CPUParticles2D = null
var _sparkle_texture: Texture2D = null


func _setup_sparkle_particles() -> void:
	if not sparkle_enabled:
		return

	if _sparkle_particles != null:
		return

	var particles := CPUParticles2D.new()

	particles.texture = _get_sparkle_texture()
	particles.texture_filter = 1
	particles.position = Vector2(0, -10)
	particles.z_index = 5

	var blend_material := CanvasItemMaterial.new()
	blend_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = blend_material

	particles.emitting = true
	particles.one_shot = false
	particles.amount = sparkle_amount
	particles.lifetime = sparkle_lifetime
	particles.preprocess = sparkle_lifetime * 0.6
	particles.explosiveness = 0.0
	particles.randomness = 0.6

	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 5.0

	particles.direction = Vector2(0, -1)
	particles.spread = 12.0
	particles.gravity = Vector2(0, -sparkle_rise_accel)
	particles.initial_velocity_min = sparkle_drift_speed * 0.6
	particles.initial_velocity_max = sparkle_drift_speed

	# Nutzer-Wunsch: die kleinen Pixel-Art-Sterne sollen unauffälliger/
	# kleiner sein (vorher 0.9-1.4, hat auf der Kiste "gestört").
	particles.scale_amount_min = 0.45
	particles.scale_amount_max = 0.7

	particles.color = _get_sparkle_color()
	particles.color_ramp = _build_sparkle_gradient()

	add_child(particles)

	_sparkle_particles = particles


func _stop_sparkle_particles() -> void:
	if _sparkle_particles == null:
		return

	_sparkle_particles.emitting = false


func _get_sparkle_color() -> Color:
	match chest_type:
		ChestType.SILVER:
			return Color(0.88, 0.93, 1.0, 1.0)

		ChestType.GOLD:
			return Color(1.0, 0.92, 0.55, 1.0)

		_:
			return Color(1.0, 0.72, 0.42, 1.0)


func _build_sparkle_gradient() -> Gradient:
	var gradient := Gradient.new()

	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0)
	])

	gradient.offsets = PackedFloat32Array([
		0.0,
		0.2,
		0.75,
		1.0
	])

	return gradient


# Handgezeichnetes 7x7-Pixel-Kreuz/Stern (keine weiche Gradiente,
# harte Pixel-Blöcke) - 0 = durchsichtig, 1 = dunkler Spitzen-Pixel,
# 2 = mittelheller Arm-Pixel, 3 = heller Kern-Pixel.
const _SPARKLE_PIXEL_MASK: Array[Array] = [
	[0, 0, 0, 1, 0, 0, 0],
	[0, 0, 0, 2, 0, 0, 0],
	[0, 0, 0, 2, 0, 0, 0],
	[1, 2, 2, 3, 2, 2, 1],
	[0, 0, 0, 2, 0, 0, 0],
	[0, 0, 0, 2, 0, 0, 0],
	[0, 0, 0, 1, 0, 0, 0]
]

const _SPARKLE_PIXEL_ALPHAS: Array[float] = [
	0.0,
	0.45,
	0.75,
	1.0
]


func _get_sparkle_texture() -> Texture2D:
	if _sparkle_texture != null:
		return _sparkle_texture

	var size: int = _SPARKLE_PIXEL_MASK.size()

	var image := Image.create(
		size,
		size,
		false,
		Image.FORMAT_RGBA8
	)

	for y in range(size):
		var row: Array = _SPARKLE_PIXEL_MASK[y]

		for x in range(size):
			var mask_value: int = row[x]
			var alpha: float = _SPARKLE_PIXEL_ALPHAS[mask_value]

			image.set_pixel(
				x,
				y,
				Color(1.0, 1.0, 1.0, alpha)
			)

	_sparkle_texture = ImageTexture.create_from_image(image)

	return _sparkle_texture


# ============================================================
# ANIMATIONEN
# ============================================================

func _setup_animation_loops() -> void:
	if sprite == null:
		return

	if sprite.sprite_frames == null:
		return

	if sprite.sprite_frames.has_animation(
		anim_closed
	):
		sprite.sprite_frames.set_animation_loop(
			anim_closed,
			true
		)

	if sprite.sprite_frames.has_animation(
		anim_opening
	):
		sprite.sprite_frames.set_animation_loop(
			anim_opening,
			false
		)

	if sprite.sprite_frames.has_animation(
		anim_opened
	):
		sprite.sprite_frames.set_animation_loop(
			anim_opened,
			true
		)


func _has_animation(
	animation_name: StringName
) -> bool:
	return (
		sprite != null
		and sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(
			animation_name
		)
	)


func _play_animation(
	animation_name: StringName
) -> void:
	if not _has_animation(animation_name):
		return

	if (
		sprite.animation != animation_name
		or not sprite.is_playing()
	):
		sprite.play(animation_name)


func _play_animation_force(
	animation_name: StringName
) -> void:
	if not _has_animation(animation_name):
		return

	sprite.play(animation_name)
	sprite.frame = 0
