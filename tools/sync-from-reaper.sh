#!/usr/bin/env bash
# Copy the release files out of the live REAPER folder into this repo.
#
#   Run it from Git Bash (Start menu -> Git Bash):
#       ./tools/sync-from-reaper.sh
#   or point it at a REAPER folder explicitly:
#       ./tools/sync-from-reaper.sh "/c/Users/tim/AppData/Roaming/REAPER"
#
# It copies ONE WAY, REAPER -> repo, and never the other way. It copies a
# named set of files rather than whole folders, because two things in those
# folders must never be published: the .ini layout and step caches, which are
# your own data, and a second copy of LICENSE, which belongs at the repo root.
#
# It does NOT commit or push. Read the summary, then commit yourself.

set -u

REAPER_DIR="${1:-}"
if [ -z "$REAPER_DIR" ]; then
  if [ -n "${APPDATA:-}" ] && [ -d "$APPDATA/REAPER" ]; then REAPER_DIR="$APPDATA/REAPER"
  elif [ -d "$HOME/mnt/REAPER" ];                       then REAPER_DIR="$HOME/mnt/REAPER"
  fi
fi
if [ -z "$REAPER_DIR" ] || [ ! -d "$REAPER_DIR/Scripts" ]; then
  echo "Cannot find your REAPER folder. Pass it as an argument:" >&2
  echo "  ./tools/sync-from-reaper.sh \"/c/Users/you/AppData/Roaming/REAPER\"" >&2
  exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
echo "from: $REAPER_DIR"
echo "to:   $REPO"
echo

copied=0
copy_one() {   # copy_one <src> <dest>
  local src="$1" dest="$2"
  [ -f "$src" ] || { echo "  MISSING in REAPER: ${src#$REAPER_DIR/}"; return; }
  if ! cmp -s "$src" "$dest" 2>/dev/null; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    echo "  updated  ${dest#$REPO/}"
    copied=$((copied + 1))
  fi
}

# ---- ChannelView: every module, the docs, the dev tools. No .ini, no LICENSE.
for f in "$REAPER_DIR/Scripts/TS_ChannelView"/*.lua; do
  copy_one "$f" "$REPO/TS_ChannelView/$(basename "$f")"
done
for f in README.md CHANGELOG.md; do
  copy_one "$REAPER_DIR/Scripts/TS_ChannelView/$f" "$REPO/TS_ChannelView/$f"
done
for f in "$REAPER_DIR/Scripts/TS_ChannelView/dev"/*; do
  [ -f "$f" ] && copy_one "$f" "$REPO/TS_ChannelView/dev/$(basename "$f")"
done

# ---- Track Analyser: scripts from Scripts/, the probe from Effects/.
for f in "$REAPER_DIR/Scripts/TS_TrackAnalyser"/*.lua; do
  copy_one "$f" "$REPO/TS_TrackAnalyser/$(basename "$f")"
done
for f in README.md CHANGELOG.md; do
  copy_one "$REAPER_DIR/Scripts/TS_TrackAnalyser/$f" "$REPO/TS_TrackAnalyser/$f"
done
copy_one "$REAPER_DIR/Effects/TS_TrackAnalyser/TS_TrackProbe.jsfx" \
         "$REPO/TS_TrackAnalyser/TS_TrackProbe.jsfx"

echo
if [ "$copied" -eq 0 ]; then
  echo "Nothing changed. The repo already matches your REAPER folder."
  exit 0
fi
echo "$copied file(s) updated."
echo

# ---- The check that matters.
#
# ReaPack pins a version to the commit where it first appeared. Change a file
# without bumping @version and users get NOTHING: no index change, no error,
# no warning. So: for each package whose files changed, was @version touched?
cd "$REPO" || exit 1
echo "--- version check ---"
stale=0
for pkg in TS_ChannelView/TS_ChannelView.lua TS_TrackAnalyser/TS_TrackAnalyser.lua; do
  dir="$(dirname "$pkg")"
  git diff --quiet -- "$dir" && continue          # nothing changed in this package
  now="$(grep -m1 -oE '@version[[:space:]]+[0-9][^[:space:]]*' "$pkg" | awk '{print $2}')"
  was="$(git show "HEAD:$pkg" 2>/dev/null | grep -m1 -oE '@version[[:space:]]+[0-9][^[:space:]]*' | awk '{print $2}')"
  if [ "$now" = "$was" ]; then
    echo "  !! $dir changed but @version is still $now"
    echo "     Publishing this will deliver nothing. Bump it before you commit."
    stale=1
  else
    echo "  ok $dir  $was -> $now"
  fi
done
[ "$stale" -eq 0 ] && echo "  (all changed packages have a new version)"

echo
echo "Next:  git add -A && git commit -m '...' && git pull && git push"
