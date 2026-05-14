#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_DESTINATION="platform=iOS Simulator,id=183D9DAD-0CB6-49DE-ABFD-53BFA7B724CB"
readonly CAPABILITIES_PATH="/_matrix/client/v3/capabilities"
readonly TOKEN_PATH="/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
readonly TOKEN_SMOKE_TEST="productionLiveKitTokenProviderMapsLocalBackendSmokeResponseToConnectionInfo"
readonly CAPABILITY_SMOKE_TEST="productionHTTPCapabilityProviderMapsLocalBackendSmokeCapabilityToDryRunDecision"
readonly SMOKE_CONFIG_FILE="/tmp/salemx-direct-call-backend-smoke.env"

fail() {
    printf '[%s] error: %s\n' "$SCRIPT_NAME" "$1" >&2
    exit 1
}

info() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$1"
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        fail "missing required env: $name"
    fi
}

require_command() {
    local name="$1"
    command -v "$name" >/dev/null 2>&1 || fail "missing required command: $name"
}

trim_trailing_slash() {
    local value="$1"
    printf '%s' "${value%/}"
}

assert_local_base_url() {
    local url="$1"
    case "$url" in
        http://127.0.0.1:*|http://127.0.0.1|http://localhost:*|http://localhost|http://[::1]:*|http://[::1])
            ;;
        *)
            fail "SALEMX_DIRECTCALL_BACKEND_BASE_URL must point to a local HTTP backend"
            ;;
    esac
}

curl_status() {
    local method="$1"
    local url="$2"
    local body_file="${3:-}"
    local output_file
    output_file="$(mktemp -t salemx-direct-call-smoke-response.XXXXXX)"

    local status
    if [[ -n "$body_file" ]]; then
        status="$(curl -sS -o "$output_file" -w '%{http_code}' \
            -X "$method" \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -H "Authorization: Bearer ${SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN}" \
            --data-binary "@$body_file" \
            "$url")"
    else
        status="$(curl -sS -o "$output_file" -w '%{http_code}' \
            -X "$method" \
            -H 'Accept: application/json' \
            -H "Authorization: Bearer ${SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN}" \
            "$url")"
    fi

    rm -f "$output_file"
    printf '%s' "$status"
}

main() {
    require_command curl
    require_command xcodebuild

    require_env SALEMX_DIRECTCALL_BACKEND_SMOKE
    require_env SALEMX_DIRECTCALL_BACKEND_BASE_URL
    require_env SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN

    if [[ "$SALEMX_DIRECTCALL_BACKEND_SMOKE" != "1" ]]; then
        fail "SALEMX_DIRECTCALL_BACKEND_SMOKE must be 1"
    fi

    local base_url
    base_url="$(trim_trailing_slash "$SALEMX_DIRECTCALL_BACKEND_BASE_URL")"
    assert_local_base_url "$base_url"

    info "Live backend smoke: enabled"
    info "Backend URL: <local-redacted>"
    info "Access credential: <redacted>"

    local capability_status
    capability_status="$(curl_status GET "${base_url}${CAPABILITIES_PATH}")"
    [[ "$capability_status" == "200" ]] || fail "capabilities endpoint returned HTTP $capability_status"
    info "Capabilities endpoint reachable"

    local token_request_file
    token_request_file="$(mktemp -t salemx-direct-call-token-request.XXXXXX)"
    cat > "$token_request_file" <<'JSON'
{
  "version": 1,
  "call_id": "local-smoke-call",
  "room_id": "!local-smoke:example.test",
  "peer_user_id": "@bob:local.test",
  "intent": "audio",
  "direction": "outgoing",
  "device_id": "DEVICEA",
  "client_transaction_id": "local-smoke-transaction"
}
JSON

    local token_status
    token_status="$(curl_status POST "${base_url}${TOKEN_PATH}" "$token_request_file")"
    rm -f "$token_request_file"
    [[ "$token_status" == "200" ]] || fail "token endpoint returned HTTP $token_status"
    info "Token endpoint reachable"

    local destination
    destination="${DIRECT_CALL_BACKEND_SMOKE_DESTINATION:-$DEFAULT_DESTINATION}"
    local result_log
    result_log="$(mktemp -t salemx-direct-call-backend-smoke-xcodebuild.XXXXXX.log)"

    umask 077
    cat > "$SMOKE_CONFIG_FILE" <<EOF
SALEMX_DIRECTCALL_BACKEND_SMOKE=1
SALEMX_DIRECTCALL_BACKEND_BASE_URL=$base_url
SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN=$SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN
SALEMX_DIRECTCALL_BACKEND_SMOKE_CREATED_AT=$(date +%s)
EOF
    trap 'rm -f "$SMOKE_CONFIG_FILE"' EXIT

    info "Running env-gated Swift tests"
    # Hosted simulator tests receive launch environment through CoreSimulator's
    # SIMCTL_CHILD_ prefix, not reliably from xcodebuild's own process env.
    export SIMCTL_CHILD_SALEMX_DIRECTCALL_BACKEND_SMOKE="$SALEMX_DIRECTCALL_BACKEND_SMOKE"
    export SIMCTL_CHILD_SALEMX_DIRECTCALL_BACKEND_BASE_URL="$base_url"
    export SIMCTL_CHILD_SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN="$SALEMX_DIRECTCALL_BACKEND_FAKE_ACCESS_TOKEN"

    if ! xcodebuild test \
        -project SalemX.xcodeproj \
        -scheme UnitTests \
        -destination "$destination" \
        -only-testing:UnitTests/DirectCallBackendSmokeTests \
        > "$result_log" 2>&1; then
        fail "xcodebuild smoke test run failed; full log: $result_log"
    fi

    if ! grep -q "Test ${TOKEN_SMOKE_TEST}() passed" "$result_log"; then
        fail "token smoke test did not pass; full log: $result_log"
    fi

    if ! grep -q "Test ${CAPABILITY_SMOKE_TEST}() passed" "$result_log"; then
        fail "capability smoke test did not pass; full log: $result_log"
    fi

    if grep -q "${TOKEN_SMOKE_TEST}() skipped" "$result_log" || grep -q "${CAPABILITY_SMOKE_TEST}() skipped" "$result_log"; then
        fail "one or more smoke tests were skipped; full log: $result_log"
    fi

    info "Token smoke test passed"
    info "Capability smoke test passed"
    info "Production direct calls remain disabled; this smoke does not start listeners, media, UI, or Matrix sends."
    info "xcodebuild log: $result_log"
}

main "$@"
