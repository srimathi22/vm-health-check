#!/usr/bin/env bash

set -Eeuo pipefail

error() {
    printf 'ERROR: %s\n' "$1" >&2
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        error "Required command not found: $1"
        return 1
    fi
}

is_percentage() {
    local value=$1

    [[ $value =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] || return 1
    awk -v value="$value" 'BEGIN { exit !(value >= 0 && value <= 100) }'
}

classify_health() {
    local cpu=$1
    local memory=$2
    local disk=$3

    is_percentage "$cpu" && is_percentage "$memory" && is_percentage "$disk" || return 2

    if awk -v cpu="$cpu" -v memory="$memory" -v disk="$disk" \
        'BEGIN { exit !(cpu < 60 && memory < 60 && disk < 60) }'; then
        printf 'HEALTHY'
    else
        printf 'NOT HEALTHY'
    fi
}

get_linux_cpu_usage() {
    local first_sample second_sample first_total first_idle second_total second_idle
    local total_delta idle_delta

    if [[ ! -r /proc/stat ]]; then
        error 'Cannot read /proc/stat to measure CPU utilization.'
        return 1
    fi

    first_sample=$(awk '/^cpu / { idle = $5 + $6; total = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9; printf "%.0f %.0f", total, idle; exit }' /proc/stat) || return 1
    read -r first_total first_idle <<< "$first_sample"
    sleep 1
    second_sample=$(awk '/^cpu / { idle = $5 + $6; total = $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9; printf "%.0f %.0f", total, idle; exit }' /proc/stat) || return 1
    read -r second_total second_idle <<< "$second_sample"

    total_delta=$((second_total - first_total))
    idle_delta=$((second_idle - first_idle))
    if (( total_delta <= 0 )); then
        error 'Could not calculate CPU utilization from /proc/stat.'
        return 1
    fi

    awk -v total="$total_delta" -v idle="$idle_delta" \
        'BEGIN { value = (1 - idle / total) * 100; if (value < 0) value = 0; if (value > 100) value = 100; printf "%.2f", value }'
}

get_macos_cpu_usage() {
    local cpu_usage

    cpu_usage=$(top -l 2 -n 0 | awk '
        /CPU usage:/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "idle") {
                    idle = $(i - 1)
                    gsub(/%/, "", idle)
                    last = 100 - idle
                }
            }
        }
        END {
            if (last == "") exit 1
            printf "%.2f", last
        }
    ') || {
        error 'Could not read CPU utilization from top.'
        return 1
    }
    printf '%s' "$cpu_usage"
}

get_cpu_usage() {
    case $(uname -s) in
        Linux)
            get_linux_cpu_usage
            ;;
        Darwin)
            get_macos_cpu_usage
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            return 1
            ;;
    esac
}

get_linux_memory_usage() {
    local memory_values total available

    if [[ ! -r /proc/meminfo ]]; then
        error 'Cannot read /proc/meminfo to measure memory utilization.'
        return 1
    fi

    memory_values=$(awk '
        $1 == "MemTotal:" { total = $2 }
        $1 == "MemAvailable:" { available = $2 }
        END {
            if (total <= 0 || available < 0) exit 1
            printf "%s %s", total, available
        }
    ' /proc/meminfo) || {
        error 'Could not calculate memory utilization from /proc/meminfo.'
        return 1
    }
    read -r total available <<< "$memory_values"
    awk -v total="$total" -v available="$available" \
        'BEGIN { printf "%.2f", ((total - available) / total) * 100 }'
}

get_macos_memory_usage() {
    local total_bytes page_size page_counts

    total_bytes=$(sysctl -n hw.memsize) || {
        error 'Could not read physical memory size with sysctl.'
        return 1
    }
    page_size=$(sysctl -n hw.pagesize) || {
        error 'Could not read the memory page size with sysctl.'
        return 1
    }
    page_counts=$(vm_stat | awk '
        /Pages free:/ || /Pages inactive:/ || /Pages speculative:/ {
            value = $NF
            gsub(/[.]/, "", value)
            available += value
        }
        END {
            if (available < 0) exit 1
            print available
        }
    ') || {
        error 'Could not read available memory from vm_stat.'
        return 1
    }

    awk -v total_bytes="$total_bytes" -v page_size="$page_size" -v pages="$page_counts" \
        'BEGIN {
            total_pages = total_bytes / page_size
            if (total_pages <= 0) exit 1
            value = (1 - pages / total_pages) * 100
            if (value < 0) value = 0
            if (value > 100) value = 100
            printf "%.2f", value
        }'
}

get_memory_usage() {
    case $(uname -s) in
        Linux)
            get_linux_memory_usage
            ;;
        Darwin)
            get_macos_memory_usage
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            return 1
            ;;
    esac
}

get_disk_usage() {
    local disk_usage

    disk_usage=$(df -Pk / | awk 'NR == 2 { if ($2 <= 0) exit 1; printf "%.2f", ($3 / $2) * 100 }') || {
        error 'Could not calculate disk utilization for the root filesystem.'
        return 1
    }
    printf '%s' "$disk_usage"
}

main() {
    local cpu memory disk status

    if (( $# > 0 )); then
        error 'This script does not accept arguments.'
        return 2
    fi

    require_command awk || return 1
    require_command df || return 1
    require_command uname || return 1

    case $(uname -s) in
        Linux)
            ;;
        Darwin)
            require_command top || return 1
            require_command sysctl || return 1
            require_command vm_stat || return 1
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            return 1
            ;;
    esac

    cpu=$(get_cpu_usage) || return 1
    memory=$(get_memory_usage) || return 1
    disk=$(get_disk_usage) || return 1
    status=$(classify_health "$cpu" "$memory" "$disk") || {
        error 'Received an invalid utilization value; no overall status was produced.'
        return 1
    }

    printf 'VM Health Check\n'
    printf 'CPU utilization:    %s%%\n' "$cpu"
    printf 'Memory utilization: %s%%\n' "$memory"
    printf 'Disk utilization:   %s%%\n' "$disk"
    printf 'Overall status:     %s\n' "$status"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi