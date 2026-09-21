extends Node


# ============================================================
# HINWEIS
# ============================================================

# Zentrale Stelle für Einstellungen, die über Spielsitzungen
# hinweg gespeichert werden sollen: Tastenbelegung und Sprache.
# Wird als Autoload beim Spielstart automatisch geladen und
# wendet gespeicherte Tastenbelegungen sofort auf die InputMap
# an, bevor irgendein anderes Script Input-Actions abfragt.
#
# Übersetzung läuft absichtlich über ein eigenes kleines
# Wörterbuch (t()) statt über Godots CSV-Import-Pipeline, damit
# neue Texte (Pause-Menü, Einstellungen, Shop-Prompt) sofort
# funktionieren, ohne dass das Projekt im Editor neu importiert
# werden muss. Kann jederzeit erweitert werden, wenn weitere
# bestehende UI umgestellt wird.


signal controls_changed(action_name: StringName)
signal language_changed(language: String)
signal hud_scale_changed(category: StringName, scale: float)
signal audio_volume_changed(category: StringName, volume: float)


const SETTINGS_PATH: String = "user://settings.cfg"

const DEFAULT_LANGUAGE: String = "de"


# ============================================================
# UI-GRÖSSE (HERZEN, TRÄNKE, BOGEN/PFEIL, ZAUBER, GOLD)
# ============================================================

const HUD_SCALE_CATEGORIES: Array[StringName] = [
	&"hearts",
	&"potions",
	&"bow",
	&"spells",
	&"gold",
	&"echo_der_flamme",
	&"skill_ring",
	&"skill_slot",
	&"vigor"
]

# Diese fünf Werte sind absichtlich "var" statt "const": der neue
# HUDScaleSettings-Node (Player/UI/hud_scale_settings.gd, liegt in
# Player/UI/canvas_layer.tscn) überschreibt sie beim Start jedes
# Raums per configure_hud_scale() mit den im Inspector
# eingestellten Werten - so lassen sich Grundeinstellung, Grenzen
# und Randverschiebung bequem einstellen, ohne Code anzufassen.
# Bis eine Szene mit diesem Node geladen wird, gelten die Werte
# hier als Ausgangswerte.
var HUD_SCALE_MIN: float = 0.75
var HUD_SCALE_MAX: float = 2.0
var HUD_SCALE_STEP: float = 0.05
var HUD_SCALE_DEFAULT: float = 1.0

# Bei 1.0 (100%) bleibt der Eck-Abstand exakt so, wie er
# ursprünglich für jede HUD-Gruppe von Hand eingestellt wurde -
# das ist die geforderte "normale" Ausgangseinstellung. Darüber
# hinaus wächst der Abstand vom Bildschirmrand etwas STÄRKER als
# die UI-Größe selbst (Faktor > 1.0 = stärker, < 1.0 = schwächer),
# damit auch bei 200% noch Luft zum Rand bleibt. Über den
# HUDScaleSettings-Node im Inspector einstellbar.
var HUD_SCALE_MARGIN_PULL: float = 0.5

var hud_scales: Dictionary = {
	&"hearts": HUD_SCALE_DEFAULT,
	&"potions": HUD_SCALE_DEFAULT,
	&"bow": HUD_SCALE_DEFAULT,
	&"spells": HUD_SCALE_DEFAULT,
	&"gold": HUD_SCALE_DEFAULT,
	&"echo_der_flamme": HUD_SCALE_DEFAULT,
	&"skill_ring": HUD_SCALE_DEFAULT,
	&"skill_slot": HUD_SCALE_DEFAULT,
	&"vigor": HUD_SCALE_DEFAULT
}


# ============================================================
# LAUTSTÄRKE (AUDIO-BUSSE)
# ============================================================

# Jeder Eintrag hier bekommt einen eigenen Godot-Audio-Bus mit
# genau diesem Namen (wird beim Start automatisch angelegt, falls
# er noch nicht existiert - siehe _ensure_audio_buses_exist()).
# "master" ist der Sonderfall: das ist Godots eingebauter
# "Master"-Bus, der immer existiert und ALLES steuert (alle
# anderen Busse hier senden an Master).
#
# Später einfach neue Einträge (z.B. &"sfx_enemy", &"sfx_player")
# hier UND in AUDIO_BUS_NAMES anhängen, plus eine "audio.xxx"-
# Übersetzung weiter unten - die Lautstärke-Liste im Hauptmenü
# baut sich automatisch aus dieser Liste auf (siehe main_menu.gd
# -> _refresh_audio_settings_list()), ohne dass dort noch was
# geändert werden muss.
const AUDIO_BUS_CATEGORIES: Array[StringName] = [
	&"master",
	&"music",
	&"sfx"
]

# category -> tatsächlicher Godot-Audio-Bus-Name.
const AUDIO_BUS_NAMES: Dictionary = {
	&"master": "Master",
	&"music": "Music",
	&"sfx": "SFX"
}

# Lineare Lautstärke (0..1, 1 = volle Lautstärke) pro Bus -
# wird beim Anwenden in Dezibel umgerechnet (siehe
# _apply_audio_volume()).
#
# Nutzer-Wunsch: Sounds sollen allgemein etwas leiser sein als die
# Musik - deshalb "sfx" hier mit einem niedrigeren Standardwert als
# "music" (1.0), NICHT weil der Sound-Bus selbst leiser gemischt ist.
var audio_volumes: Dictionary = {
	&"master": 1.0,
	&"music": 1.0,
	&"sfx": 0.7
}


# ============================================================
# BILDSCHIRM-MODUS
# ============================================================

var is_fullscreen: bool = true


# ============================================================
# REBINDBARE ACTIONS
# ============================================================

# Manche Action-Namen haben absichtlich ein Leerzeichen am Ende
# (so im Projekt/InputMap angelegt) - deshalb hier exakt so
# übernehmen. Für die Anzeige wird der Name getrimmt.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"jump",
	&"roll ",
	&"attack ",
	&"shoot_bow",
	&"use_potion",
	&"interact",
	&"spell_slot_1",
	&"spell_slot_2",
	&"spell_slot_3",
	&"drop_through",
	&"open_skill_tree",
	&"use_skill"
]


# ============================================================
# ÜBERSETZUNGEN
# ============================================================

const TRANSLATIONS: Dictionary = {
	"pause.title": {"de": "Pause", "en": "Paused"},
	"pause.resume": {"de": "Fortsetzen", "en": "Resume"},
	"pause.settings": {"de": "Einstellungen", "en": "Settings"},
	"pause.save": {"de": "Speichern", "en": "Save"},
	"pause.save_done": {"de": "Gespeichert!", "en": "Saved!"},
	"pause.main_menu": {"de": "Zurück zum Hauptmenü", "en": "Back to Main Menu"},
	"pause.confirm_title": {"de": "Wirklich zum Hauptmenü?", "en": "Really quit to the main menu?"},
	"pause.confirm_text": {"de": "Alles, was nicht gespeichert ist, geht verloren.", "en": "Anything not saved will be lost."},
	"pause.confirm_yes": {"de": "Ja, zurück zum Hauptmenü", "en": "Yes, back to main menu"},
	"pause.confirm_no": {"de": "Abbrechen", "en": "Cancel"},
	"pause.main_menu_soon": {"de": "Das Hauptmenü kommt noch.", "en": "The main menu is coming soon."},
	"settings.title": {"de": "Einstellungen", "en": "Settings"},
	"settings.controls_tab": {"de": "Steuerung", "en": "Controls"},
	"settings.language_tab": {"de": "Sprache", "en": "Language"},
	"settings.back": {"de": "Zurück", "en": "Back"},
	"settings.press_key": {"de": "Taste drücken...", "en": "Press a key..."},
	"settings.rebind": {"de": "Ändern", "en": "Rebind"},
	"settings.reset": {"de": "Zurücksetzen", "en": "Reset"},
	"settings.hud_scale_tab": {"de": "UI-Größe", "en": "UI Size"},
	"settings.display_tab": {"de": "Anzeige", "en": "Display"},
	"settings.fullscreen": {"de": "Vollbild", "en": "Fullscreen"},
	"settings.reset_all": {"de": "Auf Standard zurücksetzen", "en": "Reset to defaults"},
	"settings.audio_tab": {"de": "Lautstärke", "en": "Audio"},
	"settings.category_game_options": {"de": "Spieloptionen", "en": "Game Options"},
	"settings.category_audio": {"de": "Audio", "en": "Audio"},
	"settings.category_controls": {"de": "Steuerung", "en": "Controls"},
	"audio.master": {"de": "Gesamtlautstärke", "en": "Master Volume"},
	"audio.music": {"de": "Musik", "en": "Music"},
	"audio.sfx": {"de": "Soundeffekte", "en": "Sound Effects"},
	"hudscale.hearts": {"de": "Herzen", "en": "Hearts"},
	"hudscale.potions": {"de": "Tränke", "en": "Potions"},
	"hudscale.bow": {"de": "Bogen & Pfeile", "en": "Bow & Arrows"},
	"hudscale.spells": {"de": "Zauber", "en": "Spells"},
	"hudscale.gold": {"de": "Gold", "en": "Gold"},
	"hudscale.echo_der_flamme": {"de": "Echo der Flamme", "en": "Echo of the Flame"},
	"hudscale.skill_ring": {"de": "Skill-Ring", "en": "Skill Ring"},
	"hudscale.skill_slot": {"de": "Skill-Slot", "en": "Skill Slot"},
	"hudscale.vigor": {"de": "Vigor-Leiste", "en": "Vigor Bar"},
	"action.move_left": {"de": "Nach links", "en": "Move left"},
	"action.move_right": {"de": "Nach rechts", "en": "Move right"},
	"action.jump": {"de": "Springen", "en": "Jump"},
	"action.roll": {"de": "Rollen", "en": "Roll"},
	"action.attack": {"de": "Angriff", "en": "Attack"},
	"action.use_potion": {"de": "Trank benutzen", "en": "Use potion"},
	"action.interact": {"de": "Interagieren", "en": "Interact"},
	"action.shoot_bow": {"de": "Bogen schießen", "en": "Shoot bow"},
	"action.spell_slot_1": {"de": "Zauber 1", "en": "Spell 1"},
	"action.spell_slot_2": {"de": "Zauber 2", "en": "Spell 2"},
	"action.spell_slot_3": {"de": "Zauber 3", "en": "Spell 3"},
	"action.drop_through": {"de": "Plattform durchfallen", "en": "Drop through platform"},
	"action.open_skill_tree": {"de": "Skill-Baum öffnen", "en": "Open skill tree"},
	"action.use_skill": {"de": "Skill benutzen", "en": "Use skill"},
	"mouse.left": {"de": "Maustaste links", "en": "Left mouse button"},
	"mouse.right": {"de": "Maustaste rechts", "en": "Right mouse button"},
	"mouse.middle": {"de": "Mittlere Maustaste", "en": "Middle mouse button"},
	"mouse.other": {"de": "Maustaste", "en": "Mouse button"},
	"shop.prompt_prefix": {"de": "Kaufen", "en": "Buy"},
	"shop.title": {"de": "Händler", "en": "Merchant"},
	"shop.buy_button": {"de": "Kaufen", "en": "Buy"},
	"shop.no_item": {"de": "Kein Gegenstand", "en": "No item"},
	"shop.select_item": {"de": "Wähle einen Gegenstand.", "en": "Select an item."},
	"shop.already_sold": {"de": "Bereits verkauft.", "en": "Already sold."},
	"shop.not_enough_gold": {"de": "Nicht genug Gold.", "en": "Not enough gold."},
	"shop.cannot_purchase": {"de": "Kann nicht gekauft werden.", "en": "Cannot be purchased."},
	"shop.purchased": {"de": "Gekauft!", "en": "Purchased!"},
	"shop.cost_label": {"de": "Preis: %d Gold", "en": "Cost: %d Gold"},
	"shop.cost_placeholder": {"de": "Preis: -", "en": "Cost: -"},
	"shop.item.potion.name": {"de": "Heiltrank", "en": "Healing Potion"},
	"shop.item.potion.desc": {"de": "Fügt deinem Inventar einen Trank hinzu. Trinke ihn, um dich zu heilen.", "en": "Adds a potion to your inventory. Drink it to heal."},
	"shop.item.shield.name": {"de": "Rüstung", "en": "Armor"},
	"shop.item.shield.desc": {"de": "+1 Rüstungspunkt. Fängt den nächsten Treffer ab, bevor er deine Herzen trifft.", "en": "+1 armor point. Absorbs the next hit before it reaches your hearts."},
	"shop.item.arrows.name": {"de": "Pfeile", "en": "Arrows"},
	"shop.item.arrows.desc": {"de": "+5 Pfeile für deinen Bogen.", "en": "+5 arrows for your bow."},
	"shop.item.bow.name": {"de": "Bogen", "en": "Bow"},
	"shop.item.bow.desc": {"de": "Zweitwaffe. Schießen mit %s.", "en": "Secondary weapon. Shoot with %s."},
	"shop.item.fireball.name": {"de": "Feuerball", "en": "Fireball"},
	"shop.item.fireball.desc": {"de": "Einmal-Zauber. Schleudert einen großen Feuerball.", "en": "Single-use spell. Launches a large fireball."},
	"shop.item.lightning.name": {"de": "Blitz", "en": "Lightning"},
	"shop.item.lightning.desc": {"de": "Einmal-Zauber. Feuert einen schnellen Blitz ab.", "en": "Single-use spell. Fires a fast lightning bolt."},
	"shop.item.ice.name": {"de": "Eiswelle", "en": "Ice Wave"},
	"shop.item.ice.desc": {"de": "Einmal-Zauber. Beschwört eine Eiswelle.", "en": "Single-use spell. Summons an ice wave."},
	"shop.item.necromancy.name": {"de": "Nekromantie", "en": "Necromancy"},
	"shop.item.necromancy.desc": {"de": "Einmal-Zauber. Beschwört ein verbündetes Skelett.", "en": "Single-use spell. Summons an allied skeleton."},
	"shop.item.roots.name": {"de": "Wurzeln", "en": "Roots"},
	"shop.item.roots.desc": {"de": "Einmal-Zauber. Lässt Wurzeln über den Boden schießen.", "en": "Single-use spell. Sends roots across the ground."},
	"shop.item.lightorb.name": {"de": "Lichtkugel", "en": "Light Orb"},
	"shop.item.lightorb.desc": {"de": "Einmal-Zauber. Beschwört eine schwebende Lichtkugel.", "en": "Single-use spell. Summons a floating light orb."},
	"menu.play": {"de": "Spielen", "en": "Play"},
	"menu.settings": {"de": "Einstellungen", "en": "Settings"},
	"menu.credits": {"de": "Credits", "en": "Credits"},
	"menu.quit": {"de": "Beenden", "en": "Quit"},
	"menu.back": {"de": "Zurück", "en": "Back"},
	"menu.slot_title": {"de": "Spielstand wählen", "en": "Choose save slot"},
	"menu.new_game": {"de": "Neuer Spielstand", "en": "New game"},
	"menu.area_room": {"de": "Gebiet %d · Raum %d/10", "en": "Area %d · Room %d/10"},
	"menu.area": {"de": "Gebiet %d", "en": "Area %d"},
	"menu.room": {"de": "Raum %d/10", "en": "Room %d/10"},
	"menu.playtime": {"de": "Spielzeit", "en": "Playtime"},
	"menu.credits_title": {"de": "Credits", "en": "Credits"},
	"menu.delete_save": {"de": "Spielstand löschen", "en": "Delete save"},
	"menu.delete_select_title": {"de": "Welchen Spielstand löschen?", "en": "Which save to delete?"},
	"menu.delete_confirm_title": {"de": "Wirklich löschen?", "en": "Really delete?"},
	"menu.delete_confirm_text": {"de": "Der Spielstand wird endgültig gelöscht und kann nicht wiederhergestellt werden.", "en": "This save will be permanently deleted and cannot be restored."},
	"menu.delete_confirm_yes": {"de": "Ja, löschen", "en": "Yes, delete"},
	"menu.delete_confirm_no": {"de": "Abbrechen", "en": "Cancel"},
	"area_intro.gebiet_1_title": {"de": "GEBIET 1", "en": "AREA 1"},
	"area_intro.gebiet_1_subtitle": {"de": "DIE EINGANGSHALLEN", "en": "THE ENTRANCE HALLS"},
	"echo.echo_der_flamme_erhalten": {"de": "ECHO DER FLAMME ERHALTEN", "en": "ECHO OF THE FLAME OBTAINED"},
	"void.fire_knight_line_1": {"de": "Einer seiner Wächter wartet dahinter.", "en": "One of his guardians waits beyond."},
	"void.fire_knight_line_2": {"de": "Erschlage ihn.", "en": "Slay him."},
	"void.fire_knight_line_3": {"de": "Und setze deinen Aufstieg fort.", "en": "And continue your ascent."},
	"thought.skill_tree_line_1": {"de": "Was ist das…?", "en": "What is this…?"},
	"thought.skill_tree_line_2": {"de": "Überreste des Ordens?", "en": "Remnants of the Order?"},
	"skill_path.strength": {"de": "Pfad der Stärke", "en": "Path of Strength"},
	"skill_path.arcana": {"de": "Pfad der Arkana", "en": "Path of Arcana"},
	"skill_path.resurrection": {"de": "Pfad der Auferstehung", "en": "Path of Resurrection"},
	"skilltree.placeholder": {"de": "Testphase - echte Werte folgen", "en": "Test phase - real values coming later"},
	"skilltree.close_hint": {"de": "Erneut [%s] drücken zum Schließen", "en": "Press [%s] again to close"},
	"skilltree.points_label": {"de": "Verfügbare Punkte: %d", "en": "Available points: %d"},
	"skilltree.locked_skill": {"de": "🔒 Verdeckt", "en": "🔒 Hidden"},
	"skilltree.tooltip_type_active": {"de": "Aktive Fähigkeit", "en": "Active Ability"},
	"skilltree.tooltip_type_passive": {"de": "Passive Fähigkeit", "en": "Passive Ability"},
	"skilltree.tooltip_cost": {"de": "Kosten: %d Skillpunkt(e)", "en": "Cost: %d skill point(s)"},
	"skilltree.tooltip_unlocked": {"de": "✓ Freigeschaltet", "en": "✓ Unlocked"},
	"skilltree.info_placeholder": {"de": "Fahre mit der Maus über einen Skill für Details", "en": "Hover over a skill for details"},
	"skilltree.equipped_tag": {"de": "Ausgerüstet", "en": "Equipped"},
	"skilltree.equip_hint": {"de": "Klicken, um diesen Skill in den Skill-Slot zu legen", "en": "Click to place this skill in the skill slot"},
	# %s wird durch die aktuell gebundene Taste für "open_skill_tree"
	# ersetzt (siehe Objects/Staturen/skill_statue.gd -> _maybe_show_
	# skill_tree_open_hint()) - einmalige Bedienungshilfe, schwebt kurz
	# über dem Spieler, direkt nachdem der Skill-Baum freigeschaltet
	# wurde (Statur aufgenommen).
	"hint.skill_tree_open": {"de": "%s – Skill-Baum öffnen", "en": "%s to open the skill tree"},
	"skill.charged_strike.name": {"de": "Geladener Schlag", "en": "Charged Strike"},
	"skill.charged_strike.desc": {"de": "Schlag aufladen und ausführen. Werte (Schaden, Vigor-Kosten, Cooldown) noch nicht final.", "en": "Charge up a strike and unleash it. Values (damage, Vigor cost, cooldown) not final yet."},
	"skill.vitality.name": {"de": "Vitalität", "en": "Vitality"},
	"skill.vitality.desc": {"de": "+1 maximales Herz.", "en": "+1 maximum heart."},
	"skill.bloodlust.name": {"de": "Blutrausch", "en": "Bloodlust"},
	"skill.bloodlust.desc": {"de": "Verbessert die Vigor-Erzeugung durch Nahkampf. Genaue Balance folgt.", "en": "Improves Vigor generation from melee combat. Exact balance coming later."},
	"skill.double_roll.name": {"de": "Doppelrolle", "en": "Double Roll"},
	"skill.double_roll.desc": {"de": "2 Rollen-Ladungen statt einer.", "en": "2 roll charges instead of one."},
	"skill.iron_skin.name": {"de": "Eisenhaut", "en": "Iron Skin"},
	"skill.iron_skin.desc": {"de": "Defensiver Skill. Genaue Wirkung folgt.", "en": "Defensive skill. Exact effect coming later."},
	"skill.ground_slam.name": {"de": "Bodenschlag", "en": "Ground Slam"},
	"skill.ground_slam.desc": {"de": "Starker Flächenangriff auf den Boden. Werte folgen.", "en": "Powerful ground-slam area attack. Values coming later."},
	"skill.dash_slash.name": {"de": "Sturmhieb", "en": "Dash Slash"},
	"skill.dash_slash.desc": {"de": "Schneller offensiver Dash mit Schwerthieb.", "en": "Fast offensive dash with a sword strike."},
	"skill.parry.name": {"de": "Konter", "en": "Parry"},
	"skill.parry.desc": {"de": "Kurzes Zeitfenster: negiert einen eingehenden Angriff und ermöglicht einen starken Konter.", "en": "Short timing window: negates an incoming attack and enables a strong counter."},
	"skill.execution.name": {"de": "Hinrichtung", "en": "Execution"},
	"skill.execution.desc": {"de": "Gegner unter 20% HP können exekutiert werden (nicht bei Gebietsbossen).", "en": "Enemies below 20% HP can be executed (not against area bosses)."},
	"skill.backstep.name": {"de": "Rückstich", "en": "Backstep"},
	"skill.backstep.desc": {"de": "Schnelles Ausweichen mit kurzer Unverwundbarkeit, gefolgt von einem Konterschlag hinter dem Gegner.", "en": "Fast evasive step with brief invulnerability, followed by a counter-strike behind the enemy."},
	"skill.warlord.name": {"de": "Kriegsherr", "en": "Warlord"},
	"skill.warlord.desc": {"de": "Mächtigster Abschluss des Pfads der Stärke. Genaue Wirkung folgt.", "en": "The mightiest capstone of the Path of Might. Exact effect coming later."},
	"menu.credits_body": {
		"de": "Created by\nNyvora (5ey5)\n\nGAME DEVELOPMENT\n5ey5\n\nGAME DESIGN\n5ey5\n\nART & ANIMATION\n5ey5\n\nMUSIC & SOUND\nw0p",
		"en": "Created by\nNyvora (5ey5)\n\nGAME DEVELOPMENT\n5ey5\n\nGAME DESIGN\n5ey5\n\nART & ANIMATION\n5ey5\n\nMUSIC & SOUND\nw0p"
	}
}


# ============================================================
# STATUS
# ============================================================

var current_language: String = DEFAULT_LANGUAGE


# ============================================================
# START
# ============================================================

func _ready() -> void:
	_ensure_audio_buses_exist()
	_apply_all_audio_volumes()
	_load_settings()


# ============================================================
# ÜBERSETZUNG
# ============================================================

func t(key: String) -> String:
	if not TRANSLATIONS.has(key):
		return key

	var entry: Dictionary = TRANSLATIONS[key]

	return str(
		entry.get(
			current_language,
			entry.get("de", key)
		)
	)


func set_language(language: String) -> void:
	if language != "de" and language != "en":
		return

	if language == current_language:
		return

	current_language = language

	_save_settings()

	language_changed.emit(current_language)


func get_language() -> String:
	return current_language


# ============================================================
# UI-GRÖSSE
# ============================================================

func get_hud_scale(category: StringName) -> float:
	return float(
		hud_scales.get(category, HUD_SCALE_DEFAULT)
	)


func set_hud_scale(category: StringName, value: float) -> void:
	if not hud_scales.has(category):
		return

	var clamped_value: float = clamp(
		value,
		HUD_SCALE_MIN,
		HUD_SCALE_MAX
	)

	if is_equal_approx(clamped_value, float(hud_scales[category])):
		return

	hud_scales[category] = clamped_value

	_save_settings()

	hud_scale_changed.emit(category, clamped_value)


# Wandelt einen bei 100% von Hand eingestellten Eck-Abstand
# (in Pixeln) in den tatsächlich zu verwendenden Abstand bei
# einem bestimmten UI-Größe-Faktor um. Bei scale_factor 1.0
# kommt exakt base_margin zurück (unverändert = "normale"
# Ausgangsposition), darüber/darunter wird proportional
# stärker nach innen bzw. wieder zurück nach außen verschoben.
func get_corner_margin(
	base_margin: float,
	scale_factor: float
) -> float:
	return base_margin * (
		1.0 + (scale_factor - 1.0) * HUD_SCALE_MARGIN_PULL
	)


# Wird vom HUDScaleSettings-Node (Player/UI/hud_scale_settings.gd)
# beim Start jedes Raums aufgerufen, damit sich Grundeinstellung,
# Regler-Grenzen und die Randverschiebung bequem im Inspector
# einstellen lassen, statt Werte im Code zu ändern. Bereits
# gespeicherte UI-Größen werden dabei in die neuen Grenzen
# zurückgeklemmt, damit nichts Ungültiges übrig bleibt.
func configure_hud_scale(
	new_default: float,
	new_min: float,
	new_max: float,
	new_step: float,
	new_margin_pull: float
) -> void:
	HUD_SCALE_DEFAULT = new_default
	HUD_SCALE_MIN = new_min
	HUD_SCALE_MAX = new_max
	HUD_SCALE_STEP = new_step
	HUD_SCALE_MARGIN_PULL = new_margin_pull

	for category in HUD_SCALE_CATEGORIES:
		hud_scales[category] = clamp(
			float(hud_scales.get(category, HUD_SCALE_DEFAULT)),
			HUD_SCALE_MIN,
			HUD_SCALE_MAX
		)


# ============================================================
# BILDSCHIRM-MODUS
# ============================================================

func set_fullscreen(value: bool) -> void:
	if value == is_fullscreen:
		return

	is_fullscreen = value

	_apply_fullscreen()
	_save_settings()


func get_fullscreen() -> bool:
	return is_fullscreen


func _apply_fullscreen() -> void:
	# Bewusst über get_window().mode statt direkt über
	# DisplayServer.window_set_mode(): Nur so aktualisiert die
	# Godot-Fenster-Node ihre eigene Größe sofort intern mit -
	# sonst bleiben volle-Fläche-Controls (Anchors PRESET_FULL_
	# RECT, z.B. das Hauptmenü) auf der alten, kleinen Größe
	# hängen, obwohl das echte Fenster schon Vollbild ist.
	var window: Window = get_window()

	if window == null:
		return

	if is_fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED


# ============================================================
# LAUTSTÄRKE (AUDIO-BUSSE)
# ============================================================

# Legt fehlende Audio-Busse einmalig beim Start an (aktuell nur
# "Music" - "Master" gibt es in Godot immer automatisch). Jeder
# neue Bus sendet sein Signal an Master weiter, damit die
# Gesamtlautstärke wie erwartet ALLES mitregelt.
func _ensure_audio_buses_exist() -> void:
	for category in AUDIO_BUS_CATEGORIES:
		var bus_name: String = String(
			AUDIO_BUS_NAMES.get(category, "")
		)

		if bus_name == "" or bus_name == "Master":
			continue

		if AudioServer.get_bus_index(bus_name) != -1:
			continue

		var new_index: int = AudioServer.bus_count
		AudioServer.add_bus(new_index)
		AudioServer.set_bus_name(new_index, bus_name)
		AudioServer.set_bus_send(new_index, "Master")


func get_audio_volume(category: StringName) -> float:
	return float(audio_volumes.get(category, 1.0))


func set_audio_volume(category: StringName, value: float) -> void:
	audio_volumes[category] = clamp(value, 0.0, 1.0)

	_apply_audio_volume(category)
	_save_settings()

	audio_volume_changed.emit(category, audio_volumes[category])


func _apply_audio_volume(category: StringName) -> void:
	var bus_name: String = String(
		AUDIO_BUS_NAMES.get(category, "")
	)

	if bus_name == "":
		return

	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		return

	var volume: float = float(audio_volumes.get(category, 1.0))

	# Bei genau 0 wird der Bus stummgeschaltet statt nur sehr
	# leise gemacht (linear_to_db(0.0) wäre -unendlich) - so ist
	# "ganz runtergedreht" auch wirklich komplett still.
	AudioServer.set_bus_mute(bus_index, volume <= 0.0)
	AudioServer.set_bus_volume_db(
		bus_index, linear_to_db(max(volume, 0.0001))
	)


func _apply_all_audio_volumes() -> void:
	for category in AUDIO_BUS_CATEGORIES:
		_apply_audio_volume(category)


# ============================================================
# AUF STANDARD ZURÜCKSETZEN (PRO OBERKATEGORIE)
# ============================================================

# Die Einstellungen sind in drei Oberkategorien aufgeteilt
# (Spieloptionen / Audio / Steuerung, siehe die Kategorie-Seiten in
# pause_menu.gd und main_menu.gd) - "Zurücksetzen" auf einer
# Kategorie-Seite soll darum auch NUR die Werte DIESER Kategorie
# zurücksetzen, nicht das ganze Spiel auf einmal. Darum drei
# einzelne Funktionen statt einer - reset_to_defaults() ganz unten
# ruft bei Bedarf einfach alle drei nacheinander auf.

# Kategorie "Spieloptionen": Sprache, UI-Größe (alle HUD-
# Kategorien) und Vollbild.
func reset_game_options() -> void:
	for category in HUD_SCALE_CATEGORIES:
		hud_scales[category] = HUD_SCALE_DEFAULT

	is_fullscreen = true
	_apply_fullscreen()

	current_language = DEFAULT_LANGUAGE

	_save_settings()

	for category in HUD_SCALE_CATEGORIES:
		hud_scale_changed.emit(category, HUD_SCALE_DEFAULT)

	language_changed.emit(current_language)


# Kategorie "Audio": Gesamtlautstärke und Musik.
func reset_audio() -> void:
	for category in AUDIO_BUS_CATEGORIES:
		audio_volumes[category] = 1.0

	_apply_all_audio_volumes()
	_save_settings()

	for category in AUDIO_BUS_CATEGORIES:
		audio_volume_changed.emit(category, 1.0)


# Kategorie "Steuerung": alle Tastenbelegungen.
func reset_controls() -> void:
	for action_name in REBINDABLE_ACTIONS:
		reset_action_to_default(action_name)


# Setzt WIRKLICH ALLES zurück (alle drei Kategorien auf einmal) -
# aktuell von keiner UI mehr direkt aufgerufen (die Kategorie-Seiten
# rufen jeweils nur ihre eigene reset_*()-Funktion auf), bleibt aber
# als einzelner Einstiegspunkt erhalten, falls das später doch
# irgendwo gebraucht wird.
func reset_to_defaults() -> void:
	reset_game_options()
	reset_audio()
	reset_controls()


# ============================================================
# TASTENBELEGUNG - ANZEIGE
# ============================================================

func get_action_display_name(action_name: StringName) -> String:
	var trimmed: String = String(action_name).strip_edges()

	return t("action." + trimmed)


# Erstes gebundenes Event einer Action als lesbarer Text,
# z.B. "V", "Leertaste", "Maustaste links".
func get_binding_text(action_name: StringName) -> String:
	var events: Array = InputMap.action_get_events(action_name)

	for event in events:
		if event is InputEventKey:
			return (
				event as InputEventKey
			).as_text_physical_keycode()

		if event is InputEventMouseButton:
			return _mouse_button_text(
				(event as InputEventMouseButton).button_index
			)

	return "-"


func _mouse_button_text(button_index: int) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return t("mouse.left")
		MOUSE_BUTTON_RIGHT:
			return t("mouse.right")
		MOUSE_BUTTON_MIDDLE:
			return t("mouse.middle")
		_:
			return t("mouse.other")


# ============================================================
# TASTENBELEGUNG - ÄNDERN
# ============================================================

# Weist einer Action ein neues Event zu. Entfernt das Event
# vorher automatisch von jeder anderen rebindbaren Action,
# damit nie zwei Actions dieselbe Taste/Maustaste belegen.
func rebind_action(
	action_name: StringName,
	event: InputEvent
) -> void:
	if not InputMap.has_action(action_name):
		return

	for other_action in REBINDABLE_ACTIONS:
		if other_action == action_name:
			continue

		for existing_event in InputMap.action_get_events(
			other_action
		):
			if _events_match(existing_event, event):
				InputMap.action_erase_event(
					other_action,
					existing_event
				)

	InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, event)

	_save_settings()

	controls_changed.emit(action_name)


func reset_action_to_default(action_name: StringName) -> void:
	# ProjectSettings behält die Werkseinstellung aus der
	# project.godot, unabhängig von späteren InputMap-Änderungen.
	var project_setting_key: String = (
		"input/" + String(action_name)
	)

	if not ProjectSettings.has_setting(project_setting_key):
		return

	var default_data: Dictionary = (
		ProjectSettings.get_setting(project_setting_key)
	)

	InputMap.action_erase_events(action_name)

	for event in default_data.get("events", []):
		InputMap.action_add_event(action_name, event)

	_save_settings()

	controls_changed.emit(action_name)


func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (
			(a as InputEventKey).physical_keycode
			== (b as InputEventKey).physical_keycode
		)

	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (
			(a as InputEventMouseButton).button_index
			== (b as InputEventMouseButton).button_index
		)

	return false


# ============================================================
# SPEICHERN UND LADEN
# ============================================================

func _save_settings() -> void:
	var config := ConfigFile.new()

	config.set_value(
		"general",
		"language",
		current_language
	)

	config.set_value(
		"general",
		"fullscreen",
		is_fullscreen
	)

	for category in HUD_SCALE_CATEGORIES:
		config.set_value(
			"hud_scale",
			String(category),
			hud_scales.get(category, HUD_SCALE_DEFAULT)
		)

	for category in AUDIO_BUS_CATEGORIES:
		config.set_value(
			"audio",
			String(category),
			audio_volumes.get(category, 1.0)
		)

	for action_name in REBINDABLE_ACTIONS:
		var events: Array = InputMap.action_get_events(
			action_name
		)

		if events.is_empty():
			continue

		config.set_value(
			"controls",
			String(action_name),
			events[0]
		)

	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()

	var error: Error = config.load(SETTINGS_PATH)

	if error != OK:
		# Keine gespeicherten Einstellungen vorhanden -
		# Standardwerte aus der project.godot bleiben aktiv.
		return

	current_language = str(
		config.get_value(
			"general",
			"language",
			DEFAULT_LANGUAGE
		)
	)

	is_fullscreen = bool(
		config.get_value(
			"general",
			"fullscreen",
			true
		)
	)

	_apply_fullscreen()

	for category in HUD_SCALE_CATEGORIES:
		if not config.has_section_key(
			"hud_scale",
			String(category)
		):
			continue

		var stored_value: float = float(
			config.get_value(
				"hud_scale",
				String(category),
				HUD_SCALE_DEFAULT
			)
		)

		hud_scales[category] = clamp(
			stored_value,
			HUD_SCALE_MIN,
			HUD_SCALE_MAX
		)

	for category in AUDIO_BUS_CATEGORIES:
		if not config.has_section_key("audio", String(category)):
			continue

		var stored_volume: float = float(
			config.get_value(
				"audio",
				String(category),
				1.0
			)
		)

		audio_volumes[category] = clamp(stored_volume, 0.0, 1.0)

	_apply_all_audio_volumes()

	for action_name in REBINDABLE_ACTIONS:
		if not config.has_section_key(
			"controls",
			String(action_name)
		):
			continue

		var event: Variant = config.get_value(
			"controls",
			String(action_name)
		)

		if event is InputEvent and InputMap.has_action(action_name):
			InputMap.action_erase_events(action_name)
			InputMap.action_add_event(
				action_name,
				event as InputEvent
			)
