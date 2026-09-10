#!/bin/bash
#
# Generates projects across component combinations and builds each one with
# xcodebuild.
#
# A scaffolding tool whose output does not compile is worse than no tool, and a
# template that only works when every component is switched on is the easiest
# way to ship exactly that. Unit tests cover the file layout; only a real build
# proves the result opens in Xcode.
#
# Usage: ./Scripts/verify-generated.sh [simulator-name]

set -uo pipefail

cd "$(dirname "$0")/.."

SIMULATOR="${1:-iPhone 17}"
WORK_DIR="$(mktemp -d)"
KEEL="./.build/debug/keel"
FAILURES=0

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if [ ! -x "$KEEL" ]; then
    echo "Building keel…"
    swift build || exit 1
fi

run() {
    local name="$1"; shift
    local label="${*:-all components}"

    if ! "$KEEL" new "$name" --yes --no-git -o "$WORK_DIR" "$@" >/dev/null 2>&1; then
        printf "  \033[31mFAIL\033[0m  %-14s generation failed\n" "$name"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local errors
    errors=$(cd "$WORK_DIR/$name" && xcodebuild build \
        -scheme "$name" \
        -destination "platform=iOS Simulator,name=$SIMULATOR" \
        -quiet 2>&1 | grep -E "error:" | head -3)

    if [ -z "$errors" ]; then
        printf "  \033[32mPASS\033[0m  %-14s %s\n" "$name" "$label"
    else
        printf "  \033[31mFAIL\033[0m  %-14s %s\n" "$name" "$label"
        echo "$errors" | sed 's/^/          /'
        FAILURES=$((FAILURES + 1))
    fi

    rm -rf "${WORK_DIR:?}/$name"
}

echo "Building generated projects against $SIMULATOR"
echo

run Full
run Bare --minimal
run NoNet --no-networking
run Untested --no-testing
run NoInject --no-dependency-injection

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "All combinations built."
else
    echo "$FAILURES combination(s) failed."
    exit 1
fi
