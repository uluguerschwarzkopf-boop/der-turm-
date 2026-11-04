extends Node2D

# Nutzer-Wunsch: richtiger Nebel statt langer, gerader Bänder über den ganzen
# Bildschirm. Einzelne weiche Schwaden mit unregelmäßiger Form treiben in den
# Raum und lösen sich mitten im Raum auf.
#
# Sie entstehen IMMER knapp außerhalb des sichtbaren Bereichs und ziehen von
# dort herein, damit man nie sieht, wie sie erscheinen. Deshalb gibt es auch
# kein Einblenden am Anfang, nur das Ausblenden am Ende.
#
# Größe und Ende beziehen sich auf die Kamera, nicht auf den Raum: das Skript
# funktioniert in jedem Raum, ohne dass Koordinaten angepasst werden müssen.
# Nur die Höhe (hoehe_oben/hoehe_unten) ist raumabhängig.

@export_group("Menge")
## So viele Schwaden gibt es höchstens gleichzeitig.
@export var max_schwaden: int = 7
## Pause zwischen zwei neuen Schwaden (Sekunden, zufällig zwischen min und max).
@export var pause_min: float = 1.5
@export var pause_max: float = 5.0

@export_group("Weg")
@export var tempo_min: float = 7.0
@export var tempo_max: float = 16.0
## So weit zieht ein Schwaden, bevor er sich aufgelöst hat (Pixel).
## Kleiner als der Raum, damit er mitten im Raum endet.
@export var strecke_min: float = 180.0
@export var strecke_max: float = 520.0
## So viele Sekunden des Wegs dauert das Auflösen am Ende.
@export var aufloesen_zeit: float = 8.0

@export_group("Form")
@export var breite_min: float = 90.0
@export var breite_max: float = 230.0
@export var hoehe_min: float = 22.0
@export var hoehe_max: float = 58.0
## Anzahl verschiedener Formen (werden beim Start einmal erzeugt).
@export var formen_anzahl: int = 5

@export_group("Aussehen")
@export var farbe: Color = Color(0.55, 0.66, 0.86)
@export var deckkraft_min: float = 0.14
@export var deckkraft_max: float = 0.32
## Anteil der Schwaden VOR Spieler und Tiles (schwächer), der Rest liegt dahinter.
@export_range(0.0, 1.0, 0.05) var anteil_vorne: float = 0.2
@export var deckkraft_vorne_faktor: float = 0.55
@export var z_index_hinten: int = -1
@export var z_index_vorne: int = 3

@export_group("Höhe im Raum")
## Welt-y: in diesem Bereich liegt die Mitte der Schwaden.
@export var hoehe_oben: float = -235.0
@export var hoehe_unten: float = -165.0

@export_group("Entstehen")
## So viele Pixel außerhalb des Bildes entsteht ein Schwaden.
@export var abstand_zum_bild: float = 24.0

var _formen: Array[Texture2D] = []
var _warten: float = 0.0
var _anzahl: int = 0


func _ready() -> void:
	# Eigene Bewegung in _process: Physik-Interpolation aus, sonst Zittern.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	for i in max(formen_anzahl, 1):
		_formen.append(_erzeuge_form(i))

	_warten = randf_range(0.2, 1.0)


func _process(delta: float) -> void:
	_warten -= delta

	if _warten > 0.0 or _anzahl >= max_schwaden:
		return

	_warten = randf_range(pause_min, pause_max)
	_erzeuge_schwaden()


func _erzeuge_schwaden() -> void:
	var kamera := get_viewport().get_camera_2d()

	if kamera == null:
		return

	var bild_mitte: Vector2 = kamera.get_screen_center_position()
	var bild_groesse: Vector2 = get_viewport_rect().size / kamera.zoom

	var breite: float = randf_range(breite_min, breite_max)
	var hoehe: float = randf_range(hoehe_min, hoehe_max)
	var von_links: bool = randf() < 0.5
	var richtung: float = 1.0 if von_links else -1.0

	var start_x: float = (
		bild_mitte.x
		- richtung * (bild_groesse.x * 0.5 + breite * 0.5 + abstand_zum_bild)
	)

	var vorne: bool = randf() < anteil_vorne
	var deckkraft: float = randf_range(deckkraft_min, deckkraft_max)

	if vorne:
		deckkraft *= deckkraft_vorne_faktor

	var form: Texture2D = _formen[randi() % _formen.size()]

	var s := Sprite2D.new()
	s.texture = form
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	s.flip_h = randf() < 0.5
	s.scale = Vector2(breite / form.get_width(), hoehe / form.get_height())
	s.top_level = true
	s.global_position = Vector2(start_x, randf_range(hoehe_oben, hoehe_unten))
	s.z_index = z_index_vorne if vorne else z_index_hinten
	s.modulate = Color(farbe.r, farbe.g, farbe.b, deckkraft)
	add_child(s)

	_anzahl += 1

	var tempo: float = randf_range(tempo_min, tempo_max)
	var strecke: float = randf_range(strecke_min, strecke_max) + breite
	var dauer: float = strecke / max(tempo, 0.1)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(s, "global_position:x", start_x + richtung * strecke, dauer)
	t.tween_property(s, "modulate:a", 0.0, min(aufloesen_zeit, dauer)).set_delay(
		max(dauer - aufloesen_zeit, 0.0)
	).set_trans(Tween.TRANS_SINE)
	t.chain().tween_callback(_schwaden_fertig.bind(s))


func _schwaden_fertig(s: Sprite2D) -> void:
	_anzahl -= 1
	s.queue_free()


# Eine weiche, unregelmäßige Wolke: Rauschen, zu den Rändern hin ausgeblendet,
# damit nirgends eine gerade Kante entsteht. Bewusst weich und nicht
# gepixelt (Stilvorgabe für Nebel).
func _erzeuge_form(nummer: int) -> Texture2D:
	var breite: int = 192
	var hoehe: int = 64

	var rauschen := FastNoiseLite.new()
	rauschen.seed = 1000 + nummer * 37 + randi() % 1000
	rauschen.frequency = 0.022
	rauschen.fractal_octaves = 4

	var bild := Image.create(breite, hoehe, false, Image.FORMAT_RGBA8)

	for y in hoehe:
		for x in breite:
			var nx: float = (x + 0.5) / breite * 2.0 - 1.0
			var ny: float = (y + 0.5) / hoehe * 2.0 - 1.0
			var rand: float = 1.0 - sqrt(nx * nx + ny * ny)
			var n: float = rauschen.get_noise_2d(x, y * 1.8) * 0.9 + 0.5
			var a: float = smoothstep(0.0, 0.55, rand * 0.75 + (n - 0.5) * 0.9)
			a *= smoothstep(0.02, 0.3, rand)
			bild.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))

	return ImageTexture.create_from_image(bild)
