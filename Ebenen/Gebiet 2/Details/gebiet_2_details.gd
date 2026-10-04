extends AnimatedSprite2D

# Nutzer-Wunsch: die Animationen in diesem Sprite (Korkor + alle
# netz_X-Varianten, siehe sprite_frames) haben schon alle "loop" auf
# true stehen - es fehlte nur der Aufruf, der das Abspielen überhaupt
# erst startet, genau wie bei Objects/fackel.gd. play() OHNE Namen
# spielt einfach die Animation, die gerade im Inspector als
# "Animation" eingestellt ist (siehe node-Eigenschaft "animation"
# unten in dieser Szene) - so funktioniert das automatisch für jede
# der Varianten, egal welche man für eine bestimmte Platzierung im
# Level auswählt.
func _ready() -> void:
	play()
