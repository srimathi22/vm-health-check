#!/usr/bin/env bash

set -Eeuo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "$project_root/vm-health-check.sh"

tests_run=0
failures=0

assert_status() {
    local expected=$1
    local label=$2
    shift 2
    local actual

    tests_run=$((tests_run + 1))
    if actual=$(classify_health "$@"); then
        if [[ $actual == "$expected" ]]; then
            printf 'PASS: %s\n' "$label"
        else
            printf 'FAIL: %s (expected "%s", got "%s")\n' "$label" "$expected" "$actual"
            failures=$((failures + 1))
        fi
    else
        printf 'FAIL: %s (classification returned an error)\n' "$label"
        failures=$((failures + 1))
    fi
}

assert_invalid() {
    local label=$1
    shift

    tests_run=$((tests_run + 1))
    if classify_health "$@" >/dev/null 2>&1; then
        printf 'FAIL: %s (invalid value was accepted)\n' "$label"
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$label"
    fi
}

assert_status HEALTHY 'all metrics below 60%' 0 42.5 59.99
assert_status 'NOT HEALTHY' 'CPU exactly 60%' 60 20 30
assert_status 'NOT HEALTHY' 'memory exactly 60%' 20 60 30
assert_status 'NOT HEALTHY' 'disk exactly 60%' 20 30 60
assert_status 'NOT HEALTHY' 'memory above 60%' 20 60.01 30
assert_status 'NOT HEALTHY' 'disk above 60%' 20 30 85
assert_status HEALTHY 'zero utilization' 0 0 0
assert_invalid 'reject utilization above 100%' 101 20 30
assert_invalid 'reject non-numeric utilization' 20 unknown 30

printf '\n%d tests, %d failures\n' "$tests_run" "$failures"
(( failures == 0 ))