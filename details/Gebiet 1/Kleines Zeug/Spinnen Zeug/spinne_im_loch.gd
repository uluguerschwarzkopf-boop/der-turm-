extends AnimatedSprite2D

# ============================================================
# Spinne im Loch - reines Detail, spielt seine Animation
# durchgehend in einer Endlosschleife ab.
# ============================================================
# Die "default"-Animation hat in den SpriteFrames bereits loop=true,
# AnimatedSprite2D startet die Wiedergabe aber nicht von selbst -
# das hier stößt sie beim Erscheinen einmal an, danach loopt sie von
# alleine weiter.


func _ready() -> void:
	play()
