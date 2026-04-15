#!/bin/bash
# generate-episode.sh — Called by the Cowork scheduled task
# Expects two arguments:
#   $1 = path to the script text file (e.g., /tmp/podcast-script.txt)
#   $2 = episode date string (e.g., "2026-04-15")
#
# Requires: ELEVENLABS_API_KEY env variable, git configured with push access

set -euo pipefail

SCRIPT_FILE="$1"
EP_DATE="$2"
REPO_DIR="$HOME/Documents/jira-podcast"
EP_DIR="$REPO_DIR/episodes"
EP_FILENAME="episode-${EP_DATE}.mp3"
EP_PATH="$EP_DIR/$EP_FILENAME"
FEED_PATH="$REPO_DIR/feed.xml"

# Validate
if [ -z "${ELEVENLABS_API_KEY:-}" ]; then
  echo "ERROR: ELEVENLABS_API_KEY not set. Run: echo 'export ELEVENLABS_API_KEY=\"your-key\"' >> ~/.zshrc && source ~/.zshrc"
  exit 1
fi

if [ ! -f "$SCRIPT_FILE" ]; then
  echo "ERROR: Script file not found: $SCRIPT_FILE"
  exit 1
fi

SCRIPT_TEXT=$(cat "$SCRIPT_FILE")

echo "Generating audio via ElevenLabs TTS..."

# ElevenLabs voice ID for "Chris" — clear, natural male narrator voice
# Other good options: "Daniel" (21m00Tcm4TlvDq8ikWAM), "Josh" (TxGEqnHWrfWFTfGW9XjX)
VOICE_ID="iP95p4xoKVk53GoZ742B"

curl -s --fail \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg text "$SCRIPT_TEXT" '{
    "text": $text,
    "model_id": "eleven_multilingual_v2",
    "voice_settings": {
      "stability": 0.5,
      "similarity_boost": 0.75,
      "style": 0.4,
      "use_speaker_boost": true
    }
  }')" \
  "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}" \
  -o "$EP_PATH"

if [ ! -s "$EP_PATH" ]; then
  echo "ERROR: TTS API returned empty file"
  exit 1
fi

FILE_SIZE=$(stat -f%z "$EP_PATH" 2>/dev/null || stat --format=%s "$EP_PATH" 2>/dev/null)
# Estimate duration from file size (MP3 ~128kbps = ~16KB/sec)
DURATION_SECS=$(( FILE_SIZE / 16000 ))
DURATION_MIN=$(( DURATION_SECS / 60 ))
DURATION_SEC=$(( DURATION_SECS % 60 ))
DURATION_STR=$(printf "%d:%02d" $DURATION_MIN $DURATION_SEC)

echo "Audio saved: $EP_PATH ($FILE_SIZE bytes, ~${DURATION_STR})"

# Build RSS item
PUB_DATE=$(date -u "+%a, %d %b %Y 05:00:00 GMT")
EP_URL="https://paulpickens.github.io/jira-podcast/episodes/${EP_FILENAME}"
GUID="jira-podcast-${EP_DATE}"

# Read word count for description
WORD_COUNT=$(wc -w < "$SCRIPT_FILE" | tr -d ' ')

NEW_ITEM="    <item>
      <title>Ticket Briefing — ${EP_DATE}</title>
      <description>Daily Jira ticket briefing for ${EP_DATE}. ${WORD_COUNT} words, ~${DURATION_STR} listen.</description>
      <enclosure url=\"${EP_URL}\" length=\"${FILE_SIZE}\" type=\"audio/mpeg\"/>
      <guid isPermaLink=\"false\">${GUID}</guid>
      <pubDate>${PUB_DATE}</pubDate>
      <itunes:duration>${DURATION_STR}</itunes:duration>
      <itunes:episodeType>full</itunes:episodeType>
    </item>"

echo "Updating RSS feed..."

# Insert new episode after EPISODES_START marker
# Use a temp file for compatibility
TEMP_FEED=$(mktemp)
awk -v item="$NEW_ITEM" '
  /<!-- EPISODES_START -->/ {
    print
    print item
    next
  }
  { print }
' "$FEED_PATH" > "$TEMP_FEED"
mv "$TEMP_FEED" "$FEED_PATH"

# Prune old episodes (keep last 30)
EPISODE_COUNT=$(ls -1 "$EP_DIR"/*.mp3 2>/dev/null | wc -l | tr -d ' ')
if [ "$EPISODE_COUNT" -gt 30 ]; then
  echo "Pruning old episodes (keeping 30)..."
  ls -1t "$EP_DIR"/*.mp3 | tail -n +31 | xargs rm -f
fi

echo "Pushing to GitHub..."
cd "$REPO_DIR"
git add -A
git commit -m "Episode: ${EP_DATE}" --allow-empty
git push origin main

echo "Done. Episode live at: ${EP_URL}"
echo "Feed URL: https://paulpickens.github.io/jira-podcast/feed.xml"
