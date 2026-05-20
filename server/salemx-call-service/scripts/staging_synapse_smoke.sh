#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: staging_synapse_smoke.sh [--env-file PATH]

Runs the SalemX call service staging Synapse validation smoke with redacted output only.
The optional env file is operator-local and must not be committed.
USAGE
}

ENV_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-file)
            if [[ $# -lt 2 ]]; then
                echo "error: --env-file requires a path" >&2
                exit 2
            fi
            ENV_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -n "$ENV_FILE" ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "error: env file not found" >&2
        exit 2
    fi
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
fi

TMP_DIR="$(mktemp -d -t salemx-staging-synapse-smoke.XXXXXX)"
REPORT_FILE="$TMP_DIR/report.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

touch "$REPORT_FILE"

is_placeholder() {
    local value="${1:-}"
    [[ -z "$value" || "$value" == *"<"* || "$value" == *">"* || "$value" == *"example.invalid"* ]]
}

require_var() {
    local name="$1"
    local value="${!name:-}"
    if is_placeholder "$value"; then
        echo "missing required env: $name"
        return 1
    fi
    return 0
}

optional_present() {
    local name="$1"
    local value="${!name:-}"
    ! is_placeholder "$value"
}

append_report() {
    printf '%s\n' "$1" >> "$REPORT_FILE"
}

missing_count=0
for required_name in \
    CALL_SERVICE_BASE_URL \
    CALLER_MATRIX_ACCESS_TOKEN \
    CALLER_DEVICE_ID \
    STAGING_ENCRYPTED_DIRECT_ROOM_ID \
    STAGING_PEER_USER_ID; do
    if ! require_var "$required_name"; then
        missing_count=$((missing_count + 1))
    fi
done

if [[ "$missing_count" -gt 0 ]]; then
    echo "staging Synapse smoke blocked: missing required env vars listed above"
    exit 2
fi

BASE_URL="${CALL_SERVICE_BASE_URL%/}"
TOKEN_PATH="/_matrix/client/unstable/kz.salemx.direct_call/livekit/token"
READINESS_PATH="/_matrix/client/unstable/kz.salemx.direct_call/readiness"

curl_get() {
    local url="$1"
    local output_file="$2"
    local status
    if ! status="$(curl -sS -o "$output_file" -w '%{http_code}' "$url")"; then
        status="000"
    fi
    printf '%s' "$status"
}

curl_post() {
    local url="$1"
    local auth_token="$2"
    local request_file="$3"
    local output_file="$4"
    local status
    if ! status="$(curl -sS -o "$output_file" -w '%{http_code}' \
        -H "Authorization: Bearer ${auth_token}" \
        -H 'Content-Type: application/json' \
        --data-binary "@${request_file}" \
        "$url")"; then
        status="000"
    fi
    printf '%s' "$status"
}

write_request() {
    local output_file="$1"
    local room_id="$2"
    local peer_user_id="$3"
    local device_id="$4"
    local call_id="$5"
    python3 - "$output_file" "$room_id" "$peer_user_id" "$device_id" "$call_id" <<'PY'
import json
import sys

output_file, room_id, peer_user_id, device_id, call_id = sys.argv[1:]
payload = {
    "version": 1,
    "call_id": call_id,
    "room_id": room_id,
    "peer_user_id": peer_user_id,
    "intent": "audio",
    "direction": "outgoing",
    "device_id": device_id,
    "client_transaction_id": f"txn-{call_id}",
}
with open(output_file, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, separators=(",", ":"), sort_keys=True)
PY
    chmod 600 "$output_file"
}

summarize_readiness() {
    local status="$1"
    local body_file="$2"
    python3 - "$status" "$body_file" <<'PY'
import json
import sys

status = sys.argv[1]
body_file = sys.argv[2]
try:
    with open(body_file, encoding="utf-8") as handle:
        body = json.load(handle)
except Exception:
    print(f"case=readiness status={status} parse_error=true result=fail")
    raise SystemExit(0)
fields = [
    "ready",
    "reason",
    "allocationStoreConfigured",
    "allocationStoreShared",
    "allocationStoreConnected",
    "rateLimitConfigured",
    "rateLimitShared",
    "rateLimitConnected",
    "storageKeyConfigured",
]
summary = {field: body.get(field) for field in fields}
passed = (
    status == "200"
    and summary.get("ready") is True
    and summary.get("reason") == "ok"
    and summary.get("allocationStoreConfigured") is True
    and summary.get("allocationStoreShared") is True
    and summary.get("allocationStoreConnected") is True
    and summary.get("rateLimitConfigured") is True
    and summary.get("rateLimitShared") is True
    and summary.get("rateLimitConnected") is True
    and summary.get("storageKeyConfigured") is True
)
parts = [f"case=readiness", f"status={status}"]
parts.extend(f"{key}={value}" for key, value in summary.items())
parts.append(f"result={'pass' if passed else 'fail'}")
print(" ".join(parts))
PY
}

summarize_positive() {
    local status="$1"
    local body_file="$2"
    python3 - "$status" "$body_file" <<'PY'
import json
import sys

status = sys.argv[1]
body_file = sys.argv[2]
try:
    with open(body_file, encoding="utf-8") as handle:
        body = json.load(handle)
except Exception:
    print(f"case=positive status={status} parse_error=true result=fail")
    raise SystemExit(0)
livekit = body.get("livekit") if isinstance(body, dict) else None
allocation = body.get("allocation") if isinstance(body, dict) else None
room_name_present = isinstance(livekit, dict) and bool(livekit.get("room_name"))
token_present = isinstance(livekit, dict) and bool(livekit.get("participant_token"))
expires_at_present = isinstance(livekit, dict) and bool(livekit.get("expires_at"))
allocation_id_present = isinstance(allocation, dict) and bool(allocation.get("id"))
allocation_call_id_present = isinstance(allocation, dict) and bool(allocation.get("call_id"))
intent = allocation.get("intent") if isinstance(allocation, dict) else None
passed = status == "200" and room_name_present and token_present and expires_at_present and allocation_id_present and allocation_call_id_present and intent == "audio"
print(
    " ".join([
        "case=positive",
        f"status={status}",
        "server_url=redacted",
        f"room_name_present={room_name_present}",
        "participant_token=redacted" if token_present else "participant_token=missing",
        f"expires_at_present={expires_at_present}",
        f"allocation_id_present={allocation_id_present}",
        f"allocation_call_id_present={allocation_call_id_present}",
        f"intent={intent}",
        f"result={'pass' if passed else 'fail'}",
    ])
)
PY
}

summarize_negative() {
    local case_name="$1"
    local expected_status="$2"
    local expected_errcode="$3"
    local status="$4"
    local body_file="$5"
    python3 - "$case_name" "$expected_status" "$expected_errcode" "$status" "$body_file" <<'PY'
import json
import sys

case_name, expected_status, expected_errcode, status, body_file = sys.argv[1:]
try:
    with open(body_file, encoding="utf-8") as handle:
        body = json.load(handle)
except Exception:
    print(f"case={case_name} status={status} parse_error=true token_issued=unknown result=fail")
    raise SystemExit(0)
errcode = body.get("errcode") if isinstance(body, dict) else None
livekit = body.get("livekit") if isinstance(body, dict) else None
token_issued = isinstance(livekit, dict) and bool(livekit.get("participant_token"))
retry_after_present = isinstance(body, dict) and body.get("retry_after_ms") is not None
passed = status == expected_status and errcode == expected_errcode and not token_issued
print(
    " ".join([
        f"case={case_name}",
        f"status={status}",
        f"errcode={errcode}",
        f"retry_after_ms_present={retry_after_present}",
        f"token_issued={token_issued}",
        f"result={'pass' if passed else 'fail'}",
    ])
)
PY
}

run_case() {
    local case_name="$1"
    local room_id="$2"
    local peer_user_id="$3"
    local device_id="$4"
    local auth_token="$5"
    local expected_status="$6"
    local expected_errcode="$7"
    local request_file="$TMP_DIR/${case_name}.request.json"
    local body_file="$TMP_DIR/${case_name}.body.json"
    write_request "$request_file" "$room_id" "$peer_user_id" "$device_id" "smoke-${case_name}-$(date +%s)"
    local status
    status="$(curl_post "${BASE_URL}${TOKEN_PATH}" "$auth_token" "$request_file" "$body_file")"
    if [[ "$expected_status" == "200" ]]; then
        append_report "$(summarize_positive "$status" "$body_file")"
    else
        append_report "$(summarize_negative "$case_name" "$expected_status" "$expected_errcode" "$status" "$body_file")"
    fi
}

readiness_body="$TMP_DIR/readiness.body.json"
readiness_status="$(curl_get "${BASE_URL}${READINESS_PATH}" "$readiness_body")"
append_report "$(summarize_readiness "$readiness_status" "$readiness_body")"

run_case \
    positive \
    "$STAGING_ENCRYPTED_DIRECT_ROOM_ID" \
    "$STAGING_PEER_USER_ID" \
    "$CALLER_DEVICE_ID" \
    "$CALLER_MATRIX_ACCESS_TOKEN" \
    200 \
    none

run_case \
    invalid_bearer \
    "$STAGING_ENCRYPTED_DIRECT_ROOM_ID" \
    "$STAGING_PEER_USER_ID" \
    "$CALLER_DEVICE_ID" \
    invalid-smoke-token \
    401 \
    M_UNKNOWN_TOKEN

if optional_present WRONG_DEVICE_ID; then
    run_case \
        wrong_device \
        "$STAGING_ENCRYPTED_DIRECT_ROOM_ID" \
        "$STAGING_PEER_USER_ID" \
        "$WRONG_DEVICE_ID" \
        "$CALLER_MATRIX_ACCESS_TOKEN" \
        403 \
        M_FORBIDDEN
else
    append_report "case=wrong_device status=skipped reason=missing_fixture result=skip"
fi

if optional_present NEGATIVE_UNENCRYPTED_ROOM_ID; then
    run_case \
        room_not_encrypted \
        "$NEGATIVE_UNENCRYPTED_ROOM_ID" \
        "$STAGING_PEER_USER_ID" \
        "$CALLER_DEVICE_ID" \
        "$CALLER_MATRIX_ACCESS_TOKEN" \
        403 \
        M_ROOM_NOT_ENCRYPTED
else
    append_report "case=room_not_encrypted status=skipped reason=missing_fixture result=skip"
fi

if optional_present NEGATIVE_NON_1_TO_1_ROOM_ID; then
    run_case \
        non_1_to_1 \
        "$NEGATIVE_NON_1_TO_1_ROOM_ID" \
        "$STAGING_PEER_USER_ID" \
        "$CALLER_DEVICE_ID" \
        "$CALLER_MATRIX_ACCESS_TOKEN" \
        403 \
        M_DIRECT_CALL_NOT_1_TO_1
else
    append_report "case=non_1_to_1 status=skipped reason=missing_fixture result=skip"
fi

if optional_present NEGATIVE_PEER_NOT_JOINED_USER_ID; then
    run_case \
        peer_mismatch \
        "$STAGING_ENCRYPTED_DIRECT_ROOM_ID" \
        "$NEGATIVE_PEER_NOT_JOINED_USER_ID" \
        "$CALLER_DEVICE_ID" \
        "$CALLER_MATRIX_ACCESS_TOKEN" \
        403 \
        M_DIRECT_CALL_PEER_MISMATCH
else
    append_report "case=peer_mismatch status=skipped reason=missing_fixture result=skip"
fi

if optional_present NEGATIVE_CALLER_NOT_JOINED_ROOM_ID; then
    run_case \
        caller_not_joined \
        "$NEGATIVE_CALLER_NOT_JOINED_ROOM_ID" \
        "$STAGING_PEER_USER_ID" \
        "$CALLER_DEVICE_ID" \
        "$CALLER_MATRIX_ACCESS_TOKEN" \
        403 \
        M_NOT_JOINED
else
    append_report "case=caller_not_joined status=skipped reason=missing_fixture result=skip"
fi

redaction_failed=0
for secret_name in \
    CALLER_MATRIX_ACCESS_TOKEN \
    CALLER_DEVICE_ID \
    STAGING_ENCRYPTED_DIRECT_ROOM_ID \
    STAGING_PEER_USER_ID \
    WRONG_DEVICE_ID \
    NEGATIVE_UNENCRYPTED_ROOM_ID \
    NEGATIVE_NON_1_TO_1_ROOM_ID \
    NEGATIVE_PEER_NOT_JOINED_USER_ID \
    NEGATIVE_CALLER_NOT_JOINED_ROOM_ID; do
    secret_value="${!secret_name:-}"
    if ! is_placeholder "$secret_value" && grep -Fq -- "$secret_value" "$REPORT_FILE"; then
        echo "redaction failure: report contains value for $secret_name" >&2
        redaction_failed=1
    fi
done

if grep -Eq 'Bearer [A-Za-z0-9._-]{8,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' "$REPORT_FILE"; then
    echo "redaction failure: report contains token-shaped output" >&2
    redaction_failed=1
fi

if [[ "$redaction_failed" -ne 0 ]]; then
    exit 1
fi

cat "$REPORT_FILE"

if grep -q 'result=fail' "$REPORT_FILE"; then
    exit 1
fi
