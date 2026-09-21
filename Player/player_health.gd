extends Node

signal health_changed(current_health: int, max_health: int, old_health: int)
signal armor_changed(current_armor: int, max_armor: int, old_armor: int)
signal armor_broken(armor_index: int, armor_type: StringName)
signal hurt
signal healed
signal died

# Grundwert OHNE Skills - siehe get_max_health() für den tatsächlich
# geltenden Maximalwert (inkl. Vitality-Bonus aus dem Skill-Baum).
# Absichtlich nicht mehr direkt "max_health" genannt, damit niemand
# aus Versehen diesen ungeboosteten Grundwert statt get_max_health()
# benutzt (siehe Player/player.gd -> start_drink()).
@export var base_max_health: int = 3
@export var invincible_time: float = 0.5

# Rüstungsarten (Nutzer-Wunsch: mehrere Rüstungsquellen, gleiches
# Verhalten - 1 Herz, 1 Treffer geblockt -, aber unterschiedliche
# Optik). "" bedeutet "keine Rüstung". ARMOR_TYPE_SHIELD ist die
# bestehende Schild-Rüstung aus dem Shop (shop_overlay.gd), ARMOR_
# TYPE_IRON die neue Iron-Skin-Rüstung (siehe Player/player.gd,
# _try_start_iron_skin()). Beide Sätze Herz-Animationen liegen schon
# in derselben Herz-SpriteFrames-Ressource (Player/UI/canvas_layer.
# tscn) - hud.gd wählt anhand von armor_types[i], welche gespielt
# wird.
const ARMOR_TYPE_NONE: StringName = &""
const ARMOR_TYPE_SHIELD: StringName = &"shield"
const ARMOR_TYPE_IRON: StringName = &"iron"

var current_health: int = 3
var current_armor: int = 0
var invincible: bool = false
var dead: bool = false

# Rüstungsart je Herz-Slot, Index = Herz-Index (siehe hud.gd,
# heart_sprites). Länge wird bei Bedarf über
# _ensure_armor_types_size() an get_max_health() angeglichen - JEDES
# Herz kann maximal einen Rüstungs-Slot haben, deshalb ist die
# Rüstungs-Obergrenze jetzt immer die aktuelle Herzanzahl (siehe
# get_max_armor()), statt eines fest eingestellten Werts, der bei
# einem zusätzlichen Herz (z.B. Vitality-Skill) nicht mitgewachsen
# wäre.
var armor_types: Array[StringName] = []

# Verhindert, dass der Sofort-Heilbonus beim Freischalten von
# Vitality (siehe _on_skill_progress_changed()) mehrfach ausgelöst
# wird - einmal pro Lauf gesetzt, sobald der Bonus einmal vergeben
# wurde. Wird in _ready()/restore_from_run_state() aus dem
# tatsächlichen RunState-Freischaltstatus übernommen, statt einfach
# bei jedem Szenenwechsel wieder bei false anzufangen.
var _vitality_bonus_granted: bool = false


func _ready() -> void:
	if get_node_or_null("/root/RunState") != null:
		_vitality_bonus_granted = RunState.has_unlocked_skill(&"vitality")

		if not RunState.skill_progress_changed.is_connected(
			_on_skill_progress_changed
		):
			RunState.skill_progress_changed.connect(
				_on_skill_progress_changed
			)

		current_health = clamp(
			RunState.current_health,
			0,
			get_max_health()
		)

		current_armor = clamp(
			RunState.current_armor,
			0,
			get_max_armor()
		)

		_load_armor_types_from_run_state()
	else:
		current_health = get_max_health()
		current_armor = 0
		armor_types = []

	dead = current_health <= 0

	health_changed.emit(
		current_health,
		get_max_health(),
		current_health
	)

	armor_changed.emit(
		current_armor,
		get_max_armor(),
		current_armor
	)


# Tatsächlich geltendes Maximum: Grundwert plus, falls im laufenden
# Run freigeschaltet, der Vitality-Bonus (Skill-Baum "Pfad der
# Stärke" - siehe Game/skill_tree_data.gd, id &"vitality": "+1
# maximales Herz", einer der beiden Werte, die der Nutzer bereits
# final bestätigt hat). Wird bewusst jedes Mal frisch aus RunState
# berechnet statt zwischengespeichert, damit hier nichts veraltet
# sein kann.
func get_max_health() -> int:
	var bonus: int = 0

	if get_node_or_null("/root/RunState") != null:
		if RunState.has_unlocked_skill(&"vitality"):
			bonus = 1

	return base_max_health + bonus


# Rüstungs-Obergrenze: immer gleich der aktuellen Herzanzahl, siehe
# Kommentar bei "var armor_types" oben - jedes Herz genau ein
# Rüstungs-Slot.
func get_max_armor() -> int:
	return get_max_health()


# Gleicht die Länge von armor_types an get_max_armor() an, neue
# Slots (z.B. frisch durch Vitality dazugekommenes Herz) starten
# leer. Wird vor jedem lesenden/schreibenden Zugriff aufgerufen,
# damit armor_types nie kürzer ist als die aktuelle Herzanzahl.
func _ensure_armor_types_size() -> void:
	var target_size := get_max_armor()

	while armor_types.size() < target_size:
		armor_types.append(ARMOR_TYPE_NONE)

	if armor_types.size() > target_size:
		armor_types.resize(target_size)


# Für RunState.set_armor_types() (dort als Array[String] persistiert,
# StringName ist nicht JSON-serialisierbar).
func _armor_types_as_strings() -> Array[String]:
	var result: Array[String] = []

	for t in armor_types:
		result.append(String(t))

	return result


func _load_armor_types_from_run_state() -> void:
	armor_types = []

	if get_node_or_null("/root/RunState") == null:
		return

	for s in RunState.armor_types:
		armor_types.append(StringName(s))

	_ensure_armor_types_size()


# Auf RunState.skill_progress_changed (feuert u.a. bei jedem
# unlock_skill(), siehe Game/run_state.gd) reagiert das hier NUR,
# wenn Vitality gerade frisch dazugekommen ist - das neue Herz soll
# sofort als volles Herz spürbar sein, nicht nur als leerer Rahmen,
# den man erst mühsam mit einem Trank auffüllen muss.
func _on_skill_progress_changed(_progress: float, _points: int) -> void:
	if _vitality_bonus_granted:
		return

	if get_node_or_null("/root/RunState") == null:
		return

	if not RunState.has_unlocked_skill(&"vitality"):
		return

	_vitality_bonus_granted = true

	var old_health := current_health

	current_health = min(
		current_health + 1,
		get_max_health()
	)

	RunState.set_health(current_health)

	health_changed.emit(
		current_health,
		get_max_health(),
		old_health
	)


func take_damage(amount: int) -> void:
	if dead or invincible:
		return

	if amount <= 0:
		return

	if current_armor > 0:
		_ensure_armor_types_size()

		var old_armor := current_armor

		current_armor -= 1

		var broken_index := current_armor
		var broken_type: StringName = ARMOR_TYPE_NONE

		if broken_index >= 0 and broken_index < armor_types.size():
			broken_type = armor_types[broken_index]
			armor_types[broken_index] = ARMOR_TYPE_NONE

		if get_node_or_null("/root/RunState") != null:
			RunState.set_armor(current_armor)
			RunState.set_armor_types(_armor_types_as_strings())

		armor_broken.emit(broken_index, broken_type)

		armor_changed.emit(
			current_armor,
			get_max_armor(),
			old_armor
		)

		hurt.emit()

		start_invincible(invincible_time)
		return

	var old_health := current_health

	current_health -= amount
	current_health = max(current_health, 0)

	if get_node_or_null("/root/RunState") != null:
		RunState.set_health(current_health)

	health_changed.emit(
		current_health,
		get_max_health(),
		old_health
	)

	hurt.emit()

	if current_health <= 0:
		dead = true
		died.emit()
		return

	start_invincible(invincible_time)


func heal(amount: int) -> bool:
	if dead:
		return false

	if amount <= 0:
		return false

	if current_health >= get_max_health():
		return false

	var old_health := current_health

	current_health += amount
	current_health = min(current_health, get_max_health())

	if get_node_or_null("/root/RunState") != null:
		RunState.set_health(current_health)

	health_changed.emit(
		current_health,
		get_max_health(),
		old_health
	)

	healed.emit()

	return true


func add_armor(
	amount: int = 1,
	armor_type: StringName = ARMOR_TYPE_SHIELD
) -> bool:
	if dead:
		return false

	if amount <= 0:
		return false

	if current_health < get_max_health():
		return false

	_ensure_armor_types_size()

	if current_armor >= get_max_armor():
		return false

	var old_armor := current_armor
	var granted := 0

	for i in armor_types.size():
		if granted >= amount:
			break

		if armor_types[i] == ARMOR_TYPE_NONE:
			armor_types[i] = armor_type
			granted += 1

	if granted == 0:
		return false

	current_armor += granted
	current_armor = clamp(current_armor, 0, get_max_armor())

	if get_node_or_null("/root/RunState") != null:
		RunState.set_armor(current_armor)
		RunState.set_armor_types(_armor_types_as_strings())

	armor_changed.emit(
		current_armor,
		get_max_armor(),
		old_armor
	)

	return true


func restore_from_run_state() -> void:
	var old_health := current_health
	var old_armor := current_armor

	if get_node_or_null("/root/RunState") != null:
		_vitality_bonus_granted = RunState.has_unlocked_skill(&"vitality")

		current_health = clamp(
			RunState.current_health,
			0,
			get_max_health()
		)

		current_armor = clamp(
			RunState.current_armor,
			0,
			get_max_armor()
		)

		_load_armor_types_from_run_state()
	else:
		current_health = get_max_health()
		current_armor = 0
		armor_types = []

	dead = current_health <= 0
	invincible = false

	health_changed.emit(
		current_health,
		get_max_health(),
		old_health
	)

	armor_changed.emit(
		current_armor,
		get_max_armor(),
		old_armor
	)


func start_invincible(time: float) -> void:
	invincible = true

	await get_tree().create_timer(time).timeout

	if is_inside_tree():
		invincible = false
