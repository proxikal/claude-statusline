#!/bin/bash

################################################################################
# Claude Code Statusline Script
# Complete rewrite with modular architecture and ordering system
################################################################################

# Read JSON input from stdin
input=$(cat)

# Configuration file path (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/statusline-config.json"

################################################################################
# HELPER FUNCTIONS
################################################################################

# Read config with fallback to default
read_config() {
    local key=$1
    local default=$2
    if [ -f "$CONFIG_FILE" ]; then
        local value=$(jq -r "$key // \"$default\"" "$CONFIG_FILE" 2>/dev/null)
        if [ "$value" != "null" ] && [ -n "$value" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

# Convert color code to ANSI escape
color_code() {
    local code=$1
    echo $'\033['"${code}m"
}

# Debug logging function
debug_log() {
    if [ "$DEBUG_ENABLED" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] $1" >> "$DEBUG_LOGFILE"
    fi
}

# Check if section is enabled
section_enabled() {
    local section=$1
    local enabled=$(read_config ".sections.$section" 'false')
    [ "$enabled" = "true" ]
}

# Format tokens in K
format_tokens() {
    local tokens=$1
    if [ "$tokens" -gt 1000 ] 2>/dev/null; then
        local display=$(echo "scale=1; $tokens / 1000" | bc -l | sed 's/\.0$//')
        echo "${display}K"
    else
        echo "$tokens"
    fi
}

################################################################################
# LOAD CONFIGURATION
################################################################################

# Debug settings
DEBUG_ENABLED=$(read_config '.debug.enabled' 'false')
DEBUG_LOGFILE=$(read_config '.debug.logFile' '/tmp/statusline-debug.log')

# Load separator
SEPARATOR=$(read_config '.separator.character' '│')

# Load icons enabled status
ICONS_ENABLED=$(read_config '.icons.enabled' 'true')

# Reset color
RESET=$'\033[0m'

################################################################################
# EXTRACT VALUES FROM JSON
################################################################################

# Core values
current_dir=$(echo "$input" | jq -r '.workspace.current_dir')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir')
model_name=$(echo "$input" | jq -r '.model.display_name')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens')
used_percentage=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
context_window_size=$(echo "$input" | jq -r '.context_window.context_window_size')

# New section values
output_style=$(echo "$input" | jq -r '.output_style.name')
vim_mode=$(echo "$input" | jq -r '.vim.mode')
cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // .context_window.last_api_call.cache_read_input_tokens')
cache_write=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // .context_window.last_api_call.cache_creation_input_tokens')
last_call_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // .context_window.last_api_call.input_tokens')
last_call_output=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // .context_window.last_api_call.output_tokens')
agent_name=$(echo "$input" | jq -r '.agent.name')
app_version=$(echo "$input" | jq -r '.version')

# Derived values
dir_name=$(basename "$current_dir" 2>/dev/null)
project_name=$(basename "$project_dir" 2>/dev/null)

# Git branch
git_branch=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
fi

################################################################################
# CACHING SYSTEM (prevents blinking)
################################################################################

# Use session-specific cache directory (auto-cleaned when session ends)
# Falls back to parent shell PID for session isolation
CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline-${PPID}"
mkdir -p "$CACHE_DIR" 2>/dev/null

CACHE_PERCENTAGE="${CACHE_DIR}/cache-used_percentage"
CACHE_INPUT="${CACHE_DIR}/cache-total_input"
CACHE_OUTPUT="${CACHE_DIR}/cache-total_output"
CACHE_CONTEXT="${CACHE_DIR}/cache-context_size"

# Cache used_percentage
if [ -n "$used_percentage" ] && [ "$used_percentage" != "null" ] && [ "$used_percentage" != "empty" ]; then
    echo "$used_percentage" > "$CACHE_PERCENTAGE" 2>/dev/null
    cache_pct_status="saved"
else
    if [ -f "$CACHE_PERCENTAGE" ]; then
        used_percentage=$(cat "$CACHE_PERCENTAGE" 2>/dev/null)
        cache_pct_status="loaded"
    else
        cache_pct_status="no_cache"
    fi
fi

# Cache context_window_size
if [ -n "$context_window_size" ] && [ "$context_window_size" != "null" ]; then
    echo "$context_window_size" > "$CACHE_CONTEXT" 2>/dev/null
else
    [ -f "$CACHE_CONTEXT" ] && context_window_size=$(cat "$CACHE_CONTEXT" 2>/dev/null)
fi

# Cache total_input
if [ -n "$total_input" ] && [ "$total_input" != "null" ]; then
    echo "$total_input" > "$CACHE_INPUT" 2>/dev/null
else
    [ -f "$CACHE_INPUT" ] && total_input=$(cat "$CACHE_INPUT" 2>/dev/null)
fi

# Cache total_output
if [ -n "$total_output" ] && [ "$total_output" != "null" ]; then
    echo "$total_output" > "$CACHE_OUTPUT" 2>/dev/null
else
    [ -f "$CACHE_OUTPUT" ] && total_output=$(cat "$CACHE_OUTPUT" 2>/dev/null)
fi

# Debug logging
debug_log "=== Statusline Execution ==="
debug_log "used_percentage: '$used_percentage' (cache: $cache_pct_status)"
debug_log "context_window_size: '$context_window_size'"
debug_log "total_input: '$total_input' total_output: '$total_output'"
debug_log "output_style: '$output_style'"
debug_log "vim_mode: '$vim_mode'"
debug_log "cache_read: '$cache_read' cache_write: '$cache_write'"
debug_log "last_call_input: '$last_call_input' last_call_output: '$last_call_output'"
debug_log "agent_name: '$agent_name'"
debug_log "app_version: '$app_version'"

################################################################################
# LOAD COLORS FROM CONFIG
################################################################################

COLOR_SEPARATOR=$(color_code "$(read_config '.colors.separator' '37')")
COLOR_MODEL=$(color_code "$(read_config '.colors.model' '36')")
COLOR_TOKENS_NORMAL=$(color_code "$(read_config '.colors.totalTokens.normal' '97')")
COLOR_TOKENS_WARNING=$(color_code "$(read_config '.colors.totalTokens.warning' '38;5;208')")
COLOR_TOKENS_CRITICAL=$(color_code "$(read_config '.colors.totalTokens.critical' '31')")
COLOR_TOKENS_ICON=$(color_code "$(read_config '.colors.tokens.icon' '34')")
COLOR_TOKENS_INPUT=$(color_code "$(read_config '.colors.tokens.input' '38;5;39')")
COLOR_TOKENS_OUTPUT=$(color_code "$(read_config '.colors.tokens.output' '38;5;27')")
COLOR_GIT=$(color_code "$(read_config '.colors.git' '35')")
COLOR_DIRECTORY=$(color_code "$(read_config '.colors.directory' '31')")
COLOR_TIME=$(color_code "$(read_config '.colors.time' '36')")
COLOR_OUTPUT_STYLE=$(color_code "$(read_config '.colors.outputStyle' '38;5;213')")
COLOR_VIM_INSERT=$(color_code "$(read_config '.colors.vimMode.insert' '38;5;46')")
COLOR_VIM_NORMAL=$(color_code "$(read_config '.colors.vimMode.normal' '38;5;33')")
COLOR_SESSION_COST=$(color_code "$(read_config '.colors.sessionCost' '38;5;226')")
COLOR_CACHE_STATS=$(color_code "$(read_config '.colors.cacheStats' '38;5;141')")
COLOR_LAST_CALL=$(color_code "$(read_config '.colors.lastCallTokens' '38;5;249')")
COLOR_AGENT=$(color_code "$(read_config '.colors.agentName' '38;5;208')")
COLOR_VERSION=$(color_code "$(read_config '.colors.appVersion' '38;5;244')")
COLOR_PROJECT=$(color_code "$(read_config '.colors.projectName' '38;5;99')")

# Progress bar settings
PBAR_WIDTH=$(read_config '.progressBar.width' '20')
PBAR_THRESHOLD_YELLOW=$(read_config '.progressBar.thresholds.yellow' '60')
PBAR_THRESHOLD_RED=$(read_config '.progressBar.thresholds.red' '80')
PBAR_COLOR_GREEN=$(color_code "$(read_config '.progressBar.colors.green' '48;5;46')")
PBAR_COLOR_YELLOW=$(color_code "$(read_config '.progressBar.colors.yellow' '48;5;226')")
PBAR_COLOR_RED=$(color_code "$(read_config '.progressBar.colors.red' '48;5;196')")
PBAR_COLOR_EMPTY=$(color_code "$(read_config '.progressBar.colors.empty' '48;5;236')")
PBAR_TEXT_FILLED=$(color_code "$(read_config '.progressBar.textColors.onFilled' '30')")
PBAR_TEXT_EMPTY=$(color_code "$(read_config '.progressBar.textColors.onEmpty' '97')")

# Token warning thresholds
TOKEN_WARNING=$(read_config '.tokens.warningThresholds.warning' '60000')
TOKEN_CRITICAL=$(read_config '.tokens.warningThresholds.critical' '40000')

# Time format
TIME_FORMAT=$(read_config '.time.format' '24h')

# Session cost settings
COST_SYMBOL=$(read_config '.sessionCost.currencySymbol' '$')
COST_DECIMALS=$(read_config '.sessionCost.decimals' '4')

# Load icons
ICON_TOKENS=$(read_config '.icons.tokens' '⚡')
ICON_GIT=$(read_config '.icons.git' '⎇')
ICON_DIRECTORY=$(read_config '.icons.directory' '📁')
ICON_TIME=$(read_config '.icons.time' '⏱')
ICON_OUTPUT_STYLE=$(read_config '.icons.outputStyle' '✨')
ICON_VIM=$(read_config '.icons.vimMode' '✏️')
ICON_COST=$(read_config '.icons.sessionCost' '💰')
ICON_CACHE=$(read_config '.icons.cacheStats' '💾')
ICON_LAST_CALL=$(read_config '.icons.lastCallTokens' '🔄')
ICON_AGENT=$(read_config '.icons.agentName' '🤖')
ICON_VERSION=$(read_config '.icons.appVersion' 'ⓘ')
ICON_PROJECT=$(read_config '.icons.projectName' '📂')

################################################################################
# PROGRESS BAR CREATION FUNCTION
################################################################################

create_progress_bar() {
    local percentage=$1
    local width=$PBAR_WIDTH
    local filled=$(printf "%.0f" $(echo "$percentage * $width / 100" | bc -l))
    local empty=$((width - filled))
    local percentage_int=$(printf "%.0f" "$percentage")

    # Choose color based on thresholds
    local bar_color
    if [ "$percentage_int" -ge "$PBAR_THRESHOLD_RED" ]; then
        bar_color="$PBAR_COLOR_RED"
    elif [ "$percentage_int" -ge "$PBAR_THRESHOLD_YELLOW" ]; then
        bar_color="$PBAR_COLOR_YELLOW"
    else
        bar_color="$PBAR_COLOR_GREEN"
    fi

    # Format percentage text
    local pct_text="${percentage_int}%"
    local pct_len=${#pct_text}
    local center_pos=$(( (width - pct_len) / 2 ))

    # Determine text colors based on position
    local text_on_filled=0
    [ $center_pos -lt $filled ] && text_on_filled=1

    local text_fg text_bg
    if [ $text_on_filled -eq 1 ]; then
        text_fg="$PBAR_TEXT_FILLED"
        text_bg="$bar_color"
    else
        text_fg="$PBAR_TEXT_EMPTY"
        text_bg="$PBAR_COLOR_EMPTY"
    fi

    # Build bar
    local bar=""
    for ((i=0; i<width; i++)); do
        if [ $i -eq $center_pos ]; then
            for ((j=0; j<pct_len; j++)); do
                bar+="${text_bg}${text_fg}${pct_text:$j:1}${RESET}"
            done
            i=$((i + pct_len - 1))
        else
            if [ $i -lt $filled ]; then
                bar+="${bar_color} ${RESET}"
            else
                bar+="${PBAR_COLOR_EMPTY} ${RESET}"
            fi
        fi
    done

    echo "$bar"
}

################################################################################
# SECTION RENDER FUNCTIONS
################################################################################

render_model() {
    [ -z "$model_name" ] || [ "$model_name" = "null" ] && return
    echo "${COLOR_MODEL}${model_name}${RESET}"
}

render_progressBar() {
    local pct_value="0"
    if [ -n "$used_percentage" ] && [ "$used_percentage" != "null" ] && [ "$used_percentage" != "empty" ]; then
        pct_value="$used_percentage"
    fi
    create_progress_bar "$pct_value"
}

render_totalTokens() {
    [ -z "$used_percentage" ] || [ "$used_percentage" = "null" ] || [ "$used_percentage" = "empty" ] && return
    [ -z "$context_window_size" ] || [ "$context_window_size" = "null" ] && return

    local actual_used_tokens=$(echo "scale=2; ($used_percentage / 100) * $context_window_size" | bc -l)
    actual_used_tokens=$(printf "%.0f" "$actual_used_tokens")
    local remaining_tokens=$((context_window_size - actual_used_tokens))

    # Determine color
    local tokens_color
    if [ "$remaining_tokens" -gt "$TOKEN_WARNING" ]; then
        tokens_color="$COLOR_TOKENS_NORMAL"
    elif [ "$remaining_tokens" -gt "$TOKEN_CRITICAL" ]; then
        tokens_color="$COLOR_TOKENS_WARNING"
    else
        tokens_color="$COLOR_TOKENS_CRITICAL"
    fi

    # Format tokens
    local total_display max_display
    if [ "$actual_used_tokens" -gt 1000 ]; then
        total_display=$(echo "scale=0; $actual_used_tokens / 1000" | bc -l)
        total_display="${total_display}k"
    else
        total_display="0k"
    fi

    if [ "$context_window_size" -gt 1000 ]; then
        max_display=$(echo "scale=0; $context_window_size / 1000" | bc -l)
        max_display="${max_display}k"
    else
        max_display="$context_window_size"
    fi

    echo "${tokens_color}${total_display}/${max_display}${RESET}"
}

render_tokens() {
    [ -z "$total_input" ] || [ "$total_input" = "null" ] && return
    [ -z "$total_output" ] || [ "$total_output" = "null" ] && return

    local input_display=$(format_tokens "$total_input")
    local output_display=$(format_tokens "$total_output")

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${COLOR_TOKENS_ICON}${ICON_TOKENS}${RESET} "

    echo "${icon}${COLOR_TOKENS_INPUT}↑ ${input_display}${RESET} ${COLOR_TOKENS_OUTPUT}↓ ${output_display}${RESET}"
}

render_outputStyle() {
    [ -z "$output_style" ] || [ "$output_style" = "null" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_OUTPUT_STYLE} "

    echo "${COLOR_OUTPUT_STYLE}${icon}${output_style}${RESET}"
}

render_vimMode() {
    [ -z "$vim_mode" ] || [ "$vim_mode" = "null" ] && return

    local color
    [ "$vim_mode" = "INSERT" ] && color="$COLOR_VIM_INSERT" || color="$COLOR_VIM_NORMAL"

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_VIM} "

    echo "${color}${icon}${vim_mode}${RESET}"
}

render_sessionCost() {
    # Calculate cost based on Anthropic API pricing (January 2025)
    [ -z "$total_input" ] || [ "$total_input" = "null" ] && return
    [ -z "$total_output" ] || [ "$total_output" = "null" ] && return

    # Default to 0 for cache values if missing
    local cache_r="${cache_read:-0}"
    local cache_w="${cache_write:-0}"
    [ "$cache_r" = "null" ] && cache_r="0"
    [ "$cache_w" = "null" ] && cache_w="0"

    # Determine pricing based on model name (case insensitive)
    local model_lower=$(echo "$model_name" | tr '[:upper:]' '[:lower:]')
    local input_rate output_rate cache_write_rate cache_read_rate

    if [[ "$model_lower" == *"haiku"* ]]; then
        # Haiku pricing (per million tokens)
        input_rate="0.80"
        output_rate="4.00"
        cache_write_rate="1.00"
        cache_read_rate="0.08"
    elif [[ "$model_lower" == *"opus"* ]]; then
        # Opus pricing (per million tokens)
        input_rate="15.00"
        output_rate="75.00"
        cache_write_rate="18.75"
        cache_read_rate="1.50"
    else
        # Sonnet pricing (default - per million tokens)
        input_rate="3.00"
        output_rate="15.00"
        cache_write_rate="3.75"
        cache_read_rate="0.30"
    fi

    # Calculate cost: (tokens / 1000000) * rate
    local cost=$(echo "scale=6; \
        ($total_input / 1000000 * $input_rate) + \
        ($total_output / 1000000 * $output_rate) + \
        ($cache_w / 1000000 * $cache_write_rate) + \
        ($cache_r / 1000000 * $cache_read_rate)" | bc -l)

    # Format with configured decimals
    local formatted=$(printf "%.${COST_DECIMALS}f" "$cost" 2>/dev/null)
    [ -z "$formatted" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_COST} "

    echo "${COLOR_SESSION_COST}${icon}${COST_SYMBOL}${formatted}${RESET}"
    debug_log "Session cost calculated: \$${formatted} (model: $model_lower, input: $total_input, output: $total_output, cache_r: $cache_r, cache_w: $cache_w)"
}

render_cacheStats() {
    [ -z "$cache_read" ] || [ "$cache_read" = "null" ] && return
    [ -z "$cache_write" ] || [ "$cache_write" = "null" ] && return

    local read_display=$(format_tokens "$cache_read")
    local write_display=$(format_tokens "$cache_write")

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_CACHE} "

    echo "${COLOR_CACHE_STATS}${icon}R:${read_display} W:${write_display}${RESET}"
}

render_lastCallTokens() {
    [ -z "$last_call_input" ] || [ "$last_call_input" = "null" ] && return
    [ -z "$last_call_output" ] || [ "$last_call_output" = "null" ] && return

    local input_display=$(format_tokens "$last_call_input")
    local output_display=$(format_tokens "$last_call_output")

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_LAST_CALL} "

    echo "${COLOR_LAST_CALL}${icon}${input_display}/${output_display}${RESET}"
}

render_agentName() {
    [ -z "$agent_name" ] || [ "$agent_name" = "null" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_AGENT} "

    echo "${COLOR_AGENT}${icon}${agent_name}${RESET}"
}

render_appVersion() {
    [ -z "$app_version" ] || [ "$app_version" = "null" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_VERSION} "

    echo "${COLOR_VERSION}${icon}${app_version}${RESET}"
}

render_projectName() {
    [ -z "$project_name" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_PROJECT} "

    echo "${COLOR_PROJECT}${icon}${project_name}${RESET}"
}

render_git() {
    [ -z "$git_branch" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_GIT} "

    echo "${COLOR_GIT}${icon}${git_branch}${RESET}"
}

render_directory() {
    [ -z "$dir_name" ] && return

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_DIRECTORY} "

    echo "${COLOR_DIRECTORY}${icon}${dir_name}${RESET}"
}

render_time() {
    local current_time
    if [ "$TIME_FORMAT" = "12h" ]; then
        current_time=$(date "+%I:%M %p")
    else
        current_time=$(date "+%H:%M")
    fi

    local icon=""
    [ "$ICONS_ENABLED" = "true" ] && icon="${ICON_TIME} "

    echo "${COLOR_TIME}${icon}${current_time}${RESET}"
}

################################################################################
# BUILD STATUSLINE USING ORDER SYSTEM
################################################################################

# Get order array from config
section_order=$(read_config '.order' '')

# If no order specified, use default
if [ -z "$section_order" ] || [ "$section_order" = "null" ]; then
    section_order='["model","progressBar","totalTokens","tokens","git","directory","time"]'
fi

# Parse order array
sections=$(echo "$section_order" | jq -r '.[]' 2>/dev/null)

# Build statusline
output=""
first_section=true

for section in $sections; do
    # Check if section is enabled
    if section_enabled "$section"; then
        # Render section
        section_output=$(render_$section 2>/dev/null)

        # Add to output if not empty
        if [ -n "$section_output" ]; then
            if [ "$first_section" = true ]; then
                output="$section_output"
                first_section=false
            else
                output+=" ${COLOR_SEPARATOR}${SEPARATOR}${RESET} ${section_output}"
            fi
            debug_log "Section SHOWN: $section"
        else
            debug_log "Section HIDDEN: $section (no data)"
        fi
    fi
done

################################################################################
# OUTPUT STATUSLINE
################################################################################

echo "$output"
