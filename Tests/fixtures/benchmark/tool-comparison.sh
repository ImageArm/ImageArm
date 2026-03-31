#!/bin/zsh
# =============================================================================
# Benchmark comparatif outil-par-outil — ImageArm
# Objectif : déterminer si le pipeline compétitif multi-outils est justifié
#            ou si un outil unique par format suffit.
#
# Pour chaque image du corpus, lance chaque outil INDIVIDUELLEMENT et compare
# les tailles de sortie. Produit un CSV + rapport de synthèse.
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN="$PROJECT_ROOT/tools/bin"
RESULTS_CSV="$SCRIPT_DIR/tool-comparison-results.csv"
REPORT="$SCRIPT_DIR/tool-comparison-report.txt"

# Couleurs
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo "${CYAN}ℹ️  $1${NC}"; }
title() { echo "\n${BOLD}$1${NC}"; }

# =============================================================================
# Vérification des outils
# =============================================================================
echo "========================================"
echo " Benchmark comparatif outil-par-outil"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo "========================================"
echo ""

PNGQUANT="$BIN/pngquant"
OXIPNG="$BIN/oxipng"
PNGCRUSH="$BIN/pngcrush"
JPEGTRAN="$BIN/jpegtran"
CWEBP="$BIN/cwebp"

for tool in "$PNGQUANT" "$OXIPNG" "$PNGCRUSH" "$JPEGTRAN" "$CWEBP"; do
    name=$(basename "$tool")
    if [ -x "$tool" ]; then
        echo "  ✅ $name"
    else
        echo "  ❌ $name MANQUANT ($tool)"
    fi
done
echo ""

# =============================================================================
# Initialisation CSV
# =============================================================================
echo "file,format,original_bytes,pngquant_bytes,oxipng_o2_bytes,oxipng_o4_bytes,oxipng_o6_bytes,pngcrush_bytes,pngcrush_brute_bytes,winner,winner_bytes,savings_pct,second_bytes,margin_bytes,margin_pct" > "$RESULTS_CSV"

# =============================================================================
# Fonctions utilitaires
# =============================================================================
fsize() {
    stat -f%z "$1" 2>/dev/null || echo "0"
}

# =============================================================================
# BENCHMARK PNG — chaque outil isolément
# =============================================================================
title "═══ PNG : benchmark outil-par-outil ═══"

PNG_FILES=("$SCRIPT_DIR"/bench-png-*.png)
PNG_COUNT=${#PNG_FILES[@]}
info "Corpus : $PNG_COUNT fichiers PNG"

# Compteurs simples (pas de tableaux associatifs)
WINS_pngquant=0; WINS_oxipng_o2=0; WINS_oxipng_o4=0; WINS_oxipng_o6=0
WINS_pngcrush=0; WINS_pngcrush_brute=0; WINS_original=0
SAV_pngquant=0; SAV_oxipng_o2=0; SAV_oxipng_o4=0; SAV_oxipng_o6=0
SAV_pngcrush=0; SAV_pngcrush_brute=0
TOTAL_MARGIN=0
PNG_PROCESSED=0

for png in "${PNG_FILES[@]}"; do
    fname=$(basename "$png")
    TMPD=$(mktemp -d)
    orig_size=$(fsize "$png")

    # --- pngquant (lossy, quality 60-80, speed 1) ---
    cp "$png" "$TMPD/pq.png"
    "$PNGQUANT" --force --quality=60-80 --speed=1 --strip --output "$TMPD/pq_out.png" "$TMPD/pq.png" 2>/dev/null || true
    pq_size=$(fsize "$TMPD/pq_out.png")
    [ "$pq_size" -eq 0 ] && pq_size=$orig_size

    # --- oxipng -o2 (lossless, rapide) ---
    cp "$png" "$TMPD/oxi2.png"
    "$OXIPNG" -o 2 --threads 1 --strip safe "$TMPD/oxi2.png" 2>/dev/null || true
    oxi2_size=$(fsize "$TMPD/oxi2.png")

    # --- oxipng -o4 (lossless, standard) ---
    cp "$png" "$TMPD/oxi4.png"
    "$OXIPNG" -o 4 --threads 1 --strip safe "$TMPD/oxi4.png" 2>/dev/null || true
    oxi4_size=$(fsize "$TMPD/oxi4.png")

    # --- oxipng -o6 (lossless, maximum) ---
    cp "$png" "$TMPD/oxi6.png"
    "$OXIPNG" -o 6 --threads 1 --strip safe "$TMPD/oxi6.png" 2>/dev/null || true
    oxi6_size=$(fsize "$TMPD/oxi6.png")

    # --- pngcrush -reduce ---
    cp "$png" "$TMPD/crush_in.png"
    "$PNGCRUSH" -reduce -rem allb "$TMPD/crush_in.png" "$TMPD/crush_out.png" 2>/dev/null || true
    crush_size=$(fsize "$TMPD/crush_out.png")
    [ "$crush_size" -eq 0 ] && crush_size=$orig_size

    # --- pngcrush -brute ---
    cp "$png" "$TMPD/brute_in.png"
    "$PNGCRUSH" -reduce -brute -rem allb "$TMPD/brute_in.png" "$TMPD/brute_out.png" 2>/dev/null || true
    brute_size=$(fsize "$TMPD/brute_out.png")
    [ "$brute_size" -eq 0 ] && brute_size=$orig_size

    # --- Déterminer le gagnant ---
    winner="original"; winner_size=$orig_size

    if [ "$pq_size" -lt "$winner_size" ] && [ "$pq_size" -gt 0 ]; then winner="pngquant"; winner_size=$pq_size; fi
    if [ "$oxi2_size" -lt "$winner_size" ] && [ "$oxi2_size" -gt 0 ]; then winner="oxipng_o2"; winner_size=$oxi2_size; fi
    if [ "$oxi4_size" -lt "$winner_size" ] && [ "$oxi4_size" -gt 0 ]; then winner="oxipng_o4"; winner_size=$oxi4_size; fi
    if [ "$oxi6_size" -lt "$winner_size" ] && [ "$oxi6_size" -gt 0 ]; then winner="oxipng_o6"; winner_size=$oxi6_size; fi
    if [ "$crush_size" -lt "$winner_size" ] && [ "$crush_size" -gt 0 ]; then winner="pngcrush"; winner_size=$crush_size; fi
    if [ "$brute_size" -lt "$winner_size" ] && [ "$brute_size" -gt 0 ]; then winner="pngcrush_brute"; winner_size=$brute_size; fi

    # Second meilleur
    second_size=$orig_size
    for _s in $pq_size $oxi2_size $oxi4_size $oxi6_size $crush_size $brute_size; do
        if [ "$_s" -gt 0 ] && [ "$_s" -lt "$second_size" ] && [ "$_s" -ne "$winner_size" ]; then
            second_size=$_s
        fi
    done
    # Si second == orig, il n'y avait qu'un seul meilleur
    [ "$second_size" -eq "$orig_size" ] && [ "$winner" != "original" ] && second_size=$orig_size

    margin=$((second_size - winner_size))
    if [ "$orig_size" -gt 0 ]; then
        savings_pct=$(python3 -c "print(f'{(1 - $winner_size/$orig_size) * 100:.1f}')")
        margin_pct=$(python3 -c "print(f'{($margin/$orig_size) * 100:.2f}')")
    else
        savings_pct="0.0"; margin_pct="0.00"
    fi

    # Cumuler victoires
    case "$winner" in
        pngquant)       WINS_pngquant=$((WINS_pngquant + 1)) ;;
        oxipng_o2)      WINS_oxipng_o2=$((WINS_oxipng_o2 + 1)) ;;
        oxipng_o4)      WINS_oxipng_o4=$((WINS_oxipng_o4 + 1)) ;;
        oxipng_o6)      WINS_oxipng_o6=$((WINS_oxipng_o6 + 1)) ;;
        pngcrush)       WINS_pngcrush=$((WINS_pngcrush + 1)) ;;
        pngcrush_brute) WINS_pngcrush_brute=$((WINS_pngcrush_brute + 1)) ;;
        original)       WINS_original=$((WINS_original + 1)) ;;
    esac

    # Cumuler économies totales par outil
    SAV_pngquant=$((SAV_pngquant + orig_size - pq_size))
    SAV_oxipng_o2=$((SAV_oxipng_o2 + orig_size - oxi2_size))
    SAV_oxipng_o4=$((SAV_oxipng_o4 + orig_size - oxi4_size))
    SAV_oxipng_o6=$((SAV_oxipng_o6 + orig_size - oxi6_size))
    SAV_pngcrush=$((SAV_pngcrush + orig_size - crush_size))
    SAV_pngcrush_brute=$((SAV_pngcrush_brute + orig_size - brute_size))

    TOTAL_MARGIN=$((TOTAL_MARGIN + margin))
    PNG_PROCESSED=$((PNG_PROCESSED + 1))

    # CSV
    echo "$fname,png,$orig_size,$pq_size,$oxi2_size,$oxi4_size,$oxi6_size,$crush_size,$brute_size,$winner,$winner_size,$savings_pct,$second_size,$margin,$margin_pct" >> "$RESULTS_CSV"

    # Affichage compact
    printf "  %-25s %7s → %7s (%5s%%)  🏆 %-16s  marge: %s octets (%s%%)\n" \
        "$fname" "$orig_size" "$winner_size" "$savings_pct" "$winner" "$margin" "$margin_pct"

    rm -rf "$TMPD"
done

# =============================================================================
# BENCHMARK JPEG — jpegtran seul (lossless) vs original
# =============================================================================
title "═══ JPEG : benchmark jpegtran (lossless progressif) ═══"

JPEG_FILES=("$SCRIPT_DIR"/bench-jpeg-*.jpg)
JPEG_COUNT=${#JPEG_FILES[@]}
info "Corpus : $JPEG_COUNT fichiers JPEG"

JPEG_TOTAL_ORIG=0
JPEG_TOTAL_OPT=0

for jpg in "${JPEG_FILES[@]}"; do
    fname=$(basename "$jpg")
    TMPD=$(mktemp -d)
    orig_size=$(fsize "$jpg")

    "$JPEGTRAN" -copy none -optimize -progressive -outfile "$TMPD/moz.jpg" "$jpg" 2>/dev/null || cp "$jpg" "$TMPD/moz.jpg"
    moz_size=$(fsize "$TMPD/moz.jpg")

    if [ "$orig_size" -gt 0 ]; then
        savings_pct=$(python3 -c "print(f'{(1 - $moz_size/$orig_size) * 100:.1f}')")
    else
        savings_pct="0.0"
    fi

    JPEG_TOTAL_ORIG=$((JPEG_TOTAL_ORIG + orig_size))
    JPEG_TOTAL_OPT=$((JPEG_TOTAL_OPT + moz_size))

    printf "  %-25s %7s → %7s (%5s%%)  jpegtran\n" "$fname" "$orig_size" "$moz_size" "$savings_pct"
    rm -rf "$TMPD"
done

# =============================================================================
# RAPPORT DE SYNTHÈSE
# =============================================================================
title "═══════════════════════════════════════"
title " RAPPORT DE SYNTHÈSE"
title "═══════════════════════════════════════"

{
echo "Benchmark comparatif outil-par-outil — ImageArm"
echo "Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Machine : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo ""
echo "================================================================"
echo "  PNG — VICTOIRES PAR OUTIL ($PNG_PROCESSED images)"
echo "================================================================"

for tool_name in pngquant oxipng_o2 oxipng_o4 oxipng_o6 pngcrush pngcrush_brute original; do
    eval "wins=\$WINS_$tool_name"
    if [ "$PNG_PROCESSED" -gt 0 ]; then
        pct=$(python3 -c "print(f'{$wins/$PNG_PROCESSED * 100:.1f}')")
    else
        pct="0"
    fi
    if [ "$tool_name" != "original" ]; then
        eval "total_saved=\$SAV_$tool_name"
        saved_kb=$(python3 -c "print(f'{$total_saved/1024:.1f}')")
    else
        saved_kb="—"
    fi
    printf "  %-20s  %3d victoires (%5s%%)   économie totale: %s Ko\n" "$tool_name" "$wins" "$pct" "$saved_kb"
done

echo ""
if [ "$PNG_PROCESSED" -gt 0 ]; then
    avg_margin=$(python3 -c "print(f'{$TOTAL_MARGIN/$PNG_PROCESSED:.0f}')")
    echo "  Marge moyenne entre 1er et 2ème : $avg_margin octets/image"
fi

echo ""
echo "================================================================"
echo "  JPEG — jpegtran (seul outil lossless)"
echo "================================================================"
if [ "$JPEG_TOTAL_ORIG" -gt 0 ]; then
    jpeg_pct=$(python3 -c "print(f'{(1 - $JPEG_TOTAL_OPT/$JPEG_TOTAL_ORIG) * 100:.1f}')")
    jpeg_saved=$(python3 -c "print(f'{($JPEG_TOTAL_ORIG - $JPEG_TOTAL_OPT)/1024:.1f}')")
    echo "  Total original : $(python3 -c "print(f'{$JPEG_TOTAL_ORIG/1024:.1f}')") Ko"
    echo "  Total optimisé : $(python3 -c "print(f'{$JPEG_TOTAL_OPT/1024:.1f}')") Ko"
    echo "  Économie       : $jpeg_saved Ko ($jpeg_pct%)"
    echo "  → Un seul outil (jpegtran) suffit en mode lossless"
fi

echo ""
echo "================================================================"
echo "  CONCLUSION & RECOMMANDATIONS"
echo "================================================================"

# Calculer le gagnant dominant
max_wins=0; dominant=""
for tool_name in pngquant oxipng_o2 oxipng_o4 oxipng_o6 pngcrush pngcrush_brute; do
    eval "w=\$WINS_$tool_name"
    if [ "$w" -gt "$max_wins" ]; then
        max_wins=$w
        dominant=$tool_name
    fi
done

if [ "$PNG_PROCESSED" -gt 0 ]; then
    dom_pct=$(python3 -c "print(f'{$max_wins/$PNG_PROCESSED * 100:.0f}')")
    echo ""
    echo "  Outil dominant PNG : $dominant ($max_wins/$PNG_PROCESSED = $dom_pct%)"
    echo ""
    if [ "$max_wins" -ge $((PNG_PROCESSED * 90 / 100)) ]; then
        echo "  → $dominant gagne >90% du temps."
        echo "    RECOMMANDATION : un outil unique ($dominant) suffirait."
        echo "    Le pipeline compétitif ajoute de la complexité pour un gain marginal."
    elif [ "$max_wins" -ge $((PNG_PROCESSED * 70 / 100)) ]; then
        echo "  → $dominant gagne >70% du temps mais pas assez pour éliminer la compétition."
        echo "    RECOMMANDATION : garder le pipeline compétitif avec $dominant en priorité."
        echo "    Envisager de retirer les outils qui ne gagnent jamais."
    else
        echo "  → Aucun outil ne domine clairement."
        echo "    RECOMMANDATION : le pipeline compétitif est JUSTIFIÉ."
        echo "    Chaque outil gagne sur un type d'image différent."
    fi
fi

echo ""
echo "Données détaillées : $RESULTS_CSV"
} | tee "$REPORT"

echo ""
echo "${GREEN}Rapport sauvegardé : $REPORT${NC}"
echo "${GREEN}Données CSV : $RESULTS_CSV${NC}"
