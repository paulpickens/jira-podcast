#!/bin/bash
set -euo pipefail
cd ~/jira-podcast

ITEM_TMP=$(mktemp)
cat > "$ITEM_TMP" << 'RSSITEM'
    <item>
      <title>Ticket Briefing — 2026-04-16</title>
      <description>Daily Jira ticket briefing for 2026-04-16. 379 words, 2:24 listen.</description>
      <enclosure url="https://paulpickens.github.io/jira-podcast/episodes/episode-2026-04-16.mp3" length="2316791" type="audio/mpeg"/>
      <guid isPermaLink="false">jira-podcast-2026-04-16</guid>
      <pubDate>Thu, 16 Apr 2026 05:00:00 GMT</pubDate>
      <itunes:duration>2:24</itunes:duration>
      <itunes:episodeType>full</itunes:episodeType>
    </item>
RSSITEM

TEMP_FEED=$(mktemp)
sed -e "/<!-- EPISODES_START -->/r $ITEM_TMP" feed.xml > "$TEMP_FEED"
mv "$TEMP_FEED" feed.xml
rm -f "$ITEM_TMP"

git add -A
git commit -m "Episode: 2026-04-16"
git push origin main
echo "Done. Episode pushed."
