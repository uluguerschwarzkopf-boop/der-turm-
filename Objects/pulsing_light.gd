extends PointLight2D


# ============================================================
# HINWEIS
# ============================================================

# Lässt dieses PointLight2D sanft zwischen einem dunkleren und
# einem helleren Zustand hin- und her "atmen" (Energie UND ein
# kleines bisschen Textur-Größe zusammen) - gedacht für die
# leuchtenden Kristalle auf den drei Statuen im Skill-Tree-Raum
# (siehe Objects/Staturen/*.tscn), funktioniert aber genauso auf
# jedem anderen PointLight2D, das dieses Script bekommt.
#
# Rein zeitbasiert über einen Endlos-Tween (set_loops() ohne
# Angabe = für immer) - kein eigener _process() nötig.


@export var pulse_energy_min: float = 0.9
@export var pulse_energy_max: float = 1.6

@export var pulse_scale_min: float = 0.95
@export var pulse_scale_max: float = 1.08

@export var pulse_time: float = 1.3


func _ready() -> void:
	energy = pulse_energy_min
	texture_scale = pulse_scale_min

	var pulse_tween := create_tween()
	pulse_tween.set_loops()

	pulse_tween.tween_property(
		self, "energy", pulse_energy_max, pulse_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	pulse_tween.parallel().tween_property(
		self, "texture_scale", pulse_scale_max, pulse_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	pulse_tween.tween_property(
		self, "energy", pulse_energy_min, pulse_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	pulse_tween.parallel().tween_property(
		self, "texture_scale", pulse_scale_min, pulse_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
