#!/usr/bin/env bash
# Build the web version and publish it to GitHub Pages (the gh-pages branch).
#   tools/publish_web.sh "test 14" https://<relay host>/ai/v1 gx10-current
# The AI address goes in through --dart-define only, never into the repo's source.
set -euo pipefail
label="$1"; endpoint="$2"; model="$3"
cd "$(dirname "$0")/../app"
. ~/dev-tools/env.sh
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --base-href /HawkerHaggle/ \
  --dart-define=BUILD_LABEL="$label web" --dart-define=AI_ENDPOINT="$endpoint" --dart-define=AI_MODEL="$model"
out=$(mktemp -d)
cp -r build/web/. "$out" && touch "$out/.nojekyll"
cd "$out" && git init -q -b gh-pages && git add -A
git -c user.name=Caspar5911 -c user.email=Caspar95galaxy@gmail.com commit -qm "Web version ($label)"
git push -q -f https://github.com/caspar5911/HawkerHaggle.git gh-pages
echo "published: https://caspar5911.github.io/HawkerHaggle/"
