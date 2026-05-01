#!/bin/bash
# Run today's podcast episode generation
# Double-click this file to execute

REPO_DIR="$HOME/jira-podcast"
EP_DATE="$(date +%Y-%m-%d)"

echo "=== Ticket Podcast Episode Generator ==="
echo "Date: $EP_DATE"
echo ""

bash "$REPO_DIR/generate-episode.sh"

echo ""
echo "Press any key to close..."
read -n 1
