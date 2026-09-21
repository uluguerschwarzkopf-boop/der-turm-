extends Node2D

@export var anim_idle: StringName = &"Idle"
@export var interact_key: StringName = &"interact"


# Diese Werte werden beim Start auf das PromptLabel-Kind-Node
# (InteractionPrompt, siehe Player/interaction_prompt.gd) über-
# tragen - so lassen sie sich direkt hier im Inspector des
# Händlers einstellen, ohne erst zum verschachtelten PromptLabel-
# Node navigieren zu müssen. Der Text zeigt hier NUR die Taste
# selbst (z.B. "V"), kein Verb/keine Klammern davor.
@export_group("Schwebender Kaufen-Text")

@export var prompt_font_size: int = 10
@export var prompt_vertical_offset: float = -42.0
@export var prompt_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var prompt_wave_speed: float = 4.0
@export var prompt_wave_height: float = 3.0
@export var prompt_wave_letter_delay: float = 0.08
@export var prompt_seconds_per_letter: float = 0.04


# Wird beim Öffnen auf das gemeinsame ShopOverlay-HUD-Element
# übertragen (siehe Händler/Gebiet 1/shop_overlay.gd, set_panel_
# scale()) - so lässt sich hier im Inspector des Händlers
# einstellen, wie groß das GESAMTE Shop-Fenster (Panel, Items,
# Info-Bereich, Buttons - alles zusammen) beim Öffnen erscheint.
# 1.0 = Originalgröße, größer = größeres Fenster.
@export_group("Shop-Fenster-Größe")

@export var shop_panel_scale: float = 1.6


@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var prompt_label: InteractionPrompt = $InteractionArea/PromptLabel

var player_inside: bool = false
var shop_overlay: Control = null


func _ready() -> void:
	if sprite.sprite_frames.has_animation(anim_idle):
		sprite.play(anim_idle)

	_apply_prompt_settings()

	prompt_label.visible = false

	interaction_area.monitoring = true
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	await get_tree().process_frame
	shop_overlay = get_tree().current_scene.get_node_or_null("CanvasLayer/HUD/ShopOverlay") as Control


# Überträgt die oben im Inspector einstellbaren Werte auf das
# PromptLabel-Kind-Node. PromptLabel._ready() läuft VOR diesem
# _ready() (Kind-Nodes werden zuerst bereit), setzt seine eigene
# Position also schon anhand SEINES eigenen vertical_offset -
# darum hier die Position zusätzlich per Hand nachziehen.
func _apply_prompt_settings() -> void:
	prompt_label.font_size = prompt_font_size
	prompt_label.vertical_offset = prompt_vertical_offset
	prompt_label.text_color = prompt_text_color
	prompt_label.wave_speed = prompt_wave_speed
	prompt_label.wave_height = prompt_wave_height
	prompt_label.wave_letter_delay = prompt_wave_letter_delay
	prompt_label.seconds_per_letter = prompt_seconds_per_letter
	prompt_label.position = Vector2(0.0, prompt_vertical_offset)


func _process(_delta: float) -> void:
	if not player_inside:
		return

	if Input.is_action_just_pressed(interact_key):
		if shop_overlay == null:
			shop_overlay = get_tree().current_scene.get_node_or_null("CanvasLayer/HUD/ShopOverlay") as Control

		if shop_overlay and shop_overlay.has_method("open_shop"):
			if shop_overlay.has_method("set_panel_scale"):
				shop_overlay.set_panel_scale(shop_panel_scale)

			shop_overlay.open_shop()


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_inside = true
		# Nutzer-Wunsch: wieder "Kaufen [V]"/"Buy [V]" statt nur der
		# nackten Taste - der Text kommt aus SettingsManager.t()
		# ("shop.prompt_prefix") und wechselt dadurch automatisch mit
		# der Sprache mit.
		prompt_label.show_prompt(interact_key, "shop.prompt_prefix")


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_inside = false
		prompt_label.hide_prompt()
