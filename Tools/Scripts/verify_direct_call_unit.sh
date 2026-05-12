#!/usr/bin/env bash

# Runs the native direct-call focused UnitTests subset used during the
# production key-wrapping and diagnostic media work.
#
# This script is intentionally product-neutral: it does not launch the app,
# does not require test credentials, and does not print secrets. Override the
# simulator destination with DIRECT_CALL_TEST_DESTINATION when needed.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly DEFAULT_SIMULATOR_UDID="${SIMULATOR_UDID_A:-183D9DAD-0CB6-49DE-ABFD-53BFA7B724CB}"
readonly PROJECT="${DIRECT_CALL_TEST_PROJECT:-SalemX.xcodeproj}"
readonly SCHEME="${DIRECT_CALL_TEST_SCHEME:-UnitTests}"
readonly DESTINATION="${DIRECT_CALL_TEST_DESTINATION:-platform=iOS Simulator,id=$DEFAULT_SIMULATOR_UDID}"

usage() {
    cat <<USAGE
Usage:
  $SCRIPT_NAME

Runs focused native direct-call unit tests with xcodebuild.

Optional environment:
  DIRECT_CALL_TEST_PROJECT       Defaults to SalemX.xcodeproj.
  DIRECT_CALL_TEST_SCHEME        Defaults to UnitTests.
  DIRECT_CALL_TEST_DESTINATION   Defaults to platform=iOS Simulator,id=\$SIMULATOR_UDID_A,
                                  or the local known direct-call simulator UDID.
  DIRECT_CALL_ONLY_TESTING       Optional space-separated override for -only-testing values.

Examples:
  $SCRIPT_NAME
  DIRECT_CALL_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro' $SCRIPT_NAME
  DIRECT_CALL_ONLY_TESTING='UnitTests/DirectCallEngineTests UnitTests/DirectCallMediaEngineTests' $SCRIPT_NAME
USAGE
}

log() {
    printf '[verify-direct-call-unit] %s\n' "$*"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

cd "$REPO_ROOT"

only_testing=(
    UnitTests/DirectCallEngineTests
    UnitTests/DirectCallEngineSignalTransportTests
    UnitTests/DirectCallMediaEngineTests
    UnitTests/DirectCallProductionKeyWrappingTests
    UnitTests/NativeDirectCallCompositionFactoryTests
    UnitTests/JoinedRoomNativeDirectCallCompositionFactoryTests
    UnitTests/NativeDirectCallRoomControllerTests
    UnitTests/DirectCallMatrixSDKSignalAdapterTests
    UnitTests/RoomFlowCoordinatorTests
    UnitTests/ChatsTabFlowCoordinatorTests
)

if [[ -n "${DIRECT_CALL_ONLY_TESTING:-}" ]]; then
    # shellcheck disable=SC2206 # Intentional word splitting for space-separated test identifiers.
    only_testing=($DIRECT_CALL_ONLY_TESTING)
fi

log "project: $PROJECT"
log "scheme: $SCHEME"
log "destination: $DESTINATION"
log "test count: ${#only_testing[@]}"

args=(
    test
    -project "$PROJECT"
    -scheme "$SCHEME"
    -destination "$DESTINATION"
)

for test_identifier in "${only_testing[@]}"; do
    args+=( -only-testing:"$test_identifier" )
done

xcodebuild "${args[@]}"
