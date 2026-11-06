# -*- coding: utf-8 -*-
"""
Generator fuer den Stil von test_raum_4 (Gebiet 2).

Nutzer-Wunsch: Mix aus neuem Stil (test_raum_3) und altem Stil (raum_1),
Richtung Mockup (gotische Kathedralen-Ruine) und INMOST:
- wenig Pixel im Hintergrund, grosse ruhige Silhouetten, Tiefe ueber Helligkeit
- Hintergrund heller und dunstiger, Spielerebene fast schwarz mit tuerkiser Oberkante
- kaltes Blau/Navy/Teal, kein Gruen, keine schwarzen Outlines
- warme Akzente nur sparsam (wenige Kerzen), rote Banner kommen als eigene Sprites
- nichts schwebt: alles steht auf Boden oder haengt an Ketten bis zum oberen Rand

Aufruf (im Ordner "Raum4 Stil"):  python raum4_generator.py
Erzeugt alle PNGs neu. Godot importiert sie beim naechsten Fokus automatisch.

Koordinaten der Hintergrundbilder (1024 x 660, Sprite-Mitte (328, -230)):
  Bild-y = Welt-y + 560.  Sichtbar ist nur Bild-y 220..550 (Kamera-Limits).
  Boden der Spielerebene (Welt -160) liegt bei Bild-y 400.
  Die Bilder kacheln horizontal (texture_repeat), deshalb alles nahtlos.
  Bild-x = (lokales x in der Parallax-Ebene - 328) mod 1024
  (Region 4096 breit, mittig auf 328 -> linke Kante bei -1720).
"""
import os
import math
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HIER = os.path.dirname(os.path.abspath(__file__))
W, H = 1024, 660
BODEN_Y = 400

# Gesamt-Abdunklung im Spiel: CanvasModulate "Darkness" (0.529, 0.573, 0.710)
# multipliziert alles. Die Bilder werden in "Endfarben" entworfen und dann
# durch diesen Faktor geteilt, damit es im Spiel genau so aussieht.
DARKNESS = np.array([0.529, 0.573, 0.710])


def endfarbe_zu_bild(rgb):
    """Endfarbe (wie im Spiel gewuenscht) -> Bildfarbe vor der Abdunklung."""
    out = rgb / DARKNESS
    return np.clip(out, 0, 255)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def leer():
    """RGBA-Float-Ebene (Farbe in Endfarben 0..255, Alpha 0..1)."""
    return np.zeros((H, W, 4), dtype=np.float32)


def maske_aus_polygonen(polys, w=W, h=H, wrap=True):
    """Polygonliste -> bool-Maske. wrap=True zeichnet auch +-W versetzt (nahtlos)."""
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for p in polys:
        offs = (-w, 0, w) if wrap else (0,)
        for o in offs:
            d.polygon([(x + o, y) for x, y in p], fill=255)
    return np.array(img) > 127


def spitzbogen_maske(cx, spring_y, breite, unten_y, k=1.0, w=W, h=H, wrap=True):
    """Gotischer Spitzbogen (Fenster/Durchgang). k = Radius/Breite (>=0.5)."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    m = np.zeros((h, w), dtype=bool)
    r = k * breite
    for o in ((-w, 0, w) if wrap else (0,)):
        c = cx + o
        rect = (np.abs(xx - c) <= breite / 2) & (yy >= spring_y) & (yy <= unten_y)
        # linker Bogen gehoert zum Kreis mit Mittelpunkt rechts und umgekehrt
        cl = c - breite / 2 + r
        cr = c + breite / 2 - r
        bog = ((xx - cl) ** 2 + (yy - spring_y) ** 2 <= r * r) & \
              ((xx - cr) ** 2 + (yy - spring_y) ** 2 <= r * r) & (yy < spring_y)
        m |= rect | bog
    return m


def rand_kante(m, richtung="oben"):
    """Pixel der Maske, deren Nachbar in 'richtung' leer ist (fuer Rim Light)."""
    if richtung == "oben":
        nb = np.zeros_like(m); nb[1:] = m[:-1]
    elif richtung == "links":
        nb = np.zeros_like(m); nb[:, 1:] = m[:, :-1]
    elif richtung == "rechts":
        nb = np.zeros_like(m); nb[:, :-1] = m[:, 1:]
    else:
        nb = np.zeros_like(m); nb[:-1] = m[1:]
    return m & ~nb


def male(ebene, maske, farbe, alpha=1.0):
    farbe = np.asarray(farbe, dtype=np.float32)
    if farbe.ndim == 1:
        ebene[maske, :3] = farbe
    else:
        ebene[maske, :3] = farbe[maske]
    ebene[maske, 3] = alpha


def nebel_vertikal(ebene, nebel_rgb, y0, y1, staerke):
    """Unten in den Dunst laufen lassen (Tiefe ueber Helligkeit)."""
    ys = np.arange(H, dtype=np.float32)[:, None]
    t = smoothstep(y0, y1, ys) * staerke
    ebene[..., :3] = ebene[..., :3] * (1 - t[..., None]) + np.asarray(nebel_rgb) * t[..., None]


def steinbloecke(e, m, hoehe=8, breite=12, staerke=0.18, seed=1, schutz=None):
    """Nutzer-Wunsch (INMOST-Referenz): Steinblock-Struktur statt glatter
    Vektorflaechen. Fugen etwas dunkler, vereinzelte Kanten heller.
    Bewusst schwach, damit die Silhouette ruhig bleibt."""
    hh, ww = m.shape
    yy, xx = np.mgrid[0:hh, 0:ww]
    reihe = yy // hoehe
    fuge_h = (yy % hoehe == 0)
    versatz = np.where(reihe % 2 == 0, 0, breite // 2)
    fuge_v = ((xx + versatz) % breite == 0)
    fuge = (fuge_h | fuge_v) & m
    if schutz is not None:
        fuge &= ~schutz
    e[fuge, :3] *= (1 - staerke)
    # helle Kante direkt unter der waagrechten Fuge (Licht von oben)
    hell = np.zeros_like(m)
    hell[1:] = fuge_h[:-1]
    rng = np.random.default_rng(seed)
    hell &= m & (rng.random(m.shape) < 0.35)
    if schutz is not None:
        hell &= ~schutz
    e[hell, :3] *= (1 + staerke * 0.6)


def efeu(e, x, y_start, laenge, seed, farbe=(24, 46, 56), blatt=(34, 62, 72)):
    """Haengender Efeu (kaltes Blau-Teal, kein Gruen), 1 px Ranke + Blaetter."""
    rnd = random.Random(seed)
    xx = x
    for i in range(laenge):
        y = y_start + i
        if not (0 <= y < H):
            break
        if rnd.random() < 0.25:
            xx += rnd.choice([-1, 1])
        for o in (-W, 0, W):
            if 0 <= xx + o < W:
                e[y, xx + o, :3] = farbe
                e[y, xx + o, 3] = 1.0
                if rnd.random() < 0.35:
                    bx = xx + o + rnd.choice([-1, 1])
                    if 0 <= bx < W:
                        e[y, bx, :3] = blatt
                        e[y, bx, 3] = 1.0


def speichern(ebene, name, blur=0.0):
    rgb = endfarbe_zu_bild(ebene[..., :3])
    a = np.clip(ebene[..., 3], 0, 1) * 255
    arr = np.dstack([rgb, a]).round().astype(np.uint8)
    img = Image.fromarray(arr, "RGBA")
    if blur > 0:
        # nahtlos weichzeichnen: links/rechts anhaengen, blurren, wieder schneiden
        big = Image.new("RGBA", (W * 3, H))
        for i in range(3):
            big.paste(img, (i * W, 0))
        big = big.filter(ImageFilter.GaussianBlur(blur))
        img = big.crop((W, 0, 2 * W, H))
    img.save(os.path.join(HIER, name))
    print("geschrieben:", name, img.size)


# ---------------------------------------------------------------------------
# Farben (Endfarben, so wie sie im Spiel erscheinen sollen)
# ---------------------------------------------------------------------------
NEBEL_HELL = np.array([56, 74, 106])     # Dunst am Horizont
NEBEL_MITTEL = np.array([42, 56, 82])
NEBEL_TIEF = np.array([22, 30, 46])


# ---------------------------------------------------------------------------
# N1  ferne Kathedralen-Wand mit hohen Spitzbogenfenstern (scroll 0.55)
# ---------------------------------------------------------------------------
def ebene_fern():
    e = leer()
    ys = np.arange(H, dtype=np.float32)
    stuetz_y = [0, 200, 300, 400, 460, 560, 660]
    stuetz_c = [[12, 16, 27], [18, 24, 38], [30, 40, 60], [56, 74, 106], [46, 60, 88], [22, 29, 44], [16, 21, 33]]
    for c in range(3):
        e[:, :, c] = np.interp(ys, stuetz_y, [s_[c] for s_ in stuetz_c])[:, None]
    e[..., 3] = 1.0
    # ferne Hallenwand, oben ruinenhaft mit Tuermchen
    rnd = random.Random(11)
    oben = []
    x = 0
    while x <= W:
        oben.append((x, 205 + rnd.randint(-10, 10)))
        if rnd.random() < 0.15:
            oben.append((x + 3, 160 + rnd.randint(0, 20)))
            oben.append((x + 14, 160 + rnd.randint(0, 20)))
            x += 17
        x += rnd.randint(14, 34)
    oben.append((W, oben[0][1]))
    wand = maske_aus_polygonen([oben + [(W, H), (0, H)]])
    wand_farbe = np.zeros((H, W, 3), np.float32)
    for c, (a, b) in enumerate(zip([20, 27, 42], [34, 45, 66])):
        wand_farbe[..., c] = np.interp(ys, [180, 420], [a, b])[:, None]
    male(e, wand, wand_farbe)
    # viele kleine Spitzbogenfenster (Mockup) statt weniger grosser
    yy, xx = np.mgrid[0:H, 0:W]
    for fx in range(64, W, 128):
        sp, un, br = 290, 352, 18
        f = spitzbogen_maske(fx, sp, br, un, k=1.1)
        glas = np.zeros((H, W, 3), np.float32)
        for c, (a, b) in enumerate(zip([84, 108, 150], [60, 80, 116])):
            glas[..., c] = np.interp(ys, [260, un], [a, b])[:, None]
        male(e, f, glas)
        male(e, f & (xx == fx), wand_farbe)
        male(e, f & (yy == sp), wand_farbe)
    # weiche, sehr schwache Lichtbahnen
    strahl = Image.new("L", (W * 3, H), 0)
    d = ImageDraw.Draw(strahl)
    for fx in range(64, W, 256):
        for o in (0, W, 2 * W):
            d.polygon([(fx + o - 8, 290), (fx + o + 8, 290), (fx + o + 90, 560), (fx + o + 40, 560)], fill=255)
    strahl = strahl.filter(ImageFilter.GaussianBlur(10)).crop((W, 0, 2 * W, H))
    sv = np.array(strahl, np.float32) / 255.0 * 0.10
    sv *= (1 - smoothstep(380, 520, ys))[:, None]
    e[..., :3] = e[..., :3] + (np.array([130, 160, 205]) - e[..., :3]) * sv[..., None]
    nebel_vertikal(e, NEBEL_HELL, 340, 410, 0.7)
    nebel_vertikal(e, NEBEL_TIEF, 440, 540, 0.9)
    speichern(e, "bg4_n1_kathedrale_fern.png", blur=0.6)


# ---------------------------------------------------------------------------
# N1b  Bogenbruecke in der Ferne (scroll 0.68)
# ---------------------------------------------------------------------------
def ebene_bruecke():
    """N1b: ferne Arkadenreihe (zweite Tiefenstaffel im Mockup)."""
    e = leer()
    ys = np.arange(H, dtype=np.float32)
    rnd = random.Random(5)
    oben = []
    x = 0
    while x <= W:
        oben.append((x, 250 + rnd.randint(-8, 8)))
        x += rnd.randint(10, 26)
    oben.append((W, oben[0][1]))
    m = maske_aus_polygonen([oben + [(W, H), (0, H)]])
    for ax in range(32, W, 64):
        m &= ~spitzbogen_maske(ax, 330, 44, 700, k=0.75)
        m &= ~spitzbogen_maske(ax, 282, 8, 296, k=1.1)
    farbe = np.zeros((H, W, 3), np.float32)
    for c, (a, b) in enumerate(zip([26, 34, 52], [38, 50, 74])):
        farbe[..., c] = np.interp(ys, [240, 420], [a, b])[:, None]
    male(e, m, farbe)
    male(e, rand_kante(m, "oben"), [44, 58, 86])
    nebel_vertikal(e, NEBEL_HELL, 330, 420, 0.75)
    nebel_vertikal(e, NEBEL_TIEF, 450, 560, 0.85)
    speichern(e, "bg4_n1b_bruecke.png", blur=0.4)


# ---------------------------------------------------------------------------
# N1c  zerbrochene gotische Waende mit Fensteroeffnungen (scroll 0.74)
# ---------------------------------------------------------------------------
def ebene_ruinenwand():
    """N1c: die Bogenbruecke mit Gelaender (Mockup-Mitte), an einer Stelle
    eingebrochen. Pfeiler stehen bis in den Dunst."""
    e = leer()
    ys = np.arange(H, dtype=np.float32)
    deck_o, deck_u = 300, 310
    pfeiler = [0, 205, 410, 614, 819]
    m = maske_aus_polygonen([[(0, deck_o), (W, deck_o), (W, 360), (0, 360)]])
    for px in pfeiler:
        m &= ~spitzbogen_maske(px + 102, 372, 182, 700, k=0.6)
    for px in pfeiler:
        m |= maske_aus_polygonen([[(px - 11, deck_o), (px + 11, deck_o), (px + 13, H), (px - 13, H)]])
    gel = np.zeros((H, W), bool)
    gel[deck_o - 9:deck_o - 7, :] = True
    for x in range(0, W, 5):
        gel[deck_o - 7:deck_o, x] = True
    alles = m | gel
    bruch = maske_aus_polygonen([[(660, 270), (742, 270), (736, 318), (726, 346), (704, 352), (686, 330), (668, 312)]])
    alles &= ~bruch
    farbe = np.zeros((H, W, 3), np.float32)
    for c, (a, b) in enumerate(zip([22, 29, 45], [32, 42, 62])):
        farbe[..., c] = np.interp(ys, [280, 440], [a, b])[:, None]
    male(e, alles, farbe)
    steinbloecke(e, m & ~bruch, hoehe=6, breite=10, staerke=0.12, seed=4)
    male(e, rand_kante(alles, "oben"), [44, 58, 86])
    for i, x in enumerate((120, 300, 530, 880)):
        efeu(e, x, deck_u, 14 + (i * 7) % 18, seed=40 + i, farbe=(22, 36, 48), blatt=(30, 48, 62))
    nebel_vertikal(e, NEBEL_MITTEL, 360, 450, 0.7)
    nebel_vertikal(e, NEBEL_TIEF, 460, 560, 0.85)
    speichern(e, "bg4_n1c_ruinenwand.png", blur=0.3)


# ---------------------------------------------------------------------------
# N2  Bogengang: Saeulen + Spitzboegen (scroll 0.8). Fackeln haengen an den
#     Saeulen bei Bild-x 0, 256, 768 -> Fackeln bei lokal x -328, 584, 1096.
# ---------------------------------------------------------------------------
def ebene_bogengang():
    """N2: zerbrochene Saeulen (Fackeltraeger) mit Steinbloecken.

    Nutzer-Korrektur: die grossen glatten Gewoelbeboegen wirkten "vektorhaft"
    und deckten zu viel ab. Jetzt nur noch Saeulen mit gebrochener Spitze."""
    e = leer()
    ys = np.arange(H, dtype=np.float32)
    saeulen = {0: 214, 256: 236, 512: 318, 768: 226}
    m = np.zeros((H, W), bool)
    rnd = random.Random(31)
    for px, top in saeulen.items():
        r = [(px - 13, top + rnd.randint(2, 8)), (px - 6, top + rnd.randint(0, 4)), (px - 1, top),
             (px + 5, top + rnd.randint(3, 9)), (px + 13, top + rnd.randint(6, 14))]
        m |= maske_aus_polygonen([r + [(px + 13, 420), (px - 13, 420)]])
        if top < 290:
            m |= maske_aus_polygonen([[(px - 17, 296), (px + 17, 296), (px + 15, 304), (px - 15, 304)]])
        m |= maske_aus_polygonen([[(px - 17, 414), (px + 17, 414), (px + 19, H), (px - 19, H)]])
    farbe = np.zeros((H, W, 3), np.float32)
    for c, (a, b) in enumerate(zip([14, 19, 31], [22, 29, 44])):
        farbe[..., c] = np.interp(ys, [220, 440], [a, b])[:, None]
    male(e, m, farbe)
    steinbloecke(e, m, hoehe=8, breite=13, staerke=0.2, seed=8)
    rim = rand_kante(m, "oben") | rand_kante(m, "links")
    male(e, rim, [34, 48, 72])
    efeu(e, 254, 250, 40, seed=3)
    efeu(e, 770, 240, 26, seed=6)
    nebel_vertikal(e, NEBEL_MITTEL, 420, 500, 0.35)
    nebel_vertikal(e, NEBEL_TIEF, 480, 600, 0.6)
    speichern(e, "bg4_n2_bogengang.png")


# ---------------------------------------------------------------------------
# N2b  Bodenebene: Saeulenstumpf, Gittertor, Schaedelhaufen mit Kerzen (0.86)
# ---------------------------------------------------------------------------
def schaedel(e, cx, cy, farbe, augen):
    yy, xx = np.mgrid[0:H, 0:W]
    for o in (-W, 0, W):
        k = ((xx - cx - o) ** 2 / 2.4 + (yy - cy) ** 2 / 2.0 <= 1.6)
        kiefer = (np.abs(xx - cx - o) <= 0) & (yy == cy + 2)
        male(e, k | kiefer, farbe)
        for ax in (-1, 1):
            male(e, (xx == cx + ax + o) & (yy == cy), augen)


def kerze(e, x, y_boden, hoehe, glow_liste):
    # Kerzenschaft (gedaempftes Wachs) + Flamme (warm, 2 px)
    male(e, maske_aus_polygonen([[(x, y_boden - hoehe), (x + 1, y_boden - hoehe), (x + 1, y_boden), (x, y_boden)]]),
         [150, 140, 128])
    glow_liste.append((x, y_boden - hoehe - 2))


def ebene_boden_props():
    e = leer()
    ys = np.arange(H, dtype=np.float32)
    dunkel = np.array([14, 19, 30])
    rim = np.array([40, 56, 82])
    m = np.zeros((H, W), bool)
    # Saeulenstumpf
    m |= maske_aus_polygonen([[(110, 334), (118, 328), (124, 336), (131, 330), (134, H), (108, H)]])
    # Gittertor in einer Mauerscheibe
    tor_wand = maske_aus_polygonen([[(282, 300), (300, 292), (318, 300), (346, 294), (372, 304), (376, H), (280, H)]])
    oeffnung = spitzbogen_maske(328, 362, 46, 398, k=0.9)
    tor_wand &= ~oeffnung
    m |= tor_wand
    gitter = np.zeros((H, W), bool)
    xs = np.arange(W)[None, :]
    gitter |= oeffnung & ((xs - 306) % 6 == 0)
    gitter |= oeffnung & ((ys[:, None].astype(int) - 334) % 14 == 0)
    # Schaedelhaufen (Huegel) + Kerzen
    haufen = [(540, 40, 14), (880, 28, 10)]
    yy0, xx0 = np.mgrid[0:H, 0:W].astype(np.float32)
    rh = random.Random(9)
    for hx, hb, hh in haufen:
        for o in (-W, 0, W):
            # Grundhuegel (Ellipse) + viele kleine Buckel = Knochenhaufen
            m |= ((xx0 - hx - o) ** 2 / (hb * hb) + (yy0 - 398) ** 2 / (hh * hh) <= 1.0)
        for i in range(int(hb / 3)):
            bx = hx + rh.randint(-hb + 4, hb - 4)
            by = 398 - hh * math.sqrt(max(0.0, 1 - ((bx - hx) / hb) ** 2)) + 1
            r = rh.randint(2, 4)
            for o in (-W, 0, W):
                m |= (xx0 - bx - o) ** 2 + (yy0 - by) ** 2 <= r * r
    # Hallenboden (Props stehen darauf, in Gruben sieht man ihn tief unten)
    m |= maske_aus_polygonen([[(0, 398), (W, 398), (W, H), (0, H)]])
    farbe = np.zeros((H, W, 3), np.float32)
    for c, (a, b) in enumerate(zip(dunkel, dunkel * 1.4)):
        farbe[..., c] = np.interp(ys, [290, 420], [a, b])[:, None]
    male(e, m, farbe)
    male(e, gitter, [24, 32, 48])
    steinbloecke(e, tor_wand, hoehe=7, breite=11, staerke=0.18, seed=15)
    male(e, rand_kante(m, "oben"), rim)

    # Schaedel auf den Haufen (heller als der Untergrund -> lesbar)
    rnd = random.Random(3)
    sk_farbe = np.array([62, 74, 98])
    augen = np.array([16, 20, 30])
    for hx, hb, hh in haufen:
        for i in range(int(hb / 4)):
            sx = hx + rnd.randint(-int(hb * 0.7), int(hb * 0.7))
            sy = int(398 - hh * math.sqrt(max(0.0, 1 - ((sx - hx) / hb) ** 2))) + rnd.randint(1, 5)
            schaedel(e, sx, sy, sk_farbe, augen)

    nebel_vertikal(e, NEBEL_MITTEL * 0.8, 380, 420, 0.4)
    nebel_vertikal(e, NEBEL_TIEF * 0.55, 410, 500, 0.9)
    glow = []
    kerze(e, 532, 385, 4, glow)
    kerze(e, 538, 384, 6, glow)
    kerze(e, 884, 389, 4, glow)
    speichern(e, "bg4_n2b_bodenebene.png")
    kerzenlicht(glow)


def kerzenlicht(glow):
    """Flammen + warmer Schein als eigene Ebene.

    Nutzer-Korrektur (eigene Pruefung): Durch die blaue Abdunklung (Darkness)
    wurden die Flammen gruen-grau. Diese Ebene liegt deshalb als eigenes
    Sprite mit CanvasItemMaterial "unshaded + add" in N2b: sie leuchtet
    selbst und wird NICHT abgedunkelt. Farben hier = Endfarben.
    """
    e = np.zeros((H, W, 4), np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a_ges = np.zeros((H, W), np.float32)
    for gx, gy in glow:
        for o in (-W, 0, W):
            d2 = (xx - gx - o) ** 2 + (yy - gy) ** 2
            a_ges = np.maximum(a_ges, np.exp(-d2 / (2 * 7.0 ** 2)) * 0.22)
    e[..., :3] = [255, 150, 70]
    e[..., 3] = a_ges
    for gx, gy in glow:
        e[gy:gy + 2, gx, :3] = [255, 214, 140]
        e[gy:gy + 2, gx, 3] = 1.0
        e[gy, gx, :3] = [255, 240, 200]
    arr = np.dstack([e[..., :3], e[..., 3] * 255]).round().astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(os.path.join(HIER, "bg4_n2b_kerzenlicht.png"))
    print("geschrieben: bg4_n2b_kerzenlicht.png")


# ---------------------------------------------------------------------------
# N3  dunkle Saeulen (fuer die roten Banner) + Kaefig an Kette (scroll 0.92)
#     Saeulen bei Bild-x 134 und 646 -> Banner bei lokal x -50 / 974 (beide 646).
# ---------------------------------------------------------------------------
def ebene_saeulen_banner():
    e = leer()
    ys = np.arange(H, dtype=np.float32)
    m = np.zeros((H, W), bool)
    for px in (134, 646):
        m |= maske_aus_polygonen([[(px - 18, 0), (px + 18, 0), (px + 18, H), (px - 18, H)]])
        m |= maske_aus_polygonen([[(px - 22, 236), (px + 22, 236), (px + 20, 244), (px - 20, 244)]])
        m |= maske_aus_polygonen([[(px - 22, 410), (px + 22, 410), (px + 25, H), (px - 25, H)]])
    farbe = np.zeros((H, W, 3), np.float32)
    for c, (a, b) in enumerate(zip([9, 12, 20], [16, 21, 33])):
        farbe[..., c] = np.interp(ys, [200, 460], [a, b])[:, None]
    male(e, m, farbe)
    steinbloecke(e, m, hoehe=9, breite=14, staerke=0.25, seed=12)
    # Rim Light nur links (Licht von den fernen Fenstern) + Gesimse oben
    male(e, rand_kante(m, "links") & (ys[:, None] > 150), [30, 46, 66])
    male(e, rand_kante(m, "oben"), [36, 54, 76])

    efeu(e, 152, 244, 34, seed=21)
    efeu(e, 630, 244, 22, seed=22)
    # Kaefig an einer Kette, die bis zum oberen Bildrand geht
    kx, k_oben, k_unten = 392, 292, 326
    kette = np.zeros((H, W), bool)
    for y in range(0, k_oben - 4):
        if y % 4 in (0, 1, 2):
            kette[y, kx] = True
        if y % 4 == 3:
            kette[y, kx - 1] = kette[y, kx + 1] = True
    kaefig = np.zeros((H, W), bool)
    yy, xx = np.mgrid[0:H, 0:W]
    kuppel = ((xx - kx) ** 2 / 121.0 + (yy - (k_oben + 8)) ** 2 / 64.0 <= 1.0) & (yy <= k_oben + 8)
    kuppel_rand = kuppel & ~(((xx - kx) ** 2 / 81.0 + (yy - (k_oben + 8)) ** 2 / 42.0) <= 1.0)
    kaefig |= kuppel_rand
    kaefig[k_oben - 4:k_oben + 1, kx] = True
    for bx in range(kx - 11, kx + 12, 4):
        kaefig[k_oben + 8:k_unten, bx] = True
    kaefig[k_oben + 8, kx - 11:kx + 12] = True
    kaefig[k_unten - 2:k_unten, kx - 12:kx + 13] = True
    # Knochenarm haengt aus dem Kaefig (duester, nicht nett)
    for i in range(6):
        kaefig[k_unten + i, kx + 4 + (i // 3)] = True
    male(e, kette | kaefig, [16, 22, 34])
    male(e, (kette | kaefig) & (xx < kx), [34, 48, 70])

    nebel_vertikal(e, NEBEL_TIEF, 420, 500, 0.5)
    speichern(e, "bg4_n3_saeulen.png")


# ---------------------------------------------------------------------------
# Vordergrund-Saeule (fast schwarz, 1:1-Pixel), ersetzt die alten
# hochaufgeloesten "Saeule vorne"-Sprites.
# ---------------------------------------------------------------------------
def vordergrund_saeule():
    w, h = 48, 520
    e = np.zeros((h, w, 4), np.float32)
    ys = np.arange(h, dtype=np.float32)
    m = np.zeros((h, w), bool)
    m[:, 6:42] = True
    m[300:312, 2:46] = True       # Kapitell/Band
    m[470:, 0:48] = True          # Sockel
    for y in range(h):
        if y % 64 == 63:
            m[y, 6:9] = False      # leichte Fugen am Rand, sonst ruhig
    farbe = np.zeros((h, w, 3), np.float32)
    for c, (a, b) in enumerate(zip([6, 8, 13], [10, 13, 20])):
        farbe[..., c] = np.interp(ys, [0, h], [a, b])[:, None]
    e[m, :3] = farbe[m]
    e[m, 3] = 1.0
    nb = np.zeros_like(m); nb[:, 1:] = m[:, :-1]
    links = m & ~nb
    e[links, :3] = [26, 40, 54]
    rgb = endfarbe_zu_bild(e[..., :3])
    arr = np.dstack([rgb, e[..., 3] * 255]).round().astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(os.path.join(HIER, "vg4_saeule.png"))
    print("geschrieben: vg4_saeule.png", (w, h))


# ---------------------------------------------------------------------------
# Tileset: gleiches Layout wie tiles_raum3.png (gleiche Atlas-Koordinaten,
# gleiche Kollision/Terrain), aber neu eingefaerbt:
# - Koerper fast schwarzes Navy, Ziegel-Details stark zurueckgenommen
# - tuerkise Oberkante (Rim Light) statt grauer Kante
# - Haengewurzeln unter den Plattformen (Zeilen 0-6)
# ---------------------------------------------------------------------------
def tileset():
    quelle = Image.open(os.path.join(HIER, "..", "Raum2 Stil", "tiles_raum3.png")).convert("RGBA")
    a = np.array(quelle, np.float32)
    rgb, al = a[..., :3], a[..., 3]
    hat = al > 10
    lum = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])
    # Helle Kantenpixel der Vorlage (graue/gruenliche Oberkante) erkennen
    kante = hat & (lum > 120)

    # Koerper: Kontrast stark komprimieren (Silhouette statt Ziegel)
    t = np.clip(lum / 110.0, 0, 1) ** 1.2
    dunkel = np.array([7, 10, 16], np.float32)
    hell = np.array([24, 32, 46], np.float32)
    neu = dunkel + (hell - dunkel) * (t[..., None] * 0.75)
    out = np.zeros((256, 256, 4), np.float32)
    out[..., :3] = neu
    out[..., 3] = al

    # Rim Light: oberste Pixelreihe jeder freien Oberkante tuerkis, darunter
    # eine dunklere Uebergangsreihe. Gilt fuer alle Tiles (Plattform + Boden).
    oben_frei = np.zeros_like(hat)
    oben_frei[1:] = hat[1:] & ~hat[:-1]
    oben_frei[0] = hat[0]
    # Tile-Grenzen: oberste Reihe einer Zelle gilt nur als Kante, wenn die
    # Vorlage dort ebenfalls eine helle Kante hatte (sonst waere jede Zelle
    # im Boden-Inneren oben tuerkis).
    zell_oben = (np.arange(256) % 16 == 0)[:, None]
    rim1 = (oben_frei & ~zell_oben) | (zell_oben & kante) | (kante & oben_frei)
    rim1 |= kante & np.roll(~hat, 1, axis=0)
    rim2 = np.zeros_like(rim1)
    rim2[1:] = rim1[:-1] & hat[1:]
    rim2 &= ~rim1
    out[rim2, :3] = [38, 78, 92]
    out[rim1, :3] = [92, 176, 190]
    # Uebrige helle Vorlagen-Pixel (Kantenreste) gedaempft tuerkis
    rest = kante & ~rim1 & ~rim2
    out[rest, :3] = [40, 74, 88]

    # Haengewurzeln unter Plattform-Tiles (Atlas-Zeilen 0,2,5 -> haengen in 1,3,6)
    rnd = random.Random(7)
    plattform_spalten = {0: range(0, 16), 2: range(5, 16), 5: range(1, 16)}
    wurzel_dunkel = np.array([16, 30, 40], np.float32)
    wurzel_hell = np.array([34, 64, 76], np.float32)
    for zeile, spalten in plattform_spalten.items():
        for sp in spalten:
            x0, y0 = sp * 16, zeile * 16
            y_max = y0 + 32  # bis zum Ende der Zelle darunter
            for x in range(x0, x0 + 16):
                # unterstes deckendes Pixel in dieser Spalte suchen
                spalte = hat[y0:y_max, x]
                if not spalte.any():
                    continue
                unten = y0 + int(np.nonzero(spalte)[0].max())
                if rnd.random() < 0.22:
                    laenge = rnd.choice([2, 3, 3, 4, 5, 7, 9])
                    xx = x
                    for i in range(1, laenge + 1):
                        y = unten + i
                        if y >= y_max:
                            break
                        if rnd.random() < 0.15:
                            xx = min(max(xx + rnd.choice([-1, 1]), x0), x0 + 15)
                        if out[y, xx, 3] > 0:
                            continue
                        f = wurzel_dunkel + (wurzel_hell - wurzel_dunkel) * (0.3 if i < laenge else 0.8)
                        out[y, xx, :3] = f
                        out[y, xx, 3] = 255
    # Deko-Tiles der Hinterebene (Zeile 3/4 Spalte 0-4, dazu 0:5): keine
    # grelle Tuerkis-Kante, nur gedaempft - sie liegen hinter dem Spieler.
    deko = [(sp, z) for sp in range(5) for z in (3, 4)] + [(0, 5)]
    kant_alle = rim1 | rim2 | kante
    for sp, z in deko:
        ys_, xs_ = slice(z * 16, z * 16 + 16), slice(sp * 16, sp * 16 + 16)
        blk = out[ys_, xs_]
        km = kant_alle[ys_, xs_] & (blk[..., 3] > 10)
        blk[km, :3] = [40, 62, 78]

    # Tiles sind auf der Spielerebene und werden ebenfalls von Darkness
    # abgedunkelt -> gleiche Umrechnung wie beim Hintergrund.
    out[..., :3] = endfarbe_zu_bild(out[..., :3])
    Image.fromarray(np.clip(out, 0, 255).round().astype(np.uint8), "RGBA").save(os.path.join(HIER, "tiles_raum4.png"))
    print("geschrieben: tiles_raum4.png")


if __name__ == "__main__":
    ebene_fern()
    ebene_bruecke()
    ebene_ruinenwand()
    ebene_bogengang()
    ebene_boden_props()
    ebene_saeulen_banner()
    vordergrund_saeule()
    tileset()
