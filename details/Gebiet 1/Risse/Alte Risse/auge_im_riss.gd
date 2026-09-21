extends AnimatedSprite2D

# "Auge im Riss" (Detail-Objekt, Gebiet 1): spielt seine einzige
# Animation ("default", loop=false - siehe auge_im_riss.tscn) EIN
# EINZIGES MAL, sobald der Spieler die "interactionarea" (Area2D-
# Kind dieser Szene) zum ERSTEN Mal betritt. Betritt er den Bereich
# danach nochmal (oder mehrmals), passiert nichts mehr - die
# Animation ist "verbraucht". Nach dem einmaligen Durchlauf bleibt
# der Sprite auf Frame 1 (dem ERSTEN Frame, nicht dem letzten)
# eingefroren stehen (Nutzer-Wunsch).

const ANIM_NAME: StringName = &"default"

@onready var interaction_area: Area2D = $interactionarea

var _has_played: bool = false


func _ready() -> void:
	interaction_area.monitoring = true
	interaction_area.body_entered.connect(_on_body_entered)

	# Sicherstellen, dass wir vor dem ersten Abspielen schon auf
	# Frame 1 stehen (Standard-Ruhezustand, siehe Nutzer-Wunsch oben).
	frame = 0
	stop()


func _on_body_entered(body: Node) -> void:
	if _has_played:
		return

	if not body.is_in_group("player"):
		return

	if sprite_frames == null or not sprite_frames.has_animation(ANIM_NAME):
		return

	_has_played = true

	if not animation_finished.is_connected(_on_animation_finished):
		animation_finished.connect(_on_animation_finished)

	play(ANIM_NAME)


func _on_animation_finished() -> void:
	if animation != ANIM_NAME:
		return

	if animation_finished.is_connected(_on_animation_finished):
		animation_finished.disconnect(_on_animation_finished)

	# Nutzer-Wunsch: nach dem einmaligen Durchlauf auf Frame 1
	# (erster Frame) eingefroren stehen bleiben, nicht auf dem
	# letzten Frame.
	stop()
	frame = 0
