#!/usr/bin/env bash
# Local test suite for claude-statusline
# Run: bash test.sh (or: just test)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PASS=0
FAIL=0
TOTAL=0

# Colors for test output
GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
RESET=$'\033[0m'

run_test() {
    local name=$1
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        echo "  ${GREEN}PASS${RESET}  $name"
        PASS=$((PASS + 1))
    else
        echo "  ${RED}FAIL${RESET}  $name"
        FAIL=$((FAIL + 1))
    fi
}

assert_output_contains() {
    local input=$1
    local expected=$2
    local output
    output=$(echo "$input" | bash command.sh 2>&1)
    clean=$(echo "$output" | sed $'s/\033\[[0-9;]*m//g')
    echo "$clean" | grep -q "$expected"
}

assert_output_not_contains() {
    local input=$1
    local unexpected=$2
    local output
    output=$(echo "$input" | bash command.sh 2>&1)
    clean=$(echo "$output" | sed $'s/\033\[[0-9;]*m//g')
    ! echo "$clean" | grep -q "$unexpected"
}

assert_output_nonempty() {
    local input=$1
    local output
    output=$(echo "$input" | bash command.sh 2>&1)
    [ -n "$output" ]
}

assert_no_crash() {
    local input=$1
    echo "$input" | bash command.sh >/dev/null 2>&1
}

# Standard test input
BASIC='{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"current_dir":"/tmp/test","project_dir":"/tmp/test"},"context_window":{"total_input_tokens":45000,"total_output_tokens":12000,"used_percentage":35,"context_window_size":1000000}}'
HIGH_CTX='{"model":{"display_name":"Sonnet 4.5"},"workspace":{"current_dir":"/tmp/test","project_dir":"/tmp/test"},"context_window":{"total_input_tokens":180000,"total_output_tokens":50000,"used_percentage":85,"context_window_size":200000}}'
MILLION='{"model":{"display_name":"Opus 4.6 (1M context)"},"workspace":{"current_dir":"/tmp/test","project_dir":"/tmp/test"},"context_window":{"total_input_tokens":500000,"total_output_tokens":200000,"used_percentage":70,"context_window_size":1000000}}'

echo ""
echo "${YELLOW}=== JSON Validation ===${RESET}"
run_test "config.json is valid JSON" jq . config.json
for theme in themes/*.json; do
    run_test "$(basename "$theme") is valid JSON" jq . "$theme"
done

echo ""
echo "${YELLOW}=== Render Tests ===${RESET}"
run_test "Basic render produces output" assert_output_nonempty "$BASIC"
run_test "High context render produces output" assert_output_nonempty "$HIGH_CTX"
run_test "Empty input doesn't crash" assert_no_crash '{}'
run_test "Null fields don't crash" assert_no_crash '{"model":{"display_name":null},"workspace":{"current_dir":null}}'

echo ""
echo "${YELLOW}=== Token Display ===${RESET}"
run_test "1M context shows '1M'" assert_output_contains "$MILLION" "1M"
run_test "200k context shows 'k'" assert_output_contains "$HIGH_CTX" "k"
# Only test arrows if tokens section is enabled
if [ "$(jq -r '.sections.tokens' config.json)" = "true" ]; then
    run_test "Tokens display with arrows" assert_output_contains "$BASIC" "↑"
else
    echo "  ${YELLOW}SKIP${RESET}  Tokens display with arrows (section disabled in config)"
fi

echo ""
echo "${YELLOW}=== Model Aliases ===${RESET}"
run_test "Opus alias resolves" assert_output_contains "$BASIC" "Opus 4.6 - 1M"
run_test "Sonnet passes through" assert_output_contains "$HIGH_CTX" "Sonnet 4.5"

echo ""
echo "${YELLOW}=== Named Colors ===${RESET}"
# Source resolve_color for testing
eval "$(sed -n '/^resolve_color/,/^}/p' command.sh)"
run_test "red → 31" test "$(resolve_color red)" = "31"
run_test "cyan → 36" test "$(resolve_color cyan)" = "36"
run_test "orange → 38;5;208" test "$(resolve_color orange)" = "38;5;208"
run_test "Orange (caps) → 38;5;208" test "$(resolve_color Orange)" = "38;5;208"
run_test "purple → 35" test "$(resolve_color purple)" = "35"
run_test "gray → 90" test "$(resolve_color gray)" = "90"
run_test "bg-green → 48;5;46" test "$(resolve_color bg-green)" = "48;5;46"
run_test "Raw code passthrough (38;5;208)" test "$(resolve_color "38;5;208")" = "38;5;208"
run_test "Raw code passthrough (31)" test "$(resolve_color "31")" = "31"

echo ""
echo "${YELLOW}=== Theme Merging ===${RESET}"
cp config.json config.json.testbak
# Test minimal theme
jq '. + {"theme": "minimal"}' config.json > config.tmp && mv config.tmp config.json
run_test "Minimal theme renders" assert_output_nonempty "$BASIC"
run_test "Minimal theme hides git icon" assert_output_not_contains "$BASIC" "⎇"
# Test developer theme
jq '. + {"theme": "developer"}' config.json.testbak > config.tmp && mv config.tmp config.json
run_test "Developer theme renders" assert_output_nonempty "$BASIC"
# Restore
mv config.json.testbak config.json

echo ""
echo "${YELLOW}=== ShellCheck ===${RESET}"
if command -v shellcheck >/dev/null 2>&1; then
    run_test "command.sh passes shellcheck (severity=error)" shellcheck --severity=error command.sh
else
    echo "  ${YELLOW}SKIP${RESET}  shellcheck not installed"
fi

echo ""
echo "────────────────────────────────"
if [ "$FAIL" -eq 0 ]; then
    echo "${GREEN}All $TOTAL tests passed.${RESET}"
else
    echo "${RED}$FAIL/$TOTAL tests failed.${RESET}"
    exit 1
fi
