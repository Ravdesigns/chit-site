#!/bin/bash
# Run this the moment the ZopCloud rebuild reports Active. It checks the things
# that actually break a launch, not just that the page loads.
H=https://chit.zopcloud.zop.dev
V=https://getchit.vercel.app
pass=0; fail=0
ok(){ printf "  \033[32m✓\033[0m %s\n" "$1"; pass=$((pass+1)); }
no(){ printf "  \033[31m✗\033[0m %s\n" "$1"; fail=$((fail+1)); }

echo "▸ pages and assets"
for p in / /assets/site.css /assets/site.js /get.sh /version.txt /share.png /robots.txt /Chit.zip; do
  c=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$H$p")
  [ "$c" = "200" ] && ok "$p" || no "$p returned $c"
done
c=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$H/healthz"); [ "$c" = "200" ] && ok "/healthz" || no "/healthz returned $c"
c=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$H/definitely-not-here"); [ "$c" = "404" ] && ok "404 for a bad path" || no "bad path returned $c"

echo "▸ the new build actually shipped"
PAGE=$(curl -s -m 25 "$H/")
grep -q 'id="pricing"' <<<"$PAGE" && ok "pricing section present" || no "NO pricing section: still the old commit"
grep -q 'id="m-pro"'   <<<"$PAGE" && ok "Pro pane present"        || no "no Pro pane"
grep -q 'class="badge">PRO<' <<<"$PAGE" && ok "Pro badge on the pricing card" || no "no Pro badge"
grep -q 'You did plenty today' <<<"$PAGE" && ok "hero copy present" || no "hero copy missing"
[ "$(curl -s -m 20 "$H/version.txt" | tr -d '[:space:]')" = "1.0.0" ] && ok "version.txt 1.0.0" || no "version.txt is $(curl -s -m 20 "$H/version.txt" | tr -d '[:space:]')"

echo "▸ the trust artefact"
SHOWN=$(grep -o 'sha256 [a-f0-9]\{64\}' <<<"$PAGE" | head -1 | cut -d' ' -f2)
REAL=$(curl -s -m 60 "$H/Chit.zip" | shasum -a 256 | cut -d' ' -f1)
[ -n "$SHOWN" ] && [ "$SHOWN" = "$REAL" ] && ok "page sha matches its own zip" || no "sha MISMATCH page=${SHOWN:0:12} zip=${REAL:0:12}"
grep -q "$H/Chit.zip" <<<"$(curl -s -m 20 "$H/get.sh")" && ok "get.sh pulls from this host" || no "get.sh pulls from elsewhere"
grep -q "$H/get.sh" <<<"$PAGE" && ok "curl line names this host" || no "curl line names another host"

echo "▸ the app inside the zip"
T=$(mktemp -d); curl -fsSL -m 60 "$H/Chit.zip" -o "$T/n.zip" 2>/dev/null
if unzip -q "$T/n.zip" -d "$T" 2>/dev/null; then
  APP="$T/Chit/Chit.app"
  VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)
  [ "$VER" = "1.0.0" ] && ok "bundle is v1.0.0" || no "bundle is v$VER"
  A=$(lipo -archs "$APP/Contents/MacOS/Chit" 2>/dev/null)
  [[ "$A" == *x86_64* && "$A" == *arm64* ]] && ok "universal ($A)" || no "not universal: $A"
  # Probe CHIT1 (the licence key prefix), not "chit.licence": Swift does not emit
# that UserDefaults key as one contiguous literal, so the obvious check fails on
# a binary that is licensed perfectly well.
strings "$APP/Contents/MacOS/Chit" 2>/dev/null | grep -q "CHIT1" && ok "licensing is in the binary" || no "NO licensing in the binary: old build"
# Behaviour beats strings: a past day must be refused without a key.
"$APP/Contents/MacOS/Chit" --date=2020-01-01 >/dev/null 2>&1; [ $? -eq 2 ] && ok "past days are gated" || no "PAST DAYS ARE FREE: Pro is not gated"
"$APP/Contents/MacOS/Chit" --today >/dev/null 2>&1 && ok "today is free" || no "today is not free"
else no "zip did not unpack"; fi
rm -rf "$T"

echo "▸ generated assets describe the zip beside them"
# share.png prints the zip's size, read at render time. Rendered before a repack
# it advertises the old number on every social preview -- it once said "A 611 KB
# Mac app" for a 777 KB download. package.sh now renders after zipping; this
# catches anyone who repacks without it.
D="$(dirname "$0")"
for a in share.png assets/receipt.png; do
  if [ ! -e "$D/$a" ]; then no "$a is missing"
  elif [ "$D/$a" -ot "$D/Chit.zip" ]; then
    no "$a is OLDER than Chit.zip -- re-run package.sh, it renders them after zipping"
  else ok "$a is at least as new as the zip"; fi
done

echo "▸ the live host is THIS build, not an older one"
# Every other check in this file tests whether the live host agrees with itself,
# which a stale deploy does perfectly. This section is the only one that can
# catch "you forgot to redeploy", and it reported Ready to submit on a site
# serving a four-commits-old build until it was added.
LOCALZIP=$(shasum -a 256 "$(dirname "$0")/Chit.zip" | cut -d" " -f1)
LIVEZIP=$(curl -s -m 90 "$H/Chit.zip" | shasum -a 256 | cut -d" " -f1)
[ "$LOCALZIP" = "$LIVEZIP" ] && ok "served zip is the one in this repo" \
  || no "STALE DEPLOY: live zip ${LIVEZIP:0:12} but repo has ${LOCALZIP:0:12}"

LOCALV=$(tr -d "[:space:]" < "$(dirname "$0")/version.txt")
LIVEV=$(curl -s -m 20 "$H/version.txt" | tr -d "[:space:]")
[ "$LOCALV" = "$LIVEV" ] && ok "served version.txt matches the repo" \
  || no "STALE DEPLOY: live version $LIVEV, repo $LOCALV"

# get.sh is a deployed file too. The staleness checks covered the zip, the page
# and version.txt but not the installer, so a get.sh-only change could ship to
# git, fail to reach the host, and pass every check.
LOCALGET=$(shasum -a256 "$(dirname "$0")/get.sh" | cut -d" " -f1)
LIVEGET=$(curl -s -m 30 "$H/get.sh" | shasum -a256 | cut -d" " -f1)
[ "$LOCALGET" = "$LIVEGET" ] && ok "served get.sh matches the repo" \
  || no "STALE DEPLOY: the live get.sh is not the one in this repo"

# Compare the page itself, ignoring the host rewrite the mirror does.
LOCALPAGE=$(sed "s|getchit.vercel.app|chit.zopcloud.zop.dev|g" "$(dirname "$0")/index.html" | shasum -a 256 | cut -d" " -f1)
LIVEPAGE=$(sed "s|getchit.vercel.app|chit.zopcloud.zop.dev|g" <<<"$PAGE" | shasum -a 256 | cut -d" " -f1)
[ "$LOCALPAGE" = "$LIVEPAGE" ] && ok "served index.html matches the repo" \
  || no "STALE DEPLOY: the live page is not the page in this repo"

echo "▸ analytics reachable from this host"
# ZopCloud serves static files only, so /api/hit lives on the Vercel mirror and
# the page must call it absolutely or the counter silently records nothing.
grep -q "$V/api/hit" <<<"$PAGE" && ok "page beacon is absolute" || no "page beacon is relative"
grep -q "$V/api/hit" <<<"$(curl -s -m 20 "$H/get.sh")" && ok "get.sh install beacon is absolute" || no "get.sh beacon is relative"
# An absolute URL that 404s is worse than a relative one: it looks correct and
# records nothing. The first version of this file checked only the shape.
AC=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$V/api/hit")
[ "$AC" = "200" ] && ok "the counter actually answers ($V/api/hit)" || no "COUNTER IS DEAD: $V/api/hit returned $AC — every event is recorded nowhere"

echo
printf "  %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ] && echo "  Ready to submit." || echo "  Do not submit until these are green."
exit $fail
