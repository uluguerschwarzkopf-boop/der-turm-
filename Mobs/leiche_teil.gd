extends Node2D

# Nutzer-Wunsch: Zerfällt ein Gegner beim Tod in zwei Hälften, spielt jede Hälfte
# ihre Tot-Animation selbst weiter und hat eigene Physik: Kurz bevor sie in der
# Animation den Boden erreicht (halte_frame), prüft sie, ob dort wirklich Boden
# ist. Falls nicht, bleibt sie auf diesem Frame stehen und fällt. Beim Aufprall
# macht sie eine kleine Staubwolke und spielt die Animation am Boden zu Ende.
#
# zerlege() schneidet beide Hälften Frame für Frame aus der Tot-Animation: alles,
# was im Bild zusammenhängt, kommt je nach Lage links oder rechts von trenn_x zur
# einen oder anderen Hälfte. So braucht es keine neue Grafik.
#
# Eigene kleine Physik per Strahl statt RigidBody2D (wie beim Kopf des Kriegers):
# Stücke prallen nur an Tiles ab und versperren niemandem den Weg.


var schwerkraft: float = 320.0
var max_fall_tempo: float = 400.0
var boden_maske: int = 1
var ausnahmen: Array[RID] = []

var staub_an: bool = true
var staub_farbe_1: Color = Color.WHITE
var staub_farbe_2: Color = Color.WHITE
var staub_anzahl: int = 8
var staub_tempo: float = 26.0
var staub_dauer: float = 0.35
var staub_min_fallhoehe: float = 3.0

var frames: Array[Texture2D] = []
var frame_dauer: float = 0.125
# Index in frames, auf dem geprüft wird, ob Boden da ist.
var halte_index: int = 0
# Waagrechter Abstand der Hälfte zur Node-Mitte, dort wird nach Boden gesucht.
var boden_x: float = 0.0
var staub_breite: float = 16.0

var _sprite: Sprite2D
var _index: int = 0
var _zeit: float = 0.0
var _faellt: bool = false
var _boden_geprueft: bool = false
var _tempo_y: float = 0.0
var _gefallen: float = 0.0


# Ersetzt das Sprite ab dem aktuellen Frame durch zwei selbstständige Hälften.
# Gibt false zurück, wenn das nicht geht (dann läuft die normale Animation weiter).
static func zerlege(sprite: AnimatedSprite2D, eltern: Node2D, werte: Dictionary) -> bool:
	var anim: StringName = sprite.animation
	var alle: int = sprite.sprite_frames.get_frame_count(anim)
	var start: int = sprite.frame

	if start >= alle:
		return false

	var trenn_x: float = werte.get("trenn_x", 43.5)
	var links: Array[Texture2D] = []
	var rechts: Array[Texture2D] = []
	var mitte_links: float = 0.0
	var mitte_rechts: float = 0.0
	var breite_links: float = 16.0
	var breite_rechts: float = 16.0
	var bild_breite: float = 0.0

	for f in range(start, alle):
		var textur: Texture2D = sprite.sprite_frames.get_frame_texture(anim, f)

		if textur == null:
			return false

		var bild: Image = textur.get_image()

		if bild == null:
			return false

		if bild.is_compressed():
			bild.decompress()

		bild.convert(Image.FORMAT_RGBA8)
		bild_breite = bild.get_width()

		var b_links := Image.create(bild.get_width(), bild.get_height(), false, Image.FORMAT_RGBA8)
		var b_rechts := Image.create(bild.get_width(), bild.get_height(), false, Image.FORMAT_RGBA8)
		var r_links := Rect2i()
		var r_rechts := Rect2i()

		for gruppe: Array in _finde_stuecke(bild):
			var summe: float = 0.0

			for p: Vector2i in gruppe:
				summe += p.x

			var ist_links: bool = summe / gruppe.size() < trenn_x

			for p: Vector2i in gruppe:
				(b_links if ist_links else b_rechts).set_pixelv(p, bild.get_pixelv(p))

				if ist_links:
					r_links = _erweitere(r_links, p)
				else:
					r_rechts = _erweitere(r_rechts, p)

		links.append(ImageTexture.create_from_image(b_links))
		rechts.append(ImageTexture.create_from_image(b_rechts))

		# Der letzte Frame zeigt, wo die Hälfte am Ende liegt: dort zählt der Boden.
		if f == alle - 1:
			mitte_links = r_links.get_center().x
			mitte_rechts = r_rechts.get_center().x
			breite_links = r_links.size.x
			breite_rechts = r_rechts.size.x

	var fps: float = sprite.sprite_frames.get_animation_speed(anim) * absf(sprite.speed_scale)
	var dauer: float = 1.0 / maxf(fps, 0.1)

	for seite in [
		[links, int(werte.get("halte_frame_links", 5)), mitte_links, breite_links],
		[rechts, int(werte.get("halte_frame_rechts", 8)), mitte_rechts, breite_rechts],
	]:
		var teil = load("res://Mobs/leiche_teil.gd").new()
		teil.frames = seite[0]
		teil.frame_dauer = dauer
		teil.halte_index = clampi(int(seite[1]) - start, 0, alle - start - 1)
		teil.staub_breite = float(seite[3]) + 4.0

		var versatz: float = float(seite[2]) - bild_breite * 0.5

		if sprite.flip_h:
			versatz = -versatz

		teil.boden_x = sprite.position.x + sprite.offset.x + versatz
		teil.schwerkraft = werte.get("schwerkraft", 320.0)
		teil.max_fall_tempo = werte.get("max_fall_tempo", 400.0)
		teil.boden_maske = werte.get("boden_maske", 1)
		teil.ausnahmen = werte.get("ausnahmen", [] as Array[RID])
		teil.staub_an = werte.get("staub_an", true)
		teil.staub_farbe_1 = werte.get("staub_farbe_1", Color.WHITE)
		teil.staub_farbe_2 = werte.get("staub_farbe_2", Color.WHITE)
		teil.staub_anzahl = werte.get("staub_anzahl", 8)
		teil.staub_tempo = werte.get("staub_tempo", 26.0)
		teil.staub_dauer = werte.get("staub_dauer", 0.35)
		teil.staub_min_fallhoehe = werte.get("staub_min_fallhoehe", 3.0)

		teil.top_level = true
		teil.z_index = sprite.z_index
		teil.z_as_relative = sprite.z_as_relative
		# Die Hälften bewegen sich selbst: Interpolation aus, sonst zittern sie.
		teil.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

		var s := Sprite2D.new()
		s.position = sprite.position
		s.offset = sprite.offset
		s.centered = sprite.centered
		s.flip_h = sprite.flip_h
		s.texture_filter = sprite.texture_filter
		s.material = sprite.material
		s.light_mask = sprite.light_mask
		s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		teil.add_child(s)
		teil._sprite = s

		eltern.add_child(teil)
		teil.global_position = eltern.global_position
		teil._zeige_frame()

	return true


static func _erweitere(rahmen: Rect2i, p: Vector2i) -> Rect2i:
	if rahmen.size == Vector2i.ZERO:
		return Rect2i(p, Vector2i.ONE)

	return rahmen.expand(p).expand(p + Vector2i.ONE)


# Zusammenhängende Pixel-Gruppen eines Bildes.
static func _finde_stuecke(bild: Image) -> Array:
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

			ergebnis.append(gruppe)

	return ergebnis


func _zeige_frame() -> void:
	_sprite.texture = frames[_index]


func _physics_process(delta: float) -> void:
	if _faellt:
		_falle(delta)
		return

	if _index >= frames.size() - 1:
		set_physics_process(false)
		return

	if _index == halte_index and not _boden_geprueft:
		_boden_geprueft = true

		if not _ist_boden_unter_mir(2.0):
			_faellt = true
			return

	_zeit += delta

	if _zeit >= frame_dauer:
		_zeit -= frame_dauer
		_index += 1
		_zeige_frame()


func _falle(delta: float) -> void:
	_tempo_y = minf(_tempo_y + schwerkraft * delta, max_fall_tempo)

	var schritt: float = _tempo_y * delta
	var treffer: Dictionary = _strahl_nach_unten(schritt + 1.0)

	if treffer.is_empty():
		global_position.y += schritt
		_gefallen += schritt
		return

	# Aufgekommen: Animation am Boden zu Ende spielen.
	_faellt = false
	global_position.y = treffer["position"].y

	if staub_an and _gefallen >= staub_min_fallhoehe:
		_mache_staub(treffer["position"])


func _ist_boden_unter_mir(tiefe: float) -> bool:
	return not _strahl_nach_unten(tiefe).is_empty()


# Die Node sitzt auf Fußhöhe. Etwas darüber starten: die Hälfte steht anfangs
# direkt auf dem Boden.
func _strahl_nach_unten(tiefe: float) -> Dictionary:
	var unten: Vector2 = global_position + Vector2(boden_x, 0.0)
	var abfrage := PhysicsRayQueryParameters2D.create(
		unten + Vector2(0.0, -2.0),
		unten + Vector2(0.0, tiefe),
		boden_maske,
		ausnahmen
	)

	return get_world_2d().direct_space_state.intersect_ray(abfrage)


func _mache_staub(punkt: Vector2) -> void:
	var wolke := StaubWolke.new()
	wolke.farbe_1 = staub_farbe_1
	wolke.farbe_2 = staub_farbe_2
	wolke.anzahl = staub_anzahl
	wolke.tempo = staub_tempo
	wolke.dauer = staub_dauer
	wolke.breite = staub_breite
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
