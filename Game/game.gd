extends Node

@export var load_delay_frames: int = 1

var loading_started: bool = false


func _ready() -> void:
	if loading_started:
		return

	loading_started = true

	for i in range(max(load_delay_frames, 0)):
		await get_tree().process_frame

	_load_first_run_room()


func _load_first_run_room() -> void:
	if get_node_or_null("/root/RunState") == null:
		push_error("Game: RunState wurde nicht als Autoload gefunden.")
		return

	if RunState.room_order.is_empty():
		RunState.generate_room_order()

	# Nutzer-Wunsch: Shop-Checkpoint (siehe Game/run_state.gd ->
	# has_shop_checkpoint). Wurde der Shop in diesem Lauf bereits
	# betreten, hat RunState.reset_run() current_room_index beim Tod-
	# Neustart schon korrekt auf den Shop-Raum zurückgesetzt (siehe
	# RunState._restore_shop_checkpoint()) - hier NICHT mehr zwingend
	# auf Raum 1 überschreiben. Ohne Checkpoint (auch beim ALLERERSTEN
	# Start eines Laufs) bleibt es beim bisherigen Verhalten: immer
	# Raum 1.
	if not RunState.has_shop_checkpoint:
		RunState.current_room_index = 0

	var first_room_path: String = RunState.get_current_room_path()

	if first_room_path.is_empty():
		push_error("Game: Der Pfad für den ersten Raum ist leer.")
		return

	if not ResourceLoader.exists(first_room_path):
		push_error(
			"Game: Der erste Raum wurde nicht gefunden: "
			+ first_room_path
		)
		return

	if RunState.has_shop_checkpoint:
		print("Run startet am Shop-Checkpoint: ", first_room_path)
	else:
		print("Run startet in Raum 1: ", first_room_path)

	var error: Error = get_tree().change_scene_to_file(first_room_path)

	if error != OK:
		push_error(
			"Game: Raum konnte nicht geladen werden: "
			+ first_room_path
			+ " | Fehlercode: "
			+ str(error)
		)
