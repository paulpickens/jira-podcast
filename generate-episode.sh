#!/bin/bash
# generate-episode.sh — local TTS via macOS `say`, pushes to GitHub Pages.
set -euo pipefail

REPO_DIR="$HOME/jira-podcast"
SCRIPT_FILE="$REPO_DIR/podcast-script.txt"
EPISODES_DIR="$REPO_DIR/episodes"
FEED_FILE="$REPO_DIR/feed.xml"
VOICE="Evan (Enhanced)"
GITHUB_USER="paulpickens"
REPO_NAME="jira-podcast"

cd "$REPO_DIR"

[[ -f "$SCRIPT_FILE" ]] || { echo "ERROR: $SCRIPT_FILE not found." >&2; exit 1; }
[[ -s "$SCRIPT_FILE" ]] || { echo "ERROR: $SCRIPT_FILE is empty." >&2; exit 1; }

mkdir -p "$EPISODES_DIR"

TODAY=$(date +"%Y-%m-%d")
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")
EPISODE_TITLE="Jira Briefing — $(date +"%A, %B %-d, %Y")"
EPISODE_FILE="episodes/episode-$TODAY.m4a"
EPISODE_PATH="$REPO_DIR/$EPISODE_FILE"

echo "Generating audio with voice: $VOICE"
say -v "$VOICE" -o "$EPISODE_PATH" --data-format=aac -f "$SCRIPT_FILE"
[[ -f "$EPISODE_PATH" ]] || { echo "ERROR: audio generation failed." >&2; exit 1; }

FILE_SIZE=$(stat -f%z "$EPISODE_PATH")
DURATION_SECS=$(afinfo "$EPISODE_PATH" | awk '/estimated duration/ {print int($3)}')
DURATION_MMSS=$(printf "%d:%02d" $((DURATION_SECS/60)) $((DURATION_SECS%60)))

EPISODE_URL="https://${GITHUB_USER}.github.io/${REPO_NAME}/${EPISODE_FILE}"

python3 - <<PYEOF
import re
from pathlib import Path

feed = Path("$FEED_FILE")
content = feed.read_text() if feed.exists() else """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.apple.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Jira Briefing</title>
    <link>https://${GITHUB_USER}.github.io/${REPO_NAME}/</link>
    <description>Daily Jira ticket briefing for Paul Pickens.</description>
    <language>en-us</language>
    <lastBuildDate></lastBuildDate>
  </channel>
</rss>
"""

new_item = '''    <item>
      <title>$EPISODE_TITLE</title>
      <description>Daily Jira ticket briefing for Paul Pickens.</description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="$EPISODE_URL" length="$FILE_SIZE" type="audio/mp4"/>
      <guid isPermaLink="false">jira-podcast-$TODAY</guid>
      <itunes:duration>$DURATION_MMSS</itunes:duration>
    </item>
'''

if re.search(r'<language>[^<]+</language>\s*\n', content):
    content = re.sub(r'(<language>[^<]+</language>\s*\n)', r'\1' + new_item, content, count=1)
else:
    content = content.replace('</channel>', new_item + '</channel>')

content = re.sub(r'<lastBuildDate>[^<]*</lastBuildDate>', '<lastBuildDate>$PUB_DATE</lastBuildDate>', content)

feed.write_text(content)
PYEOF

find "$EPISODES_DIR" -name "episode-*.m4a" -type f | sort -r | tail -n +31 | xargs -I {} rm -f {}

git add -A
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "Episode $TODAY"
  git push origin main
  echo "Published: $EPISODE_URL"
fi
