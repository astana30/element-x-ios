#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: check_staging_readiness.sh [--env-file PATH]

Checks the SalemX call service readiness endpoint and prints redacted readiness only.
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

is_placeholder() {
    local value="${1:-}"
    [[ -z "$value" || "$value" == *"<"* || "$value" == *">"* || "$value" == *"example.invalid"* ]]
}

if is_placeholder "${CALL_SERVICE_BASE_URL:-}"; then
    echo "missing required env: CALL_SERVICE_BASE_URL"
    echo "staging readiness check blocked: missing required env vars listed above"
    exit 2
fi

BASE_URL="${CALL_SERVICE_BASE_URL%/}"
READINESS_PATH="/_matrix/client/unstable/kz.salemx.direct_call/readiness"
TMP_DIR="$(mktemp -d -t salemx-staging-readiness.XXXXXX)"
BODY_FILE="$TMP_DIR/readiness.json"
REPORT_FILE="$TMP_DIR/report.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! status="$(curl -sS -o "$BODY_FILE" -w '%{http_code}' "${BASE_URL}${READINESS_PATH}")"; then
    status="000"
fi

python3 - "$status" "$BODY_FILE" > "$REPORT_FILE" <<'PY'
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
parts = ["case=readiness", f"status={status}"]
parts.extend(f"{key}={value}" for key, value in summary.items())
parts.append(f"result={'pass' if passed else 'fail'}")
print(" ".join(parts))
PY

redaction_failed=0
for secret_name in \
    SYNAPSE_ADMIN_TOKEN \
    LIVEKIT_API_KEY \
    LIVEKIT_API_SECRET \
    SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET \
    SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL \
    SALEMX_CALL_SERVICE_RATE_LIMIT_STORE_URL \
    CALLER_MATRIX_ACCESS_TOKEN \
    CALLER_DEVICE_ID \
    STAGING_ENCRYPTED_DIRECT_ROOM_ID \
    STAGING_PEER_USER_ID; do
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
