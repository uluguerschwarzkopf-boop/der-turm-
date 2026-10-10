extends Node2D


# ============================================================
# HINWEIS
# ============================================================

# Einmal benutzbare Echo-Tür: lässt sich nur mit einem bestimmten
# Boss-Echo (siehe required_echo) überhaupt öffnen. Ablauf:
#
#   InActiv (Start, noch nichts gemacht)
#   -> [OpenArea betreten, Echo vorhanden]
#   -> Opening -> Opened
#   -> [EntranceArea betreten]
#   -> Durchgehen -> Szenenwechsel in next_room_path
#   -> Activ (Endzustand, "verbraucht")
#
# Einmal Activ, reagiert die Tür auf nichts mehr - man kommt kein
# zweites Mal durch. Ohne das Echo passiert beim Betreten von
# OpenArea gar nichts, die Tür bleibt InActiv.
#
# Der Verbraucht-Status wird über door_id in RunState.used_doors
# gespeichert (RunState.mark_door_used()/has_used_door()) - bleibt
# also über Speichern/Laden hinweg erhalten, wird aber beim
# Tod-Neustart zurückgesetzt, genau wie die freigeschalteten Echos
# (RunState.start_new_run()).
#
# Nach dem Durchgehen (Durchgehen-Animation fertig) wechselt die
# Szene per change_scene_to_file() direkt in next_room_path (siehe
# unten, Standard: der Skill-Tree-Raum) - genau wie RoomManager das
# bei einem normalen Raumwechsel macht (siehe Levels/room_manager.gd
# -> _on_phase_2_finished()). Der Zielraum hat noch keinen eigenen
# Spawnpunkt/Rückweg - der Spieler landet einfach dort, wo er in
# der Zielszene platziert ist (RoomManager._enter_at_normal_spawn()
# lässt ihn an seiner Instanz-Position, wenn kein SpawnDoor/
# PlayerSpawn gefunden wird).


# ============================================================
# EINSTELLUNGEN
# ============================================================

# Eindeutiger Schlüssel für RunState.used_doors - bei mehreren
# Echo-Türen im Spiel braucht jede Instanz ihren eigenen Wert im
# Inspector, sonst teilen sie sich denselben "benutzt"-Status.
@export var door_id: StringName = &"gebiet_1_flame_echo_door"

# Welches Echo man besitzen muss, damit OpenArea überhaupt reagiert.
@export var required_echo: StringName = &"echo_der_flamme"

# Raum, in den man nach der Durchgehen-Animation wechselt. Diesen
# Pfad im Inspector mit dem Ordner-Symbol auswählen, falls sich der
# Skill-Tree-Raum nochmal verschiebt/umbenennt.
@export_file("*.tscn")
var next_room_path: String = "res://Levels/Gebiet 1/skill_tree_room.tscn"


# ============================================================
# ANIMATIONEN (Namen exakt wie im SpriteFrames-Resource)
# ============================================================

const ANIM_INACTIVE: StringName = &"InActiv"
const ANIM_ACTIVE: StringName = &"Activ"
const ANIM_OPENING: StringName = &"Opening"
const ANIM_OPENED: StringName = &"Opened"
const ANIM_PASSING: StringName = &"Durchgehen"


# ============================================================
# STATUS
# ============================================================

enum State {
	INACTIVE,
	OPENED,
	BUSY,
	ACTIVE,
}

var _state: State = State.INACTIVE


# ============================================================
# NODES
# ============================================================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var open_area: Area2D = $OpenArea
@onready var entrance_area: Area2D = $EntranceArea
@onready var spawn_marker: Marker2D = $Spawnmarker


func _ready() -> void:
	open_area.body_entered.connect(_on_open_area_body_entered)
	entrance_area.body_entered.connect(_on_entrance_area_body_entered)

	if (
		get_node_or_null("/root/RunState") != null
		and RunState.has_used_door(door_id)
	):
		# Schon früher in diesem Run verbraucht (z.B. Raum verlassen
		# und wieder betreten, oder ein Spielstand geladen) - direkt
		# im Endzustand starten, nicht nochmal von vorne InActiv.
		_state = State.ACTIVE
		_play_anim_safe(ANIM_ACTIVE)
	else:
		_state = State.INACTIVE
		_play_anim_safe(ANIM_INACTIVE)


# ============================================================
# ÖFFNEN (OpenArea)
# ============================================================

func _on_open_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if _state != State.INACTIVE:
		return

	if (
		get_node_or_null("/root/RunState") == null
		or not RunState.has_echo(required_echo)
	):
		# Ohne das Echo passiert nichts - Tür bleibt InActiv.
		return

	_state = State.BUSY

	if body.has_method("lock_control"):
		body.lock_control()

	# Der Spieler ist schon fest in die Opening-Animation
	# eingezeichnet (siehe Sprite-Sheet) - der echte Spieler-Node
	# muss währenddessen unsichtbar sein, sonst sieht man beide
	# übereinander.
	if body is CanvasItem:
		(body as CanvasItem).visible = false

	_play_anim_safe(ANIM_OPENING)
	await _await_animation_or_fallback()

	_state = State.OPENED
	_play_anim_safe(ANIM_OPENED)

	if body is CanvasItem:
		(body as CanvasItem).visible = true

	if body.has_method("unlock_control"):
		body.unlock_control()


# ============================================================
# DURCHGEHEN (EntranceArea)
# ============================================================

func _on_entrance_area_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if _state != State.OPENED:
		return

	_state = State.BUSY

	if body.has_method("lock_control"):
		body.lock_control()

	# Genau wie bei Opening: der Spieler ist schon Teil der
	# Durchgehen-Animation, der echte Spieler-Node muss also
	# während der ganzen Animation unsichtbar sein.
	if body is CanvasItem:
		(body as CanvasItem).visible = false

	_play_anim_safe(ANIM_PASSING)
	await _await_animation_or_fallback()

	if body is CharacterBody2D:
		(body as CharacterBody2D).velocity = Vector2.ZERO

	if get_node_or_null("/root/RunState") != null:
		RunState.mark_door_used(door_id)

	_state = State.ACTIVE

	# Ab hier wechselt gleich die ganze Szene - der echte Spieler-
	# Node und diese Tür werden dabei sowieso ersetzt/freigegeben,
	# deshalb hier bewusst KEIN body.visible=true/unlock_control()
	# mehr: der RoomManager im Zielraum sperrt/entsperrt die
	# Steuerung des dortigen (neuen) Spieler-Node schon selbst
	# (siehe enter_room() in Levels/room_manager.gd).
	_change_to_next_room()


# ============================================================
# RAUMWECHSEL
# ============================================================

func _change_to_next_room() -> void:
	if next_room_path.is_empty():
		push_warning("FlameEchoDoor: next_room_path ist leer.")
		return

	if not ResourceLoader.exists(next_room_path):
		push_error(
			"FlameEchoDoor: Folgeraum fehlt: " + next_room_path
		)
		return

	var tree := get_tree()

	if tree == null:
		return

	# call_deferred, genau wie RoomManager._on_phase_2_finished() -
	# der Szenenwechsel soll nicht noch mitten in der laufenden
	# body_entered-Signalverarbeitung passieren.
	tree.call_deferred("change_scene_to_file", next_room_path)


# ============================================================
# HILFSFUNKTIONEN
# ============================================================

func _play_anim_safe(anim_name: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(anim_name):
		push_warning(
			"FlameEchoDoor: Animation fehlt: " + String(anim_name)
		)
		return

	sprite.play(anim_name)


# Wartet auf animation_finished - falls die Animation aus
# irgendeinem Grund fehlt/nicht startet (has_animation() oben
# schon fehlgeschlagen), würde is_playing() nie true und
# animation_finished nie feuern, deshalb hier ein kurzer
# Sicherheits-Timer als Rückfall, statt für immer hängenzubleiben.
func _await_animation_or_fallback() -> void:
	if sprite != null and sprite.is_playing():
		await sprite.animation_finished
	else:
		await get_tree().create_timer(0.6).timeout
