#!/bin/zsh
# Verifies that the app installed on a simulator is byte-for-byte the build in DerivedData,
# and optionally that its binaries contain (or do not contain) a marker string.
#
# A build log saying BUILD SUCCEEDED does not mean the change reached the binary: a changed
# default-argument value in the DiscogsKit package rebuilds the package but not the modules that
# call it, because the default is materialised at the call site. Check the installed binary.
#
# Usage:
#   Scripts/verify-installed.sh <udid> [--expect <string>] [--forbid <string>]
set -eu

UDID="${1:?usage: verify-installed.sh <udid> [--expect s] [--forbid s]}"
shift
BUNDLE_ID="com.mlkshkvch.recogs"
BUILT="${DERIVED_APP:-$HOME/Library/Developer/Xcode/DerivedData/Recogs-fkbfybkrgqgkvlaixvsuakofqrhy/Build/Products/Debug-iphonesimulator/Recogs.app}"

EXPECT=""
FORBID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --expect) EXPECT="$2"; shift 2 ;;
    --forbid) FORBID="$2"; shift 2 ;;
    *) print -u2 "unknown argument: $1"; exit 2 ;;
  esac
done

INSTALLED="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" app)"

fail() { print -u2 "FAIL: $1"; exit 1; }

for binary in "Recogs" "Frameworks/RecogsKit.framework/RecogsKit"; do
  [[ -f "$BUILT/$binary" ]] || fail "no built binary at $BUILT/$binary — build first"
  [[ -f "$INSTALLED/$binary" ]] || fail "no installed binary at $INSTALLED/$binary"
  if ! cmp -s "$BUILT/$binary" "$INSTALLED/$binary"; then
    fail "$binary on the simulator differs from the build — reinstall before testing"
  fi
done

if [[ -n "$EXPECT" ]]; then
  strings "$INSTALLED/Frameworks/RecogsKit.framework/RecogsKit" "$INSTALLED/Recogs" \
    | grep -qF -- "$EXPECT" || fail "installed binary does not contain \"$EXPECT\""
fi

if [[ -n "$FORBID" ]]; then
  if strings "$INSTALLED/Frameworks/RecogsKit.framework/RecogsKit" "$INSTALLED/Recogs" \
    | grep -qF -- "$FORBID"; then
    fail "installed binary still contains \"$FORBID\""
  fi
fi

print "OK: the simulator is running this build."
