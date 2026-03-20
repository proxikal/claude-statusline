# Claude Code Statusline
# Shell script project

default:
    @just --list

# View main script
view:
    bat command.sh

# Edit main script
edit:
    ${EDITOR:-vim} command.sh

# Install (add to Claude config)
install:
    @echo "Add to ~/.claude/settings.json:"
    @echo '  "statusLine": {"command": "bash /Users/proxikal/dev/projects/claude-statusline/command.sh"}'

# Test run
test:
    bash command.sh

# Deploy to global ~/.claude/statusline
deploy:
    ./deploy.sh
