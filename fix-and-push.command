#!/bin/bash
cd "$HOME/Documents/jira-podcast"
rm -f .git/index.lock .git/HEAD.lock .git/objects/maintenance.lock 2>/dev/null
git add .nojekyll index.html fix-pages.command push-episode.command run-episode.command
git commit -m "Add GitHub Pages config and helper scripts"
git push origin main
echo ""
echo "Done. Feed: https://paulpickens.github.io/jira-podcast/feed.xml"
echo ""
echo "If Pages isn't live yet, enable it at:"
echo "github.com/paulpickens/jira-podcast > Settings > Pages > Source: main branch"
echo ""
echo "Press any key to close..."
read -n 1
