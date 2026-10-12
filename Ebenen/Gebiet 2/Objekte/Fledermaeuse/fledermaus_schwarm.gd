extends Node2D

# Nutzer-Wunsch: Im Hintergrund fliegen Fledermäuse durch den Raum - immer mal
# wieder ein ganzer Schwarm und zwischendurch einzelne Tiere kreuz und quer.
# Reine Deko (keine Kollision, kein Schaden).
#
# Die Tiere werden knapp außerhalb des sichtbaren Bildes erzeugt, fliegen
# durchs Bild und werden entfernt, sobald sie wieder draußen sind. So fliegt
# immer etwas dort, wo der Spieler gerade ist, ohne dass im ganzen Raum Tiere
# herumfliegen müssen.
#
# Nutzer-Korrektur: Grafik = die kleinen schwarzen Hintergrund-Fledermäuse
# (Mobs/Gebiet 2/Hintergrund/Fliegen-Sheet.png, 32x32, von VORNE gezeichnet),
# nicht die große Gegner-Fledermaus. Deshalb wird standardmäßig nicht gespiegelt.
# Position dieses Nodes = Bodenhöhe; die Flughöhe wird relativ dazu angegeben.

@export_group("Grafik")
## Sprite-Sheet mit der Flug-Animation (Frames nebeneinander).
@export var sheet: Texture2D
@export var frame_count: int = 4
@export var frame_size: Vector2i = Vector2i(32, 32)
## Nur anschalten, wenn die Grafik seitlich (nach rechts) gezeichnet ist.
@export var flip_with_direction: bool = false
## Flügelschläge: Bilder pro Sekunde.
@export var anim_fps: float = 9.0
## Größe der Tiere (klein = wirkt weiter weg). Zufällig zwischen min und max.
@export var scale_min: float = 0.8
@export var scale_max: float = 1.0
## Farbe/Helligkeit. Etwas heller und bläulich wirkt wie im Dunst weiter hinten.
@export var bat_color: Color = Color(1, 1, 1, 1)

@export_group("Flugbereich")
## Flughöhe über diesem Node (Pixel nach oben), zufällig zwischen min und max.
@export var height_min: float = 45.0
@export var height_max: float = 150.0
## So weit außerhalb des Bildrands starten und enden die Tiere (Pixel).
@export var spawn_margin: float = 30.0

@export_group("Einzelne Fledermäuse")
@export var singles_enabled: bool = true
## Pause zwischen zwei einzelnen Tieren (Sekunden, zufällig).
@export var single_interval_min: float = 8.0
@export var single_interval_max: float = 18.0
@export var single_speed_min: float = 45.0
@export var single_speed_max: float = 80.0
## Wie schräg sie fliegen dürfen (Grad nach oben/unten) - "kreuz und quer".
@export var single_max_angle: float = 28.0

@export_group("Schwarm")
@export var swarm_enabled: bool = true
## Pause zwischen zwei Schwärmen (Sekunden, zufällig).
@export var swarm_interval_min: float = 40.0
@export var swarm_interval_max: float = 80.0
@export var swarm_count_min: int = 3
@export var swarm_count_max: int = 5
@export var swarm_speed_min: float = 75.0
@export var swarm_speed_max: float = 105.0
## Wie weit der Schwarm auseinandergezogen ist (Breite, Höhe in Pixeln).
@export var swarm_spread: Vector2 = Vector2(60, 30)

@export_group("Flattern")
## Auf und ab während des Flugs (Pixel) und wie schnell.
@export var wobble_px: float = 5.0
@export var wobble_speed: float = 5.0

var _frames: SpriteFrames = null
var _bats: Array[Dictionary] = []
var _single_timer: float = 0.0
var _swarm_timer: float = 0.0


func _ready() -> void:
	_frames = _build_frames()
	_single_timer = randf_range(0.5, single_interval_min)
	_swarm_timer = randf_range(swarm_interval_min * 0.3, swarm_interval_min)


func _process(delta: float) -> void:
	var view: Rect2 = _get_view_rect()
	if view.size == Vector2.ZERO:
		return

	if singles_enabled:
		_single_timer -= delta
		if _single_timer <= 0.0:
			_single_timer = randf_range(single_interval_min, single_interval_max)
			spawn_single()
	if swarm_enabled:
		_swarm_timer -= delta
		if _swarm_timer <= 0.0:
			_swarm_timer = randf_range(swarm_interval_min, swarm_interval_max)
			spawn_swarm()

	# Bewegen und aufräumen.
	var outer: Rect2 = view.grow(spawn_margin + 80.0)
	var alive: Array[Dictionary] = []
	for b in _bats:
		var spr: AnimatedSprite2D = b["sprite"]
		if not is_instance_valid(spr):
			continue
		b["age"] += delta
		b["pos"] += b["vel"] * delta
		var wobble: float = sin(b["age"] * wobble_speed + b["phase"]) * wobble_px
		spr.global_position = b["pos"] + Vector2(0.0, wobble)
		# Erst entfernen, wenn es das Bild einmal betreten hat oder zu alt ist.
		if view.has_point(b["pos"]):
			b["seen"] = true
		if (b["seen"] and not outer.has_point(b["pos"])) or b["age"] > 40.0:
			spr.queue_free()
			continue
		alive.append(b)
	_bats = alive


# ============================================================
# ERZEUGEN
# ============================================================

## Eine einzelne Fledermaus fliegt von einer Seite zur anderen, leicht schräg.
func spawn_single() -> void:
	var view: Rect2 = _get_view_rect()
	var dir: float = 1.0 if randf() > 0.5 else -1.0
	var angle: float = deg_to_rad(randf_range(-single_max_angle, single_max_angle))
	var speed: float = randf_range(single_speed_min, single_speed_max)
	var start := Vector2(
		view.position.x - spawn_margin if dir > 0.0 else view.end.x + spawn_margin,
		global_position.y - randf_range(height_min, height_max)
	)
	_add_bat(start, Vector2(cos(angle) * dir, sin(angle)) * speed)


## Ein ganzer Schwarm zieht in eine Richtung durchs Bild.
func spawn_swarm() -> void:
	var view: Rect2 = _get_view_rect()
	var dir: float = 1.0 if randf() > 0.5 else -1.0
	var angle: float = deg_to_rad(randf_range(-10.0, 10.0))
	var base_speed: float = randf_range(swarm_speed_min, swarm_speed_max)
	var center := Vector2(
		view.position.x - spawn_margin - swarm_spread.x * 0.5 if dir > 0.0 else view.end.x + spawn_margin + swarm_spread.x * 0.5,
		global_position.y - randf_range(height_min + swarm_spread.y * 0.5, maxf(height_max - swarm_spread.y * 0.5, height_min + swarm_spread.y * 0.5))
	)
	for i in randi_range(swarm_count_min, swarm_count_max):
		var offset := Vector2(randf_range(-0.5, 0.5) * swarm_spread.x, randf_range(-0.5, 0.5) * swarm_spread.y)
		var a: float = angle + deg_to_rad(randf_range(-6.0, 6.0))
		var speed: float = base_speed * randf_range(0.88, 1.12)
		_add_bat(center + offset, Vector2(cos(a) * dir, sin(a)) * speed)


func _add_bat(start: Vector2, vel: Vector2) -> void:
	if _frames == null:
		return
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = _frames
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var s: float = randf_range(scale_min, scale_max)
	spr.scale = Vector2(s, s)
	spr.modulate = bat_color
	spr.flip_h = flip_with_direction and vel.x < 0.0
	add_child(spr)
	spr.global_position = start
	spr.play(&"fliegen")
	# Nicht alle im Gleichtakt flattern lassen.
	spr.frame = randi() % maxi(frame_count, 1)
	spr.speed_scale = randf_range(0.85, 1.2)
	_bats.append({
		"sprite": spr,
		"pos": start,
		"vel": vel,
		"age": 0.0,
		"phase": randf() * TAU,
		"seen": false,
	})


# ============================================================
# HILFEN
# ============================================================

func _build_frames() -> SpriteFrames:
	if sheet == null:
		push_warning("Fledermaus-Schwarm: kein Sprite-Sheet gesetzt (sheet).")
		return null
	var frames := SpriteFrames.new()
	frames.add_animation(&"fliegen")
	frames.set_animation_loop(&"fliegen", true)
	frames.set_animation_speed(&"fliegen", anim_fps)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(i * frame_size.x, 0, frame_size.x, frame_size.y)
		frames.add_frame(&"fliegen", atlas)
	return frames


# Sichtbarer Bildausschnitt in Weltkoordinaten.
func _get_view_rect() -> Rect2:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return Rect2()
	var size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom
	return Rect2(cam.get_screen_center_position() - size * 0.5, size)
