# Claude Code Statusline

Highly customizable, colorful statusline for Claude Code with dynamic progress indicators, token tracking, and git integration.

## What This Is

A statusline plugin for Claude Code that shows real-time information about your session: model, progress, tokens, git branch, directory, time, and more.

## Tech Stack

- **Language:** Bash
- **Integration:** Claude Code statusLine setting

## Installation

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "command": "bash /Users/proxikal/dev/projects/claude-statusline/command.sh"
  }
}
```

## Commands

```bash
# View script
just view

# Edit script
just edit

# Test run
just test
```

## Features

- **16 Configurable Sections:** Model, progress bar, tokens, git, directory, time, cost, cache stats
- **Dynamic Progress Bar:** Color-coded context usage (green/yellow/red)
- **Token Tracking:** Input/output tokens with autocompact warnings
- **Session Cost Calculator:** Real-time cost based on Anthropic pricing
- **Git Integration:** Shows current branch
- **Vim Mode Support:** INSERT/NORMAL indicators
- **Auto-updates:** Check for new versions from GitHub
- **256-Color Support:** Full ANSI color palette

## Configuration

Edit `config.json` to customize:
- Colors (256-color palette)
- Icons
- Section ordering
- Thresholds (context warnings)
- Enable/disable sections

## Customization

The statusline is a shell script that outputs ANSI-formatted text. You can modify `command.sh` directly to add new sections or change behavior.

See README.md for full configuration options and screenshots.
