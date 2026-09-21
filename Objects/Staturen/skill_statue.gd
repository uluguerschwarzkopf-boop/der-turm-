extends Area2D
class_name SkillStatue


# ============================================================
# HINWEIS
# ============================================================

# Eine der 3 Skill-Baum-Staturen (Stärke/Arkana/Auferstehung) im
# Skill-Tree-Raum. Zeigt den Namen ihres Pfades schwebend über der
# Statur an, sobald der Spieler ihre Fläche (CollisionShape2D)
# betritt - buchstabenweise rein/raus, wellenförmig schwebend, das
# ist GENAU derselbe Effekt wie beim Händler-Tipp (Player/
# interaction_prompt.gd).
#
# path_name_key: SettingsManager-Übersetzungsschlüssel für den
# Pfad-Namen (z.B. "skill_path.strength") - wird pro Statur-
# Instanz im Inspector gesetzt.
#
# AUSWAHL: nur EIN Pfad pro Run wählbar (siehe RunState.
# choose_skill_path()/has_chosen_skill_path()/chosen_skill_path).
# Solange noch keiner gewählt wurde, zeigt die Statur den Namen MIT
# Tasten-Hinweis an ("Pfad der Stärke [E]") - der Spieler kann dann
# mit der Interact-Taste wählen.
#
# Sobald EINE Statur gewählt wurde (auch schon in einem früheren
# Betreten dieses Raums, RunState-Wert bleibt für den ganzen Lauf
# bestehen):
#   - Die GEWÄHLTE Statur spielt einmalig ihre "Aufnehmen"-Animation
#     ab - der Spieler wird währenddessen unsichtbar und die
#     Steuerung gesperrt (er "steckt" quasi in der Animation).
#   - Die BEIDEN ANDEREN Staturen spielen ihre "Break"-Animation ab
#     und frieren danach auf dem letzten Frame ein (loop=false macht
#     das in Godot automatisch).
#   - Das Fenster, die Fackeln UND das eigene Kristall-Licht auf dem
#     Kopf der beiden ANDEREN Staturen gehen aus (siehe
#     _turn_off_nearby_lights()/_turn_off_crystal_light()) - beim
#     Fenster wird dabei NUR die farbige Glasscheibe schwarz/grau
#     (Verlauf: ehemals weißes Glanzlicht -> helles Grau -> stufenlos
#     dunkler -> Schwarz), der graue Steinrahmen bleibt unangetastet.
#     Die Fackeln verlieren ihre Flamme (nur noch der Ständer). Die
#     Lichter der GEWÄHLTEN Statur bleiben unverändert an.
#   - Der schwebende Text verschwindet komplett und keine der 3
#     Staturen reagiert danach noch auf den Spieler.
#
# Beim erneuten Betreten des Raums (z.B. nach Raumwechsel) wird der
# Endzustand sofort (ohne die Animationen nochmal abzuspielen)
# wiederhergestellt - siehe _show_resolved_state().
#
# nearby_window_path / nearby_torch_paths: NodePaths (relativ zu
# dieser Statur, siehe skill_tree_room.tscn) zu dem Fenster bzw. den
# 1-2 Fackeln, die farblich/thematisch zu dieser Statur gehören -
# werden nur abgedunkelt, wenn eine ANDERE Statur gewählt wird.


@export var interact_key: StringName = &"interact"
@export var path_name_key: String = ""

@export_group("Animationen")
@export var anim_idle: StringName = &"default"
@export var anim_aufnehmen: StringName = &"Aufnehmen"
@export var anim_break: StringName = &"Break"

@export_group("Umgebung (nur diese Statur betreffend)")
@export var nearby_window_path: NodePath = NodePath("")
@export var nearby_torch_paths: Array[NodePath] = []

# Position (relativ zu dieser Statur), an der der Spieler-Charakter
# fest in die "Aufnehmen"-Textur eingezeichnet ist - per Bildanalyse an
# allen 3 Staturen ermittelt (identisch bei Beschwörer/Mage/Schwert-
# Statur, da alle 3 Sprite-Sheets dieselbe Rahmengröße und dieselbe
# Spieler-Position verwenden).
@export_group("Aufnehmen-Animation")
@export var player_spot_offset: Vector2 = Vector2(-12.5, -1.0)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var path_label: InteractionPrompt = $PathLabel
@onready var crystal_light: PointLight2D = get_node_or_null("KristallLicht") as PointLight2D

var _player_inside: bool = false

# Siehe _intro_narration_finished() unten.
var _ready_time_ms: int = 0

# Deutlich mehr, als die Eingangs-Sprechblase (2s Verzögerung + 2
# Zeilen Tipp-Effekt/Halten/Ausblenden, siehe Player/player_thought_
# bubble.gd) unter normalen Umständen braucht - reines Sicherheitsnetz,
# siehe _intro_narration_finished().
const _NARRATION_SAFETY_TIMEOUT_MS: int = 30000

# Fenster verlieren beim Ausschalten NUR die farbige Glasscheibe
# (schwarz, mit demselben Helligkeitsverlauf wie vorher - das
# ehemals weiße Glanzlicht wird zu hellem Grau, alles andere
# darunter wird stufenlos immer dunkler bis Schwarz). Der graue
# Steinrahmen drumherum bleibt komplett unangetastet - dafür wird
# pro Pixel die Sättigung geprüft: nur farbige (gesättigte) Pixel
# werden umgefärbt, graue/entsättigte Rahmen-Pixel bleiben original.
# Als Laufzeit-Shader gebaut, genau wie z.B. der Trefferschein-
# Shader beim Spieler-Summon oder die Vignette bei der Leere.
const _WINDOW_OFF_SHADER_CODE: String = """
shader_type canvas_item;

void fragment() {
	vec4 source = texture(TEXTURE, UV);

	float max_c = max(source.r, max(source.g, source.b));
	float min_c = min(source.r, min(source.g, source.b));
	float saturation = max_c - min_c;

	float luminance = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float grey = pow(clamp(luminance, 0.0, 1.0), 1.4) * 0.85;

	float is_colored = smoothstep(0.06, 0.16, saturation);
	vec3 final_color = mix(source.rgb, vec3(grey), is_colored);

	COLOR = vec4(final_color, source.a);
}
"""

# Die Fackel-Texturen haben die Flamme immer in den obersten Zeilen
# (per Bildanalyse ermittelt: Zeile 0-18 ist ausschließlich Flamme,
# ab Zeile 19 beginnt der Ständer) - beim Ausgehen wird dieser
# Bereich einfach transparent gemacht, der Rest bleibt unverändert.
const _TORCH_FLAME_CUTOFF_ROW: int = 19


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Sicherheitsnetz für _intro_narration_finished() unten - siehe
	# dort.
	_ready_time_ms = Time.get_ticks_msec()

	if not is_in_group(&"skill_statue"):
		add_to_group(&"skill_statue")

	if _has_chosen_path():
		_show_resolved_state()
	else:
		sprite.stop()
		sprite.play(anim_idle)


func _process(_delta: float) -> void:
	if not _player_inside:
		return

	if not Input.is_action_just_pressed(interact_key):
		return

	if _has_chosen_path():
		return

	if not _intro_narration_finished():
		return

	_choose_this_path()


# Blockiert das Wählen eines Pfades, bis die Eingangs-Gedankenblase
# dieses Raums fertig durchgelaufen ist (siehe Levels/Gebiet 1/
# skill_tree_room.tscn -> thought_bubble_id = &"skill_tree_room_
# reaction", ausgelöst über Levels/room_manager.gd -> _maybe_show_
# room_thought_bubble()) - Nutzer-Wunsch: der Spieler soll die
# Staturen nicht schon benutzen können, während er noch "spricht".
# RunState.mark_narration_shown() wird dort GENAU dann aufgerufen,
# wenn die Sprechblase komplett fertig ist (nicht schon beim Start,
# siehe room_manager.gd) - has_shown_narration() ist deshalb schon
# exakt die richtige Prüfung, ohne ein zusätzliches "läuft gerade"-
# Flag zu brauchen. Existiert RunState nicht, wird NICHT blockiert
# (siehe restliche Datei: RunState fehlt praktisch nie im echten
# Spiel, nur eine defensive Absicherung).
func _intro_narration_finished() -> bool:
	if get_node_or_null("/root/RunState") == null:
		return true

	if RunState.has_shown_narration(&"skill_tree_room_reaction"):
		return true

	# Sicherheitsnetz: die Sprechblase wird beim erneuten Betreten
	# dieses Raums über einen Rückkehrpunkt (Levels/room_manager.gd ->
	# _enter_at_return_spawn()) NICHT nochmal ausgelöst - lief sie beim
	# allerersten Betreten aus irgendeinem Grund nie zu Ende durch
	# (z.B. Raum sofort wieder verlassen), würde RunState.mark_
	# narration_shown() nie aufgerufen und der Spieler bliebe sonst für
	# den GANZEN Lauf von den Staturen ausgesperrt. Nach ausreichend
	# Zeit (großzügig über der normalen Sprechdauer) wird deshalb
	# trotzdem freigegeben.
	return (
		Time.get_ticks_msec() - _ready_time_ms
		> _NARRATION_SAFETY_TIMEOUT_MS
	)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	# Nach einer Wahl reagiert keine der 3 Staturen mehr auf den
	# Spieler (siehe Klassenkommentar oben).
	if _has_chosen_path():
		return

	_player_inside = true
	_refresh_label()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		path_label.hide_prompt()


func _refresh_label() -> void:
	if _has_chosen_path():
		path_label.hide_prompt()
		return

	path_label.show_prompt(interact_key, path_name_key)


func _has_chosen_path() -> bool:
	if get_node_or_null("/root/RunState") == null:
		return false

	return RunState.has_chosen_skill_path()


func _is_chosen_statue() -> bool:
	if get_node_or_null("/root/RunState") == null:
		return false

	return RunState.chosen_skill_path == StringName(path_name_key)


# ============================================================
# WAHL TREFFEN (EINMALIG, ERSTES BETRETEN NACH DER WAHL)
# ============================================================

func _choose_this_path() -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	RunState.choose_skill_path(StringName(path_name_key))

	for statue in get_tree().get_nodes_in_group(&"skill_statue"):
		if statue is SkillStatue:
			(statue as SkillStatue).on_path_resolved(self)


# Wird auf JEDER der 3 Staturen aufgerufen (auch auf der gewählten
# selbst), sobald irgendeine Statur gerade gewählt wurde.
func on_path_resolved(chosen_statue: SkillStatue) -> void:
	_player_inside = false
	path_label.hide_prompt()
	monitoring = false

	if chosen_statue == self:
		_play_aufnehmen_sequence()
	else:
		_play_break_sequence()


# Wird beim erneuten Betreten des Raums aufgerufen, wenn die Wahl
# schon getroffen wurde - stellt den Endzustand sofort her, OHNE
# die Animationen nochmal abzuspielen.
func _show_resolved_state() -> void:
	path_label.hide_prompt()
	monitoring = false

	if _is_chosen_statue():
		_freeze_on_last_frame(anim_aufnehmen)
		_turn_off_crystal_light()

		if get_node_or_null("/root/RunState") != null:
			RunState.skill_ring_revealed = true
	else:
		_freeze_on_last_frame(anim_break)
		_turn_off_nearby_lights()
		_turn_off_crystal_light()


func _freeze_on_last_frame(anim_name: StringName) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		return

	sprite.stop()
	sprite.animation = anim_name

	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	sprite.frame = max(frame_count - 1, 0)


# ============================================================
# GEWÄHLTE STATUR: AUFNEHMEN-ANIMATION, SPIELER UNSICHTBAR
# ============================================================

func _play_aufnehmen_sequence() -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")

	if player != null and player.has_method("lock_control"):
		player.lock_control()

	if player != null:
		player.visible = false
		_move_player_to_spot(player)

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_aufnehmen)
	):
		sprite.stop()
		sprite.play(anim_aufnehmen)

		var last_frame: int = sprite.sprite_frames.get_frame_count(anim_aufnehmen) - 1

		# Der Spieler wird schon ab dem LETZTEN Frame der Animation
		# wieder sichtbar (nicht erst, wenn die Animation komplett
		# durchgelaufen ist) - die Steuerung bleibt aber bis zum
		# tatsächlichen Ende der Animation gesperrt.
		while sprite.is_playing() and sprite.frame < last_frame:
			await get_tree().process_frame

		if player != null and is_instance_valid(player):
			player.visible = true

		if sprite.is_playing():
			await sprite.animation_finished

	if player != null and is_instance_valid(player):
		player.visible = true

		if player.has_method("unlock_control"):
			player.unlock_control()

	# Der Spieler nimmt den Kristall jetzt sichtbar auf - dessen
	# eigenes Licht geht deshalb erst HIER (am Ende der Aufnehmen-
	# Animation) aus, nicht schon bei der Wahl selbst. Die beiden
	# ANDEREN Staturen verlieren ihr Kristall-Licht weiterhin sofort
	# beim Zerbrechen (siehe _play_break_sequence()).
	_turn_off_crystal_light()

	# Der XP-Ring im HUD soll erst jetzt erscheinen, nicht schon beim
	# Drücken der Interact-Taste - das HUD liest dieses Feld jeden
	# Frame selbst aus (siehe Player/UI/skill_ring_hud.gd), eine
	# reine Property-Zuweisung auf dem Autoload kann anders als eine
	# Gruppen-Suche/Signal-Verbindung nicht still fehlschlagen.
	if get_node_or_null("/root/RunState") != null:
		RunState.skill_ring_revealed = true

	_maybe_show_skill_tree_open_hint(player)


# ============================================================
# TUTORIAL-HINWEIS: "T ZUM ÖFFNEN" (EINMALIG PRO LAUF)
# ============================================================

# Zeigt EINMALIG pro Lauf (siehe RunState.has_shown_narration()/
# mark_narration_shown()) einen Hinweis mit der aktuell gebundenen
# Taste für "open_skill_tree" (Standard "T") über dem Spieler - reine
# Bedienungshilfe direkt nach dem Freischalten des Skill-Baums.
#
# Nutzt bewusst SkillTreeHint (Player/skill_tree_hint.gd) statt
# PlayerThoughtBubble (die Raum-Gedankenblasen weiter unten nutzen
# genau diese, siehe Levels/room_manager.gd) - Nutzer-Wunsch: dieser
# Hinweis soll OHNE Box erscheinen, NICHT nach fester Zeit
# verschwinden (sondern erst, wenn "open_skill_tree" tatsächlich
# gedrückt wurde) und live auf ein Rebind reagieren - SkillTreeHint
# übernimmt das komplett selbst (Text/Taste/Verschwinden), siehe
# dort - hier muss nur noch dismiss_action gesetzt werden.
#
# Bewusst NICHT awaited aufgerufen (Fire-and-forget), blockiert
# dadurch nichts hier in der Aufnehmen-Sequenz - RunState wird sofort
# als "gezeigt" markiert, nicht erst wenn der Hinweis verschwindet
# (SkillTreeHint kann beliebig lange stehen bleiben).
func _maybe_show_skill_tree_open_hint(player: Node) -> void:
	if get_node_or_null("/root/RunState") == null:
		return

	if RunState.has_shown_narration(&"skill_tree_open_hint"):
		return

	if player == null or not is_instance_valid(player):
		return

	var hint := SkillTreeHint.new()
	hint.dismiss_action = &"open_skill_tree"

	player.add_child(hint)

	RunState.mark_narration_shown(&"skill_tree_open_hint")


# Schiebt den (gerade unsichtbaren) Spieler an die Stelle, an der der
# Spieler-Charakter in der "Aufnehmen"-Textur eingezeichnet ist, und
# lässt ihn nach rechts schauen - genau wie in der Animation zu sehen.
func _move_player_to_spot(player: Node) -> void:
	if "global_position" in player:
		player.global_position = global_position + player_spot_offset

	if "facing_right" in player:
		player.facing_right = true

	if "sprite" in player and player.sprite != null:
		player.sprite.flip_h = false


# ============================================================
# NICHT GEWÄHLTE STATUR: ZERBRECHEN, LICHTER AUS
# ============================================================

func _play_break_sequence() -> void:
	_turn_off_nearby_lights()
	_turn_off_crystal_light()

	if (
		sprite.sprite_frames != null
		and sprite.sprite_frames.has_animation(anim_break)
	):
		sprite.stop()
		sprite.play(anim_break)
		# loop = false -> Godot friert automatisch auf dem letzten
		# Frame ein, sobald die Animation durchgelaufen ist.


func _turn_off_crystal_light() -> void:
	if crystal_light != null:
		crystal_light.visible = false


func _turn_off_nearby_lights() -> void:
	if nearby_window_path != NodePath(""):
		_turn_off_window(get_node_or_null(nearby_window_path))

	for torch_path in nearby_torch_paths:
		_turn_off_torch(get_node_or_null(torch_path))


func _turn_off_window(window_node: Node) -> void:
	if window_node == null:
		return

	var window_sprite: AnimatedSprite2D = (
		window_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	)

	if window_sprite != null:
		window_sprite.material = _build_window_off_material()

	var window_light: PointLight2D = (
		window_node.get_node_or_null("FensterLicht") as PointLight2D
	)

	if window_light != null:
		window_light.visible = false


func _build_window_off_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _WINDOW_OFF_SHADER_CODE

	var material := ShaderMaterial.new()
	material.shader = shader

	return material


func _turn_off_torch(torch_node: Node) -> void:
	if torch_node == null:
		return

	var torch_sprite: AnimatedSprite2D = torch_node as AnimatedSprite2D

	if torch_sprite != null:
		var off_texture: Texture2D = _build_torch_off_texture(torch_sprite)

		if off_texture != null:
			var off_frames := SpriteFrames.new()
			off_frames.add_animation(&"off")
			off_frames.set_animation_loop(&"off", false)
			off_frames.add_frame(&"off", off_texture)

			torch_sprite.stop()
			torch_sprite.sprite_frames = off_frames
			torch_sprite.animation = &"off"
			torch_sprite.frame = 0

	var torch_light: PointLight2D = (
		torch_node.get_node_or_null("PointLight2D") as PointLight2D
	)

	if torch_light != null:
		torch_light.visible = false


# Baut aus dem aktuell angezeigten Fackel-Frame eine neue, eigene
# (nicht mit anderen Fackel-Instanzen geteilte) Textur, bei der die
# obersten Zeilen (die Flamme) komplett transparent sind - übrig
# bleibt nur der Ständer, exakt wie in der Textur der Original-Fackel,
# nur ohne das Feuer.
func _build_torch_off_texture(torch_sprite: AnimatedSprite2D) -> Texture2D:
	if torch_sprite.sprite_frames == null:
		return null

	var current_anim: StringName = torch_sprite.animation

	if not torch_sprite.sprite_frames.has_animation(current_anim):
		return null

	var base_texture: Texture2D = torch_sprite.sprite_frames.get_frame_texture(
		current_anim, 0
	)

	if base_texture == null:
		return null

	# AtlasTexture liefert über get_image() nicht zuverlässig den
	# zugeschnittenen Ausschnitt zurück - deshalb wird hier bei
	# Bedarf direkt aus dem zugrunde liegenden Atlas-Bild
	# ausgeschnitten (region), statt sich auf get_image() zu
	# verlassen.
	var image: Image = null

	if base_texture is AtlasTexture:
		var atlas_texture: AtlasTexture = base_texture as AtlasTexture
		var source_image: Image = (
			atlas_texture.atlas.get_image()
			if atlas_texture.atlas != null
			else null
		)

		if source_image != null:
			image = source_image.get_region(Rect2i(atlas_texture.region))
	else:
		image = base_texture.get_image()

	if image == null:
		return null

	image = image.duplicate()

	var clear_height: int = min(_TORCH_FLAME_CUTOFF_ROW, image.get_height())
	image.fill_rect(
		Rect2i(0, 0, image.get_width(), clear_height),
		Color(0, 0, 0, 0)
	)

	return ImageTexture.create_from_image(image)
