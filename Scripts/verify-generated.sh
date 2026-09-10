#!/bin/bash
#
# Generates projects across component combinations and builds each one with
# xcodebuild.
#
# A scaffolding tool whose output does not compile is worse than no tool, and a
# module that only works when everything else is switched on is the easiest way
# to ship exactly that. Unit tests cover file layout; only a real build proves
# the result opens in Xcode.
#
# Usage: ./Scripts/verify-generated.sh [simulator-name]

set -uo pipefail

cd "$(dirname "$0")/.."

SIMULATOR="${1:-iPhone 17}"
WORK_DIR="$(mktemp -d)"
KEEL="./.build/debug/keel"
FAILURES=0

ALL_COMPONENTS=(
    networking dependency-injection persistence authentication
    keychain localization testing design-system example-feature
)

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if [ ! -x "$KEEL" ]; then
    echo "Building keel…"
    swift build || exit 1
fi

build() {
    local name="$1"; shift
    local label="$1"; shift

    if ! "$KEEL" new "$name" --yes --no-git -o "$WORK_DIR" "$@" >/dev/null 2>&1; then
        printf "  \033[31mFAIL\033[0m  %-22s generation failed\n" "$label"
        FAILURES=$((FAILURES + 1))
        return
    fi

    local errors
    errors=$(cd "$WORK_DIR/$name" && xcodebuild build \
        -scheme "$name" \
        -destination "platform=iOS Simulator,name=$SIMULATOR" \
        -quiet 2>&1 | grep -E "error:" | head -3)

    if [ -z "$errors" ]; then
        printf "  \033[32mPASS\033[0m  %s\n" "$label"
    else
        printf "  \033[31mFAIL\033[0m  %s\n" "$label"
        echo "$errors" | sed 's/^/          /'
        FAILURES=$((FAILURES + 1))
    fi

    rm -rf "${WORK_DIR:?}/$name"
}

# Builds a project with exactly one component enabled, by disabling all others.
# This is the case that catches a module quietly depending on a sibling.
only() {
    local keep="$1"
    local flags=()
    for component in "${ALL_COMPONENTS[@]}"; do
        [ "$component" = "$keep" ] || flags+=("--no-$component")
    done
    # Target names must be valid Swift identifiers, so strip the hyphens.
    build "Only${keep//-/}" "only $keep" "${flags[@]}"
}

echo "Building generated projects against $SIMULATOR"
echo

build Full "all components"
build Bare "no components" --minimal

for component in "${ALL_COMPONENTS[@]}"; do
    only "$component"
done

build NoNet "without networking" --no-networking
build NoInject "without dependency injection" --no-dependency-injection

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "All combinations built."
else
    echo "$FAILURES combination(s) failed."
    exit 1
fi
