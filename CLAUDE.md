# Occultra – Projektregeln für Claude

Diese Datei liest Claude Code automatisch beim Start in diesem Ordner. Wenn sich am Spiel etwas Grundlegendes ändert, diese Datei mit aktualisieren.

2D-Pixel-Art-Tower-Climbing-Roguelike in **Godot 4.7.2** (GDScript).
Turmaufstieg, vergleichbar mit Hollow Knight. Wirkt schlicht, ist aber dunkel und tiefgründig:
Ambient-Musik, Death Traps, Gore-Momente.
Story: Ein Orden erschafft Mutationen und Assassinen. Ein Magier befreit Schattenwesen,
indem er ihre Rüstung sprengt.

Team:
- Nico (dieser Rechner)
- sein Bruder: Design, Art, Animation, Sound. **Er hat die visuelle Hoheit und das Veto bei Stilfragen.**
- sein Cousin: Marketing

Art entsteht in Aseprite mit dem PixelLab-AI-Plugin. Zusätzlich gibt es einen Fiverr-Artist im Testauftrag.

Zeitplan: Demo in ca. 3–4 Monaten, Release in 6–12 Monaten (Ziel: Steam, Release-Fenster „2027“).

## Arbeitsregeln (wichtig)

- **Nichts am Projekt ändern ohne ausdrückliches Go.** Erst kurz zusammenfassen, was geändert würde, dann auf "go"/"los" warten.
- Antworten auf Deutsch. Erst die gestellte Frage direkt beantworten, ohne langen Vorbau.
- Kritisch und ungeschönt bewerten, aber immer mit konkretem Lösungsweg.
- Fachbegriffe verwenden, aber kurz in Klammern erklären.
- Vor dem Schreiben einer `.tscn`: Nico soll die Szene im Godot-Editor speichern/schließen. Sonst überschreibt Godot die Änderung, oder nach der Änderung "Von Festplatte neu laden" wählen.
- Nach Änderungen an Szenen/Skripten wenn möglich headless prüfen, ob alles fehlerfrei lädt.
- Godot-Version ist 4.7.2. Der Bruder hatte noch 4.6, deshalb kommt es zu Versions-Ping-Pong in `project.godot` (`config/features`). Das ist kein Bug, alle sollten 4.7.2 nutzen.
- Git-Konflikte in `.tscn`: eine Version behalten und die kleine Änderung neu einbauen, nicht von Hand mergen.
- Nico schreibt schnell und mit vielen Tippfehlern; einfach sinngemäß verstehen. Er baut Szenen, Animationen und Hitboxen selbst im Godot-Editor und lässt sich den GDScript-Code schreiben.
- Alle sinnvollen Werte als `@export` im Inspektor einstellbar machen (Schaden, Cooldowns, Dauer, Animationsnamen, Frames), gruppiert mit `@export_group`.
- Fragt er "habe ich was vergessen?", wirklich mitdenken und bei echten Unklarheiten eine kurze Zwischenfrage stellen, bevor programmiert wird. Eine Empfehlung als erste Option nennen.
- Wenn er sich gegen eine Empfehlung entscheidet, seine Entscheidung umsetzen und später nicht wieder zurückdrehen.
- Nichts an Szenen (`.tscn`) oder Kunst ändern, was er nicht verlangt hat. `.tscn` nur anfassen, wenn nötig, und vorher den aktuellen Stand lesen.
- Im Code auf Deutsch kommentieren, warum etwas so gebaut ist. Bisherige Konvention: Kommentare beginnen oft mit "Nutzer-Wunsch:" oder "Nutzer-Korrektur:".
- Nach jeder Änderung kurz sagen, welche Datei geändert wurde, und daran erinnern, die Szene/das Skript in Godot neu zu laden und zu testen. Was sich nur statisch vermuten lässt, ehrlich als Vermutung kennzeichnen.
- Vor größeren Änderungen `git status`/`git diff` ansehen, um zu sehen, was Nico zuletzt im Editor geändert hat.

## Spielsystem

Occultra ist ein 2D-Pixel-Art-Action-Platformer mit Roguelite-Runs, gebaut in Godot 4.7.2 (Forward Plus, 1920x1080, Fenster im Vollbild). Der Spieler steigt durch einen Turm ("der Turm"), Gebiet für Gebiet. Ein Run besteht aus zufälligen Kampfräumen, einem Shop (Händler mit Pack-Lizard), einem Miniboss und einem Bossraum am Ende des Gebiets. Stirbt der Spieler, startet der Run neu. Ganz oben im Turm ist "die Leere" gefangen, eine Stimme, die mit dem Spieler spricht (z.B. beim Betreten eines Bossraums, siehe `Game/void_narration.gd`).

Startwerte eines Runs stehen in `Game/run_state.gd` (3 Herzen, 2 Tränke, kein Bogen). Es gibt Gold, Truhen (Bronze/Silber/Gold), Rüstung (Schild aus dem Shop, Iron Skin aus dem Skill-Baum, jeweils 1 Treffer geblockt), Bogen + Pfeile, bis zu 3 Zauber-Slots und einen Skill-Baum (Pfad der Stärke ist ausgearbeitet; Arcana und Resurrection sind noch leer).

Steuerung: A/D laufen, Leertaste springen, Shift rollen, Linksklick angreifen, Rechtsklick Bogen, Q Trank, V interagieren, 1/2/3 Zauber, S durch Plattformen fallen, T Skill-Baum.

Sprachen: Deutsch (Standard) und Englisch. Alle Texte laufen über das `TRANSLATIONS`-Dictionary in `Game/settings_manager.gd`; neue Texte dort mit Schlüssel eintragen, nicht hart in den Code schreiben.

## Ordnerstruktur

- `Game/` Autoloads und Menüs. Autoloads: `SettingsManager`, `GoldSystem`, `RunState`, `CutsceneManager`, `SaveManager`, `PauseMenu`, `MusicManager`, `SkillTreeMenu`, `EnemySoundManager`. Hauptszene: `Game/main_menu.tscn`.
- `Player/` Spieler. `player.gd` ist der Kern (Bewegung, Rolle, aktive Skills, Statuseffekte), daneben `player_combat.gd`, `player_health.gd`, `player_bow.gd`, `spell_manager.gd`, `player_summons.gd`, `hud.gd`. Zauber (Feuerball, Eis, Blitz, Licht-Orb, Wurzeln, beschworenes Skelett) unter `Player/Spells/`.
- `Mobs/Gebiet 1/` Skelett, Skelett-Archer (mit Pfeil), Bush Mob. `Mobs/Gebiet 2/` Ratte, Fledermaus gros, Schatten Mutant, Spinne gros (mit Spinnenwebenball). Achtung: `Mobs/Skellete/` gibt es zusätzlich, vermutlich eine ältere Kopie. Vor Änderungen an Skeletten prüfen, welche Datei die Szenen wirklich benutzen.
- `mini bosse/Skelleton Tank/` Miniboss Gebiet 1. `Bosse/Gebiet_1/` Feuerritter, Phase 1 und Phase 2 (Fire Lord) mit Cutscene.
- Level-Ordner (`Levels/` bzw. in Nicos aktuellem Checkout `Ebenen/`, siehe Hinweis unten): `Gebiet 1/` Räume level_01 bis level_7, Skill-Baum-Raum. `Gebiet 2/` ist im Aufbau (Räume, Hintergründe, Tilesets, Fackeln). `room_manager.gd` im Level-Ordner steuert Raumwechsel, Tod und Bossphasen.
- `Händler/`, `Objects/` (Türen, Truhen, Fallen, Statuen, Deko), `details/`, `Musik/`, `Fonts/`, `Debug Stuff/`.

Ordner- und Dateinamen enthalten Leerzeichen und Umlaute (z.B. `Mobs/Gebiet 2/Spinne gros/`, `Händler/`). Pfade immer in Anführungszeichen setzen. Wo Ordner schon einmal umbenannt wurden, lieber UIDs statt `res://`-Pfade verwenden (siehe Kommentar zu `BOSS_ROOM_PATH` in `run_state.gd`).

Hinweis Pfade: In Nicos Ordner heißt der Level-Ordner aktuell `Ebenen/`, in älteren Notizen (auch in den Pfaden weiter unten) steht `Levels/`. Vor dem Benutzen eines Pfads prüfen, welcher Ordner wirklich existiert. Die Spinne gros lag beim letzten Blick noch nicht in Nicos Checkout (`Mobs/Gebiet 2/` enthielt nur Ratte, Fledermaus gros, schatten mutant); ggf. erst `git pull`.

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

## Stilvorgaben (Ziel: INMOST-artig, ernst statt Mobile-Look)

- Kaltes, dunkles **Blau/Navy/Teal**. **Kein Grün** als Stimmungsfarbe.
- Begrenzte Palette, Tiefe über Helligkeit: Hintergrund heller/dunstiger, Vordergrund fast schwarz.
- Silhouetten mit heller Oberkante (Rim Light) statt viel Innendetail. **Keine schwarzen Outlines.**
- Warme Akzente nur sparsam (Fackeln, Kerzen).
- **Shader nie pixelig/quantisiert** – weiche Übergänge, Blur und Glow sind erwünscht.
- Lichtstrahlen statisch (nur leichtes "Atmen"), kein Flackern.

## Wichtige Pfade

- Testraum Gebiet 2 (Kerker/Verlies): `Levels/Gebiet 2/Räume/Raum1.tscn`
- Hintergrund-Szene: `Levels/Gebiet 2/Hintergründe/Hintergrund 1/gebiet_2_hintergrund_1.tscn` (+ `.gd`)
- Vordergrund-Geländer: `details/Gebiet 2/Vordergrund/vordergrund.tscn` (als Instanz in der Hintergrund-Szene)
- Shader: `Levels/Gebiet 2/shader/` (`ebene_look`, `nebel_blur`, `lichtstrahlen`, `Partikelshader`; `fogdshader` ist alt/ungenutzt)
- Fackel-Flackern: `Levels/Gebiet 2/shader/torch_light_flicker.gd`
- Wandfackel: `Levels/Gebiet 2/Objekte/Beleuchtung/wand_fackel.tscn`
- Kamera-Grenzen: `Levels/Gebiet 1/camera_bounds.gd` (setzt Camera2D-Limits aus der CollisionShape2D)
- Dev-Raumauswahl im Hauptmenü: `Game/main_menu.gd` (Pfade dort fest eingetragen; bei verschobenen Szenen anpassen)
- Godot-Logs: `C:\Users\Nico\AppData\Roaming\Godot\app_userdata\Occultra\logs\godot.log`
- Schatten-Mutant (Gegner): `Mobs/Gebiet 2/schatten mutant/`

## Technisches Setup Gebiet 2 (Raum1)

### Licht
- `Darkness` = CanvasModulate `Color(0.1, 0.13, 0.24)`. **Nur ein CanvasModulate pro Canvas**, sonst ist das Ergebnis undefiniert.
- Hintergrund-Sprites: `light_mask = 0` → werden von Fackeln NICHT beleuchtet, aber von Darkness abgedunkelt.
  - NICHT `Unshaded` verwenden: das ignoriert auch Darkness und macht alles grell.
- Materials auf einem Node2D vererben sich nicht an Kinder (nur mit `use_parent_material`).
- PointLight2D-Größe über `texture_scale`, nicht über ungleichmäßiges `scale`.
- Bekannt, noch offen: Die Wandfackel hat zwei Lichter übereinander (eins in `wand_fackel.tscn`, eins in Raum1) und ist oval skaliert.
- WorldEnvironment: Glow mit `background_mode = Canvas`, threshold 0.75, additiv. Kein HDR 2D (würde auf linearen Farbraum umschalten).

### Parallax (eigenes System!)
- `gebiet_2_hintergrund_1.gd` positioniert alle direkten Parallax2D-Kinder selbst:
  `Position = Basis + (Kameramitte − Anker) × (1 − scroll_scale)`.
  - Anker = Mitte der Kamera-Limits.
  - `lock_vertical` = keine vertikale Verschiebung.
  - Basis = Container-Position + `child.position` + `child.scroll_offset`.
- Grund: Parallax2D rechnet relativ zum Welt-Nullpunkt, deshalb sah es im Spiel verschoben aus.
- Neue Parallax-Ebenen deshalb **als Kind dieser Hintergrund-Szene** anlegen und über `scroll_offset` verschieben.
- `scroll_scale` < 1 = Hintergrund, > 1 = Vordergrund.

| Ebene | scroll_scale | z_index |
|---|---|---|
| Ebene 1 (Himmel) | 0.88 | −8 |
| Architektur fern | 0.84 | −8 |
| Ebene 2 | 0.9 | −7 |
| Ebene 3 | 0.92 | −6 |
| Ebene 4 | 0.95 | −5 |
| Ebene 5 | 0.96 | −4 |
| Ebene 6 (Statue, scharf) | 0.98 | −3 |
| Vordergrund Käfige | 1.08 | 5 |
| Vordergrund (Geländer) | 1.15 | 10 |

- Jede Ebene nutzt `ebene_look.gdshader`: brightness, saturation, tint (0.72, 0.84, 1), tint_amount, blur_radius, blur_mix. Weiter hinten = heller, entsättigter, mehr Blur.
- Das Geländer ist ein Sprite2D mit Region + `texture_repeat` (gekachelt).

### Nebel und Effekte (Node "Nebel" in Raum1)
- `nebel_blur.gdshader` liest den Bildschirm (`hint_screen_texture` + `textureLod`) und blurrt/färbt dahinter. **Vor jeder Nebellage ein BackBufferCopy (copy_mode Viewport).**
- Drei Lagen:

| Lage | z_index | max_alpha | blur |
|---|---|---|---|
| fern | −6 | 0.75 | 4 |
| hinten | −5 | 0.45 | 3 |
| vorne | −1 | 0.25 | 1.5 |

- `Lichtstrahlen`: ColorRect, z −5, `lichtstrahlen.gdshader` (blend_add, statisch).
- `Staub Gruppe 1–4`: GPUParticles2D, z −1, mit `Partikelshader.gdshader` (blend_add).
  - `INSTANCE_CUSTOM` nur in vertex() verfügbar → per varying weitergeben.
- Zeichenreihenfolge: z_index zuerst, bei Gleichstand entscheidet die Baumreihenfolge.
  - Gameplay liegt auf z 0, die TileMapback2 auf −1.

### Kamera
- Zoom 5.5, Fenster 1920×1080 (stretch canvas_items / expand) → sichtbar ca. 349×196 px.
- CameraBounds Raum1: Mitte (154, −223), Größe 864×177. Limits links −278, rechts 586, oben −312, unten −135.
- Die Höhe 177 ist kleiner als die sichtbaren 196 → unten wird ein Streifen über die Grenze hinaus gezeigt (dort sitzt das Geländer).

## Allgemeine Godot-Hinweise

- **TileMap ist seit 4.3 veraltet → TileMapLayer verwenden.**
  - In Teilen des Projekts ist das schon umgestellt.
  - Raum1 (Gebiet 2) nutzt noch alte `TileMap`-Nodes (`TileMap2`, `TileMapback2`, `TileMapfront`).
- Nach der Umstellung heißen die Nodes teils mit „2“ am Ende.
  - Vor dem Umbenennen projektweit nach Node-Pfaden suchen (z. B. `$TileMapBack`), sonst laufen Skriptzugriffe ins Leere.
- Ebenen-Reihenfolge: Back → Spieler-Ebene → Front. Kollisionen nur auf der Spieler-Ebene, nicht auf Hinter- oder Vordergrund.
- Tiles sind **16×16**.
  - Alles, was immer als Ganzes vorkommt (Türen, Bögen, Gitter), als große Kachel über mehrere Zellen anlegen.
  - Wände und Böden bleiben 16×16.
- Für Parallax nur `Parallax2D` verwenden, nicht das alte `ParallaxBackground`/`ParallaxLayer`.
  - In Gebiet 2 gilt das **eigene Positionierungs-System** (siehe oben). Allgemeine Parallax-Tipps wie „CanvasLayer −100“ oder scroll_scale 0.1–0.8 dort NICHT anwenden.
- `SCREEN_TEXTURE` gibt es in Godot 4 nicht mehr.
  - Stattdessen ein eigenes Uniform `sampler2D … : hint_screen_texture, filter_linear_mipmap` deklarieren.
  - Bei Alpha durch `a` teilen (premultiplied alpha, sonst dunkle Säume).
- Blur von Vordergrund-Elementen:
  - nicht per ColorRect mit Bildschirm-Blur, weil das auch alles dahinter verwischt;
  - in Gebiet 2 per `ebene_look.gdshader` direkt am Sprite gelöst;
  - für statische Grafiken ist Vorab-Blur in Aseprite die billigste Alternative.
- Der Warnhinweis bei CollisionShape2D unter CameraBounds ist kosmetisch.
  - Fix: CameraBounds per „Typ ändern“ zu Area2D machen, `monitoring` und `monitorable` aus.
  - Bei der Änderung prüfen, dass `camera_bounds.gd` weiter funktioniert (extends anpassen).
- Gegen Flimmern bei Pixel-Art optional: Projekteinstellungen → Rendering → 2D → „Snap 2D Transforms to Pixel“.
  - Vorher testen, ob Parallax und Partikel dann ruckeln.
- Animations-Richtwerte: Charakter ~10 fps, Deko-Idle (Flaggen, Banner) 4–6 fps.
  - Mehrere gleiche Deko-Objekte mit versetztem Startframe: `frame = randi() % frame_count`.

## PixelLab-Erfahrungswerte

- Strichstärke immer angeben („1-2 pixel tendrils“, „1 pixel wide cracks“), sonst entstehen Blobs.
- Auf dunkler Wand muss Bewuchs bzw. Detail HELLER sein als der Untergrund.
- Risse: der helle Pixel neben der dunklen Linie macht den Bruch.
  - Ungleich verteilen: 2–3 beschädigte Steine pro Kachel.
- Idle-Animationen hängender Objekte: „top edge stays fixed“, wenige Frames (4), max. 1–2 px Bewegung.
- Details (Risse, Ranken) in getrennten Durchläufen auf eigene Layer.
  - Mehrere Generierungen machen und die beste nehmen.
  - Farben am Ende auf die eigene Palette ziehen.
- „Target palette“ braucht ein nicht-leeres Dokument, sonst kommt der Fehler „Missing image: target palette“.

## Business-Kontext (nur relevant, wenn danach gefragt wird)

- Plattform: Steam zuerst (Coming-Soon-Seite früh live). Der wichtigste Hebel sind Wishlists vor dem Launch (Ziel 7.000–10.000+).
- Steam-Capsule-Maße (seit 11/2024):
  - Small 462×174
  - Header 920×430
  - Main 1232×706
  - Vertical 748×896
  - Library 600×900
- Steam-Screenshots:
  - mindestens 1920×1080 (16:9), 8–10 Stück;
  - nur echtes Gameplay;
  - mindestens 4 als „für alle Altersgruppen geeignet“ markieren.
- KI-Inhalte müssen im Steam-Inhaltsfragebogen angegeben werden. Für Spieler sichtbare KI-Assets (PixelLab) betrifft das, reine Dev-Tools nicht.
- Für Assets von Freelancern immer ein übertragbares, ausschließliches Nutzungsrecht inkl. Bearbeitungsrecht sichern.
- Ein interner Vertrag zu dritt (Umsatz, Rechte, Ausstieg) ist offen und hat hohe Priorität.

## Stand Gameplay (Oktober 2026)

- Spinne gros ist komplett: Ei-Schlüpfen (alte Spinne bleibt als Eierschale stehen, neue Spinne wird gespawnt), Fernkampf (Spucken, Spinnenwebenball), Wegspringen nach Treffer, Nahkampf mit eigenem Cooldown über "Nahkampfangriff Area" (Form im Editor bestimmt die Reichweite). Steht der Spieler in ihrer Hurtbox, macht sie den Nahkampfangriff. Kein Wegspringen bei Überlappung, das hat Nico bewusst wieder entfernt.
- Zuletzt behoben, von Nico noch nicht bestätigt: Spinne gros hat den Nahkampf nur einmal gemacht (Fern- und Nahkampf-Cooldown haben sich gegenseitig unterbrochen). Die zweiten `_decide_next_state()`-Aufrufe in `_finish_attack()`/`_finish_melee_attack()` sind jetzt gegen den jeweils anderen Angriff abgesichert.
- Gelegentlich nicht treffbare Spinne gros: Nico hat die Hitbox-Größen selbst im Editor angepasst; beobachten, ob das Problem bleibt.
- Bossraum: Spieler blieb nach der Leere-Erzählung manchmal gesperrt. `void_narration.gd` entsperrt jetzt in jedem Fall; Ursache nicht 100 % bestätigt.
- Gebiet 2 hat noch keinen eigenen Raum-Ablauf in `run_state.gd` (dort sind bisher nur die Räume von Gebiet 1 eingetragen).

## Bekannte offene Punkte

- `schatten_mutant.gd` `_die()` setzt `monitoring` während eines Signals → `set_deferred("monitoring", false)` verwenden.
- Doppeltes Fackellicht und ovale Skalierung bereinigen.
- Tileset in Richtung INMOST erneuern:
  - dunkle Silhouetten-Tiles, helle Oberkante, keine Ziegel-Details, keine Outlines;
  - Tiles dunkler als der Hintergrund, damit begehbare Flächen lesbar bleiben.
- Ideen für später:
  - kaltes PointLight unter der Lichtöffnung;
  - Bounce Light (schwaches Rücklicht von Wand und Boden);
  - Rim-Light-Shader auf der TileMap;
  - Tropfen-Partikel und Decals;
  - Color Grading (Bild auf eine feste Palette umfärben).
- Projekt liegt im OneDrive-Ordner und in Git → Sync-Konflikte möglich; vor größeren Änderungen committen.
- TileMap → TileMapLayer in Raum1 umstellen (Node-Namen danach prüfen).
- CameraBounds → Area2D (siehe oben).
- Store-Assets: Capsule Art in allen fünf Formaten (aktueller Blocker für die Steam-Seite), Screenshots auf Spec.
