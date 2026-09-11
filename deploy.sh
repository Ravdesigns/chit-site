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
/usr/bin/sed -i '' 's|chit\.zopcloud\.zop\.dev|chit.vercel.app|g' "$STAGE/index.html" "$STAGE/get.sh"
cp -R "$SRC/.vercel" "$STAGE/.vercel" 2>/dev/null || true

cd "$STAGE"
vercel --prod --yes >/dev/null 2>&1
cd "$SRC"; rm -rf "$STAGE"

B=https://chit.vercel.app
for u in / /get.sh /Chit.zip /version.txt /assets/site.css; do
  printf "  %s  %s\n" "$(curl -s -o /dev/null -w '%{http_code}' "$B$u")" "$u"
done
echo "✓ mirror live at $B"
