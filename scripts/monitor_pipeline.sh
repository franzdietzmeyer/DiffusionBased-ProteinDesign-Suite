#!/bin/bash
#
# Pipeline Job Monitor - Beautiful live status dashboard for multi-stage design pipeline
# Optimized for portrait orientation
# Usage: ./monitor_pipeline.sh [--live] [--interval 5]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$REPO_ROOT/logs"

# Parse arguments
LIVE_UPDATE=false
UPDATE_INTERVAL=5

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --live) LIVE_UPDATE=true ;;
        --interval) UPDATE_INTERVAL="$2"; shift ;;
        -h|--help) echo "Usage: $0 [--live] [--interval SECONDS]"; exit 0 ;;
    esac
    shift
done

# Colors for output
RED='\033[0;31m'
DARK_RED='\033[0;91m'
GREEN='\033[0;32m'
DARK_GREEN='\033[0;92m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
DARK_BLUE='\033[0;94m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

get_stage_from_log() {
    local log_file=$1
    if [[ ! -f "$log_file" ]]; then
        echo "❓"
        return
    fi

    if grep -q "STAGE 2 COMPLETE\|Generating Analysis Plots" "$log_file"; then
        echo "✅ DONE"
    elif grep -q "Analyzing and Filtering" "$log_file"; then
        echo "🔍 ANALYZE"
    elif grep -q "Structure Prediction" "$log_file" && ! grep -q "STAGE 1" "$log_file"; then
        echo "🧬 FOLD"
    elif grep -q "STAGE 1 COMPLETE" "$log_file"; then
        echo "➡️  S2"
    elif grep -q "Running MPNN\|Sequence Design" "$log_file"; then
        echo "🔗 MPNN"
    elif grep -q "Running RFD3\|Backbone Generation" "$log_file"; then
        echo "🎲 RFD3"
    elif grep -q "Configuration loaded" "$log_file"; then
        echo "⚙️  INIT"
    else
        echo "❓"
    fi
}

get_config_from_log() {
    local log_file=$1
    if [[ ! -f "$log_file" ]]; then
        return
    fi
    grep -oP 'settings_json["\047s]*:\s*"\K[^"]*' "$log_file" | xargs basename 2>/dev/null | sed 's/.json$//' | head -1
}

get_subdir_from_log() {
    local log_file=$1
    if [[ ! -f "$log_file" ]]; then
        return
    fi
    grep -oP 'design_generation/\K[^/]+' "$log_file" | head -1
}

get_status_icon() {
    local state=$1
    case $state in
        R) echo "▶️ " ;;
        PD) echo "⏳" ;;
        F) echo "❌" ;;
        CA) echo "⛔" ;;
        *) echo "❓" ;;
    esac
}

get_state_color() {
    local state=$1
    case $state in
        R) echo "$DARK_GREEN" ;;
        PD) echo "$YELLOW" ;;
        F) echo "$RED" ;;
        CA) echo "$DARK_RED" ;;
        *) echo "$CYAN" ;;
    esac
}

print_header() {
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════╗"
    echo "║  🚀 PIPELINE JOB MONITOR 🚀          ║"
    echo "║  $(date '+%H:%M:%S') - $(date '+%a, %b %d')              ║"
    echo "╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

print_job_card() {
    local jobid=$1
    local state=$2
    local stage=$3
    local config=$4
    local subdir=$5
    local time=$6

    local state_color=$(get_state_color "$state")
    local status_icon=$(get_status_icon "$state")

    # Shorten subdir for display
    local display_subdir=$(echo "$subdir" | cut -c1-20)
    local display_config=$(echo "$config" | cut -c1-18)

    echo -e "${GRAY}┌─────────────────────────────────────┐${NC}"
    echo -e "│ ${BOLD}Job:${NC} ${BLUE}$jobid${NC}"
    echo -e "│ ${status_icon} ${state_color}${BOLD}$state${NC}"
    echo -e "│ ${stage}"
    [[ -n "$display_config" ]] && echo -e "│ ${MAGENTA}📋${NC} $display_config"
    [[ -n "$display_subdir" ]] && echo -e "│ ${CYAN}📁${NC} $display_subdir"
    echo -e "│ ${GRAY}⏱${NC}  $time"
    echo -e "${GRAY}└─────────────────────────────────────┘${NC}"
}

print_detailed_view() {
    clear
    print_header

    # Get job counts
    local total=$(squeue -u $USER -h 2>/dev/null | wc -l)
    local running=$(squeue -u $USER -h -t RUNNING 2>/dev/null | wc -l)
    local pending=$(squeue -u $USER -h -t PENDING 2>/dev/null | wc -l)

    # Summary bar
    echo -e "${BOLD}📊 SUMMARY${NC}"
    echo -e "${GRAY}├${NC} Total:   ${BOLD}$total${NC}"
    echo -e "${GRAY}├${NC} Running: ${DARK_GREEN}${BOLD}$running${NC} ▶️"
    echo -e "${GRAY}└${NC} Pending: ${YELLOW}${BOLD}$pending${NC} ⏳"
    echo ""

    # Get all jobs for this user
    if [[ $total -eq 0 ]]; then
        echo -e "${GRAY}No jobs running${NC}"
    else
        echo -e "${BOLD}🎯 ACTIVE JOBS${NC}"
        echo ""

        squeue -u $USER -h -o "%.10i %.2t" 2>/dev/null | while read jobid state; do
            # Find corresponding log files
            stage1_log=$(ls "$LOGS_DIR"/stage1_${jobid}.log 2>/dev/null)
            stage2_log=$(ls "$LOGS_DIR"/stage2_${jobid}.log 2>/dev/null)

            # Determine which log to use
            if [[ -f "$stage2_log" ]]; then
                log_file="$stage2_log"
            elif [[ -f "$stage1_log" ]]; then
                log_file="$stage1_log"
            else
                log_file=""
            fi

            # Extract info from logs
            config=$(get_config_from_log "$log_file")
            subdir=$(get_subdir_from_log "$log_file")
            stage=$(get_stage_from_log "$log_file")

            # Get time
            time=$(squeue -u $USER -h -j $jobid -o "%.8M" 2>/dev/null)

            # Print card
            print_job_card "$jobid" "$state" "$stage" "$config" "$subdir" "$time"
            echo ""
        done
    fi

    # Footer with tips
    echo -e "${GRAY}────────────────────────────────────${NC}"
    echo -e "${BOLD}💡 Quick Commands:${NC}"
    echo -e "  ${DIM}tail -f logs/stage1_JOBID.log${NC}  → Full log"
    echo -e "  ${DIM}cat logs/stage2_JOBID.err${NC}       → Errors"
    echo -e "  ${DIM}scancel JOBID${NC}                   → Cancel"
    [[ "$LIVE_UPDATE" == false ]] && echo -e "  ${DIM}$0 --live${NC}              → Live view"
    echo ""
}

if [[ "$LIVE_UPDATE" == true ]]; then
    while true; do
        print_detailed_view
        echo -e "${BOLD}${CYAN}🔄 Updates every ${UPDATE_INTERVAL}s (Ctrl+C to exit)${NC}"
        sleep "$UPDATE_INTERVAL"
    done
else
    print_detailed_view
fi
