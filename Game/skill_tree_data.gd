class_name SkillTreeData
extends RefCounted


# ============================================================
# HINWEIS
# ============================================================

# Reine Datenklasse (keine Instanz nötig, nur statische
# Funktionen/Konstanten - siehe unten) mit den Skill-Definitionen
# pro Pfad. RunState.can_unlock_skill()/unlock_skill()/
# skill_prerequisites_met() (siehe Game/run_state.gd) greifen
# direkt hierauf zu.
#
# ECHTER Inhalt für "Pfad der Stärke" (Path of Might) nach der vom
# Nutzer gegebenen Vorlage (Punkte 19-32 im Chat). Konkrete
# Zahlenwerte für die Fähigkeiten selbst (Schaden, Vigor-Kosten,
# Cooldowns usw.) sind laut Vorlage AUSDRÜCKLICH noch nicht final -
# hier deshalb bewusst NUR Skillpunkt-Kosten und Baumstruktur, keine
# erfundenen Kampfwerte. Arcana/Resurrection bleiben leer, bis Might
# vollständig steht (siehe Vorlage Punkt 32, Implementierungs-
# reihenfolge).
#
# Jeder Skill-Eintrag (Dictionary):
#   "id"             StringName, eindeutig INNERHALB eines Pfads
#   "type"           &"active" ([A] in der Vorlage) oder &"passive"
#                    ([P] in der Vorlage)
#   "cost"           int, wie viele Skillpunkte er kostet
#   "prerequisites"  Array[StringName] - leer = keine Voraussetzung
#                    (Start des Baums). Mehrere Einträge bedeuten
#                    ODER (mindestens EINER davon muss schon
#                    freigeschaltet sein) - wichtig für Warlord, der
#                    laut Vorlage nur EINEN Skill aus der 2-Punkte-
#                    Reihe braucht, nicht alle drei.
#   "min_points_invested"  optional int (0 = kein Minimum) -
#                    zusätzliche Bedingung "insgesamt schon X
#                    Skillpunkte in diesem Pfad ausgegeben", siehe
#                    Warlord (Vorlage Punkt 26: "aktuell 6, sollte
#                    konfigurierbar bleiben" - deshalb hier als
#                    einfacher Datenwert statt hart codiert).
#   "tier"           int, Reihe im Baum (0 = Start, wächst nach
#                    unten) - rein fürs Platzhalter-UI-Layout.
#   "branch"         int, welcher der 3 Äste (0=Vitality/Defense,
#                    1=Bloodlust/Offense, 2=Double Roll/Mobility),
#                    -1 für Charged Strike (Start) und Warlord
#                    (Ende) - ebenfalls nur fürs UI-Layout.
#   "ability_id"     StringName - für aktive Skills die spätere
#                    Q/E-Fähigkeits-ID (noch ungenutzt, kommt erst
#                    mit den Ability-Slots, Vorlage Punkt 27/29).
#                    Bei passiven Skills leer.
#   "name_key"       Übersetzungsschlüssel für den Namen
#   "desc_key"       Übersetzungsschlüssel für die Beschreibung


# ============================================================
# PFAD DER STÄRKE (PATH OF MIGHT)
# ============================================================

const PATH_STRENGTH_SKILLS: Array[Dictionary] = [
	{
		"id": &"charged_strike",
		"type": &"active",
		"cost": 1,
		"prerequisites": [],
		"tier": 0,
		"branch": -1,
		"ability_id": &"charged_strike",
		"name_key": "skill.charged_strike.name",
		"desc_key": "skill.charged_strike.desc",
	},
	{
		"id": &"vitality",
		"type": &"passive",
		"cost": 1,
		"prerequisites": [&"charged_strike"],
		"tier": 1,
		"branch": 0,
		"ability_id": &"",
		"name_key": "skill.vitality.name",
		"desc_key": "skill.vitality.desc",
	},
	{
		"id": &"bloodlust",
		"type": &"passive",
		"cost": 1,
		"prerequisites": [&"charged_strike"],
		"tier": 1,
		"branch": 1,
		"ability_id": &"",
		"name_key": "skill.bloodlust.name",
		"desc_key": "skill.bloodlust.desc",
	},
	{
		"id": &"double_roll",
		"type": &"passive",
		"cost": 1,
		"prerequisites": [&"charged_strike"],
		"tier": 1,
		"branch": 2,
		"ability_id": &"",
		"name_key": "skill.double_roll.name",
		"desc_key": "skill.double_roll.desc",
	},
	{
		"id": &"iron_skin",
		"type": &"active",
		"cost": 1,
		"prerequisites": [&"vitality"],
		"tier": 2,
		"branch": 0,
		"ability_id": &"iron_skin",
		"name_key": "skill.iron_skin.name",
		"desc_key": "skill.iron_skin.desc",
	},
	{
		"id": &"ground_slam",
		"type": &"active",
		"cost": 1,
		"prerequisites": [&"bloodlust"],
		"tier": 2,
		"branch": 1,
		"ability_id": &"ground_slam",
		"name_key": "skill.ground_slam.name",
		"desc_key": "skill.ground_slam.desc",
	},
	{
		"id": &"dash_slash",
		"type": &"active",
		"cost": 1,
		"prerequisites": [&"double_roll"],
		"tier": 2,
		"branch": 2,
		"ability_id": &"dash_slash",
		"name_key": "skill.dash_slash.name",
		"desc_key": "skill.dash_slash.desc",
	},
	{
		"id": &"parry",
		"type": &"active",
		"cost": 2,
		"prerequisites": [&"iron_skin"],
		"tier": 3,
		"branch": 0,
		"ability_id": &"parry",
		"name_key": "skill.parry.name",
		"desc_key": "skill.parry.desc",
	},
	{
		"id": &"execution",
		"type": &"passive",
		"cost": 2,
		"prerequisites": [&"ground_slam"],
		"tier": 3,
		"branch": 1,
		"ability_id": &"",
		"name_key": "skill.execution.name",
		"desc_key": "skill.execution.desc",
	},
	{
		"id": &"backstep",
		"type": &"active",
		"cost": 2,
		"prerequisites": [&"dash_slash"],
		"tier": 3,
		"branch": 2,
		"ability_id": &"backstep",
		"name_key": "skill.backstep.name",
		"desc_key": "skill.backstep.desc",
	},
	{
		"id": &"warlord",
		"type": &"passive",
		"cost": 3,
		# Absichtlich ODER (mindestens EINER der drei 2-Punkte-Skills,
		# siehe Vorlage Punkt 26), nicht alle drei gleichzeitig -
		# das ist genau der Sinn von "prerequisites" als Array.
		"prerequisites": [&"parry", &"execution", &"backstep"],
		# Konfigurierbarer Mindestwert statt hart codiert (Vorlage
		# Punkt 26: "aktuell 6, sollte konfigurierbar bleiben").
		"min_points_invested": 6,
		"tier": 4,
		"branch": -1,
		"ability_id": &"",
		"name_key": "skill.warlord.name",
		"desc_key": "skill.warlord.desc",
	},
]


# ============================================================
# ZUGRIFF
# ============================================================

const SKILLS_BY_PATH: Dictionary = {
	&"skill_path.strength": PATH_STRENGTH_SKILLS,
	&"skill_path.arcana": [],
	&"skill_path.resurrection": [],
}


static func get_skills_for_path(path_key: StringName) -> Array[Dictionary]:
	var skills: Array = SKILLS_BY_PATH.get(path_key, [])

	# Explizit typisiert zurückgeben (Godot gibt bei .get() auf einem
	# Dictionary sonst ein untypisiertes Array zurück).
	var result: Array[Dictionary] = []

	for skill in skills:
		result.append(skill)

	return result


static func get_skill(
	path_key: StringName,
	skill_id: StringName
) -> Dictionary:
	for skill in get_skills_for_path(path_key):
		if skill.get("id", &"") == skill_id:
			return skill

	return {}


# ============================================================
# SKILL-ICONS
# ============================================================

# Dieselbe Bilddatei wie beim "Skill Tree Icons"-AnimatedSprite2D auf
# der Schwertstatur (Objects/Staturen/schwertsatur.tscn), hier aber
# direkt geladen und per Rect2-Ausschnitt (AtlasTexture, siehe
# get_skill_icon_texture()/get_locked_icon_texture() unten) verwendet -
# der Skill-Baum (Game/skill_tree_menu.gd) UND das HUD (Player/hud.gd,
# aktiver Skill-Slot) brauchen dieselben Icons, deshalb hier zentral
# an EINER Stelle statt doppelt gepflegt.
const _STRENGTH_SKILL_ICON_ATLAS: Texture2D = preload(
	"res://Player/Icons/Kireger skill tree/ICONS FERTIG.png"
)

# skill_id -> Rect2(x, y, 42, 42)-Ausschnitt im obigen Atlas - 1:1 aus
# den Animationsnamen/-regionen des "Skill Tree Icons"-Sprites in
# schwertsatur.tscn übernommen, nur nach Skill-ID statt nach
# Animationsname sortiert (Zuordnung von Hand geprüft: "Charge
# Attack" -> charged_strike, "Iron SKin" -> iron_skin, "double roll"
# -> double_roll, usw.).
const _STRENGTH_SKILL_ICON_REGIONS: Dictionary = {
	&"charged_strike": Rect2(0, 0, 42, 42),
	&"vitality": Rect2(42, 0, 42, 42),
	&"bloodlust": Rect2(84, 0, 42, 42),
	&"double_roll": Rect2(126, 0, 42, 42),
	&"iron_skin": Rect2(168, 0, 42, 42),
	&"ground_slam": Rect2(210, 0, 42, 42),
	&"dash_slash": Rect2(252, 0, 42, 42),
	&"parry": Rect2(294, 0, 42, 42),
	&"execution": Rect2(0, 42, 42, 42),
	&"backstep": Rect2(42, 42, 42, 42),
	&"warlord": Rect2(84, 42, 42, 42),
}

# Eigenes Icon (Animation &"Locked" im "Skill Tree Icons"-Sprite) für
# noch verdeckte ("hidden") Skills - EIN Icon pro Pfad, unabhängig
# vom konkreten Skill dahinter.
const _STRENGTH_SKILL_LOCKED_ICON_REGION: Rect2 = Rect2(126, 42, 42, 42)

# path_key -> Icon-Atlas-Textur bzw. -Regionen-Dictionary/-Locked-
# Region. Arkana/Auferstehung haben noch keine eigenen Icons (siehe
# PATH_STRENGTH_SKILLS oben, dort aktuell leere Skill-Listen) - fehlt
# ein Eintrag, fallen get_skill_icon_texture()/get_locked_icon_
# texture() automatisch auf null zurück.
const _SKILL_ICON_ATLAS_BY_PATH: Dictionary = {
	&"skill_path.strength": _STRENGTH_SKILL_ICON_ATLAS,
}
const _SKILL_ICON_REGIONS_BY_PATH: Dictionary = {
	&"skill_path.strength": _STRENGTH_SKILL_ICON_REGIONS,
}
const _SKILL_LOCKED_ICON_REGION_BY_PATH: Dictionary = {
	&"skill_path.strength": _STRENGTH_SKILL_LOCKED_ICON_REGION,
}


# Liefert - falls für "path_key"/"skill_id" eine Region hinterlegt
# ist - das passende Icon als eigene AtlasTexture, sonst null (z.B.
# für Pfade, die noch keine eigenen Icons haben).
static func get_skill_icon_texture(
	path_key: StringName,
	skill_id: StringName
) -> Texture2D:
	var regions: Dictionary = _SKILL_ICON_REGIONS_BY_PATH.get(
		path_key, {}
	)

	if not regions.has(skill_id):
		return null

	return _build_icon_atlas_texture(path_key, regions[skill_id])


# Liefert das "verdeckt"-Icon für "path_key" (siehe HINWEIS oben),
# sonst null.
static func get_locked_icon_texture(path_key: StringName) -> Texture2D:
	if not _SKILL_LOCKED_ICON_REGION_BY_PATH.has(path_key):
		return null

	return _build_icon_atlas_texture(
		path_key,
		_SKILL_LOCKED_ICON_REGION_BY_PATH[path_key]
	)


static func _build_icon_atlas_texture(
	path_key: StringName,
	region: Rect2
) -> Texture2D:
	var atlas: Texture2D = _SKILL_ICON_ATLAS_BY_PATH.get(path_key)

	if atlas == null:
		return null

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = region

	return atlas_texture
