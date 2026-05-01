#!/bin/bash
# generate-episode.sh — local TTS, pushes to GitHub Pages.
# Mondays use ElevenLabs (MP3); Tue–Fri use macOS `say` (M4A/AAC).
set -euo pipefail

REPO_DIR="$HOME/jira-podcast"
SCRIPT_FILE="$REPO_DIR/podcast-script.txt"
EPISODES_DIR="$REPO_DIR/episodes"
FEED_FILE="$REPO_DIR/feed.xml"
ENV_FILE="$REPO_DIR/.env"
SAY_VOICE="Evan (Enhanced)"
ELEVENLABS_VOICE_ID="bIHbv24MWmeRgasZH58o"
ELEVENLABS_MODEL="eleven_multilingual_v2"
GITHUB_USER="paulpickens"
REPO_NAME="jira-podcast"

cd "$REPO_DIR"

# Load .env if present (KEY=value lines, e.g. ELEVENLABS_API_KEY=sk_xxx)
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

[[ -f "$SCRIPT_FILE" ]] || { echo "ERROR: $SCRIPT_FILE not found." >&2; exit 1; }
[[ -s "$SCRIPT_FILE" ]] || { echo "ERROR: $SCRIPT_FILE is empty." >&2; exit 1; }

mkdir -p "$EPISODES_DIR"

TODAY=$(date +"%Y-%m-%d")
DOW=$(date +%u)              # 1=Mon … 7=Sun
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")
EPISODE_TITLE="Jira Briefing — $(date +"%A, %B %-d, %Y")"

# Defaults are set inside each generator function; these get overwritten there.
EPISODE_EXT="m4a"
MIME_TYPE="audio/mp4"
EPISODE_FILE="episodes/episode-$TODAY.$EPISODE_EXT"
EPISODE_PATH="$REPO_DIR/$EPISODE_FILE"

generate_with_say() {
  echo "Generating audio with macOS say (voice: $SAY_VOICE)"
  EPISODE_EXT="m4a"
  MIME_TYPE="audio/mp4"
  EPISODE_FILE="episodes/episode-$TODAY.$EPISODE_EXT"
  EPISODE_PATH="$REPO_DIR/$EPISODE_FILE"
  say -v "$SAY_VOICE" -o "$EPISODE_PATH" --data-format=aac -f "$SCRIPT_FILE"
}

generate_with_elevenlabs() {
  echo "Generating audio with ElevenLabs (voice: $ELEVENLABS_VOICE_ID, model: $ELEVENLABS_MODEL)"
  if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo "ERROR: ELEVENLABS_API_KEY not set." >&2
    return 1
  fi
  EPISODE_EXT="mp3"
  MIME_TYPE="audio/mpeg"
  EPISODE_FILE="episodes/episode-$TODAY.$EPISODE_EXT"
  EPISODE_PATH="$REPO_DIR/$EPISODE_FILE"

  local payload
  payload=$(python3 -c '
import json, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text()
print(json.dumps({"text": text, "model_id": sys.argv[2]}))
' "$SCRIPT_FILE" "$ELEVENLABS_MODEL")

  local http_status
  http_status=$(curl -sS -w "%{http_code}" -o "$EPISODE_PATH" \
    -X POST "https://api.elevenlabs.io/v1/text-to-speech/$ELEVENLABS_VOICE_ID" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -H "Accept: audio/mpeg" \
    --data-binary "$payload") || true

  if [[ "$http_status" != "200" ]] || [[ ! -s "$EPISODE_PATH" ]]; then
    echo "ERROR: ElevenLabs request failed (HTTP $http_status)." >&2
    [[ -s "$EPISODE_PATH" ]] && head -c 500 "$EPISODE_PATH" >&2 && echo >&2
    rm -f "$EPISODE_PATH"
    return 1
  fi
}

if [[ "$DOW" == "1" ]]; then
  if ! generate_with_elevenlabs; then
    echo "Falling back to macOS say." >&2
    generate_with_say
  fi
else
  generate_with_say
fi

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
      <enclosure url="$EPISODE_URL" length="$FILE_SIZE" type="$MIME_TYPE"/>
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

# Prune old episodes (keep newest 30 across both formats)
find "$EPISODES_DIR" \( -name "episode-*.m4a" -o -name "episode-*.mp3" \) -type f | sort -r | tail -n +31 | xargs -I {} rm -f {}

# Stash any stray local changes (e.g. log files) so rebase can't fail
STASHED=0
if ! git diff --quiet || ! git diff --cached --quiet; then
  git stash push -u -m "auto-stash before episode push" && STASHED=1
fi

if ! git pull --rebase origin main; then
  echo "Pull failed; aborting." >&2
  [[ $STASHED -eq 1 ]] && git stash pop
  exit 1
fi

[[ $STASHED -eq 1 ]] && git stash pop || true

git add -A
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "Episode $TODAY"
  git push origin main
  echo "Published: $EPISODE_URL"
fi
