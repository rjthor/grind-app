#!/bin/bash
# Publish a change to GRIND: bump the visible build stamp, commit, push.
# GitHub Pages serves straight from main/root with no build step, so a push
# is a deploy — usually live within 30-60s.
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${1:-}" ]; then
  echo "Usage: ./publish.sh \"commit message\""
  exit 1
fi

MSG="$1"
BUILD_ID="$(date +%Y-%m-%d_%H:%M)"

python3 - "$BUILD_ID" <<'PYEOF'
import re, sys
build_id = sys.argv[1]
with open("grind.html") as f:
    content = f.read()
new_content = re.sub(r"const BUILD_ID = '[^']*';", f"const BUILD_ID = '{build_id}';", content, count=1)
if new_content == content:
    sys.exit("BUILD_ID marker not found in grind.html — aborting so it doesn't publish silently unstamped.")
with open("grind.html", "w") as f:
    f.write(new_content)
PYEOF

git add grind.html index.html
git commit -m "$MSG"
git push origin main

echo ""
echo "Pushed. Build: $BUILD_ID"
echo "Live in ~30-60s at:"
echo "  https://rjthor.github.io/grind-app/grind.html"
echo "  https://rjthor.github.io/grind-app/  (redirects to the above)"
echo ""
echo "On your phone: force-quit and reopen the home-screen app (or hard-refresh in browser)"
echo "to bypass caching. Settings screen should show Build: $BUILD_ID once it's landed."
