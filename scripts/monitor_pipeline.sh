#!/bin/bash
#
# Pipeline Job Monitor - Simple, clean job status display
# Usage: ./monitor_pipeline.sh [--live] [--interval 5]
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$REPO_ROOT/logs"

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

# Get stage from log
get_stage() {
    local log_file=$1
    [[ ! -f "$log_file" ]] && echo "?" && return

    grep -q "STAGE 2 COMPLETE" "$log_file" && echo "DONE" && return
    grep -q "Analyzing and Filtering" "$log_file" && echo "ANALYZE" && return
    grep -q "Structure Prediction" "$log_file" && ! grep -q "STAGE 1" "$log_file" && echo "FOLD" && return
    grep -q "STAGE 1 COMPLETE" "$log_file" && echo "STAGE2" && return
    grep -q "Running MPNN" "$log_file" && echo "MPNN" && return
    grep -q "Running RFD3" "$log_file" && echo "RFD3" && return
    grep -q "Configuration loaded" "$log_file" && echo "INIT" && return
    echo "?"
}

# Get config name from log
get_config() {
    local log_file=$1
    [[ ! -f "$log_file" ]] && return
    grep -oP 'settings_json["\047s]*:\s*"\K[^"]*' "$log_file" | xargs basename 2>/dev/null | sed 's/.json$//' | head -1
}

# Get subdirectory from log
get_subdir() {
    local log_file=$1
    [[ ! -f "$log_file" ]] && return
    grep -oP 'design_generation/\K[^/]+' "$log_file" | head -1
}

print_monitor() {
    clear

    local total=$(squeue -u $USER -h 2>/dev/null | wc -l)
    local running=$(squeue -u $USER -h -t RUNNING 2>/dev/null | wc -l)
    local pending=$(squeue -u $USER -h -t PENDING 2>/dev/null | wc -l)

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "PIPELINE MONITOR  |  $(date '+%H:%M:%S')  |  Jobs: $running running, $pending pending, $total total"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [[ $total -eq 0 ]]; then
        echo "No active jobs"
        echo ""
        return
    fi

    echo "JOBID       STATE  STAGE      CONFIG              SUBDIR"
    echo "────────────────────────────────────────────────────────────────────"

    squeue -u $USER -h -o "%.10i %.2t" 2>/dev/null | while read jobid state; do
        # Determine log file
        stage2_log="$LOGS_DIR/stage2_${jobid}.log"
        stage1_log="$LOGS_DIR/stage1_${jobid}.log"

        if [[ -f "$stage2_log" ]]; then
            log_file="$stage2_log"
        elif [[ -f "$stage1_log" ]]; then
            log_file="$stage1_log"
        else
            log_file=""
        fi

        # Extract info
        config=$(get_config "$log_file")
        subdir=$(get_subdir "$log_file")
        stage=$(get_stage "$log_file")

        # Format state
        case $state in
            R) state_str="RUN   " ;;
            PD) state_str="PEND  " ;;
            F) state_str="FAIL  " ;;
            CA) state_str="CANCEL" ;;
            *) state_str="$state    " ;;
        esac

        # Get time
        time=$(squeue -u $USER -h -j $jobid -o "%.5M" 2>/dev/null)

        # Truncate for display
        config="${config:0:18}"
        subdir="${subdir:0:23}"

        printf "%-12s%-7s%-11s%-20s%-25s\n" "$jobid" "$state_str" "$stage" "$config" "$subdir"
    done

    echo "────────────────────────────────────────────────────────────────────"
    echo "Tip: tail -f logs/stage1_JOBID.log  or  ./monitor_pipeline.sh --live"
    echo ""
}

if [[ "$LIVE_UPDATE" == true ]]; then
    while true; do
        print_monitor
        echo "Updates every ${UPDATE_INTERVAL}s (Ctrl+C to exit)"
        sleep "$UPDATE_INTERVAL"
    done
else
    print_monitor
fi
