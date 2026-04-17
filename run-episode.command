#!/bin/bash
# Run today's podcast episode generation
# Double-click this file to execute

# Load user environment (needed for ELEVENLABS_API_KEY)
source ~/.zshrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || true

REPO_DIR="$HOME/jira-podcast"
SCRIPT_FILE="$REPO_DIR/podcast-script.txt"
EP_DATE="2026-04-15"

echo "=== Ticket Podcast Episode Generator ==="
echo "Date: $EP_DATE"
echo "Script: $SCRIPT_FILE"
echo ""

bash "$REPO_DIR/generate-episode.sh" "$SCRIPT_FILE" "$EP_DATE"

echo ""
echo "Press any key to close..."
read -n 1
