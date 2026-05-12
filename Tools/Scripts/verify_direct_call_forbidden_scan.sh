#!/usr/bin/env bash

# Scans native direct-call code/test/tooling surfaces for accidental raw/debug
# receive paths and obvious secret-like literals. The scan intentionally allows
# safe DTO/env key names and redaction assertions; it is not a generic whole-app
# credentials scanner.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly RAW_PATH_PATTERN='debugInfo|originalJSON|originalJson|raw JSON|raw key'
readonly ENCRYPTED_PAYLOAD_PATTERN='encrypted_payload'
readonly JWT_PATTERN='eyJ[[:alnum:]_-]+\.[[:alnum:]_-]+\.[[:alnum:]_-]+'

usage() {
    cat <<USAGE
Usage:
  $SCRIPT_NAME

Scans the native direct-call working set for forbidden raw/debug/secret markers.

Optional environment:
  DIRECT_CALL_FORBIDDEN_SCAN_PATHS   Space-separated override for paths to scan.

Notes:
  - DTO and environment variable names containing token-like words are allowed.
  - The direct-call encrypted payload coding key and tests that prove redaction
    are allowlisted.
  - No file contents containing secrets are printed by this script beyond rg's
    matching source lines; do not add real secrets to the repository.
USAGE
}

log() {
    printf '[verify-direct-call-forbidden-scan] %s\n' "$*"
}

fail() {
    printf '[verify-direct-call-forbidden-scan] error: %s\n' "$*" >&2
    exit 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

command -v rg >/dev/null 2>&1 || fail "Missing required command: rg"

cd "$REPO_ROOT"

if [[ -n "${DIRECT_CALL_FORBIDDEN_SCAN_PATHS:-}" ]]; then
    # shellcheck disable=SC2206 # Intentional word splitting for space-separated paths.
    scan_paths=($DIRECT_CALL_FORBIDDEN_SCAN_PATHS)
else
    shopt -s nullglob
    scan_paths=(
        ElementX/Sources/Services/Calls/DirectCall*.swift
        ElementX/Sources/Services/Calls/NativeDirectCall*.swift
        ElementX/Sources/Services/Calls/LiveKitDirectCall*.swift
        ElementX/Sources/Services/Calls/NoOpDirectCallMediaEngine.swift
        ElementX/Sources/Services/Room/JoinedRoomProxy.swift
        ElementX/Sources/Application/AppCoordinator.swift
        ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift
        ElementX/Sources/FlowCoordinators/ChatsTabFlowCoordinator.swift
        ElementX/Sources/FlowCoordinators/RoomFlowCoordinator.swift
        UnitTests/Sources/DirectCall*.swift
        UnitTests/Sources/RoomFlowCoordinatorTests.swift
        UnitTests/Sources/ChatsTabFlowCoordinatorTests.swift
        Tools/Scripts/run_native_direct_call_diagnostic_two_client.sh
    )
    shopt -u nullglob
fi

if [[ ${#scan_paths[@]} -eq 0 ]]; then
    fail "No scan paths found. Check DIRECT_CALL_FORBIDDEN_SCAN_PATHS."
fi

log "scan path count: ${#scan_paths[@]}"

raw_hits="$(rg -n --color never -e "$RAW_PATH_PATTERN" "${scan_paths[@]}" || true)"
if [[ -n "$raw_hits" ]]; then
    printf '%s\n' "$raw_hits" >&2
    fail "Forbidden raw/debug receive marker found."
fi

encrypted_payload_hits="$(rg -n --color never -e "$ENCRYPTED_PAYLOAD_PATTERN" "${scan_paths[@]}" || true)"
if [[ -n "$encrypted_payload_hits" ]]; then
    encrypted_payload_hits="$(printf '%s\n' "$encrypted_payload_hits" \
        | grep -v 'case encryptedPayload = "encrypted_payload"' \
        | grep -v 'contains("encrypted_payload") == false' \
        | grep -v 'json.contains("\\"encrypted_payload\\"")' \
        || true)"
fi
if [[ -n "$encrypted_payload_hits" ]]; then
    printf '%s\n' "$encrypted_payload_hits" >&2
    fail "Unexpected encrypted_payload reference found."
fi

jwt_hits="$(rg -n --color never -e "$JWT_PATTERN" "${scan_paths[@]}" || true)"
if [[ -n "$jwt_hits" ]]; then
    printf '%s\n' "$jwt_hits" >&2
    fail "JWT-looking literal found."
fi

log "scan passed"
