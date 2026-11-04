extends Node

# Nutzer-Wunsch: alle Gegner ignorieren sich untereinander und laufen
# durcheinander hindurch. Bewusst zentral statt in jedem Gegner-Skript:
# jeder Gegner in der Gruppe "enemy" wird automatisch erfasst, auch
# später gespawnte (z.B. geschlüpfte Spinne, Mutant aus der Käfig-Falle)
# und neue Gegner, ohne dass jemand daran denken muss.
#
# Reine Kollisions-Ausnahmen zwischen den Körpern, statt die Physik-Layer
# umzustellen: Boden, Wände und der Spieler bleiben unverändert, und die
# Zauber des Spielers (die Gegner-Körper über Layer 1 finden) treffen weiter.
#
# Wird von Game/enemy_sound_manager.gd als Kind erzeugt und nicht als
# eigener Autoload: den Eintrag in project.godot würde ein offener
# Godot-Editor beim nächsten Speichern wieder überschreiben.

@export var enemy_group: StringName = &"enemy"


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is PhysicsBody2D:
		# Deferred: die meisten Gegner treten der Gruppe erst in ihrem
		# eigenen _ready() bei, das läuft nach node_added.
		_register_enemy.call_deferred(node)


func _register_enemy(body: PhysicsBody2D) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return

	if not body.is_in_group(enemy_group):
		return

	for other: Node in get_tree().get_nodes_in_group(enemy_group):
		if other == body or not (other is PhysicsBody2D):
			continue

		# Beide Richtungen: eine Ausnahme gilt nur für den Körper, der
		# sich gerade bewegt.
		body.add_collision_exception_with(other)
		(other as PhysicsBody2D).add_collision_exception_with(body)
