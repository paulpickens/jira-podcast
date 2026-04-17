#!/bin/bash
cd "$HOME/jira-podcast"
git add .nojekyll index.html
git commit -m "Add .nojekyll and index.html for GitHub Pages"
git push origin main
echo ""
echo "Done. GitHub Pages should now serve the feed correctly."
echo "Feed URL: https://paulpickens.github.io/jira-podcast/feed.xml"
echo ""
echo "IMPORTANT: Make sure GitHub Pages is enabled in the repo settings:"
echo "  github.com/paulpickens/jira-podcast -> Settings -> Pages -> Source: main branch"
echo ""
echo "Press any key to close..."
read -n 1
