#!/bin/zsh
# =============================================================================
# Benchmark comparatif SVG — configurations svgo
# Compare svgo default vs svgo --multipass vs ré-optimisations successives
# pour déterminer si multipass apporte un gain significatif.
# =============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BIN="$PROJECT_ROOT/tools/bin"
RESULTS_CSV="$SCRIPT_DIR/svg-comparison-results.csv"
REPORT="$SCRIPT_DIR/svg-comparison-report.txt"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo "${CYAN}ℹ️  $1${NC}"; }
title() { echo "\n${BOLD}$1${NC}"; }

echo "========================================"
echo " Benchmark comparatif SVG (svgo configs)"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Machine: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo "========================================"
echo ""

SVGO="$BIN/svgo"
if [ -x "$SVGO" ]; then
    echo "  ✅ svgo"
    echo "  Version: $("$SVGO" --version 2>/dev/null || echo 'inconnue')"
else
    echo "  ❌ svgo MANQUANT ($SVGO)"
    exit 1
fi
echo ""

# CSV header
echo "file,original_bytes,svgo_default_bytes,svgo_multipass_bytes,svgo_2passes_bytes,winner,winner_bytes,savings_pct,multipass_gain_vs_default" > "$RESULTS_CSV"

fsize() { stat -f%z "$1" 2>/dev/null || echo "0"; }

# =============================================================================
# BENCHMARK SVG
# =============================================================================
title "═══ SVG : benchmark svgo configurations ═══"

SVG_FILES=("$SCRIPT_DIR"/bench-svg-*.svg)
SVG_COUNT=${#SVG_FILES[@]}
info "Corpus : $SVG_COUNT fichiers SVG"

WINSdef=0; WINSmp=0; WINS2p=0; WINSorig=0
SAVdef=0; SAVmp=0; SAV2p=0
TOTAL_MULTIPASS_GAIN=0
SVG_PROCESSED=0

echo ""
echo "  Fichier                    Original  default  multipass  2passes   Gagnant         multipass gain"
echo "  $(printf '─%.0s' {1..100})"

for svg in "${SVG_FILES[@]}"; do
    fname=$(basename "$svg")
    TMPD=$(mktemp -d)
    orig_size=$(fsize "$svg")

    # --- svgo default (single pass) ---
    "$SVGO" -i "$svg" -o "$TMPD/default.svg" 2>/dev/null || cp "$svg" "$TMPD/default.svg"
    default_size=$(fsize "$TMPD/default.svg")

    # --- svgo --multipass ---
    "$SVGO" -i "$svg" -o "$TMPD/multipass.svg" --multipass 2>/dev/null || cp "$svg" "$TMPD/multipass.svg"
    multipass_size=$(fsize "$TMPD/multipass.svg")

    # --- svgo 2 passes manuelles (optimiser le résultat de la première passe) ---
    "$SVGO" -i "$TMPD/default.svg" -o "$TMPD/pass2.svg" 2>/dev/null || cp "$TMPD/default.svg" "$TMPD/pass2.svg"
    pass2_size=$(fsize "$TMPD/pass2.svg")

    # --- Déterminer le gagnant ---
    winner="original"; winner_size=$orig_size

    if [ "$default_size" -lt "$winner_size" ] && [ "$default_size" -gt 0 ]; then winner="svgo_default"; winner_size=$default_size; fi
    if [ "$multipass_size" -lt "$winner_size" ] && [ "$multipass_size" -gt 0 ]; then winner="svgo_multipass"; winner_size=$multipass_size; fi
    if [ "$pass2_size" -lt "$winner_size" ] && [ "$pass2_size" -gt 0 ]; then winner="svgo_2passes"; winner_size=$pass2_size; fi

    if [ "$orig_size" -gt 0 ]; then
        savings_pct=$(python3 -c "print(f'{(1 - $winner_size/$orig_size) * 100:.1f}')")
    else
        savings_pct="0.0"
    fi

    # Gain multipass vs default
    if [ "$default_size" -gt 0 ] && [ "$multipass_size" -gt 0 ]; then
        mp_gain=$((default_size - multipass_size))
        mp_gain_pct=$(python3 -c "print(f'{($mp_gain/$default_size) * 100:.1f}' if $default_size > 0 else '0.0')")
    else
        mp_gain=0; mp_gain_pct="0.0"
    fi

    # Cumuler victoires
    case "$winner" in
        svgo_default)   WINSdef=$((WINSdef + 1)) ;;
        svgo_multipass) WINSmp=$((WINSmp + 1)) ;;
        svgo_2passes)   WINS2p=$((WINS2p + 1)) ;;
        original)       WINSorig=$((WINSorig + 1)) ;;
    esac

    SAVdef=$((SAVdef + orig_size - default_size))
    SAVmp=$((SAVmp + orig_size - multipass_size))
    SAV2p=$((SAV2p + orig_size - pass2_size))
    TOTAL_MULTIPASS_GAIN=$((TOTAL_MULTIPASS_GAIN + mp_gain))
    SVG_PROCESSED=$((SVG_PROCESSED + 1))

    echo "$fname,$orig_size,$default_size,$multipass_size,$pass2_size,$winner,$winner_size,$savings_pct,$mp_gain" >> "$RESULTS_CSV"

    printf "  %-25s %8s %8s %9s %8s   🏆 %-16s %+d octets (%s%%)\n" \
        "$fname" "$orig_size" "$default_size" "$multipass_size" "$pass2_size" "$winner" "$mp_gain" "$mp_gain_pct"

    rm -rf "$TMPD"
done

# =============================================================================
# RAPPORT
# =============================================================================
title "═══════════════════════════════════════"
title " RAPPORT DE SYNTHÈSE SVG"
title "═══════════════════════════════════════"

{
echo "Benchmark comparatif SVG (svgo configurations) — ImageArm"
echo "Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Machine : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
echo ""
echo "================================================================"
echo "  SVG — VICTOIRES PAR CONFIGURATION ($SVG_PROCESSED images)"
echo "================================================================"

for entry in "svgo_default:$WINSdef:$SAVdef" "svgo_multipass:$WINSmp:$SAVmp" "svgo_2passes:$WINS2p:$SAV2p" "original:$WINSorig:0"; do
    tool_name="${entry%%:*}"; rest="${entry#*:}"; wins="${rest%%:*}"; ts="${rest##*:}"
    if [ "$SVG_PROCESSED" -gt 0 ]; then
        pct=$(python3 -c "print(f'{$wins/$SVG_PROCESSED * 100:.1f}')")
    else
        pct="0"
    fi
    if [ "$tool_name" != "original" ]; then
        saved_kb=$(python3 -c "print(f'{$ts/1024:.1f}')")
    else
        saved_kb="—"
    fi
    printf "  %-20s  %3d victoires (%5s%%)  économie totale: %s Ko\n" "$tool_name" "$wins" "$pct" "$saved_kb"
done

echo ""
if [ "$SVG_PROCESSED" -gt 0 ]; then
    avg_mp_gain=$(python3 -c "print(f'{$TOTAL_MULTIPASS_GAIN/$SVG_PROCESSED:.0f}')")
    echo "  Gain moyen multipass vs default : $avg_mp_gain octets/image"
fi

echo ""
echo "================================================================"
echo "  CONCLUSION SVG"
echo "================================================================"
echo ""
if [ "$WINSmp" -ge "$SVG_PROCESSED" ] || [ "$WINS2p" -ge "$SVG_PROCESSED" ]; then
    echo "  → multipass gagne systématiquement."
    echo "    RECOMMANDATION : toujours utiliser --multipass."
elif [ "$TOTAL_MULTIPASS_GAIN" -le 100 ]; then
    echo "  → Le gain de multipass est négligeable (<100 octets total)."
    echo "    RECOMMANDATION : svgo default suffit. Multipass uniquement en Ultra."
else
    echo "  → multipass apporte un gain mesurable."
    echo "    RECOMMANDATION : utiliser multipass en High/Ultra, default en Quick/Standard."
fi
echo ""
echo "  NOTE: svgo est le seul outil SVG. Pas de compétition multi-outils possible."
echo "  Le pipeline SVG actuel (svgo seul) est optimal."

echo ""
echo "Données détaillées : $RESULTS_CSV"
} | tee "$REPORT"

echo ""
echo "${GREEN}Rapport sauvegardé : $REPORT${NC}"
echo "${GREEN}Données CSV : $RESULTS_CSV${NC}"
