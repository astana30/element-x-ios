#!/usr/bin/env bash

# Builds the Release app target used as a guardrail for native direct-call work.
# The build keeps production behavior unchanged and does not require any
# diagnostic, LiveKit, Matrix, or password environment variables.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly PROJECT="${DIRECT_CALL_RELEASE_PROJECT:-SalemX.xcodeproj}"
readonly SCHEME="${DIRECT_CALL_RELEASE_SCHEME:-SalemX}"
readonly CONFIGURATION="${DIRECT_CALL_RELEASE_CONFIGURATION:-Release}"
readonly DESTINATION="${DIRECT_CALL_RELEASE_DESTINATION:-generic/platform=iOS Simulator}"

usage() {
    cat <<USAGE
Usage:
  $SCRIPT_NAME

Runs the Release build guard for native direct-call changes.

Optional environment:
  DIRECT_CALL_RELEASE_PROJECT        Defaults to SalemX.xcodeproj.
  DIRECT_CALL_RELEASE_SCHEME         Defaults to SalemX.
  DIRECT_CALL_RELEASE_CONFIGURATION  Defaults to Release.
  DIRECT_CALL_RELEASE_DESTINATION    Defaults to generic/platform=iOS Simulator.
USAGE
}

log() {
    printf '[verify-direct-call-release] %s\n' "$*"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

cd "$REPO_ROOT"

log "project: $PROJECT"
log "scheme: $SCHEME"
log "configuration: $CONFIGURATION"
log "destination: $DESTINATION"

xcodebuild \
    -quiet \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    build
