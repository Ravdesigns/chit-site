#!/bin/bash
# Chit installer.  curl -fsSL https://chit.zopcloud.zop.dev/get.sh | bash
# curl does not quarantine what it fetches, so this skips the Gatekeeper warning.
set -euo pipefail
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Count this install. The one-liner never loads the page, so this is the only way
# it shows up in the tally. Capped at two seconds and allowed to fail: it cannot
# hang the install and cannot break it.
curl -fsS -m 2 -X POST "https://getchit.vercel.app/api/hit?e=install" </dev/null >/dev/null 2>&1 || true

echo "▸ downloading Chit…"
curl -fsSL "https://chit.zopcloud.zop.dev/Chit.zip" -o "$TMP/Chit.zip"
echo "  sha256 $(shasum -a 256 "$TMP/Chit.zip" | cut -d' ' -f1)"
unzip -q "$TMP/Chit.zip" -d "$TMP"
[ -d "$TMP/Chit/Chit.app" ] || { echo "✗ that archive didn't contain Chit.app"; exit 1; }

# /Applications is not writable for every account, so fall back rather than fail
DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

# Stage the copy first, then swap it in: if anything goes wrong you still have the
# app you started with, and ditto (not cp) is what preserves a bundle intact.
STAGE="$DEST/.Chit.app.incoming"
rm -rf "$STAGE"
ditto "$TMP/Chit/Chit.app" "$STAGE"
pkill -x Chit 2>/dev/null || true
rm -rf "$DEST/Chit.app"
mv "$STAGE" "$DEST/Chit.app"

# LaunchServices can still be holding the bundle we just replaced, which makes an
# immediate `open` fail with -600. Give it a beat, re-register, then fall back to
# launching the binary directly so an upgrade never ends with nothing running.
sleep 1
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if ! open "$DEST/Chit.app" 2>/dev/null; then
  [ -x "$LSREG" ] && "$LSREG" -f "$DEST/Chit.app" >/dev/null 2>&1 || true
  sleep 1
  open "$DEST/Chit.app" 2>/dev/null || "$DEST/Chit.app/Contents/MacOS/Chit" >/dev/null 2>&1 &
fi
# The site and the launch copy both advertise `chit --today` as a headline
# feature, but nothing ever put `chit` on anyone's PATH: a reader who followed
# that line got "command not found". Link it into the first writable directory
# already on PATH. Never sudo — /usr/local/bin needs it, and a curl | bash that
# asks for a password is a good way to teach people a bad habit. Never fatal:
# the app itself is installed and working by this point.
BIN=""
for d in "$HOME/.local/bin" "$HOME/bin" /opt/homebrew/bin; do
  case ":$PATH:" in *":$d:"*) [ -d "$d" ] && [ -w "$d" ] && BIN="$d" && break ;; esac
done
if [ -n "$BIN" ]; then
  ln -sf "$DEST/Chit.app/Contents/MacOS/Chit" "$BIN/chit" 2>/dev/null \
    && echo "  cli: chit -> $BIN/chit" || BIN=""
fi
[ -z "$BIN" ] && echo "  cli: add it yourself with
       ln -s \"$DEST/Chit.app/Contents/MacOS/Chit\" /usr/local/bin/chit"

echo "Done 🧾  Installed to $DEST. Look top right, or press ⌥⌃⌘C."
