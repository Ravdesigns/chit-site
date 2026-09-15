#!/bin/bash
# Deploy the standalone Chit site to its Vercel mirror.
#
# Chit lives on its OWN hostname because Product Hunt will not accept a second
# launch that shares a domain with an existing listing, and both
# crew-deskmates.vercel.app (Crew) and notchling.zopcloud.zop.dev (Notchling)
# are already spent. ZopCloud at chit.zopcloud.zop.dev is the canonical host;
# this Vercel copy is the mirror and the home of /api/hit, which ZopCloud cannot
# serve because that host is static files only.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"

# The published size and sha must always describe the zip actually being shipped,
# so they are injected from the file rather than typed by hand.
ZIP="$SRC/Chit.zip"
if [ -f "$ZIP" ]; then
  SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
  KB=$(( $(stat -f%z "$ZIP") / 1024 ))
  python3 - "$SHA" "$KB" "$SRC/index.html" <<'PYEOF'
import re, sys, pathlib
sha, kb, path = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
s = path.read_text()
s = re.sub(r'(id="zipsha"[^>]*>)[^<]*', lambda m: m.group(1) + "sha256 " + sha, s)
s = re.sub(r'(id="dlsize"[^>]*>)[^<]*', lambda m: m.group(1) + kb + " KB", s)
s = re.sub(r'(id="herosize"[^>]*>)[^<]*', lambda m: m.group(1) + kb + " KB", s)
s = re.sub(r'(id="factsize"[^>]*>)[^<]*', lambda m: m.group(1) + kb + " KB", s)
# Prose too, not just the tagged spans. These two are outside any id and went
# stale once already, leaving the page quoting two different sizes at once.
s = re.sub(r'A \d+ KB Mac app', f'A {kb} KB Mac app', s)
s = re.sub(r'A \d+ KB zip', f'A {kb} KB zip', s)
path.write_text(s)
PYEOF
  unzip -p "$ZIP" Chit/Chit.app/Contents/Info.plist \
    | plutil -extract CFBundleShortVersionString raw -o - - 2>/dev/null > "$SRC/version.txt" || true
fi

# Each host must be internally consistent. ZopCloud is canonical, so the source
# files name it: but while ZopCloud lags a rebuild, the Vercel page would publish
# its own zip's sha next to a curl line fetching ZopCloud's older zip. A visitor
# who follows the trust instructions then sees a mismatch and reasonably concludes
# the download was tampered with. So the Vercel copy is deployed pointing at
# itself. Nothing is committed: the swap happens in a staging copy.
STAGE=$(mktemp -d)
/usr/bin/rsync -a --exclude .vercel --exclude .git "$SRC/" "$STAGE/"
/usr/bin/sed -i '' 's|chit\.zopcloud\.zop\.dev|getchit.vercel.app|g' "$STAGE/index.html" "$STAGE/get.sh"
cp -R "$SRC/.vercel" "$STAGE/.vercel" 2>/dev/null || true

cd "$STAGE"
vercel --prod --yes >/dev/null 2>&1
cd "$SRC"; rm -rf "$STAGE"

# Ask the API which deployment is newest rather than scraping the deploy output,
# which writes its URL to a stream that is not reliably captured.
URL=$(vercel ls chit 2>/dev/null | grep -oE 'https://chit-[a-z0-9]+-team-11199\.vercel\.app' | head -1)

# Re-point the stable alias at THIS deployment.
#
# `vercel alias set` pins a name to one specific deployment, and `vercel --prod`
# does not move it: it only updates the auto-generated aliases. Without this the
# name silently freezes on whatever build it was first pointed at, which is
# exactly what happened — getchit.vercel.app kept serving a pre-redesign page
# for hours while every other host had the current one.
if [ -n "$URL" ]; then
  vercel alias set "$URL" getchit.vercel.app >/dev/null 2>&1 \
    && echo "  alias getchit.vercel.app -> $URL" \
    || echo "  ! could not move the alias; getchit.vercel.app may be stale"
fi

# The mirror exists for /api/hit only. Everything else redirects to the
# canonical ZopCloud host, so there is exactly one page on the internet and no
# duplicate to land on by accident.
B=https://getchit.vercel.app
fail=0
c=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$B/api/hit")
printf "  %s  %s\n" "$c" "/api/hit (must be 200)"
[ "$c" = "200" ] || fail=1
for u in / /get.sh /assets/site.css; do
  c=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$B$u")
  printf "  %s  %s\n" "$c" "$u (must redirect)"
  case "$c" in 30*) ;; *) fail=1 ;; esac
done
L=$(curl -s -o /dev/null -m 20 -D - "$B/" | awk 'tolower($1)=="location:"{print $2}' | tr -d "\r")
printf "  ->   %s\n" "${L:-no Location header}"
case "$L" in https://chit.zopcloud.zop.dev*) ;; *) fail=1 ;; esac
# This used to print success unconditionally, and did exactly that while every
# path 404'd. A deploy script that cannot fail is not a check.
if [ "$fail" -eq 0 ]; then
  echo "✓ mirror live at $B"
else
  echo "✗ mirror NOT healthy at $B — do not rely on the counter"; exit 1
fi
