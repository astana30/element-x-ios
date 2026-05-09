#!/usr/bin/env bash

#
# Host-side skeleton for a future two-simulator native direct-call diagnostic
# proof. The first proof is signalling-only; active audio is not expected until
# real LiveKit runtime dependencies are intentionally wired.
#
# This script is safe-by-default:
# - DRY_RUN defaults to 1.
# - It does not erase, reset, or otherwise clean simulators.
# - It does not print credential values.
# - It writes only redacted UITestsSignalling command/status messages.
#
# Preconditions for a real run:
# - Build the DEBUG app first.
# - Boot two simulators.
# - Open the same encrypted 1:1 room in both app instances.
# - Run commands one step at a time and inspect redacted status.
#

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_BUNDLE_ID="kz.salemx.msg"
readonly SIGNAL_DIR="/Users/Shared"
readonly DRY_RUN="${DRY_RUN:-1}"
readonly WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-30}"
readonly POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-1}"
readonly BUNDLE_ID="${SALEMX_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"

readonly COMMANDS=(
    prepare
    startListener
    startOutgoingAudioCall
    acceptIncomingCall
    hangup
    stop
    reset
)

usage() {
    cat <<USAGE
Usage:
  DRY_RUN=1 $SCRIPT_NAME plan
  DRY_RUN=1 $SCRIPT_NAME validate
  DRY_RUN=0 $SCRIPT_NAME init A|B|both
  DRY_RUN=0 $SCRIPT_NAME launch A|B|both
  DRY_RUN=0 $SCRIPT_NAME send A|B <command>
  DRY_RUN=0 $SCRIPT_NAME status A|B

Supported commands:
  ${COMMANDS[*]}

Required environment:
  SALEMX_APP_PATH
  SIMULATOR_UDID_A
  SIMULATOR_UDID_B
  INTEGRATION_TESTS_HOST
  INTEGRATION_TESTS_USERNAME_A
  INTEGRATION_TESTS_PASSWORD_A
  INTEGRATION_TESTS_USERNAME_B
  INTEGRATION_TESTS_PASSWORD_B

Optional environment:
  SALEMX_BUNDLE_ID                 Defaults to $DEFAULT_BUNDLE_ID.
  SIMULATOR_NAME_A / SIMULATOR_NAME_B
                                  Avoids deriving simulator names from UDIDs.
  WAIT_TIMEOUT_SECONDS             Defaults to 30.
  DRY_RUN                          Defaults to 1.

Example planned signalling sequence:
  $SCRIPT_NAME init both
  $SCRIPT_NAME launch both
  $SCRIPT_NAME send A prepare
  $SCRIPT_NAME send B prepare
  $SCRIPT_NAME send A startListener
  $SCRIPT_NAME send B startListener
  $SCRIPT_NAME send A startOutgoingAudioCall
  $SCRIPT_NAME status B
  $SCRIPT_NAME send B acceptIncomingCall
  $SCRIPT_NAME status A
  $SCRIPT_NAME send A hangup
  $SCRIPT_NAME status A
  $SCRIPT_NAME status B
USAGE
}

log() {
    printf '[native-direct-call-runner] %s\n' "$*"
}

fail() {
    printf '[native-direct-call-runner] error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required host command: $1"
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        fail "Missing required environment variable: $name"
    fi
}

require_common_environment() {
    require_env SALEMX_APP_PATH
    require_env SIMULATOR_UDID_A
    require_env SIMULATOR_UDID_B
    require_env INTEGRATION_TESTS_HOST
    require_env INTEGRATION_TESTS_USERNAME_A
    require_env INTEGRATION_TESTS_PASSWORD_A
    require_env INTEGRATION_TESTS_USERNAME_B
    require_env INTEGRATION_TESTS_PASSWORD_B
}

require_host_tools() {
    require_command python3
    require_command xcrun
}

sanitize_identifier() {
    python3 - "$1" <<'PY'
import sys

value = sys.argv[1]
result = []
previous_separator = False
for character in value:
    if len(result) >= 48:
        break
    if character.isalnum() or character in "_-":
        result.append(character)
        previous_separator = False
    elif not previous_separator:
        result.append("-")
        previous_separator = True

sanitized = "".join(result).strip("-_")
print(sanitized)
PY
}

client_udid() {
    case "$1" in
        A) printf '%s\n' "$SIMULATOR_UDID_A" ;;
        B) printf '%s\n' "$SIMULATOR_UDID_B" ;;
        *) fail "Unknown client '$1'. Expected A, B, or both." ;;
    esac
}

client_username() {
    case "$1" in
        A) printf '%s\n' "$INTEGRATION_TESTS_USERNAME_A" ;;
        B) printf '%s\n' "$INTEGRATION_TESTS_USERNAME_B" ;;
        *) fail "Unknown client '$1'. Expected A or B." ;;
    esac
}

client_credential() {
    case "$1" in
        A) printf '%s\n' "$INTEGRATION_TESTS_PASSWORD_A" ;;
        B) printf '%s\n' "$INTEGRATION_TESTS_PASSWORD_B" ;;
        *) fail "Unknown client '$1'. Expected A or B." ;;
    esac
}

client_channel() {
    case "$1" in
        A|B) printf '%s\n' "$1" ;;
        *) fail "Unknown client '$1'. Expected A or B." ;;
    esac
}

client_name() {
    local client="$1"
    local name_var="SIMULATOR_NAME_$client"
    if [[ -n "${!name_var:-}" ]]; then
        printf '%s\n' "${!name_var}"
        return
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'SIMULATOR-%s\n' "$client"
        return
    fi

    xcrun simctl getenv "$(client_udid "$client")" SIMULATOR_DEVICE_NAME
}

signal_file() {
    local client="$1"
    local device_name
    local channel
    device_name="$(client_name "$client")"
    channel="$(client_channel "$client")"

    local sanitized_device_name
    local sanitized_channel
    sanitized_device_name="${device_name// /-}"
    sanitized_channel="$(sanitize_identifier "$channel")"

    printf '%s/UITestsSignalling-%s-%s\n' "$SIGNAL_DIR" "$sanitized_device_name" "$sanitized_channel"
}

run_or_print() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: $*"
    else
        "$@"
    fi
}

write_ready() {
    local client="$1"
    local file
    file="$(signal_file "$client")"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: initialize channel=$client file=$file with tests-ready signal"
        return
    fi

    python3 - "$file" <<'PY'
import json
import sys

file_path = sys.argv[1]
message = {
    "mode": {
        "tests": {}
    },
    "signal": {
        "ready": {}
    }
}
with open(file_path, "w", encoding="utf-8") as handle:
    json.dump(message, handle, sort_keys=True, separators=(",", ":"))
PY
    log "initialized channel=$client"
}

write_command() {
    local client="$1"
    local command_name="$2"
    local correlation_id="$3"
    local file
    file="$(signal_file "$client")"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: send channel=$client command=$command_name correlationID=$correlation_id"
        return
    fi

    python3 - "$file" "$command_name" "$correlation_id" <<'PY'
import json
import sys

file_path, command_name, correlation_id = sys.argv[1:4]
message = {
    "mode": {
        "tests": {}
    },
    "signal": {
        "nativeDirectCallDiagnostic": {
            "_0": {
                "command": command_name,
                "correlationID": correlation_id,
            }
        }
    }
}
with open(file_path, "w", encoding="utf-8") as handle:
    json.dump(message, handle, sort_keys=True, separators=(",", ":"))
PY
}

write_status_request() {
    local client="$1"
    local correlation_id="$2"
    local file
    file="$(signal_file "$client")"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: query-status channel=$client correlationID=$correlation_id"
        return
    fi

    python3 - "$file" "$correlation_id" <<'PY'
import json
import sys

file_path, correlation_id = sys.argv[1:3]
message = {
    "mode": {
        "tests": {}
    },
    "signal": {
        "nativeDirectCallDiagnosticStatus": {
            "_0": {
                "correlationID": correlation_id,
            }
        }
    }
}
with open(file_path, "w", encoding="utf-8") as handle:
    json.dump(message, handle, sort_keys=True, separators=(",", ":"))
PY
}

extract_result() {
    local client="$1"
    local expected_signal="$2"
    local correlation_id="$3"
    local file
    file="$(signal_file "$client")"

    python3 - "$file" "$expected_signal" "$correlation_id" <<'PY'
import json
import sys

file_path, expected_signal, correlation_id = sys.argv[1:4]

try:
    with open(file_path, "r", encoding="utf-8") as handle:
        message = json.load(handle)
except Exception:
    sys.exit(2)

mode = message.get("mode")
if not (mode == "app" or (isinstance(mode, dict) and "app" in mode)):
    sys.exit(3)

signal = message.get("signal", {})
payload = signal.get(expected_signal)
if not isinstance(payload, dict):
    sys.exit(4)

body = payload.get("_0")
if not isinstance(body, dict):
    sys.exit(5)

if body.get("correlationID") != correlation_id:
    sys.exit(6)

if expected_signal == "nativeDirectCallDiagnosticResult":
    outcome = body.get("outcome", {})
    if "success" in outcome:
        value = outcome["success"]
        if isinstance(value, dict):
            value = value.get("_0", "unknown")
        print(f"outcome=success code={value}")
        sys.exit(0)
    if "failure" in outcome:
        value = outcome["failure"]
        if isinstance(value, dict):
            value = value.get("_0", "unknown")
        print(f"outcome=failure code={value}")
        sys.exit(0)
    sys.exit(7)

if expected_signal == "nativeDirectCallDiagnosticStatusResult":
    status = body.get("status", {})
    print(
        "state={state} listenerStarted={listener} hasActiveSession={session}".format(
            state=status.get("state", "unknown"),
            listener=str(status.get("listenerStarted", "unknown")).lower(),
            session=str(status.get("hasActiveSession", "unknown")).lower(),
        )
    )
    sys.exit(0)

sys.exit(8)
PY
}

is_app_ready() {
    local client="$1"
    local file
    file="$(signal_file "$client")"

    python3 - "$file" <<'PY'
import json
import sys

file_path = sys.argv[1]

try:
    with open(file_path, "r", encoding="utf-8") as handle:
        message = json.load(handle)
except Exception:
    sys.exit(1)

mode = message.get("mode")
if not (mode == "app" or (isinstance(mode, dict) and "app" in mode)):
    sys.exit(2)

signal = message.get("signal", {})
if isinstance(signal, dict) and isinstance(signal.get("ready"), dict):
    sys.exit(0)

sys.exit(3)
PY
}

pause_for_poll_interval() {
    python3 - "$POLL_INTERVAL_SECONDS" <<'PY'
import select
import sys

select.select([], [], [], float(sys.argv[1]))
PY
}

wait_for_result() {
    local client="$1"
    local expected_signal="$2"
    local correlation_id="$3"
    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    local result=""

    while (( SECONDS <= deadline )); do
        if result="$(extract_result "$client" "$expected_signal" "$correlation_id" 2>/dev/null)"; then
            printf '%s\n' "$result"
            return 0
        fi
        pause_for_poll_interval
    done

    fail "Timed out waiting for channel=$client correlationID=$correlation_id signal=$expected_signal"
}

wait_for_app_ready() {
    local client="$1"
    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

    while (( SECONDS <= deadline )); do
        if is_app_ready "$client"; then
            log "channel=$client app diagnostic signalling ready"
            return 0
        fi
        pause_for_poll_interval
    done

    fail "Timed out waiting for channel=$client app diagnostic signalling readiness. Ensure the app is logged in, integration diagnostics are enabled, and the real room flow has started."
}

correlation_id() {
    local client="$1"
    local action="$2"
    local suffix
    suffix="$(date +%s)"
    sanitize_identifier "${client}-${action}-${suffix}"
}

validate_command_name() {
    local command_name="$1"
    local command
    for command in "${COMMANDS[@]}"; do
        if [[ "$command" == "$command_name" ]]; then
            return
        fi
    done
    fail "Unsupported diagnostic command: $command_name"
}

for_each_client() {
    local selector="$1"
    shift

    case "$selector" in
        A|B)
            "$@" "$selector"
            ;;
        both)
            "$@" A
            "$@" B
            ;;
        *)
            fail "Expected A, B, or both. Received: $selector"
            ;;
    esac
}

init_channel() {
    write_ready "$1"
}

set_client_environment() {
    local client="$1"

    if [[ "$DRY_RUN" == "1" ]]; then
        local udid
        udid="$(client_udid "$client")"
        log "DRY_RUN: set integration env for channel=$client udid=$udid host=<set> username=<set> credential=<redacted>"
        return
    fi

    # simctl launch reads per-process environment from SIMCTL_CHILD_* values,
    # so the real environment is applied by launch_client_with_environment.
    :
}

launch_client_with_environment() {
    local client="$1"
    local udid="$2"
    local username
    local credential
    local channel
    username="$(client_username "$client")"
    credential="$(client_credential "$client")"
    channel="$(client_channel "$client")"

    SIMCTL_CHILD_IS_RUNNING_INTEGRATION_TESTS=1 \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_DIAGNOSTICS=1 \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED=1 \
        SIMCTL_CHILD_UI_TESTS_SIGNALLING_CHANNEL="$channel" \
        SIMCTL_CHILD_INTEGRATION_TESTS_HOST="$INTEGRATION_TESTS_HOST" \
        SIMCTL_CHILD_INTEGRATION_TESTS_USERNAME="$username" \
        SIMCTL_CHILD_INTEGRATION_TESTS_PASSWORD="$credential" \
        xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
}

launch_client() {
    local client="$1"
    local udid
    udid="$(client_udid "$client")"

    init_channel "$client"
    set_client_environment "$client"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: install app for channel=$client udid=$udid app=${SALEMX_APP_PATH:-<missing>}"
        log "DRY_RUN: launch bundle=$BUNDLE_ID for channel=$client udid=$udid"
        log "DRY_RUN: wait for channel=$client app diagnostic signalling readiness"
        return
    fi

    xcrun simctl install "$udid" "$SALEMX_APP_PATH"
    launch_client_with_environment "$client" "$udid"
    log "launched channel=$client udid=$udid bundle=$BUNDLE_ID"
    wait_for_app_ready "$client"
}

send_command() {
    local client="$1"
    local command_name="$2"
    validate_command_name "$command_name"

    local id
    id="$(correlation_id "$client" "$command_name")"
    write_command "$client" "$command_name" "$id"

    if [[ "$DRY_RUN" == "1" ]]; then
        return
    fi

    local result
    result="$(wait_for_result "$client" nativeDirectCallDiagnosticResult "$id")"
    log "channel=$client command=$command_name correlationID=$id $result"
}

query_status() {
    local client="$1"
    local id
    id="$(correlation_id "$client" status)"
    write_status_request "$client" "$id"

    if [[ "$DRY_RUN" == "1" ]]; then
        return
    fi

    local result
    result="$(wait_for_result "$client" nativeDirectCallDiagnosticStatusResult "$id")"
    log "channel=$client command=status correlationID=$id $result"
}

print_plan() {
    cat <<PLAN
Two-simulator diagnostic skeleton plan:
  1. Build the DEBUG app and set SALEMX_APP_PATH.
  2. Boot two simulators and set SIMULATOR_UDID_A / SIMULATOR_UDID_B.
  3. Provide INTEGRATION_TESTS_HOST and per-client credentials.
  4. Initialize both redacted signalling channels.
  5. Launch both app instances with integration diagnostics enabled.
  6. Manually or separately open the same encrypted 1:1 room on both clients.
  7. Run the signalling-only diagnostic sequence:
     send A prepare
     send B prepare
     send A startListener
     send B startListener
     send A startOutgoingAudioCall
     status B
     send B acceptIncomingCall
     status A
     send A hangup
     status A
     status B

Dry-run mode is currently: DRY_RUN=$DRY_RUN
Full two-client proof is intentionally not run by this skeleton.
PLAN
}

main() {
    local action="${1:-plan}"

    case "$action" in
        help|-h|--help)
            usage
            ;;
        plan)
            print_plan
            ;;
        validate)
            require_host_tools
            require_common_environment
            log "validated required environment; credential values were not printed"
            ;;
        init)
            require_host_tools
            require_common_environment
            for_each_client "${2:-both}" init_channel
            ;;
        launch)
            require_host_tools
            require_common_environment
            for_each_client "${2:-both}" launch_client
            ;;
        send)
            require_host_tools
            require_common_environment
            [[ $# -eq 3 ]] || fail "Usage: $SCRIPT_NAME send A|B <command>"
            send_command "$2" "$3"
            ;;
        status)
            require_host_tools
            require_common_environment
            [[ $# -eq 2 ]] || fail "Usage: $SCRIPT_NAME status A|B"
            query_status "$2"
            ;;
        *)
            usage
            fail "Unknown action: $action"
            ;;
    esac
}

main "$@"
