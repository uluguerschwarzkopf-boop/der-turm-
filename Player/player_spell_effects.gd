extends Node2D


# ============================================================
# ZENTRALE EINSTELLUNGEN FÜR ALLE ZAUBER-EFFEKTE
# ============================================================

# Hier werden ALLE Werte für Status-Effekte eingestellt, die
# der Spieler mit seinen Zaubern auf Gegner anwendet (Dauer,
# Stärke, Farben). Die eigentliche Anwendung übernimmt
# enemy_spell_effects.gd am jeweiligen Gegner - dieses Script
# liefert nur die Zahlen, damit man alles an einer Stelle im
# Inspector einstellen kann, statt in jedem Zauber-Script
# einzeln.
#
# Später kann dasselbe Prinzip umgekehrt verwendet werden
# (z.B. ein Boss, der dem Spieler einen Effekt gibt) - dafür
# würde man ein analoges Script an den Boss hängen.


# ============================================================
# PARALYSE (BLITZ)
# ============================================================

@export_group("Paralyse (Blitz)")

@export var paralyze_duration: float = 1.5

@export var paralyze_tint_color: Color = Color(
	1.0,
	0.78,
	0.05,
	1.0
)

@export_range(0.0, 1.0, 0.01)
var paralyze_tint_strength: float = 0.55

@export var paralyze_pause_animations: bool = true
@export var paralyze_disable_physics: bool = true
@export var paralyze_disable_process: bool = true


# ============================================================
# EINFRIEREN (EIS)
# ============================================================

@export_group("Einfrieren (Eis)")

@export var freeze_duration: float = 2.5

# 0.0 = Gegner steht während des Einfrierens komplett still.
# 1.0 = keine Verlangsamung (Effekt wäre wirkungslos).
@export_range(0.0, 1.0, 0.01)
var freeze_slow_multiplier: float = 0.35

# Keine Einfärbung mehr - stattdessen spawnt Eis-Partikel
# (siehe PlayerSpellParticles / player_spell_particles.gd).


# ============================================================
# FESTHALTEN (RANKEN)
# ============================================================

@export_group("Festhalten (Ranken)")

# Die eigentliche Dauer richtet sich nach der Ranken-Animation
# selbst (roots_hold.gd hebt die Wurzel exakt dann wieder auf,
# wenn die Animation verschwindet). Das hier ist nur ein
# Sicherheits-Timeout, falls das mal nicht passiert
# (z.B. der Gegner stirbt mitten in der Animation).
@export var root_safety_duration: float = 4.0


# ============================================================
# VERLANGSAMEN (LICHTKUGEL-AURA)
# ============================================================

@export_group("Verlangsamen (Lichtkugel-Aura)")

@export_range(0.0, 1.0, 0.01)
var lightorb_enemy_slow_multiplier: float = 0.5

@export_range(0.0, 1.0, 0.01)
var lightorb_projectile_slow_multiplier: float = 0.35
