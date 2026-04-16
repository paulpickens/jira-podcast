#!/bin/bash
cd "$HOME/Documents/jira-podcast"
echo "Pushing episode to GitHub..."
git push origin main
echo ""
echo "Done. Episode live at:"
echo "https://paulpickens.github.io/jira-podcast/episodes/episode-2026-04-15.mp3"
echo "Feed: https://paulpickens.github.io/jira-podcast/feed.xml"
echo ""
echo "Press any key to close..."
read -n 1
