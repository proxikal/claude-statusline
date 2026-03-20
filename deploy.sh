#!/bin/bash

################################################################################
# Claude Statusline Deployment Script
# Syncs changed files from project folder to ~/.claude/statusline
################################################################################

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Directories
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_DIR="$HOME/.claude/statusline"

echo -e "${GREEN}Claude Statusline Deployment${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Project: $PROJECT_DIR"
echo "Target:  $GLOBAL_DIR"
echo ""

# Create global directory if it doesn't exist
if [ ! -d "$GLOBAL_DIR" ]; then
    echo -e "${YELLOW}Creating global directory...${NC}"
    mkdir -p "$GLOBAL_DIR"
fi

# Files to deploy
FILES=(
    "command.sh"
    "config.json"
    "README.md"
)

# Track changes
UPDATED=0
SKIPPED=0
ERRORS=0

# Deploy each file
for file in "${FILES[@]}"; do
    SRC="$PROJECT_DIR/$file"
    DST="$GLOBAL_DIR/$file"

    if [ ! -f "$SRC" ]; then
        echo -e "${RED}✗${NC} $file (source not found)"
        ((ERRORS++))
        continue
    fi

    # Check if files are different
    if [ -f "$DST" ]; then
        if cmp -s "$SRC" "$DST"; then
            echo -e "${YELLOW}⊙${NC} $file (unchanged)"
            ((SKIPPED++))
            continue
        fi

        # Backup existing file
        BACKUP="${DST}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$DST" "$BACKUP"
        echo -e "${GREEN}✓${NC} $file (backed up to $(basename "$BACKUP"))"
    fi

    # Copy file
    cp "$SRC" "$DST"

    # Make command.sh executable
    if [ "$file" = "command.sh" ]; then
        chmod +x "$DST"
    fi

    echo -e "${GREEN}✓${NC} $file (deployed)"
    ((UPDATED++))
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Updated: ${GREEN}$UPDATED${NC} | Skipped: ${YELLOW}$SKIPPED${NC} | Errors: ${RED}$ERRORS${NC}"

if [ $UPDATED -gt 0 ]; then
    echo -e "${GREEN}Deployment complete!${NC}"
    echo "Restart your Claude Code sessions to see changes."
else
    echo -e "${YELLOW}No files updated.${NC}"
fi
