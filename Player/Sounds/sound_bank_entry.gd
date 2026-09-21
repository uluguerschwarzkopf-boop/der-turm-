class_name SoundEntry
extends Resource

# ============================================================
# EIN SOUND MIT EIGENER LAUTSTÄRKE & GESCHWINDIGKEIT (NUTZER-WUNSCH)
# ============================================================
#
# Wert-Typ für Player/player_sound_manager.gd -> sound_bank: pro
# Sound-Name (der Schlüssel in der Sound Bank) genau EIN Eintrag mit
# der Audiodatei UND direkt darunter ihrer eigenen Lautstärke UND
# Geschwindigkeit - alles an einer Stelle, kein weiteres Feld
# irgendwo anders, das von Hand mit demselben Namen abgeglichen
# werden müsste.

# Die Audiodatei selbst - aus dem FileSystem-Tab hier reinziehen.
@export var clip: AudioStream = null

# Lautstärke NUR für diesen einen Sound - 1.0 = normal, 0.5 = halb so
# laut, 0.0 = stumm. Wirkt ZUSÄTZLICH zur allgemeinen Sound-
# Lautstärke (siehe Player/player_sound_manager.gd -> volume_
# multiplier) und zum "Soundeffekte"-Regler in den Einstellungen -
# alle drei multiplizieren sich miteinander.
@export_range(0.0, 1.0, 0.01) var volume: float = 1.0

# 1.0 = normale Geschwindigkeit, 0.5 = halb so schnell (klingt
# dadurch automatisch auch tiefer), 2.0 = doppelt so schnell (klingt
# automatisch höher) - Godots AudioStreamPlayer kann Geschwindigkeit
# nicht unabhängig von der Tonhöhe ändern, beides hängt zusammen.
@export_range(0.1, 3.0, 0.01) var speed: float = 1.0
