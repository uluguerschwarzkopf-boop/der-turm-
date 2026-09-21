extends Node


# ============================================================
# RUN START VALUES
# ============================================================

const START_HEALTH: int = 3
const START_GOLD: int = 0
const START_POTIONS: int = 2
const START_ARMOR: int = 0
const START_ARROWS: int = 0
const START_BOW_UNLOCKED: bool = false

const START_AREA: int = 1
const START_ROOM_INDEX: int = 0


# ============================================================
# ROOM PATHS – AREA 1
# ============================================================

const NORMAL_ROOM_PATHS: Array[String] = [
	"res://Levels/Gebiet 1/level_01.tscn",
	"res://Levels/level_02.tscn",
	"res://Levels/Gebiet 1/level_03.tscn",
	"res://Levels/Gebiet 1/level_4.tscn",
	"res://Levels/Gebiet 1/level_5.tscn",
	"res://Levels/Gebiet 1/level_6.tscn",
	"res://Levels/Gebiet 1/level_7.tscn"
]

const MINIBOSS_ROOM_PATH: String = (
	"res://mini bosse/mini_boss_room.tscn"
)

const SHOP_ROOM_PATH: String = (
	"res://Händler/Gebiet 1/shop_room_1.tscn"
)

# Als UID statt als res://-Pfad, weil der Ordner "Bosse/Gebiet 1"
# irgendwann in "Bosse/Gebiet_1" (Unterstrich) umbenannt wurde -
# der alte res://-Pfad mit Leerzeichen zeigte danach ins Leere
# (ResourceLoader.exists() lieferte false, deshalb kam man über
# den Dev-Modus nie in den Bossraum). Dieselbe UID benutzt auch
# schon Levels/Gebiet 1/level_01.tscn (RoomManager.boss_room_path)
# für den ganz normalen Raum-9-zu-Raum-10-Übergang - UIDs bleiben
# stabil, auch wenn der Ordner nochmal verschoben/umbenannt wird.
const BOSS_ROOM_PATH: String = "uid://b135dvcl4iyjo"


# ============================================================
# CURRENT RUN
# ============================================================

var current_area: int = START_AREA
var current_room_index: int = START_ROOM_INDEX

var current_health: int = START_HEALTH
var current_gold: int = START_GOLD
var current_potions: int = START_POTIONS
var current_armor: int = START_ARMOR
var current_arrows: int = START_ARROWS
var bow_unlocked: bool = START_BOW_UNLOCKED

var spell_slots: Array[String] = ["", "", ""]

# Rüstungsart je Herz-Slot ("" = keine, "shield" = Schild aus dem
# Shop, "iron" = Iron Skin) - Index entspricht dem Herz-Index in
# hud.gd. Länge folgt lose der aktuellen Herzanzahl (siehe
# player_health.gd: armor_types/_ensure_armor_types_size()), wird
# hier nur roh gespeichert/geladen, ohne eigene Validierung.
var armor_types: Array[String] = []

var bosses_killed: int = 0
var minibosses_killed: int = 0
var rooms_finished: int = 0
var enemies_killed: int = 0

var current_run_seed: int = 0

var room_order: Array[String] = []

# Welcher Spielstand-Slot (1-3) gerade aktiv ist, damit
# "Speichern" im Pause-Menü in den richtigen Slot schreibt.
# -1 = kein Slot zugeordnet (z.B. vor dem ersten Start/Laden).
var current_save_slot: int = -1

# Wird NUR beim Einstieg über einen Spielstand im Hauptmenü auf
# true gesetzt (siehe main_menu.gd -> _on_slot_pressed), NICHT
# beim Neustart nach einem Tod (RoomManager.reset_run() ruft zwar
# auch start_new_run() auf, setzt dieses Flag aber bewusst nicht).
# RoomManager liest es beim Betreten von Raum 1 aus, um das
# Gebiets-Intro ("GEBIET 1 - DIE EINGANGSHALLEN") zu zeigen, und
# verbraucht es dabei sofort (auf false), damit es garantiert nur
# einmal auslöst.
var show_area_intro_pending: bool = false

# ============================================================
# SHOP-CHECKPOINT (NUTZER-WUNSCH)
# ============================================================

# Sobald der Spieler den Shop-Raum betritt (siehe Händler/Gebiet 1/
# shop_overlay.gd -> _ready() -> save_shop_checkpoint()), wird hier
# ein kompletter Snapshot des laufenden Runs gespeichert (identisches
# Schema wie get_current_run_data(), siehe dort). Stirbt der Spieler
# DANACH, stellt reset_run() unten diesen Snapshot wieder her statt
# komplett neu zu starten - der Spieler landet dann wieder im Shop-
# Raum, mit Gold/Items/Fortschritt genau wie beim Betreten (nur die
# Herzen werden wieder voll). Stirbt der Spieler VOR dem ersten Shop-
# Besuch, bleibt es beim normalen kompletten Reset (has_shop_
# checkpoint ist dann noch false). Wird bei jedem komplett neuen Lauf
# zurückgesetzt (siehe start_new_run()) - ein Checkpoint gilt immer
# nur für den einen Lauf, in dem der Shop erreicht wurde.
var has_shop_checkpoint: bool = false
var _shop_checkpoint_data: Dictionary = {}

# Jedes bisher freigeschaltete Boss-Echo (siehe unlock_echo()) -
# bleibt für den ganzen Lauf gespeichert (Teil von
# get_current_run_data()/SaveManager._apply_run_data()), damit ein
# Neuladen des Spielstands das Echo im HUD wieder zeigt. Wird beim
# Tod-Neustart (start_new_run()) bewusst zurückgesetzt, genau wie
# bosses_killed - ein neuer Lauf muss den Boss also wieder besiegen.
var unlocked_echoes: Array[StringName] = []

# Welches Echo gerade frisch enthüllt werden soll (Spieler-
# Animation -> Banner -> HUD-Icon, siehe Levels/room_manager.gd).
# Wird dort gesetzt UND sofort wieder verbraucht (auf &""), damit
# die Enthüllungs-Sequenz garantiert nur einmal abläuft. Leer
# ("") bedeutet: gerade nichts enthüllen.
var pending_echo_reveal: StringName = &""

# Zentrale Stelle für jedes neue Boss-Echo: id ist der Schlüssel in
# unlocked_echoes, anim_name die im Spieler-SpriteFrames hinterlegte
# Enthüllungs-Animation (siehe Player/player.tscn), translation_key
# der übersetzte Banner-Text ("... erhalten") in
# SettingsManager.TRANSLATIONS. Spätere Bosse ergänzen hier einfach
# einen weiteren Eintrag.
const ECHO_DEFINITIONS: Dictionary = {
	&"echo_der_flamme": {
		"anim_name": &"Echo der Flamme",
		"translation_key": "echo.echo_der_flamme_erhalten",
	},
}

# Echo-Türen (siehe Objects/Doors/Echo Doors/.../flame_echo_door.gd),
# die im laufenden Run bereits benutzt wurden - Schlüssel ist die
# jeweilige door_id der Tür (Inspector-Export). Bleibt für den
# ganzen Lauf gespeichert (Teil von get_current_run_data()/
# SaveManager._apply_run_data()), damit eine schon benutzte Tür
# nach einem Neuladen wieder als benutzt/Activ startet. Wird beim
# Tod-Neustart (start_new_run()) bewusst zurückgesetzt, genau wie
# unlocked_echoes - ein neuer Lauf darf jede Tür wieder benutzen.
var used_doors: Array[StringName] = []

# IDs bereits gezeigter Void-Erzählsequenzen (siehe Game/void_
# narration.gd, ausgelöst über Levels/room_manager.gd -> void_
# intro_id) - verhindert, dass "Die Leere" dieselbe Zeile beim
# erneuten Betreten desselben Raums nochmal abspielt. Bleibt für
# den ganzen Lauf gespeichert (Teil von get_current_run_data()/
# SaveManager._apply_run_data()), wird beim Tod-Neustart
# (start_new_run()) bewusst zurückgesetzt, genau wie used_doors -
# ein neuer Lauf darf jede Erzählung wieder hören.
var shown_narrations: Array[StringName] = []

# Der im Skill-Tree-Raum gewählte Pfad (siehe Objects/Staturen/
# skill_statue.gd - path_name_key der jeweiligen Statur, z.B.
# "skill_path.strength"). Leer = noch keine Wahl getroffen. Einmal
# gesetzt bleibt es für den gesamten Lauf fest (siehe
# choose_skill_path() - wählt nur, wenn noch leer, kein Wechsel
# mehr möglich), genau wie shown_narrations Teil von
# get_current_run_data()/SaveManager._apply_run_data() und wird
# beim Tod-Neustart (start_new_run()) bewusst zurückgesetzt.
var chosen_skill_path: StringName = &""

# Wird EINMALIG ausgelöst, direkt nachdem chosen_skill_path gesetzt
# wurde (siehe choose_skill_path()) - lässt z.B. das HUD (Player/
# hud.gd) den XP-Ring sofort einblenden, sobald eine Statur gewählt
# wurde, ohne dass das HUD dafür jeden Frame chosen_skill_path
# abfragen müsste.
signal skill_path_chosen(path_key: StringName)


# ============================================================
# SKILL-BAUM: ERFAHRUNGSPUNKTE (XP-RING IM HUD)
# ============================================================

# EIN Kill (egal ob normaler Mob, Mini-Boss oder Boss) füllt 5% des
# Rings - der Ring braucht also 100% / 5% = 20 Kills, bis er sich
# schließt (siehe skeleton.gd/skeleton_archer.gd -> _die(), die
# add_enemy_kill() aufrufen).
const SKILL_XP_PER_ENEMY_KILL: float = 0.05

# Fortschritt des GERADE LAUFENDEN XP-Rings: 0.0 = leer, wächst mit
# jedem add_skill_path_xp()-Aufruf. Erreicht er 1.0, schließt sich
# der Ring (siehe add_skill_path_xp()) - skill_points geht um 1
# hoch und dieser Wert startet wieder bei 0.0, kein "Level-Up"-
# Zwischenschritt, einfach direkt weiter (siehe Nutzer-Wunsch: "wie
# bei ori ... die punkte gehen einfach hoch").
var skill_path_xp: float = 0.0

# Anzahl bereits verdienter Skillpunkte in diesem Lauf (jeder volle
# XP-Ring = +1, siehe add_skill_path_xp()). Wofür die am Ende
# ausgegeben werden, klärt der eigentliche Skill-Baum (nächster
# Schritt) - hier werden sie erstmal nur gesammelt und im HUD in
# der Mitte des Rings angezeigt.
var skill_points: int = 0

# Steuert, ob der XP-Ring im HUD schon sichtbar sein soll (siehe
# Player/UI/skill_ring_hud.gd -> _process(), liest dieses Feld JEDEN
# FRAME direkt aus). Bleibt false, obwohl chosen_skill_path schon
# gesetzt ist, bis skill_statue.gd es am ENDE der "Aufnehmen"-
# Animation auf true setzt (siehe _play_aufnehmen_sequence()) - der
# Ring soll ja erst nach der Animation erscheinen, nicht schon beim
# Drücken der Interact-Taste.
var skill_ring_revealed: bool = false

# Wird ausgelöst, wann immer sich skill_path_xp und/oder
# skill_points ändern (siehe add_skill_path_xp()) - aktuell von
# player_health.gd für den Vitalität-Pfad benutzt. Der XP-Ring selbst
# (Player/UI/skill_ring_hud.gd) hört NICHT hierauf, sondern fragt
# jeden Frame direkt ab (siehe HINWEIS dort) - Ausnahme: der Kill-
# Pixel-Effekt unten (enemy_killed_for_xp), der bewusst separat ist.
signal skill_progress_changed(progress: float, points: int)

# Wird bei JEDEM Gegner-Kill ausgelöst, der auch tatsächlich XP für
# den Skill-Pfad einbringt (siehe add_enemy_kill() unten) - trägt die
# Todesposition des Gegners, damit der XP-Ring (Player/UI/skill_ring_
# hud.gd) von dort einen kleinen Pixel zu sich hinfliegen lassen kann
# und den Ring-Füllstand ERST bei dessen Ankunft weiterzieht (Nutzer-
# Wunsch), statt sofort bei jedem Kill zu springen.
signal enemy_killed_for_xp(death_position: Vector2)

# Farbe des XP-Rings je gewähltem Pfad (siehe Objects/Staturen/
# skill_statue.gd -> path_name_key). An die tatsächlichen Kristall-/
# Fensterfarben der Staturen angeglichen (Stärke=Rot, Arkana=Blau,
# Wiederbelebung=Lila-Pink - siehe Beschwörer-Statur im Skilltree-
# Raum).
const SKILL_PATH_COLORS: Dictionary = {
	&"skill_path.strength": Color(0.82, 0.24, 0.2),
	&"skill_path.arcana": Color(0.3, 0.55, 0.95),
	&"skill_path.resurrection": Color(0.75, 0.3, 0.85),
}

# ============================================================
# SKILL-BAUM: FREIGESCHALTETE SKILLS
# ============================================================

# IDs bereits freigeschalteter Skills des GEWÄHLTEN Pfads (siehe
# Game/skill_tree_data.gd für die eigentlichen Skill-Definitionen -
# id/Kosten/requires pro Pfad). Bewusst nur eine flache Liste von
# IDs, kein verschachteltes Pfad->Skills-Dictionary: es kann pro Run
# eh nur EIN Pfad gewählt sein, also reicht das.
var unlocked_skills: Array[StringName] = []


func has_unlocked_skill(skill_id: StringName) -> bool:
	return unlocked_skills.has(skill_id)


# ============================================================
# VIGOR (RESSOURCE FÜR AKTIVE SKILLS, PFAD DER STÄRKE)
# ============================================================

# Vigor ist die Ressource, die aktive Skills des "Pfad der Stärke"
# verbrauchen (siehe Game/skill_tree_data.gd bzw. settings_manager.gd -
# z.B. skill.charged_strike.desc: "Vigor-Kosten noch nicht final").
# Wird durch Nahkampf-Treffer aufgeladen (siehe Player/player_
# combat.gd -> _damage_body()); Bloodlust soll später die Erzeugungs-
# rate verbessern (skill.bloodlust.desc), ist aber selbst noch nicht
# umgesetzt (siehe Passiv-Skill-Einschränkung: nur Vitality/Double
# Roll haben bestätigte Endwerte).
#
# Vigor pro gelandetem Nahkampf-Treffer (auf JEDEN Gegner - normale
# Mobs, Mini-Bosse, Bosse). Mit dem passiven Skill "Bloodlust"
# freigeschaltet gibt's pro Treffer nochmal +VIGOR_BLOODLUST_BONUS
# oben drauf (siehe Player/player_combat.gd -> _damage_body()).
const VIGOR_MAX: int = 100
const VIGOR_PER_MELEE_HIT: int = 5
const VIGOR_BLOODLUST_BONUS: int = 6

var current_vigor: int = 0

signal vigor_changed(current: int, max_vigor: int)


func add_vigor(amount: int) -> void:
	if amount <= 0:
		return

	var old_vigor: int = current_vigor

	current_vigor = min(current_vigor + amount, VIGOR_MAX)

	if current_vigor != old_vigor:
		vigor_changed.emit(current_vigor, VIGOR_MAX)


# Gibt true zurück, wenn genug Vigor da war und sie abgezogen wurde -
# false ohne jede Wirkung, wenn nicht genug da ist (Aufrufer soll den
# Skill dann gar nicht erst auslösen, siehe Player/player.gd ->
# _use_equipped_skill()).
func spend_vigor(amount: int) -> bool:
	if amount <= 0:
		return false

	if current_vigor < amount:
		return false

	current_vigor -= amount
	vigor_changed.emit(current_vigor, VIGOR_MAX)

	return true


# ============================================================
# SKILL-SLOT (AUSGERÜSTETER AKTIVER SKILL)
# ============================================================

# Welcher bereits freigeschaltete AKTIVE Skill gerade im Skill-Slot
# liegt (siehe Player/hud.gd für die Anzeige, Player/player.gd für
# die Auslösung über die Taste "use_skill"). Leer = kein Skill
# ausgerüstet. Nur EIN Slot fürs Erste (Nutzer-Wunsch), kein Array.
var equipped_active_skill: StringName = &""

signal equipped_active_skill_changed(skill_id: StringName)


# Rüstet einen bereits freigeschalteten aktiven Skill in den Slot -
# ausgelöst durch Anklicken im Skill-Baum (siehe skill_tree_menu.gd
# -> _on_skill_button_pressed()). Passive Skills lassen sich absicht-
# lich nicht ausrüsten (kein Slot-Konzept für sie), genau wie noch
# nicht freigeschaltete Skills.
func equip_active_skill(skill_id: StringName) -> bool:
	if not has_chosen_skill_path():
		return false

	if not has_unlocked_skill(skill_id):
		return false

	var skill: Dictionary = SkillTreeData.get_skill(
		chosen_skill_path,
		skill_id
	)

	if skill.is_empty():
		return false

	if skill.get("type", &"passive") != &"active":
		return false

	equipped_active_skill = skill_id
	equipped_active_skill_changed.emit(skill_id)

	return true


# Nutzer-Wunsch (wörtlich): "wenn man ein Upgrade macht, kann man
# dann erst auf das nächste Upgrade, das davor verdeckt wurde" -
# GEPRÜFT wird das hier über "prerequisites" (siehe Game/
# skill_tree_data.gd): ein Skill mit Voraussetzungen lässt sich nur
# freischalten, wenn MINDESTENS EINE davon selbst schon
# freigeschaltet ist (ODER-Verknüpfung - für die normalen Ketten
# im Baum hat jeder Skill eh nur eine einzige Voraussetzung, aber
# Warlord braucht laut Vorlage nur EINEN der drei 2-Punkte-Skills,
# nicht alle drei gleichzeitig).
#
# Prüft NUR die Voraussetzungs-/Punkte-Bedingungen, NICHT ob der
# Skill schon freigeschaltet ist oder genug Skillpunkte da sind -
# wird von can_unlock_skill() (Kosten-Check) UND vom Skilltree-UI
# (fürs "verdeckt"-Anzeigen, unabhängig von den Kosten) gebraucht.
func skill_prerequisites_met(skill_id: StringName) -> bool:
	if not has_chosen_skill_path():
		return false

	var skill: Dictionary = SkillTreeData.get_skill(
		chosen_skill_path,
		skill_id
	)

	if skill.is_empty():
		return false

	var prerequisites: Array = skill.get("prerequisites", [])

	if not prerequisites.is_empty():
		var any_prerequisite_met: bool = false

		for prerequisite_id in prerequisites:
			if has_unlocked_skill(prerequisite_id):
				any_prerequisite_met = true
				break

		if not any_prerequisite_met:
			return false

	# Zusätzliche Bedingung nur für Warlord (siehe Vorlage Punkt 26):
	# insgesamt schon eine bestimmte Menge Skillpunkte in diesem Pfad
	# investiert, unabhängig davon, WELCHE Skills das waren.
	var min_points_invested: int = int(
		skill.get("min_points_invested", 0)
	)

	if (
		min_points_invested > 0
		and _total_points_spent_in_path(chosen_skill_path) < min_points_invested
	):
		return false

	return true


func can_unlock_skill(skill_id: StringName) -> bool:
	if not has_chosen_skill_path():
		return false

	if has_unlocked_skill(skill_id):
		return false

	if not skill_prerequisites_met(skill_id):
		return false

	var skill: Dictionary = SkillTreeData.get_skill(
		chosen_skill_path,
		skill_id
	)

	var cost: int = int(skill.get("cost", 1))

	return skill_points >= cost


# Gibt true zurück, wenn der Skill wirklich freigeschaltet wurde
# (siehe can_unlock_skill() für alle Bedingungen) - false, wenn eine
# Bedingung fehlschlägt (z.B. zu wenig Punkte), OHNE dabei
# irgendwas zu verändern.
func unlock_skill(skill_id: StringName) -> bool:
	if not can_unlock_skill(skill_id):
		return false

	var skill: Dictionary = SkillTreeData.get_skill(
		chosen_skill_path,
		skill_id
	)

	var cost: int = int(skill.get("cost", 1))

	skill_points -= cost
	unlocked_skills.append(skill_id)

	skill_progress_changed.emit(skill_path_xp, skill_points)

	return true


# Summe der Kosten aller schon freigeschalteten Skills EINES Pfads -
# für die "mindestens X Skillpunkte insgesamt investiert"-Bedingung
# von Warlord (siehe skill_prerequisites_met()). Zählt bewusst
# ausgegebene Punkte, nicht die noch übrigen skill_points.
func _total_points_spent_in_path(path_key: StringName) -> int:
	var total: int = 0

	for skill_id in unlocked_skills:
		var skill: Dictionary = SkillTreeData.get_skill(
			path_key,
			skill_id
		)

		if not skill.is_empty():
			total += int(skill.get("cost", 0))

	return total


# Spielzeit des aktuellen Runs in Sekunden. Läuft nur, solange
# _time_tracking_active true ist (siehe start_time_tracking()/
# stop_time_tracking()) - zählt also nicht im Hauptmenü und
# pausiert automatisch mit get_tree().paused, da RunState wie
# jeder normale Node beim Pausieren nicht mehr prozessiert wird.
var current_playtime_seconds: float = 0.0

var _time_tracking_active: bool = false


# ============================================================
# SHOP DATA FOR THE CURRENT RUN
# ============================================================

# Stores the six shop item IDs for the whole run.
# The first two entries are always potion and shield.
var shop_item_ids: Array[String] = []

# Stores unique items that have already been bought,
# for example the bow.
var bought_unique_shop_items: Dictionary = {}

# Friendly summon persisted between rooms.
var summon_active: bool = false
var summon_health: int = 0


# ============================================================
# LAST FINISHED RUN
# ============================================================

var last_run_gold: int = 0
var last_run_bosses_killed: int = 0
var last_run_minibosses_killed: int = 0
var last_run_rooms_finished: int = 0
var last_run_enemies_killed: int = 0
var last_run_area: int = 1


func _ready() -> void:
	if current_run_seed == 0:
		current_run_seed = randi()

	if room_order.is_empty():
		generate_room_order()


func _process(delta: float) -> void:
	if _time_tracking_active:
		current_playtime_seconds += delta


# ============================================================
# SPIELZEIT
# ============================================================

func start_time_tracking() -> void:
	_time_tracking_active = true


func stop_time_tracking() -> void:
	_time_tracking_active = false


func get_playtime_seconds() -> float:
	return current_playtime_seconds


func set_active_save_slot(slot: int) -> void:
	current_save_slot = slot


# ============================================================
# START / RESET RUN
# ============================================================

func start_new_run() -> void:
	current_area = START_AREA
	current_room_index = START_ROOM_INDEX

	current_health = START_HEALTH
	current_gold = START_GOLD
	current_potions = START_POTIONS
	current_armor = START_ARMOR
	current_arrows = START_ARROWS
	bow_unlocked = START_BOW_UNLOCKED

	spell_slots = ["", "", ""]
	armor_types = []

	bosses_killed = 0
	minibosses_killed = 0
	rooms_finished = 0
	enemies_killed = 0

	unlocked_echoes = []
	pending_echo_reveal = &""
	used_doors = []
	shown_narrations = []
	chosen_skill_path = &""
	skill_path_xp = 0.0
	skill_points = 0
	skill_ring_revealed = false
	unlocked_skills = []
	current_vigor = 0
	equipped_active_skill = &""

	# Ein komplett neuer Lauf beginnt immer ohne Shop-Checkpoint -
	# ein Checkpoint aus einem vorherigen Lauf darf hier nicht
	# stehen bleiben (siehe has_shop_checkpoint oben).
	has_shop_checkpoint = false
	_shop_checkpoint_data = {}

	current_run_seed = randi()

	current_playtime_seconds = 0.0
	start_time_tracking()

	# A new run receives a new random shop offer.
	clear_shop_data()
	clear_summon_data()

	generate_room_order()

	print("New run started.")
	print_room_order()


func reset_run() -> void:
	if has_shop_checkpoint:
		_restore_shop_checkpoint()
	else:
		start_new_run()

	# Absicherung: reset_run() wird nur bei einem Tod-Neustart
	# mitten im Lauf aufgerufen (siehe room_manager.gd) - das
	# Gebiets-Intro soll dabei NICHT nochmal erscheinen.
	show_area_intro_pending = false


# Wird von Händler/Gebiet 1/shop_overlay.gd (_ready()) aufgerufen,
# sobald der Shop-Raum betreten wird - siehe has_shop_checkpoint oben
# für die komplette Erklärung.
func save_shop_checkpoint() -> void:
	has_shop_checkpoint = true
	_shop_checkpoint_data = get_current_run_data()

	print("Shop-Checkpoint gespeichert.")


# Stellt den beim Shop-Betreten gespeicherten Snapshot wieder her
# (siehe has_shop_checkpoint oben) - benutzt denselben Ablauf wie das
# normale Laden eines Spielstands (SaveManager.apply_run_data()), nur
# aus dem im Speicher gehaltenen Snapshot statt aus einer JSON-Datei.
# has_shop_checkpoint bleibt dabei bewusst true, damit ein erneuter
# Tod danach wieder an denselben Punkt zurückspringt.
func _restore_shop_checkpoint() -> void:
	if get_node_or_null("/root/SaveManager") != null:
		SaveManager.apply_run_data(_shop_checkpoint_data)

	# SaveManager._apply_run_data() setzt has_shop_checkpoint als
	# Absicherung für den NORMALEN "Spielstand laden"-Weg immer auf
	# false (siehe dort) - hier aber, beim Wiederherstellen GENAU
	# dieses Checkpoints, muss er wieder true werden, sonst würde ein
	# weiterer Tod danach fälschlich zum kompletten Reset führen statt
	# wieder zum Shop-Checkpoint zurückzuspringen.
	has_shop_checkpoint = true

	# Nach einem Tod-Neustart immer volle Herzen, genau wie beim
	# normalen kompletten Reset (start_new_run() -> START_HEALTH).
	current_health = START_HEALTH

	start_time_tracking()

	print("Shop-Checkpoint wiederhergestellt.")


# ============================================================
# RANDOM ROOM ORDER
# ============================================================

func generate_room_order() -> void:
	room_order.clear()

	var shuffled_normal_rooms: Array[String] = []

	for room_path in NORMAL_ROOM_PATHS:
		shuffled_normal_rooms.append(room_path)

	shuffled_normal_rooms.shuffle()

	# Rooms 1–4
	room_order.append(shuffled_normal_rooms[0])
	room_order.append(shuffled_normal_rooms[1])
	room_order.append(shuffled_normal_rooms[2])
	room_order.append(shuffled_normal_rooms[3])

	# Room 5: Miniboss
	room_order.append(MINIBOSS_ROOM_PATH)

	# Room 6: Merchant
	room_order.append(SHOP_ROOM_PATH)

	# Rooms 7–9
	room_order.append(shuffled_normal_rooms[4])
	room_order.append(shuffled_normal_rooms[5])
	room_order.append(shuffled_normal_rooms[6])

	# Room 10: Boss
	room_order.append(BOSS_ROOM_PATH)

	current_room_index = START_ROOM_INDEX


func get_current_room_path() -> String:
	if room_order.is_empty():
		generate_room_order()

	if current_room_index < 0:
		return ""

	if current_room_index >= room_order.size():
		return ""

	return room_order[current_room_index]


func get_next_room_path() -> String:
	if room_order.is_empty():
		generate_room_order()

	var next_index: int = current_room_index + 1

	if next_index < 0:
		return ""

	if next_index >= room_order.size():
		return ""

	return room_order[next_index]


func advance_to_next_room() -> String:
	if room_order.is_empty():
		generate_room_order()

	if not has_next_room():
		return ""

	current_room_index += 1
	rooms_finished += 1

	return room_order[current_room_index]


func has_next_room() -> bool:
	if room_order.is_empty():
		return false

	return current_room_index + 1 < room_order.size()


func find_room_index(room_path: String) -> int:
	if room_path.is_empty():
		return -1

	if room_order.is_empty():
		generate_room_order()

	return room_order.find(room_path)


func sync_room_index_from_path(room_path: String) -> bool:
	var found_index: int = find_room_index(room_path)

	if found_index == -1:
		return false

	current_room_index = found_index
	return true


func is_boss_room() -> bool:
	return current_room_index == 9


func get_current_room_number() -> int:
	return current_room_index + 1


func get_total_room_count() -> int:
	return room_order.size()


func print_room_order() -> void:
	print("========== ROOM ORDER ==========")

	for i in range(room_order.size()):
		print(
			"Room ",
			i + 1,
			": ",
			room_order[i]
		)

	print("================================")


# ============================================================
# SHOP
# ============================================================

func has_shop_offer() -> bool:
	return not shop_item_ids.is_empty()


func set_shop_offer(new_item_ids: Array[String]) -> void:
	shop_item_ids.clear()

	for item_id in new_item_ids:
		shop_item_ids.append(item_id)


func get_shop_offer() -> Array[String]:
	return shop_item_ids.duplicate()


func mark_unique_shop_item_bought(item_id: String) -> void:
	if item_id.is_empty():
		return

	bought_unique_shop_items[item_id] = true


func is_unique_shop_item_bought(item_id: String) -> bool:
	if item_id.is_empty():
		return false

	return bought_unique_shop_items.has(item_id)


func clear_shop_data() -> void:
	shop_item_ids.clear()
	bought_unique_shop_items.clear()


# ============================================================
# FRIENDLY SUMMON
# ============================================================

func save_summon_data(active: bool, health: int = 0) -> void:
	summon_active = active
	summon_health = max(health, 0)


func clear_summon_data() -> void:
	summon_active = false
	summon_health = 0


func has_saved_summon() -> bool:
	return summon_active and summon_health > 0


# ============================================================
# FINISH RUN
# ============================================================

func finish_run() -> void:
	last_run_gold = current_gold
	last_run_bosses_killed = bosses_killed
	last_run_minibosses_killed = minibosses_killed
	last_run_rooms_finished = rooms_finished
	last_run_enemies_killed = enemies_killed
	last_run_area = current_area


# ============================================================
# HEALTH
# ============================================================

func set_health(amount: int) -> void:
	current_health = max(amount, 0)


# ============================================================
# GOLD
# ============================================================

func set_gold(amount: int) -> void:
	current_gold = max(amount, 0)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return

	current_gold += amount


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return false

	if current_gold < amount:
		return false

	current_gold -= amount
	return true


# ============================================================
# POTIONS
# ============================================================

func set_potions(amount: int) -> void:
	current_potions = max(amount, 0)


# ============================================================
# ARMOR
# ============================================================

func set_armor(amount: int) -> void:
	current_armor = max(amount, 0)


# Speichert, welche Rüstungsart (siehe armor_types oben) auf welchem
# Herz-Slot sitzt - wird von player_health.gd nach jeder Änderung
# (Rüstung dazu/kaputt) aufgerufen, damit es Szenenwechsel/Speichern
# übersteht.
func set_armor_types(types: Array) -> void:
	armor_types = []

	for t in types:
		armor_types.append(str(t))


# ============================================================
# BOW AND ARROWS
# ============================================================

func set_bow_unlocked(unlocked: bool) -> void:
	bow_unlocked = unlocked


func set_arrows(amount: int) -> void:
	current_arrows = max(amount, 0)


# ============================================================
# SPELL SLOTS
# ============================================================

func set_spell_slots(new_slots: Array[String]) -> void:
	spell_slots = ["", "", ""]

	for i in range(min(new_slots.size(), spell_slots.size())):
		spell_slots[i] = new_slots[i]


func clear_spell_slots() -> void:
	spell_slots = ["", "", ""]


# ============================================================
# RUN STATISTICS
# ============================================================

func add_boss_kill(amount: int = 1) -> void:
	if amount <= 0:
		return

	bosses_killed += amount


func add_miniboss_kill(amount: int = 1) -> void:
	if amount <= 0:
		return

	minibosses_killed += amount


func add_finished_room(amount: int = 1) -> void:
	if amount <= 0:
		return

	rooms_finished += amount


func add_enemy_kill(
	amount: int = 1,
	death_position: Vector2 = Vector2.ZERO
) -> void:
	if amount <= 0:
		return

	enemies_killed += amount

	# Ein Pixel-Effekt PRO Kill (siehe enemy_killed_for_xp oben) - nur
	# wenn überhaupt ein Pfad gewählt ist, sonst gibt es weder einen
	# sichtbaren Ring noch (siehe add_skill_path_xp() unten) echte XP
	# zum Anfliegen.
	if has_chosen_skill_path():
		for i in range(amount):
			enemy_killed_for_xp.emit(death_position)

	add_skill_path_xp(SKILL_XP_PER_ENEMY_KILL * amount)


# ============================================================
# ECHOS (BOSS-BELOHNUNGEN)
# ============================================================

func has_echo(echo_id: StringName) -> bool:
	return unlocked_echoes.has(echo_id)


# Schaltet ein Echo frei - gibt true zurück, wenn es davor noch
# NICHT freigeschaltet war (der Aufrufer soll dann die einmalige
# Enthüllungs-Sequenz auslösen), false, wenn es schon vorhanden
# war (z.B. weil der Bossraum erneut betreten wurde).
func unlock_echo(echo_id: StringName) -> bool:
	if unlocked_echoes.has(echo_id):
		return false

	unlocked_echoes.append(echo_id)
	return true


# ============================================================
# ECHO-TÜREN (EINMAL BENUTZBAR)
# ============================================================

func has_used_door(door_id: StringName) -> bool:
	return used_doors.has(door_id)


func mark_door_used(door_id: StringName) -> void:
	if used_doors.has(door_id):
		return

	used_doors.append(door_id)


# ============================================================
# VOID-ERZÄHLUNGEN (EINMAL PRO RUN)
# ============================================================

func has_shown_narration(narration_id: StringName) -> bool:
	return shown_narrations.has(narration_id)


func mark_narration_shown(narration_id: StringName) -> void:
	if shown_narrations.has(narration_id):
		return

	shown_narrations.append(narration_id)


# ============================================================
# SKILL-BAUM-PFAD (EINMAL PRO RUN, NICHT MEHR ÄNDERBAR)
# ============================================================

func has_chosen_skill_path() -> bool:
	return chosen_skill_path != &""


# Legt path_key als Pfad für den restlichen Lauf fest - NUR wenn
# noch keiner gewählt wurde (siehe skill_statue.gd: sobald
# has_chosen_skill_path() true ist, wird gar nicht mehr aufgerufen,
# aber sicherheitshalber hier nochmal geprüft).
func choose_skill_path(path_key: StringName) -> void:
	if has_chosen_skill_path():
		return

	chosen_skill_path = path_key
	skill_path_chosen.emit(path_key)


# Farbe des XP-Rings für den aktuell gewählten Pfad (siehe
# SKILL_PATH_COLORS oben) - neutrales Grau, solange noch gar kein
# Pfad gewählt wurde (sollte praktisch nie sichtbar werden, da der
# Ring selbst erst ab has_chosen_skill_path() eingeblendet wird).
func get_skill_path_color() -> Color:
	return SKILL_PATH_COLORS.get(
		chosen_skill_path,
		Color(0.85, 0.85, 0.85)
	)


# Zentrale Stelle für JEDEN Erfahrungsgewinn Richtung Skill-Baum -
# aktuell nur über add_enemy_kill() aufgerufen. Ohne gewählten Pfad
# passiert bewusst nichts (siehe has_chosen_skill_path()): vor der
# Statur-Wahl im Skill-Tree-Raum gibt es noch keinen Ring, der XP
# aufnehmen könnte.
func add_skill_path_xp(amount: float) -> void:
	if amount <= 0.0:
		return

	if not has_chosen_skill_path():
		return

	skill_path_xp += amount

	while skill_path_xp >= 1.0:
		skill_path_xp -= 1.0
		skill_points += 1

	skill_progress_changed.emit(skill_path_xp, skill_points)


# ============================================================
# AREA / ROOM
# ============================================================

func set_current_area(area_number: int) -> void:
	current_area = max(area_number, 1)


func set_current_room_index(room_index: int) -> void:
	if room_order.is_empty():
		generate_room_order()

	current_room_index = clamp(
		room_index,
		0,
		max(room_order.size() - 1, 0)
	)


# ============================================================
# DATA
# ============================================================

func get_current_run_data() -> Dictionary:
	return {
		"area": current_area,
		"room_index": current_room_index,
		"room_number": get_current_room_number(),
		"room_path": get_current_room_path(),
		"room_order": room_order.duplicate(),
		"playtime_seconds": current_playtime_seconds,
		"health": current_health,
		"gold": current_gold,
		"potions": current_potions,
		"armor": current_armor,
		"armor_types": armor_types.duplicate(),
		"arrows": current_arrows,
		"bow_unlocked": bow_unlocked,
		"spell_slots": spell_slots.duplicate(),
		"bosses_killed": bosses_killed,
		"minibosses_killed": minibosses_killed,
		"rooms_finished": rooms_finished,
		"enemies_killed": enemies_killed,
		"run_seed": current_run_seed,
		"shop_item_ids": shop_item_ids.duplicate(),
		"bought_unique_shop_items": bought_unique_shop_items.duplicate(),
		"summon_active": summon_active,
		"summon_health": summon_health,
		"unlocked_echoes": _echoes_to_string_array(),
		"used_doors": _doors_to_string_array(),
		"shown_narrations": _narrations_to_string_array(),
		"chosen_skill_path": String(chosen_skill_path),
		"skill_path_xp": skill_path_xp,
		"skill_points": skill_points,
		"skill_ring_revealed": skill_ring_revealed,
		"unlocked_skills": _unlocked_skills_to_string_array(),
		"vigor": current_vigor,
		"equipped_active_skill": String(equipped_active_skill)
	}


func _echoes_to_string_array() -> Array[String]:
	var result: Array[String] = []

	for echo_id in unlocked_echoes:
		result.append(String(echo_id))

	return result


func _doors_to_string_array() -> Array[String]:
	var result: Array[String] = []

	for door_id in used_doors:
		result.append(String(door_id))

	return result


func _narrations_to_string_array() -> Array[String]:
	var result: Array[String] = []

	for narration_id in shown_narrations:
		result.append(String(narration_id))

	return result


func _unlocked_skills_to_string_array() -> Array[String]:
	var result: Array[String] = []

	for skill_id in unlocked_skills:
		result.append(String(skill_id))

	return result


# ============================================================
# TEMPORÄRER TEST-BUTTON (PAUSE-MENÜ) - SPÄTER WIEDER ENTFERNEN
# ============================================================

# Nur zum Testen des Skill-Baums: gibt sofort weitere Skillpunkte,
# ohne dass man dafür wirklich Gegner besiegen muss. Wird über den
# rot markierten Debug-Button im Pause-Menü aufgerufen (siehe Game/
# pause_menu.gd -> _on_debug_add_skill_point_pressed()) - beide
# Stellen sind bewusst so markiert, dass sie sich später leicht
# wiederfinden und zusammen entfernen lassen.
func debug_add_skill_point(amount: int = 1) -> void:
	if amount <= 0:
		return

	skill_points += amount

	skill_progress_changed.emit(skill_path_xp, skill_points)

	# Nutzer-Wunsch: Beim Debug-Testen des Skill-Baums soll die Vigor-
	# Leiste gleich mit voll gehen, damit sich aktive Skills (Charge
	# Attack usw.) sofort ausprobieren lassen, ohne dafür erst Gegner
	# im Nahkampf treffen zu müssen.
	current_vigor = VIGOR_MAX
	vigor_changed.emit(current_vigor, VIGOR_MAX)


func get_last_run_data() -> Dictionary:
	return {
		"gold": last_run_gold,
		"bosses_killed": last_run_bosses_killed,
		"minibosses_killed": last_run_minibosses_killed,
		"rooms_finished": last_run_rooms_finished,
		"enemies_killed": last_run_enemies_killed,
		"area": last_run_area
	}
