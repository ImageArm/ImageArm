#!/bin/zsh
# =============================================================================
# Benchmark comparatif JPEG — outils CLI
# Compare jpegtran (lossless) vs cjpeg (lossy à différentes qualités)
# pour déterminer le pipeline JPEG optimal.
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN="$PROJECT_ROOT/tools/bin"
RESULTS_CSV="$SCRIPT_DIR/jpeg-comparison-results.csv"
REPORT="$SCRIPT_DIR/jpeg-comparison-report.txt"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo "${CYAN}ℹ️  $1${NC}"; }
title() { echo "\n${BOLD}$1${NC}"; }

echo "========================================"
echo " Benchmark comparatif JPEG outil-par-outil"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo "========================================"
echo ""

JPEGTRAN="$BIN/jpegtran"
CJPEG="$BIN/cjpeg"

for tool in "$JPEGTRAN" "$CJPEG"; do
    name=$(basename "$tool")
    if [ -x "$tool" ]; then
        echo "  ✅ $name"
    else
        echo "  ❌ $name MANQUANT ($tool)"
    fi
done
echo ""

# CSV header
echo "file,original_bytes,jpegtran_lossless_bytes,cjpeg_q95_bytes,cjpeg_q85_bytes,cjpeg_q75_bytes,cjpeg_q65_bytes,winner,winner_bytes,savings_pct,margin_bytes" > "$RESULTS_CSV"

fsize() { stat -f%z "$1" 2>/dev/null || echo "0"; }

# =============================================================================
# BENCHMARK JPEG
# =============================================================================
title "═══ JPEG : benchmark outil-par-outil ═══"

JPEG_FILES=("$SCRIPT_DIR"/bench-jpeg-*.jpg)
JPEG_COUNT=${#JPEG_FILES[@]}
info "Corpus : $JPEG_COUNT fichiers JPEG"

# Compteurs
WINS_jpegtran=0; WINS_cjpeg_q95=0; WINS_cjpeg_q85=0; WINS_cjpeg_q75=0; WINS_cjpeg_q65=0; WINS_original=0
SAV_jpegtran=0; SAV_cjpeg_q95=0; SAV_cjpeg_q85=0; SAV_cjpeg_q75=0; SAV_cjpeg_q65=0
TOTAL_MARGIN=0
JPEG_PROCESSED=0

echo ""
echo "  Fichier                    Original  jpegtran   cjpeg95   cjpeg85   cjpeg75   cjpeg65  Gagnant"
echo "  $(printf '─%.0s' {1..100})"

for jpg in "${JPEG_FILES[@]}"; do
    fname=$(basename "$jpg")
    TMPD=$(mktemp -d)
    orig_size=$(fsize "$jpg")

    # --- jpegtran (lossless progressive, strip metadata) ---
    "$JPEGTRAN" -copy none -optimize -progressive -outfile "$TMPD/jt.jpg" "$jpg" 2>/dev/null || cp "$jpg" "$TMPD/jt.jpg"
    jt_size=$(fsize "$TMPD/jt.jpg")

    # --- cjpeg qualité 95 (lossy, quasi-transparent) ---
    # cjpeg prend du PPM/BMP en entrée, pas du JPEG. On décode d'abord via djpeg si dispo,
    # sinon via sips (macOS natif).
    # Convertir JPEG → BMP pour cjpeg
    sips -s format bmp "$jpg" --out "$TMPD/input.bmp" 2>/dev/null || true

    if [ -f "$TMPD/input.bmp" ]; then
        "$CJPEG" -quality 95 -optimize -progressive -outfile "$TMPD/cj95.jpg" "$TMPD/input.bmp" 2>/dev/null || true
        "$CJPEG" -quality 85 -optimize -progressive -outfile "$TMPD/cj85.jpg" "$TMPD/input.bmp" 2>/dev/null || true
        "$CJPEG" -quality 75 -optimize -progressive -outfile "$TMPD/cj75.jpg" "$TMPD/input.bmp" 2>/dev/null || true
        "$CJPEG" -quality 65 -optimize -progressive -outfile "$TMPD/cj65.jpg" "$TMPD/input.bmp" 2>/dev/null || true
    fi

    cj95_size=$(fsize "$TMPD/cj95.jpg"); [ "$cj95_size" -eq 0 ] && cj95_size=$orig_size
    cj85_size=$(fsize "$TMPD/cj85.jpg"); [ "$cj85_size" -eq 0 ] && cj85_size=$orig_size
    cj75_size=$(fsize "$TMPD/cj75.jpg"); [ "$cj75_size" -eq 0 ] && cj75_size=$orig_size
    cj65_size=$(fsize "$TMPD/cj65.jpg"); [ "$cj65_size" -eq 0 ] && cj65_size=$orig_size

    # --- Déterminer le gagnant ---
    winner="original"; winner_size=$orig_size

    if [ "$jt_size" -lt "$winner_size" ] && [ "$jt_size" -gt 0 ]; then winner="jpegtran"; winner_size=$jt_size; fi
    if [ "$cj95_size" -lt "$winner_size" ] && [ "$cj95_size" -gt 0 ]; then winner="cjpeg_q95"; winner_size=$cj95_size; fi
    if [ "$cj85_size" -lt "$winner_size" ] && [ "$cj85_size" -gt 0 ]; then winner="cjpeg_q85"; winner_size=$cj85_size; fi
    if [ "$cj75_size" -lt "$winner_size" ] && [ "$cj75_size" -gt 0 ]; then winner="cjpeg_q75"; winner_size=$cj75_size; fi
    if [ "$cj65_size" -lt "$winner_size" ] && [ "$cj65_size" -gt 0 ]; then winner="cjpeg_q65"; winner_size=$cj65_size; fi

    # Second meilleur
    second_size=$orig_size
    for _s in $jt_size $cj95_size $cj85_size $cj75_size $cj65_size; do
        if [ "$_s" -gt 0 ] && [ "$_s" -lt "$second_size" ] && [ "$_s" -ne "$winner_size" ]; then
            second_size=$_s
        fi
    done

    margin=$((second_size - winner_size))
    if [ "$orig_size" -gt 0 ]; then
        savings_pct=$(python3 -c "print(f'{(1 - $winner_size/$orig_size) * 100:.1f}')")
    else
        savings_pct="0.0"
    fi

    # Cumuler victoires
    case "$winner" in
        jpegtran)   WINS_jpegtran=$((WINS_jpegtran + 1)) ;;
        cjpeg_q95)  WINS_cjpeg_q95=$((WINS_cjpeg_q95 + 1)) ;;
        cjpeg_q85)  WINS_cjpeg_q85=$((WINS_cjpeg_q85 + 1)) ;;
        cjpeg_q75)  WINS_cjpeg_q75=$((WINS_cjpeg_q75 + 1)) ;;
        cjpeg_q65)  WINS_cjpeg_q65=$((WINS_cjpeg_q65 + 1)) ;;
        original)   WINS_original=$((WINS_original + 1)) ;;
    esac

    SAV_jpegtran=$((SAV_jpegtran + orig_size - jt_size))
    SAV_cjpeg_q95=$((SAV_cjpeg_q95 + orig_size - cj95_size))
    SAV_cjpeg_q85=$((SAV_cjpeg_q85 + orig_size - cj85_size))
    SAV_cjpeg_q75=$((SAV_cjpeg_q75 + orig_size - cj75_size))
    SAV_cjpeg_q65=$((SAV_cjpeg_q65 + orig_size - cj65_size))

    TOTAL_MARGIN=$((TOTAL_MARGIN + margin))
    JPEG_PROCESSED=$((JPEG_PROCESSED + 1))

    echo "$fname,jpeg,$orig_size,$jt_size,$cj95_size,$cj85_size,$cj75_size,$cj65_size,$winner,$winner_size,$savings_pct,$margin" >> "$RESULTS_CSV"

    printf "  %-25s %8s %8s %8s %8s %8s %8s  🏆 %s\n" \
        "$fname" "$orig_size" "$jt_size" "$cj95_size" "$cj85_size" "$cj75_size" "$cj65_size" "$winner"

    rm -rf "$TMPD"
done

# =============================================================================
# RAPPORT
# =============================================================================
title "═══════════════════════════════════════"
title " RAPPORT DE SYNTHÈSE JPEG"
title "═══════════════════════════════════════"

{
echo "Benchmark comparatif JPEG outil-par-outil — ImageArm"
echo "Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Machine : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo ""
echo "================================================================"
echo "  JPEG — VICTOIRES PAR OUTIL ($JPEG_PROCESSED images)"
echo "================================================================"
echo "  NOTE: cjpeg est LOSSY (ré-encode), jpegtran est LOSSLESS (restructure)"
echo "  La comparaison lossy vs lossless est indicative — la qualité visuelle diffère."
echo ""

for tool_name in jpegtran cjpeg_q95 cjpeg_q85 cjpeg_q75 cjpeg_q65 original; do
    eval "wins=\$WINS_$tool_name"
    if [ "$JPEG_PROCESSED" -gt 0 ]; then
        pct=$(python3 -c "print(f'{$wins/$JPEG_PROCESSED * 100:.1f}')")
    else
        pct="0"
    fi
    if [ "$tool_name" != "original" ]; then
        eval "total_saved=\$SAV_$tool_name"
        saved_kb=$(python3 -c "print(f'{$total_saved/1024:.1f}')")
    else
        saved_kb="—"
    fi
    mode="lossy"
    [ "$tool_name" = "jpegtran" ] && mode="lossless"
    [ "$tool_name" = "original" ] && mode="—"
    printf "  %-20s  %3d victoires (%5s%%)  %-8s  économie: %s Ko\n" "$tool_name" "$wins" "$pct" "$mode" "$saved_kb"
done

echo ""
if [ "$JPEG_PROCESSED" -gt 0 ]; then
    avg_margin=$(python3 -c "print(f'{$TOTAL_MARGIN/$JPEG_PROCESSED:.0f}')")
    echo "  Marge moyenne entre 1er et 2ème : $avg_margin octets/image"
fi

echo ""
echo "================================================================"
echo "  ANALYSE LOSSLESS vs LOSSY"
echo "================================================================"
echo ""
echo "  jpegtran (lossless) : $WINS_jpegtran victoires"
LOSSY_WINS=$((WINS_cjpeg_q95 + WINS_cjpeg_q85 + WINS_cjpeg_q75 + WINS_cjpeg_q65))
echo "  cjpeg (lossy total) : $LOSSY_WINS victoires"
echo ""
if [ "$WINS_jpegtran" -ge "$JPEG_PROCESSED" ]; then
    echo "  → jpegtran gagne 100% du temps en taille."
    echo "    Mais cjpeg lossy produit des fichiers plus petits par définition."
    echo "    La question est : la perte de qualité est-elle acceptable ?"
elif [ "$LOSSY_WINS" -gt "$WINS_jpegtran" ]; then
    echo "  → cjpeg lossy produit des fichiers plus petits (normal : ré-encodage avec perte)."
    echo "    Le choix dépend du niveau d'optimisation sélectionné par l'utilisateur."
    echo "    En Rapide/Standard : jpegtran (lossless) est le bon choix."
    echo "    En Maximum/Ultra : cjpeg lossy + jpegtran → keepBest() est justifié."
fi

echo ""
echo "Données détaillées : $RESULTS_CSV"
} | tee "$REPORT"

echo ""
echo "${GREEN}Rapport sauvegardé : $REPORT${NC}"
echo "${GREEN}Données CSV : $RESULTS_CSV${NC}"
