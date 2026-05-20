#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: run_staging_call_service_local.sh --env-file PATH [--host HOST] [--port PORT]

Starts the SalemX call service in staging mode using an operator-local env file.
The script validates guardrail env vars and never prints env values.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE=""
HOST="127.0.0.1"
PORT="8088"

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
        --host)
            if [[ $# -lt 2 ]]; then
                echo "error: --host requires a value" >&2
                exit 2
            fi
            HOST="$2"
            shift 2
            ;;
        --port)
            if [[ $# -lt 2 ]]; then
                echo "error: --port requires a value" >&2
                exit 2
            fi
            PORT="$2"
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

if [[ -z "$ENV_FILE" ]]; then
    echo "error: --env-file is required" >&2
    usage >&2
    exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "error: env file not found" >&2
    exit 2
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

is_placeholder() {
    local value="${1:-}"
    [[ -z "$value" || "$value" == *"<"* || "$value" == *">"* || "$value" == *"example.invalid"* ]]
}

missing=0
require_value() {
    local name="$1"
    local value="${!name:-}"
    if is_placeholder "$value"; then
        echo "missing required env: $name"
        missing=$((missing + 1))
    fi
}

require_equal() {
    local name="$1"
    local expected="$2"
    local value="${!name:-}"
    if [[ "$value" != "$expected" ]]; then
        echo "invalid env: $name"
        missing=$((missing + 1))
    fi
}

require_prefix() {
    local name="$1"
    local prefix="$2"
    local value="${!name:-}"
    if is_placeholder "$value" || [[ "$value" != "$prefix"* ]]; then
        echo "invalid env: $name"
        missing=$((missing + 1))
    fi
}

require_positive_integer() {
    local name="$1"
    local value="${!name:-}"
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo "invalid env: $name"
        missing=$((missing + 1))
    fi
}

for required_name in \
    SYNAPSE_BASE_URL \
    SYNAPSE_ADMIN_TOKEN \
    LIVEKIT_API_KEY \
    LIVEKIT_API_SECRET \
    SALEMX_CALL_SERVICE_STORAGE_KEY_SECRET \
    SALEMX_CALL_SERVICE_ALLOCATION_STORE_URL \
    SALEMX_CALL_SERVICE_RATE_LIMIT_STORE_URL; do
    require_value "$required_name"
done

require_equal SALEMX_CALL_SERVICE_MODE staging
require_equal SALEMX_CALL_SERVICE_FAKE_MODE 0
require_equal SALEMX_CALL_SERVICE_ALLOCATION_STORE redis
require_equal SALEMX_CALL_SERVICE_RATE_LIMIT_STORE redis
require_prefix LIVEKIT_URL wss://
require_positive_integer TOKEN_TTL_SECONDS
require_positive_integer ALLOCATION_TTL_SECONDS
require_positive_integer SALEMX_CALL_SERVICE_RATE_LIMIT_PER_MINUTE

if [[ "${TOKEN_TTL_SECONDS:-0}" =~ ^[0-9]+$ && "${ALLOCATION_TTL_SECONDS:-0}" =~ ^[0-9]+$ ]]; then
    if [[ "$ALLOCATION_TTL_SECONDS" -lt "$TOKEN_TTL_SECONDS" ]]; then
        echo "invalid env: ALLOCATION_TTL_SECONDS"
        missing=$((missing + 1))
    fi
fi

if [[ "$missing" -gt 0 ]]; then
    echo "staging call service start blocked: fix env vars listed above"
    exit 2
fi

if ! python3 -c 'import fastapi, redis, uvicorn' >/dev/null 2>&1; then
    echo "error: Python dependencies unavailable; install server/salemx-call-service/requirements.txt" >&2
    exit 2
fi

echo "starting SalemX call service in staging mode with redacted env"
echo "host=${HOST} port=${PORT}"
cd "$SERVICE_DIR"
exec python3 -m uvicorn salemx_call_service.app:app --host "$HOST" --port "$PORT"
