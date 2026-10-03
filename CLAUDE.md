# Occultra (Projektordner: der-turm-)

Diese Datei liest Claude Code automatisch beim Start in diesem Ordner. Sie beschreibt das Spiel, den Code-Aufbau und wie Nico gerne arbeitet. Wenn sich am Spiel etwas Grundlegendes ändert, diese Datei mit aktualisieren.

## Wer und wie

Entwickler ist Nico. Er schreibt Deutsch, schnell und mit vielen Tippfehlern; einfach sinngemäß verstehen und auf Deutsch antworten. Er baut Szenen, Animationen und Hitboxen selbst im Godot-Editor und lässt sich den GDScript-Code schreiben.

So möchte Nico arbeiten:

- Alle sinnvollen Werte als `@export` im Inspektor einstellbar machen (Schaden, Cooldowns, Dauer, Animationsnamen, Frames), gruppiert mit `@export_group`.
- Fragt er "habe ich was vergessen?", wirklich mitdenken und bei echten Unklarheiten eine kurze Zwischenfrage stellen, bevor programmiert wird. Eine Empfehlung als erste Option nennen.
- Wenn er sich gegen eine Empfehlung entscheidet, seine Entscheidung umsetzen und später nicht wieder zurückdrehen.
- Nichts an Szenen (`.tscn`) oder Kunst ändern, was er nicht verlangt hat. Er editiert `.tscn`-Dateien oft parallel im Editor, deshalb `.tscn` nur anfassen, wenn nötig, und vorher den aktuellen Stand lesen.
- Im Code kommentieren, warum etwas so gebaut ist, auf Deutsch. Bisherige Konvention: Kommentare beginnen oft mit "Nutzer-Wunsch:" oder "Nutzer-Korrektur:" und verweisen auf die zugehörigen Dateien/Funktionen.
- Nach jeder Änderung kurz sagen, welche Datei geändert wurde, und daran erinnern, die Szene/das Skript in Godot neu zu laden und zu testen. Claude kann das Spiel nicht selbst starten; Ursachen, die sich nur statisch vermuten lassen, ehrlich als Vermutung kennzeichnen.

## Das Spiel

Occultra ist ein 2D-Pixel-Art-Action-Platformer mit Roguelite-Runs, gebaut in Godot 4.6 (Forward Plus, 1920x1080, Fenster im Vollbild). Der Spieler steigt durch einen Turm ("der Turm"), Gebiet für Gebiet. Ein Run besteht aus zufälligen Kampfräumen, einem Shop (Händler mit Pack-Lizard), einem Miniboss und einem Bossraum am Ende des Gebiets. Stirbt der Spieler, startet der Run neu. Ganz oben im Turm ist "die Leere" gefangen, eine Stimme, die mit dem Spieler spricht (z.B. beim Betreten eines Bossraums, siehe `Game/void_narration.gd`).

Startwerte eines Runs stehen in `Game/run_state.gd` (3 Herzen, 2 Tränke, kein Bogen). Es gibt Gold, Truhen (Bronze/Silber/Gold), Rüstung (Schild aus dem Shop, Iron Skin aus dem Skill-Baum, jeweils 1 Treffer geblockt), Bogen + Pfeile, bis zu 3 Zauber-Slots und einen Skill-Baum (Pfad der Stärke ist ausgearbeitet; Arcana und Resurrection sind noch leer).

Steuerung: A/D laufen, Leertaste springen, Shift rollen, Linksklick angreifen, Rechtsklick Bogen, Q Trank, V interagieren, 1/2/3 Zauber, S durch Plattformen fallen, T Skill-Baum.

Sprachen: Deutsch (Standard) und Englisch. Alle Texte laufen über das `TRANSLATIONS`-Dictionary in `Game/settings_manager.gd`; neue Texte dort mit Schlüssel eintragen, nicht hart in den Code schreiben.

## Ordnerstruktur

- `Game/` Autoloads und Menüs. Autoloads: `SettingsManager`, `GoldSystem`, `RunState`, `CutsceneManager`, `SaveManager`, `PauseMenu`, `MusicManager`, `SkillTreeMenu`, `EnemySoundManager`. Hauptszene: `Game/main_menu.tscn`.
- `Player/` Spieler. `player.gd` ist der Kern (Bewegung, Rolle, aktive Skills, Statuseffekte), daneben `player_combat.gd`, `player_health.gd`, `player_bow.gd`, `spell_manager.gd`, `player_summons.gd`, `hud.gd`. Zauber (Feuerball, Eis, Blitz, Licht-Orb, Wurzeln, beschworenes Skelett) unter `Player/Spells/`.
- `Mobs/Gebiet 1/` Skelett, Skelett-Archer (mit Pfeil), Bush Mob. `Mobs/Gebiet 2/` Ratte, Fledermaus gros, Schatten Mutant, Spinne gros (mit Spinnenwebenball). Achtung: `Mobs/Skellete/` gibt es zusätzlich, vermutlich eine ältere Kopie. Vor Änderungen an Skeletten prüfen, welche Datei die Szenen wirklich benutzen.
- `mini bosse/Skelleton Tank/` Miniboss Gebiet 1. `Bosse/Gebiet_1/` Feuerritter, Phase 1 und Phase 2 (Fire Lord) mit Cutscene.
- `Levels/Gebiet 1/` Räume level_01 bis level_7, Skill-Baum-Raum. `Levels/Gebiet 2/` ist im Aufbau (Räume, Hintergründe, Tilesets, Fackeln). `Levels/room_manager.gd` steuert Raumwechsel, Tod und Bossphasen.
- `Händler/`, `Objects/` (Türen, Truhen, Fallen, Statuen, Deko), `details/`, `Musik/`, `Fonts/`, `Debug Stuff/`.

Ordner- und Dateinamen enthalten Leerzeichen und Umlaute (z.B. `Mobs/Gebiet 2/Spinne gros/`, `Händler/`). Pfade immer in Anführungszeichen setzen. Wo Ordner schon einmal umbenannt wurden, lieber UIDs statt `res://`-Pfade verwenden (siehe Kommentar zu `BOSS_ROOM_PATH` in `run_state.gd`).

## Wie Mobs gebaut sind

Alle Mobs folgen demselben Muster; für einen neuen Mob den ähnlichsten bestehenden als Vorlage nehmen (Nahkampf: `ratte.gd`, Fernkampf mit Projektil: `skeleton_archer.gd` + `arrow.gd`, Fern- und Nahkampf kombiniert: `spinne_gros.gd`).

- `CharacterBody2D` mit `enum State` und `match state` in `_physics_process()`. Zustände z.B. SLEEP, IDLE, WALK, ATTACK, HURT/WEGSPRINGEN, DEAD.
- `_try_start_attack_if_in_range()` wird in jeder Entscheidungsfunktion als Erstes geprüft, damit "Ziel in Reichweite" immer Vorrang vor Laufen/Umdrehen hat.
- Treffer durch den Spieler erkennt die `Hurtbox` (Area2D) des Mobs selbst: per `area_entered` und zusätzlich jeden Physik-Frame per `get_overlapping_areas()`. Die Waffe muss in der Gruppe `player_attack` sein und `meta("active") == true` haben. `damage_hit_locked` verhindert Doppeltreffer, `invincible` blockt Treffer (außer während eigener Angriffs-States).
- Schaden zu bestimmten Animationsframes über `sprite.frame_changed`. Spinne gros Nahkampf trifft auf Nicos Wunsch nur exakt auf `melee_active_frame` (nicht "ab Frame").
- Robustheit: State-Ende nicht nur über `animation_finished`, sondern zusätzlich mit einem Timer aus Frameanzahl/FPS absichern, sonst können Mobs dauerhaft hängen bleiben (z.B. für immer unverwundbar).
- Gebiet-2-Mobs lassen den Spieler durch ihren Körper laufen (`add_collision_exception_with(player)`); Treffer laufen trotzdem über Areas.
- Ziele sind der Spieler (Gruppe `player`) und beschworene Skelette (Gruppe `player_summon`, Hurtbox-Fallback, weil deren Body `collision_layer = 0` hat).
- Blickrichtung/Spiegeln hängt davon ab, in welche Richtung die Grafik gezeichnet ist. Ratte, Schatten Mutant und der Spinnenwebenball sind nach RECHTS gezeichnet, der Archer-Pfeil nach LINKS. Nie raten, im Zweifel Nico fragen oder testen lassen.
- Sounds über den Autoload `EnemySoundManager` (Kategorien `skelette`, `mini_boss`, `boss`; Gebiet-2-Mobs nutzen `skelette`).

## Spieler: aktive Skills und Statuseffekte

Aktive Skills (Charge Attack, Ground Slam, Iron Skin, Dash Slash, Backstep, Parry) und Statuseffekte arbeiten jeweils mit einem Bool-Flag (z.B. `_parry_active`, `_web_wrapped_active`). Das Flag wird in `_is_active_skill_busy()` eingetragen (blockt Eingaben in `_input()`) und hat einen frühen Return-Zweig in `_physics_process()`. Für Wartezeiten in Coroutinen `_wait_safely()` bzw. `_wait_safely_for_animation()` benutzen, die prüfen, ob der Spieler noch lebt und kein Szenenwechsel läuft. Neue Flags auch in `_on_died()` zurücksetzen.

Eingesponnen: Trifft der Spinnenwebenball den Spieler, ruft er `start_web_wrap(dauer)` auf. Der Spieler kann sich dann nicht bewegen und nicht angreifen, spielt "Spieler eingespinnt", danach "spieler eingespinnt brechen". Die Dauer ist an der Spinne gros einstellbar (`web_wrap_duration`).

## Stand und offene Punkte (Oktober 2026)

- Spinne gros ist komplett: Ei-Schlüpfen (alte Spinne bleibt als Eierschale stehen, neue Spinne wird gespawnt), Fernkampf (Spucken, Spinnenwebenball), Wegspringen nach Treffer, Nahkampf mit eigenem Cooldown über "Nahkampfangriff Area" (Form im Editor bestimmt die Reichweite). Steht der Spieler in ihrer Hurtbox, macht sie den Nahkampfangriff. Kein Wegspringen bei Überlappung, das hat Nico bewusst wieder entfernt.
- Zuletzt behoben, von Nico noch nicht bestätigt: Spinne gros hat den Nahkampf nur einmal gemacht (Fern- und Nahkampf-Cooldown haben sich gegenseitig unterbrochen). Die zweiten `_decide_next_state()`-Aufrufe in `_finish_attack()`/`_finish_melee_attack()` sind jetzt gegen den jeweils anderen Angriff abgesichert.
- Gelegentlich nicht treffbare Spinne gros: Nico hat die Hitbox-Größen selbst im Editor angepasst; beobachten, ob das Problem bleibt.
- Bossraum: Spieler blieb nach der Leere-Erzählung manchmal gesperrt. `void_narration.gd` entsperrt jetzt in jedem Fall; Ursache nicht 100 % bestätigt.
- Gebiet 2 hat noch keinen eigenen Raum-Ablauf in `run_state.gd` (dort sind bisher nur die Räume von Gebiet 1 eingetragen).
- Das Projekt ist ein Git-Repository. Vor größeren Änderungen hilft `git status`/`git diff`, um zu sehen, was Nico zuletzt im Editor geändert hat.
