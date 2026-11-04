extends Node2D

# Nutzer-Wunsch: zerfällt ein Gegner beim Tod in Stücke, hat jedes Stück eigene
# Physik: Liegt es in der Luft, fällt es, bis es auf Boden trifft, und macht
# beim Aufprall eine kleine Staubwolke. Liegt es auf Boden, bleibt es einfach da.
#
# zerlege() schneidet die Stücke aus dem letzten Frame der Tot-Animation: alles,
# was im Bild zusammenhängt, ist ein Stück. So braucht es keine neue Grafik.
# Aufgerufen vom Gegner, alle Werte kommen aus dessen Inspektor.
#
# Eigene kleine Physik per Strahl statt RigidBody2D (wie beim Kopf des Kriegers):
# Stücke prallen nur an Tiles ab und versperren niemandem den Weg.


var schwerkraft: float = 320.0
var max_fall_tempo: float = 400.0
var boden_maske: int = 1
var ausnahmen: Array[RID] = []
var unten_abstand: float = 0.0

var staub_an: bool = true
var staub_farbe_1: Color = Color.WHITE
var staub_farbe_2: Color = Color.WHITE
var staub_anzahl: int = 8
var staub_tempo: float = 26.0
var staub_dauer: float = 0.35
var staub_min_fallhoehe: float = 3.0

var _tempo_y: float = 0.0
var _gefallen: float = 0.0
var _fertig: bool = false


# Erzeugt die Stücke. einstellungen enthält die Werte aus dem Inspektor.
# Gibt false zurück, wenn es keine zwei Stücke gibt (dann bleibt das normale Bild).
static func zerlege(sprite: AnimatedSprite2D, eltern: Node, einstellungen: Dictionary) -> bool:
	var textur: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)

	if textur == null:
		return false

	var bild: Image = textur.get_image()

	if bild == null:
		return false

	if bild.is_compressed():
		bild.decompress()

	bild.convert(Image.FORMAT_RGBA8)

	var stuecke: Array = _finde_stuecke(bild, int(einstellungen.get("min_pixel", 12)))

	if stuecke.size() < 2:
		return false

	var groesse: Vector2 = bild.get_size()

	for pixel: Array in stuecke:
		var rahmen := Rect2i(pixel[0], Vector2i.ONE)

		for p: Vector2i in pixel:
			rahmen = rahmen.expand(p)

		rahmen.size += Vector2i.ONE

		var teil_bild := Image.create(rahmen.size.x, rahmen.size.y, false, Image.FORMAT_RGBA8)

		for p: Vector2i in pixel:
			teil_bild.set_pixelv(p - rahmen.position, bild.get_pixelv(p))

		var mitte_im_bild: Vector2 = Vector2(rahmen.position) + Vector2(rahmen.size) * 0.5 - groesse * 0.5

		# Gespiegelter Sprite: das Bild klappt um seine Mitte.
		if sprite.flip_h:
			mitte_im_bild.x = -mitte_im_bild.x

		var teil = load("res://Mobs/leiche_teil.gd").new()
		teil.top_level = true
		teil.z_index = sprite.z_index
		teil.z_as_relative = sprite.z_as_relative
		# Stücke bewegen sich selbst: Interpolation aus, sonst zittern sie.
		teil.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		teil.schwerkraft = einstellungen.get("schwerkraft", 320.0)
		teil.max_fall_tempo = einstellungen.get("max_fall_tempo", 400.0)
		teil.boden_maske = einstellungen.get("boden_maske", 1)
		teil.ausnahmen = einstellungen.get("ausnahmen", [] as Array[RID])
		teil.unten_abstand = rahmen.size.y * 0.5
		teil.staub_an = einstellungen.get("staub_an", true)
		teil.staub_farbe_1 = einstellungen.get("staub_farbe_1", Color.WHITE)
		teil.staub_farbe_2 = einstellungen.get("staub_farbe_2", Color.WHITE)
		teil.staub_anzahl = einstellungen.get("staub_anzahl", 8)
		teil.staub_tempo = einstellungen.get("staub_tempo", 26.0)
		teil.staub_dauer = einstellungen.get("staub_dauer", 0.35)
		teil.staub_min_fallhoehe = einstellungen.get("staub_min_fallhoehe", 3.0)

		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(teil_bild)
		s.flip_h = sprite.flip_h
		s.texture_filter = sprite.texture_filter
		s.material = sprite.material
		s.light_mask = sprite.light_mask
		teil.add_child(s)

		eltern.add_child(teil)
		teil.global_position = sprite.to_global(sprite.offset + mitte_im_bild)

	return true


# Zusammenhängende Pixel-Gruppen ab min_pixel Größe (kleine Krümel entfallen).
static func _finde_stuecke(bild: Image, min_pixel: int) -> Array:
	var breite: int = bild.get_width()
	var hoehe: int = bild.get_height()
	var gesehen := {}
	var ergebnis: Array = []

	for y in hoehe:
		for x in breite:
			var start := Vector2i(x, y)

			if gesehen.has(start) or bild.get_pixelv(start).a < 0.1:
				continue

			var stapel: Array[Vector2i] = [start]
			var gruppe: Array = []
			gesehen[start] = true

			while not stapel.is_empty():
				var p: Vector2i = stapel.pop_back()
				gruppe.append(p)

				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						var q := p + Vector2i(dx, dy)

						if q.x < 0 or q.y < 0 or q.x >= breite or q.y >= hoehe or gesehen.has(q):
							continue

						if bild.get_pixelv(q).a >= 0.1:
							gesehen[q] = true
							stapel.append(q)

			if gruppe.size() >= min_pixel:
				ergebnis.append(gruppe)

	return ergebnis


func _physics_process(delta: float) -> void:
	if _fertig:
		set_physics_process(false)
		return

	_tempo_y = minf(_tempo_y + schwerkraft * delta, max_fall_tempo)

	var schritt: float = _tempo_y * delta
	var unten: Vector2 = global_position + Vector2(0.0, unten_abstand)
	# Etwas über der Unterkante starten: das Stück liegt anfangs direkt auf dem Boden.
	var abfrage := PhysicsRayQueryParameters2D.create(
		unten + Vector2(0.0, -2.0),
		unten + Vector2(0.0, schritt + 1.0),
		boden_maske,
		ausnahmen
	)
	var treffer: Dictionary = get_world_2d().direct_space_state.intersect_ray(abfrage)

	if treffer.is_empty():
		global_position.y += schritt
		_gefallen += schritt
		return

	_fertig = true
	global_position.y = treffer["position"].y - unten_abstand

	if staub_an and _gefallen >= staub_min_fallhoehe:
		_mache_staub(treffer["position"])


func _mache_staub(punkt: Vector2) -> void:
	var wolke := StaubWolke.new()
	wolke.farbe_1 = staub_farbe_1
	wolke.farbe_2 = staub_farbe_2
	wolke.anzahl = staub_anzahl
	wolke.tempo = staub_tempo
	wolke.dauer = staub_dauer
	wolke.breite = unten_abstand * 2.0 + 8.0
	wolke.z_index = z_index + 1
	wolke.z_as_relative = z_as_relative
	wolke.top_level = true
	wolke.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(wolke)
	wolke.global_position = punkt + Vector2(0.0, -1.0)


# Ganz schlichter Staub: einzelne Pixel in zwei Farben fliegen nach links und
# rechts und verschwinden. Bewusst ohne Weichzeichnen, passend zur Pixel-Grafik.
class StaubWolke extends Node2D:
	var farbe_1: Color = Color.WHITE
	var farbe_2: Color = Color.WHITE
	var anzahl: int = 8
	var tempo: float = 26.0
	var dauer: float = 0.35
	var breite: float = 16.0

	var _pixel: Array[Dictionary] = []
	var _alter: float = 0.0

	func _ready() -> void:
		for i in maxi(anzahl, 1):
			var richtung: float = -1.0 if i % 2 == 0 else 1.0
			_pixel.append({
				"pos": Vector2(richtung * randf_range(0.0, breite * 0.5), randf_range(-2.0, 0.0)),
				"vel": Vector2(richtung * randf_range(tempo * 0.4, tempo), randf_range(-9.0, -2.0)),
				"weg_bei": randf_range(dauer * 0.5, dauer),
				"farbe": farbe_1 if i % 3 != 0 else farbe_2,
			})

	func _process(delta: float) -> void:
		_alter += delta

		if _alter >= dauer:
			queue_free()
			return

		for p: Dictionary in _pixel:
			p["vel"] = p["vel"] * maxf(1.0 - 5.0 * delta, 0.0)
			p["pos"] += p["vel"] * delta

		queue_redraw()

	func _draw() -> void:
		for p: Dictionary in _pixel:
			if _alter < p["weg_bei"]:
				draw_rect(Rect2((p["pos"] as Vector2).floor(), Vector2.ONE), p["farbe"])
