#!/usr/bin/env python3
"""
Génère un corpus de benchmark pour ImageArm.
- 50 PNG variés ~500 Ko chacun
- 10 JPEG variés
- 5 WebP variés
- 3 SVG
- 3 HEIF (via sips macOS — nécessite macOS)
Les images sont variées (couleurs, motifs, gradients, bruit) pour être représentatives.
"""

import os
import sys
import random
import struct
import zlib
import math

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("ERREUR: Pillow requis — pip3 install Pillow")
    sys.exit(1)

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
PNG_COUNT = 50
JPEG_COUNT = 10
WEBP_COUNT = 5
SVG_COUNT = 3
HEIF_COUNT = 3
TARGET_PNG_SIZE_KB = 500  # ~500 Ko par PNG


def random_color():
    return (random.randint(0, 255), random.randint(0, 255), random.randint(0, 255))


def generate_gradient_image(width, height, seed):
    """Génère une image avec gradient + formes géométriques."""
    random.seed(seed)
    img = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(img)

    # Gradient de fond
    c1 = random_color()
    c2 = random_color()
    for y in range(height):
        r = int(c1[0] + (c2[0] - c1[0]) * y / height)
        g = int(c1[1] + (c2[1] - c1[1]) * y / height)
        b = int(c1[2] + (c2[2] - c1[2]) * y / height)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))

    # Formes aléatoires
    for _ in range(random.randint(10, 40)):
        shape_type = random.choice(["rect", "ellipse", "line"])
        color = random_color() + (random.randint(80, 255),)
        x1 = random.randint(0, width)
        y1 = random.randint(0, height)
        x2 = x1 + random.randint(20, 200)
        y2 = y1 + random.randint(20, 200)
        if shape_type == "rect":
            draw.rectangle([x1, y1, x2, y2], fill=color)
        elif shape_type == "ellipse":
            draw.ellipse([x1, y1, x2, y2], fill=color)
        else:
            draw.line([x1, y1, x2, y2], fill=color, width=random.randint(1, 8))

    return img


def generate_noisy_image(width, height, seed):
    """Génère une image avec du bruit — simule une photo réaliste (plus difficile à compresser)."""
    random.seed(seed)
    img = Image.new("RGB", (width, height))
    pixels = img.load()
    base_r, base_g, base_b = random_color()

    for y in range(height):
        for x in range(width):
            noise = random.randint(-60, 60)
            r = max(0, min(255, base_r + noise + int(30 * math.sin(x / 30.0))))
            g = max(0, min(255, base_g + noise + int(30 * math.cos(y / 25.0))))
            b = max(0, min(255, base_b + noise))
            pixels[x, y] = (r, g, b)

    return img


def generate_pattern_image(width, height, seed):
    """Génère une image avec des motifs répétitifs — simule du contenu structuré."""
    random.seed(seed)
    img = Image.new("RGB", (width, height), random_color())
    draw = ImageDraw.Draw(img)

    pattern_size = random.randint(20, 60)
    colors = [random_color() for _ in range(random.randint(3, 8))]

    for y in range(0, height, pattern_size):
        for x in range(0, width, pattern_size):
            color = colors[(x // pattern_size + y // pattern_size) % len(colors)]
            draw.rectangle([x, y, x + pattern_size - 2, y + pattern_size - 2], fill=color)

    return img


def adjust_image_to_target_size(img, target_kb, fmt="PNG"):
    """Ajuste la taille de l'image pour approcher la taille cible.
    Pour les PNG, on garde des dimensions réalistes (max ~1500px)
    et on ajoute du bruit pour atteindre la taille cible plutôt
    que d'agrandir les dimensions."""
    from io import BytesIO

    # Essai initial
    buf = BytesIO()
    if fmt == "PNG":
        img.save(buf, format="PNG", optimize=False)
    elif fmt == "JPEG":
        img.save(buf, format="JPEG", quality=85)
    elif fmt == "WEBP":
        img.save(buf, format="WEBP", quality=80)

    current_kb = buf.tell() / 1024

    if fmt == "PNG" and current_kb < target_kb * 0.5:
        # Ajouter du bruit léger pour augmenter la taille (simule une photo réelle)
        # plutôt que d'agrandir les dimensions (ce qui ralentit oxipng)
        import numpy as np
        arr = np.array(img)
        noise_level = 15
        while current_kb < target_kb * 0.7 and noise_level < 60:
            noise = np.random.randint(-noise_level, noise_level + 1, arr.shape, dtype=np.int16)
            noisy = np.clip(arr.astype(np.int16) + noise, 0, 255).astype(np.uint8)
            img_test = Image.fromarray(noisy, mode=img.mode)
            buf = BytesIO()
            img_test.save(buf, format="PNG", optimize=False)
            current_kb = buf.tell() / 1024
            if current_kb >= target_kb * 0.7:
                img = img_test
                break
            noise_level += 10

    return img


def generate_png_corpus():
    """Génère 50 PNG variés ~500 Ko.
    Utilise principalement des images bruiteuses (simulent des photos) pour des
    dimensions réalistes. Les images à gradients/motifs sont mélangées pour la variété.
    """
    print(f"Génération de {PNG_COUNT} PNG...")
    generators = [generate_noisy_image, generate_noisy_image, generate_gradient_image,
                  generate_noisy_image, generate_pattern_image]

    for i in range(PNG_COUNT):
        gen = generators[i % len(generators)]
        # Dimensions calibrées pour ~500 Ko en PNG :
        # - Noisy images : ~500x450 → ~500 Ko (haute entropie, compresse peu)
        # - Gradient/pattern : ~1000x800 → ~300-500 Ko (basse entropie, compresse bien)
        if gen == generate_noisy_image:
            w = random.randint(450, 600)
            h = random.randint(400, 550)
        else:
            w = random.randint(900, 1300)
            h = random.randint(700, 1100)

        img = gen(w, h, seed=i * 42)

        # Convertir en RGB pour les PNG (pas besoin d'alpha pour le benchmark)
        if img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg

        path = os.path.join(OUTPUT_DIR, f"bench-png-{i+1:03d}.png")
        img.save(path, format="PNG", optimize=False)
        size_kb = os.path.getsize(path) / 1024
        print(f"  [{i+1}/{PNG_COUNT}] {os.path.basename(path)} — {size_kb:.0f} Ko ({img.width}x{img.height})")


def generate_jpeg_corpus():
    """Génère 10 JPEG variés."""
    print(f"\nGénération de {JPEG_COUNT} JPEG...")
    for i in range(JPEG_COUNT):
        gen = [generate_gradient_image, generate_noisy_image, generate_pattern_image][i % 3]
        w, h = random.randint(800, 1600), random.randint(800, 1600)
        img = gen(w, h, seed=1000 + i)
        if img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg

        path = os.path.join(OUTPUT_DIR, f"bench-jpeg-{i+1:03d}.jpg")
        img.save(path, format="JPEG", quality=92)
        size_kb = os.path.getsize(path) / 1024
        print(f"  [{i+1}/{JPEG_COUNT}] {os.path.basename(path)} — {size_kb:.0f} Ko")


def generate_webp_corpus():
    """Génère 5 WebP variés."""
    print(f"\nGénération de {WEBP_COUNT} WebP...")
    for i in range(WEBP_COUNT):
        gen = [generate_gradient_image, generate_noisy_image][i % 2]
        w, h = random.randint(800, 1200), random.randint(800, 1200)
        img = gen(w, h, seed=2000 + i)
        if img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg

        path = os.path.join(OUTPUT_DIR, f"bench-webp-{i+1:03d}.webp")
        img.save(path, format="WEBP", quality=85)
        size_kb = os.path.getsize(path) / 1024
        print(f"  [{i+1}/{WEBP_COUNT}] {os.path.basename(path)} — {size_kb:.0f} Ko")


def generate_svg_corpus():
    """Génère 3 SVG variés."""
    print(f"\nGénération de {SVG_COUNT} SVG...")
    for i in range(SVG_COUNT):
        random.seed(3000 + i)
        w, h = 800, 600
        shapes = []
        for _ in range(random.randint(20, 80)):
            shape_type = random.choice(["rect", "circle", "line", "polygon"])
            color = f"rgb({random.randint(0,255)},{random.randint(0,255)},{random.randint(0,255)})"
            opacity = round(random.uniform(0.3, 1.0), 2)
            if shape_type == "rect":
                x, y = random.randint(0, w), random.randint(0, h)
                rw, rh = random.randint(20, 200), random.randint(20, 200)
                shapes.append(f'<rect x="{x}" y="{y}" width="{rw}" height="{rh}" fill="{color}" opacity="{opacity}"/>')
            elif shape_type == "circle":
                cx, cy = random.randint(0, w), random.randint(0, h)
                r = random.randint(10, 100)
                shapes.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}" opacity="{opacity}"/>')
            elif shape_type == "line":
                x1, y1 = random.randint(0, w), random.randint(0, h)
                x2, y2 = random.randint(0, w), random.randint(0, h)
                sw = random.randint(1, 5)
                shapes.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{sw}" opacity="{opacity}"/>')
            else:
                points = " ".join(f"{random.randint(0,w)},{random.randint(0,h)}" for _ in range(random.randint(3, 6)))
                shapes.append(f'<polygon points="{points}" fill="{color}" opacity="{opacity}"/>')

        svg_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">
  <rect width="{w}" height="{h}" fill="rgb({random.randint(0,255)},{random.randint(0,255)},{random.randint(0,255)})"/>
  {"".join(shapes)}
</svg>'''

        path = os.path.join(OUTPUT_DIR, f"bench-svg-{i+1:03d}.svg")
        with open(path, "w") as f:
            f.write(svg_content)
        size_kb = os.path.getsize(path) / 1024
        print(f"  [{i+1}/{SVG_COUNT}] {os.path.basename(path)} — {size_kb:.1f} Ko")


def generate_heif_corpus():
    """Génère 3 HEIF variés via sips (macOS uniquement).
    Convertit les 3 premiers PNG du corpus en HEIC.
    Nécessite macOS — sips est un outil système."""
    import subprocess
    print(f"\nGénération de {HEIF_COUNT} HEIF via sips...")

    for i in range(HEIF_COUNT):
        src = os.path.join(OUTPUT_DIR, f"bench-png-{i+1:03d}.png")
        path = os.path.join(OUTPUT_DIR, f"bench-heif-{i+1:03d}.heic")
        if not os.path.exists(src):
            print(f"  [{i+1}/{HEIF_COUNT}] ERREUR: source PNG manquante ({src})")
            continue
        result = subprocess.run(
            ["sips", "-s", "format", "heic", src, "--out", path],
            capture_output=True
        )
        if result.returncode == 0 and os.path.exists(path):
            size_kb = os.path.getsize(path) / 1024
            print(f"  [{i+1}/{HEIF_COUNT}] {os.path.basename(path)} — {size_kb:.0f} Ko")
        else:
            print(f"  [{i+1}/{HEIF_COUNT}] ERREUR sips: {result.stderr.decode().strip()}")


def main():
    print(f"=== Génération du corpus de benchmark ImageArm ===")
    print(f"Dossier de sortie : {OUTPUT_DIR}\n")

    generate_png_corpus()
    generate_jpeg_corpus()
    generate_webp_corpus()
    generate_svg_corpus()
    generate_heif_corpus()

    # Résumé
    print("\n=== Résumé ===")
    total = 0
    total_size = 0
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.startswith("bench-"):
            total += 1
            total_size += os.path.getsize(os.path.join(OUTPUT_DIR, f))
    print(f"Total : {total} fichiers, {total_size / (1024*1024):.1f} Mo")
    print("Corpus prêt pour les benchmarks !")


if __name__ == "__main__":
    main()
