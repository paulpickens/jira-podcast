#!/bin/bash
# generate-episode.sh — Generates podcast audio from a script file
# Can be called by launchd or manually.
#
# Usage:
#   ./generate-episode.sh [script-file] [date]
#
# If no arguments, uses today's date and looks for the script at
# ~/jira-podcast/podcast-script.txt
#
# Requires: say (macOS), ffmpeg (brew install ffmpeg), git with push access

set -euo pipefail

REPO_DIR="$HOME/jira-podcast"
EP_DIR="$REPO_DIR/episodes"
LOG_FILE="$REPO_DIR/generate.log"

# Redirect all output to log file AND stdout
exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== $(date) ==="

# Default script file and date
SCRIPT_FILE="${1:-$REPO_DIR/podcast-script.txt}"
EP_DATE="${2:-$(date +%Y-%m-%d)}"
EP_FILENAME="episode-${EP_DATE}.mp3"
EP_PATH="$EP_DIR/$EP_FILENAME"
FEED_PATH="$REPO_DIR/feed.xml"
AIFF_TMP="$EP_DIR/.tmp-episode.aiff"

# Voice config — change this to switch voices
VOICE="Evan (Enhanced)"

# Validate
if ! command -v ffmpeg &>/dev/null; then
  echo "ERROR: ffmpeg not found. Run: brew install ffmpeg"
  exit 1
fi

if [ ! -f "$SCRIPT_FILE" ]; then
  echo "ERROR: Script file not found: $SCRIPT_FILE"
  echo "The Cowork scheduled task may not have run yet."
  exit 1
fi

# Skip if today's episode already exists
if [ -f "$EP_PATH" ]; then
  echo "Episode already exists: $EP_PATH — skipping."
  exit 0
fi

echo "Generating audio with macOS say (voice: $VOICE)..."

# Generate AIFF with say, then convert to MP3 with ffmpeg
say -v "$VOICE" -o "$AIFF_TMP" -f "$SCRIPT_FILE"

if [ ! -s "$AIFF_TMP" ]; then
  echo "ERROR: say produced empty file"
  exit 1
fi

# Convert to MP3 (128kbps, mono, podcast-friendly)
ffmpeg -y -i "$AIFF_TMP" -ac 1 -ab 128k -ar 44100 "$EP_PATH" 2>/dev/null

rm -f "$AIFF_TMP"

if [ ! -s "$EP_PATH" ]; then
  echo "ERROR: ffmpeg conversion failed"
  exit 1
fi

FILE_SIZE=$(stat -f%z "$EP_PATH" 2>/dev/null || stat --format=%s "$EP_PATH" 2>/dev/null)
# Get actual duration from ffmpeg
DURATION_RAW=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$EP_PATH" 2>/dev/null | cut -d. -f1)
DURATION_SECS=${DURATION_RAW:-0}
DURATION_MIN=$(( DURATION_SECS / 60 ))
DURATION_SEC=$(( DURATION_SECS % 60 ))
DURATION_STR=$(printf "%d:%02d" $DURATION_MIN $DURATION_SEC)

echo "Audio saved: $EP_PATH ($FILE_SIZE bytes, ${DURATION_STR})"

# Build RSS item
PUB_DATE=$(date -u "+%a, %d %b %Y 05:00:00 GMT")
EP_URL="https://paulpickens.github.io/jira-podcast/episodes/${EP_FILENAME}"
GUID="jira-podcast-${EP_DATE}"
WORD_COUNT=$(wc -w < "$SCRIPT_FILE" | tr -d ' ')

NEW_ITEM="    <item>
      <title>Ticket Briefing — ${EP_DATE}</title>
      <description>Daily Jira ticket briefing for ${EP_DATE}. ${WORD_COUNT} words, ${DURATION_STR} listen.</description>
      <enclosure url=\"${EP_URL}\" length=\"${FILE_SIZE}\" type=\"audio/mpeg\"/>
      <guid isPermaLink=\"false\">${GUID}</guid>
      <pubDate>${PUB_DATE}</pubDate>
      <itunes:duration>${DURATION_STR}</itunes:duration>
      <itunes:episodeType>full</itunes:episodeType>
    </item>"

echo "Updating RSS feed..."

# Write the new item to a temp file (avoids awk multiline issues)
ITEM_TMP=$(mktemp)
cat > "$ITEM_TMP" <<RSSITEM
    <item>
      <title>Ticket Briefing — ${EP_DATE}</title>
      <description>Daily Jira ticket briefing for ${EP_DATE}. ${WORD_COUNT} words, ${DURATION_STR} listen.</description>
      <enclosure url="${EP_URL}" length="${FILE_SIZE}" type="audio/mpeg"/>
      <guid isPermaLink="false">${GUID}</guid>
      <pubDate>${PUB_DATE}</pubDate>
      <itunes:duration>${DURATION_STR}</itunes:duration>
      <itunes:episodeType>full</itunes:episodeType>
    </item>
RSSITEM

# Replace everything between EPISODES_START and EPISODES_END with just the new item.
# Keeps the feed to a single latest episode.
python3 - "$FEED_PATH" "$ITEM_TMP" <<'PYEOF'
import re, sys
feed_path, item_path = sys.argv[1], sys.argv[2]
with open(feed_path) as f: content = f.read()
with open(item_path) as f: new_item = f.read().rstrip("\n")
pattern = r'(<!-- EPISODES_START -->).*?(\s*<!-- EPISODES_END -->)'
replacement = r'\1\n' + new_item + r'\n    <!-- EPISODES_END -->'
content = re.sub(pattern, replacement, content, count=1, flags=re.DOTALL)
with open(feed_path, "w") as f: f.write(content)
PYEOF
rm -f "$ITEM_TMP"

# Prune old episodes (keep only the latest one)
EPISODE_COUNT=$(ls -1 "$EP_DIR"/*.mp3 2>/dev/null | wc -l | tr -d ' ')
if [ "$EPISODE_COUNT" -gt 1 ]; then
  echo "Pruning old episodes (keeping latest)..."
  ls -1t "$EP_DIR"/*.mp3 | tail -n +2 | xargs rm -f
fi

echo "Pushing to GitHub..."
cd "$REPO_DIR"
git add -A
git commit -m "Episode: ${EP_DATE}" --allow-empty
git push origin main

echo "Done. Episode live at: ${EP_URL}"
echo "Feed URL: https://paulpickens.github.io/jira-podcast/feed.xml"
