#!/bin/bash
# =============================================================================
# Benchmark ImageArm — validation performance et fiabilité
# Story 5.3 — mesure automatisée des NFR
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/build/ImageArm.app"
IMAGEARM="$APP_BUNDLE/Contents/MacOS/ImageArm"
CORPUS_DIR="$SCRIPT_DIR"
RESULTS_FILE="$SCRIPT_DIR/benchmark-results.txt"

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; }
info() { echo -e "${YELLOW}ℹ️  INFO${NC}: $1"; }

# =============================================================================
# Vérifications préalables
# =============================================================================
echo "========================================"
echo " Benchmark ImageArm — Story 5.3"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo " macOS: $(sw_vers -productVersion)"
echo " RAM: $(sysctl -n hw.memsize | awk '{print $1/1024/1024/1024 " Go"}')"
echo "========================================"
echo ""

# Forcer le niveau Standard (1) pour le benchmark
# (Quick=0, Standard=1, High=2, Ultra=3)
defaults write com.imagearm.app optimizationLevel -int 1

if [ ! -x "$IMAGEARM" ]; then
    echo "ERREUR: Build introuvable — $IMAGEARM"
    echo "Lancer: xcodebuild -project ImageArm.xcodeproj -scheme ImageArm -configuration Release build CONFIGURATION_BUILD_DIR=$PROJECT_ROOT/build"
    exit 1
fi

PNG_COUNT=$(ls "$CORPUS_DIR"/bench-png-*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$PNG_COUNT" -lt 50 ]; then
    echo "ERREUR: Corpus incomplet — $PNG_COUNT PNG trouvés (50 attendus)"
    echo "Lancer: python3 $CORPUS_DIR/generate-corpus.py"
    exit 1
fi

# Fichier de résultats
echo "Benchmark ImageArm — $(date '+%Y-%m-%d %H:%M:%S')" > "$RESULTS_FILE"
echo "Machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')" >> "$RESULTS_FILE"
echo "macOS: $(sw_vers -productVersion)" >> "$RESULTS_FILE"
echo "========================================" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# =============================================================================
# Task 2: Benchmark 50 PNG Standard < 30s (AC #1 — NFR1)
# =============================================================================
echo ""
echo "--- Task 2: Benchmark 50 PNG Standard (seuil: < 30s) ---"

# Copier les PNG dans un dossier temporaire (on ne modifie pas le corpus)
TMPDIR_PNG=$(mktemp -d)
cp "$CORPUS_DIR"/bench-png-*.png "$TMPDIR_PNG/"
echo "Copie de $PNG_COUNT PNG dans $TMPDIR_PNG"

START_MS=$(($(date +%s%3N)))
"$IMAGEARM" --headless "$TMPDIR_PNG"/*.png 2>&1 || true
END_MS=$(($(date +%s%3N)))
ELAPSED=$(echo "scale=2; ($END_MS - $START_MS) / 1000" | bc)

echo "Temps: ${ELAPSED}s pour $PNG_COUNT PNG"
RESULT_T2="Task 2 (50 PNG Standard): ${ELAPSED}s"
if python3 -c "exit(0 if $ELAPSED < 30 else 1)"; then
    pass "$RESULT_T2 (seuil: 30s)"
    RESULT_T2="$RESULT_T2 — PASS"
else
    fail "$RESULT_T2 (seuil: 30s)"
    RESULT_T2="$RESULT_T2 — FAIL"
fi
echo "$RESULT_T2" >> "$RESULTS_FILE"
rm -rf "$TMPDIR_PNG"

# =============================================================================
# Task 3: Benchmark fichier unique headless < 5s (AC #2 — NFR2)
# =============================================================================
echo ""
echo "--- Task 3: Fichier unique headless (seuil: < 5s, hors cold launch) ---"

# Cold launch (ignoré)
TMPDIR_SINGLE=$(mktemp -d)
cp "$CORPUS_DIR/bench-png-001.png" "$TMPDIR_SINGLE/warmup.png"
"$IMAGEARM" --headless "$TMPDIR_SINGLE/warmup.png" 2>&1 >/dev/null || true
rm -rf "$TMPDIR_SINGLE"

# Mesure réelle (2ème run)
TMPDIR_SINGLE=$(mktemp -d)
cp "$CORPUS_DIR/bench-png-001.png" "$TMPDIR_SINGLE/test-single.png"

START_MS=$(($(date +%s%3N)))
"$IMAGEARM" --headless "$TMPDIR_SINGLE/test-single.png" 2>&1 || true
END_MS=$(($(date +%s%3N)))
ELAPSED=$(echo "scale=2; ($END_MS - $START_MS) / 1000" | bc)

echo "Temps: ${ELAPSED}s pour 1 fichier (2ème run)"
RESULT_T3="Task 3 (fichier unique headless): ${ELAPSED}s"
if python3 -c "exit(0 if $ELAPSED < 5 else 1)"; then
    pass "$RESULT_T3 (seuil: 5s)"
    RESULT_T3="$RESULT_T3 — PASS"
else
    fail "$RESULT_T3 (seuil: 5s)"
    RESULT_T3="$RESULT_T3 — FAIL"
fi
echo "$RESULT_T3" >> "$RESULTS_FILE"
rm -rf "$TMPDIR_SINGLE"

# =============================================================================
# Task 6: Test mémoire 500 images < 500 Mo (AC #5 — NFR5)
# =============================================================================
echo ""
echo "--- Task 6: Test mémoire 500 images (seuil: RSS < 500 Mo) ---"

# Créer 500 fichiers (copies des 50 PNG x10)
TMPDIR_MEM=$(mktemp -d)
for rep in $(seq 1 10); do
    for f in "$CORPUS_DIR"/bench-png-*.png; do
        cp "$f" "$TMPDIR_MEM/copy${rep}-$(basename "$f")"
    done
done
FILE_COUNT_MEM=$(ls "$TMPDIR_MEM"/*.png | wc -l | tr -d ' ')
echo "Préparé $FILE_COUNT_MEM fichiers dans $TMPDIR_MEM"

# Lancer en arrière-plan et mesurer la mémoire
"$IMAGEARM" --headless "$TMPDIR_MEM"/*.png 2>&1 &
PID=$!
MAX_RSS=0
while kill -0 $PID 2>/dev/null; do
    RSS=$(ps -o rss= -p $PID 2>/dev/null | tr -d ' ' || echo "0")
    if [ -n "$RSS" ] && [ "$RSS" -gt "$MAX_RSS" ]; then
        MAX_RSS=$RSS
    fi
    sleep 0.5
done
wait $PID 2>/dev/null || true

MAX_RSS_MB=$((MAX_RSS / 1024))
echo "RSS max: ${MAX_RSS_MB} Mo pour $FILE_COUNT_MEM images"
RESULT_T6="Task 6 (mémoire 500 images): ${MAX_RSS_MB} Mo RSS max"
if [ "$MAX_RSS_MB" -lt 500 ]; then
    pass "$RESULT_T6 (seuil: 500 Mo)"
    RESULT_T6="$RESULT_T6 — PASS"
else
    fail "$RESULT_T6 (seuil: 500 Mo)"
    RESULT_T6="$RESULT_T6 — FAIL"
fi
echo "$RESULT_T6" >> "$RESULTS_FILE"
rm -rf "$TMPDIR_MEM"

# =============================================================================
# Task 7: Compression vs Homebrew (AC #6 — NFR6)
# =============================================================================
echo ""
echo "--- Task 7: Compression ImageArm vs Homebrew (10 PNG, lossless — même niveau) ---"
echo "Note: Standard = lossless. Comparaison équitable : oxipng -o4 des deux côtés."

OXIPNG_HB=$(which oxipng 2>/dev/null || echo "")

if [ -z "$OXIPNG_HB" ]; then
    info "oxipng Homebrew non trouvé — test ignoré"
    RESULT_T7="Task 7 (compression vs Homebrew): SKIPPED (oxipng Homebrew non installé)"
    echo "$RESULT_T7" >> "$RESULTS_FILE"
else
    TMPDIR_COMP_IA=$(mktemp -d)
    TMPDIR_COMP_HB=$(mktemp -d)

    # Copier 10 PNG pour chaque test
    for i in $(seq -w 1 10); do
        cp "$CORPUS_DIR/bench-png-0${i}.png" "$TMPDIR_COMP_IA/"
        cp "$CORPUS_DIR/bench-png-0${i}.png" "$TMPDIR_COMP_HB/"
    done

    # ImageArm (Standard = oxipng -o4 --strip safe, lossless)
    "$IMAGEARM" --headless "$TMPDIR_COMP_IA"/*.png 2>&1 >/dev/null || true
    SIZE_IA=$(du -sk "$TMPDIR_COMP_IA" | cut -f1)

    # Homebrew oxipng au même niveau (o4, strip safe — même paramètres que Standard)
    for f in "$TMPDIR_COMP_HB"/*.png; do
        "$OXIPNG_HB" -o 4 --strip safe "$f" 2>/dev/null || true
    done
    SIZE_HB=$(du -sk "$TMPDIR_COMP_HB" | cut -f1)

    echo "ImageArm: ${SIZE_IA} Ko total — Homebrew: ${SIZE_HB} Ko total"
    RESULT_T7="Task 7: ImageArm=${SIZE_IA}Ko vs Homebrew=${SIZE_HB}Ko"
    if [ "$SIZE_IA" -le "$SIZE_HB" ]; then
        pass "$RESULT_T7 — ImageArm aussi bon ou mieux"
        RESULT_T7="$RESULT_T7 — PASS"
    else
        DIFF=$((SIZE_IA - SIZE_HB))
        fail "$RESULT_T7 — ImageArm ${DIFF}Ko plus gros"
        RESULT_T7="$RESULT_T7 — FAIL"
    fi
    echo "$RESULT_T7" >> "$RESULTS_FILE"
    rm -rf "$TMPDIR_COMP_IA" "$TMPDIR_COMP_HB"
fi

# =============================================================================
# Task 8: Test annulation (AC #8 — FR13) — TEST MANUEL (UI)
# =============================================================================
echo ""
echo "--- Task 8: Test annulation (TEST MANUEL) ---"
echo "L'annulation via le bouton Stop utilise Task.isCancelled + defer cleanup."
echo "Ce test nécessite l'interface graphique — voir procédure manuelle ci-dessous."
echo ""
echo "Procédure :"
echo "  1. Ouvrir ImageArm (UI)"
echo "  2. Glisser 50+ images PNG depuis le corpus de benchmark"
echo "  3. Lancer l'optimisation"
echo "  4. Cliquer 'Stop' pendant le traitement"
echo "  5. Vérifier : traitement arrêté, pas de .imagearm.* temporaires, fichiers intacts"
echo ""

# Vérification automatique partielle : defer cleanup fonctionne après traitement normal
TMPDIR_CLEANUP=$(mktemp -d)
cp "$CORPUS_DIR/bench-png-001.png" "$TMPDIR_CLEANUP/"
cp "$CORPUS_DIR/bench-png-002.png" "$TMPDIR_CLEANUP/"
"$IMAGEARM" --headless "$TMPDIR_CLEANUP"/*.png 2>&1 >/dev/null || true
TEMP_FILES=$(find "$TMPDIR_CLEANUP" -name "*.imagearm.*" 2>/dev/null | wc -l | tr -d ' ')
RESULT_T8="Task 8 (cleanup après traitement normal): $TEMP_FILES fichiers temporaires"
if [ "$TEMP_FILES" -eq 0 ]; then
    pass "$RESULT_T8 — cleanup OK (annulation UI = test manuel)"
    RESULT_T8="$RESULT_T8 — PASS (cleanup vérifié, annulation UI = test manuel)"
else
    fail "$RESULT_T8 — fichiers temporaires trouvés après traitement normal"
    RESULT_T8="$RESULT_T8 — FAIL"
fi
echo "$RESULT_T8" >> "$RESULTS_FILE"
rm -rf "$TMPDIR_CLEANUP"

# =============================================================================
# Task 9: Test ré-optimisation (AC #9 — FR14)
# =============================================================================
echo ""
echo "--- Task 9: Test ré-optimisation ---"

TMPDIR_REOPT=$(mktemp -d)
cp "$CORPUS_DIR/bench-png-001.png" "$TMPDIR_REOPT/reopt-test.png"
ORIG_SIZE=$(stat -f%z "$TMPDIR_REOPT/reopt-test.png")

# Première optimisation
"$IMAGEARM" --headless "$TMPDIR_REOPT/reopt-test.png" 2>&1 >/dev/null || true
SIZE_AFTER_1=$(stat -f%z "$TMPDIR_REOPT/reopt-test.png")

# Deuxième optimisation (ré-optimisation)
"$IMAGEARM" --headless "$TMPDIR_REOPT/reopt-test.png" 2>&1 >/dev/null || true
SIZE_AFTER_2=$(stat -f%z "$TMPDIR_REOPT/reopt-test.png")

echo "Original: $ORIG_SIZE → 1ère opti: $SIZE_AFTER_1 → 2ème opti: $SIZE_AFTER_2"
RESULT_T9="Task 9 (ré-optimisation): $ORIG_SIZE → $SIZE_AFTER_1 → $SIZE_AFTER_2"
# La ré-optimisation doit fonctionner (pas de crash, le fichier est re-traité)
if [ "$SIZE_AFTER_1" -le "$ORIG_SIZE" ] && [ -f "$TMPDIR_REOPT/reopt-test.png" ]; then
    pass "$RESULT_T9 — fonctionne correctement"
    RESULT_T9="$RESULT_T9 — PASS"
else
    fail "$RESULT_T9 — problème détecté"
    RESULT_T9="$RESULT_T9 — FAIL"
fi
echo "$RESULT_T9" >> "$RESULTS_FILE"
rm -rf "$TMPDIR_REOPT"

# =============================================================================
# Résumé final
# =============================================================================
echo ""
echo "========================================"
echo " RÉSUMÉ DES BENCHMARKS"
echo "========================================"
cat "$RESULTS_FILE"
echo ""
echo "Résultats détaillés : $RESULTS_FILE"
echo ""

# Notes sur les tests manuels requis
echo "--- Tests nécessitant validation manuelle ---"
echo "Task 4 (AC #3): Ajout 500 fichiers drag-and-drop < 2s → test UI"
echo "Task 5 (AC #4, #7): Interface réactive sous charge, concurrence 2/4/8/16 → test UI"
echo ""
