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
  DRY_RUN=0 $SCRIPT_NAME wait-status A|B incomingRinging
  DRY_RUN=0 $SCRIPT_NAME accept-when-ringing A|B

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
  NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION
                                  Optional. Set to 1 for diagnostic-only key exchange.
  NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET
                                  Optional shared diagnostic secret; never printed.
  NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT
                                  Optional. Set to 1 for diagnostic-only LiveKit media DI.
  NATIVE_DIRECT_CALL_LIVEKIT_URL  Required only when diagnostic LiveKit is enabled; never printed.
  NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A
                                  Required only when diagnostic LiveKit is enabled; never printed.
  NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B
                                  Required only when diagnostic LiveKit is enabled; never printed.
  NATIVE_DIRECT_CALL_LIVEKIT_ROOM Optional diagnostic LiveKit room name; never printed.

Example planned signalling sequence:
  $SCRIPT_NAME init both
  $SCRIPT_NAME launch both
  $SCRIPT_NAME send A prepare
  $SCRIPT_NAME send B prepare
  $SCRIPT_NAME send A startListener
  $SCRIPT_NAME send B startListener
  $SCRIPT_NAME send A startOutgoingAudioCall
  $SCRIPT_NAME accept-when-ringing B
  $SCRIPT_NAME status B
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
    require_livekit_environment_if_enabled
}

require_host_tools() {
    require_command python3
    require_command xcrun
}

is_livekit_diagnostics_enabled() {
    [[ "${NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT:-}" == "1" ]]
}

require_livekit_environment_if_enabled() {
    if ! is_livekit_diagnostics_enabled; then
        return
    fi

    require_env NATIVE_DIRECT_CALL_LIVEKIT_URL
    require_env NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A
    require_env NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B
}

redacted_env_state() {
    local name="$1"
    if [[ -n "${!name:-}" ]]; then
        printf '<set>\n'
    else
        printf '<missing>\n'
    fi
}

log_livekit_environment_summary() {
    if is_livekit_diagnostics_enabled; then
        log "LiveKit diagnostics: enabled"
        log "LiveKit URL: $(redacted_env_state NATIVE_DIRECT_CALL_LIVEKIT_URL)"
        log "LiveKit token A: <redacted>"
        log "LiveKit token B: <redacted>"
        log "LiveKit room: $(redacted_env_state NATIVE_DIRECT_CALL_LIVEKIT_ROOM)"
    else
        log "LiveKit diagnostics: disabled"
    fi
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
    reason = body.get("reason")
    reason_suffix = f" reason={reason}" if isinstance(reason, str) else ""
    if "success" in outcome:
        value = outcome["success"]
        if isinstance(value, dict):
            value = value.get("_0", "unknown")
        print(f"outcome=success code={value}{reason_suffix}")
        sys.exit(0)
    if "failure" in outcome:
        value = outcome["failure"]
        if isinstance(value, dict):
            value = value.get("_0", "unknown")
        print(f"outcome=failure code={value}{reason_suffix}")
        sys.exit(0)
    sys.exit(7)

if expected_signal == "nativeDirectCallDiagnosticStatusResult":
    status = body.get("status", {})
    print(
        "state={state} listenerStarted={listener} hasActiveSession={session} activeSessionPhase={phase} lastSignalEventEmitted={event} lastSignalSendAttempted={attempted} lastSignalSendSucceeded={succeeded} lastSignalSendFailureReason={failure} lastTerminalReason={terminal} listenerAttached={attached} listenerHandleRetained={handle_retained} listenerStartCount={start_count} timelineUpdateCount={update_count} timelineDiffReceivedCount={diff_count} lastTimelineDiffKind={diff_kind} lastTimelineDiffItemCount={diff_item_count} timelineEventReceivedCount={event_count} directCallEventTypeSeenCount={type_count} envelopeExtractedCount={extracted_count} envelopeDeliveredToEngineCount={delivered_count} lastReceiveEventKind={receive_kind} lastEnvelopeRejectedReason={rejected_reason} lastReceiveFailureReason={receive_failure} sendRoomFingerprint={send_room} receiveRoomFingerprint={receive_room} mediaFactoryInjected={media_factory} mediaCredentialProviderAvailable={media_credential} mediaE2EEProviderAvailable={media_e2ee} mediaKeyHandleAvailable={media_key_handle} mediaKeyBridgeHit={media_key_bridge} mediaConnectAttempted={media_connect} liveKitClientConnectAttempted={livekit_connect} mediaFailureReason={media_failure}".format(
            state=status.get("state", "unknown"),
            listener=str(status.get("listenerStarted", "unknown")).lower(),
            session=str(status.get("hasActiveSession", "unknown")).lower(),
            phase=status.get("activeSessionPhase", "unknown"),
            event=status.get("lastSignalEventEmitted", "none"),
            attempted=str(status.get("lastSignalSendAttempted", "unknown")).lower(),
            succeeded=str(status.get("lastSignalSendSucceeded", "unknown")).lower(),
            failure=status.get("lastSignalSendFailureReason", "none"),
            terminal=status.get("lastTerminalReason", "none"),
            attached=str(status.get("listenerAttached", "unknown")).lower(),
            handle_retained=str(status.get("listenerHandleRetained", "unknown")).lower(),
            start_count=status.get("listenerStartCount", "unknown"),
            update_count=status.get("timelineUpdateCount", "unknown"),
            diff_count=status.get("timelineDiffReceivedCount", "unknown"),
            diff_kind=status.get("lastTimelineDiffKind", "none"),
            diff_item_count=status.get("lastTimelineDiffItemCount", "unknown"),
            event_count=status.get("timelineEventReceivedCount", "unknown"),
            type_count=status.get("directCallEventTypeSeenCount", "unknown"),
            extracted_count=status.get("envelopeExtractedCount", "unknown"),
            delivered_count=status.get("envelopeDeliveredToEngineCount", "unknown"),
            receive_kind=status.get("lastReceiveEventKind", "none"),
            rejected_reason=status.get("lastEnvelopeRejectedReason", "none"),
            receive_failure=status.get("lastReceiveFailureReason", "none"),
            send_room=status.get("sendRoomFingerprint", "none"),
            receive_room=status.get("receiveRoomFingerprint", "none"),
            media_factory=str(status.get("mediaFactoryInjected", "unknown")).lower(),
            media_credential=str(status.get("mediaCredentialProviderAvailable", "unknown")).lower(),
            media_e2ee=str(status.get("mediaE2EEProviderAvailable", "unknown")).lower(),
            media_key_handle=str(status.get("mediaKeyHandleAvailable", "unknown")).lower(),
            media_key_bridge=str(status.get("mediaKeyBridgeHit", "unknown")).lower(),
            media_connect=str(status.get("mediaConnectAttempted", "unknown")).lower(),
            livekit_connect=str(status.get("liveKitClientConnectAttempted", "unknown")).lower(),
            media_failure=status.get("mediaFailureReason", "none"),
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

    if wait_for_result_until_deadline "$client" "$expected_signal" "$correlation_id" "$deadline"; then
        return 0
    fi

    fail "Timed out waiting for channel=$client correlationID=$correlation_id signal=$expected_signal"
}

wait_for_result_until_deadline() {
    local client="$1"
    local expected_signal="$2"
    local correlation_id="$3"
    local deadline="$4"
    local result=""

    while (( SECONDS <= deadline )); do
        if result="$(extract_result "$client" "$expected_signal" "$correlation_id" 2>/dev/null)"; then
            printf '%s\n' "$result"
            return 0
        fi
        pause_for_poll_interval
    done

    return 1
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

validate_status_name() {
    case "$1" in
        incomingRinging)
            ;;
        *)
            fail "Unsupported status wait target: $1"
            ;;
    esac
}

status_matches_expectation() {
    local status_result="$1"
    local expected="$2"

    case "$expected" in
        incomingRinging)
            [[ "$status_result" == *"state=ringing"* &&
                "$status_result" == *"hasActiveSession=true"* &&
                "$status_result" == *"activeSessionPhase=incomingRinging"* ]]
            ;;
        *)
            return 1
            ;;
    esac
}

status_is_incoming_ringing() {
    local status_result="$1"

    [[ "$status_result" == *"state=ringing"* &&
        "$status_result" == *"hasActiveSession=true"* &&
        "$status_result" == *"activeSessionPhase=incomingRinging"* ]]
}

status_is_active() {
    local status_result="$1"

    [[ "$status_result" == *"state=active"* &&
        "$status_result" == *"hasActiveSession=true"* &&
        "$status_result" == *"activeSessionPhase=active"* ]]
}

status_is_terminal_or_failed() {
    local status_result="$1"

    [[ "$status_result" == *"state=failed"* ||
        "$status_result" == *"state=terminal"* ||
        "$status_result" == *"lastTerminalReason="* &&
        "$status_result" != *"lastTerminalReason=none"* ]]
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
        log "DRY_RUN: set integration env for channel=$client udid=$udid host=<set> username=<set> credential=<redacted> diagnosticEncryption=${NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION:-0}"
        log_livekit_environment_summary
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
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION="${NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION:-}" \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET="${NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET:-}" \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT="${NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT:-}" \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_LIVEKIT_URL="${NATIVE_DIRECT_CALL_LIVEKIT_URL:-}" \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A="${NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A:-}" \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B="${NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B:-}" \
        SIMCTL_CHILD_NATIVE_DIRECT_CALL_LIVEKIT_ROOM="${NATIVE_DIRECT_CALL_LIVEKIT_ROOM:-}" \
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

wait_for_status() {
    local client="$1"
    local expected="$2"
    validate_status_name "$expected"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: wait channel=$client status=$expected timeout=${WAIT_TIMEOUT_SECONDS}s"
        return
    fi

    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    local id
    local result

    while (( SECONDS <= deadline )); do
        id="$(correlation_id "$client" "status-$expected")"
        write_status_request "$client" "$id"

        if result="$(wait_for_result_until_deadline "$client" nativeDirectCallDiagnosticStatusResult "$id" "$deadline")"; then
            log "channel=$client wait-status=$expected correlationID=$id $result"
            if status_matches_expectation "$result" "$expected"; then
                return
            fi
        fi

        pause_for_poll_interval
    done

    fail "Timed out waiting for channel=$client status=$expected"
}

accept_when_ringing() {
    local client="$1"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: wait channel=$client status=incomingRinging-or-active timeout=${WAIT_TIMEOUT_SECONDS}s"
        log "DRY_RUN: send channel=$client command=acceptIncomingCall only if incomingRinging"
        return
    fi

    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    local id
    local result

    while (( SECONDS <= deadline )); do
        id="$(correlation_id "$client" accept-status)"
        write_status_request "$client" "$id"

        if result="$(wait_for_result_until_deadline "$client" nativeDirectCallDiagnosticStatusResult "$id" "$deadline")"; then
            log "channel=$client accept-when-ringing correlationID=$id $result"
            if status_is_incoming_ringing "$result"; then
                send_command "$client" acceptIncomingCall
                return
            fi
            if status_is_active "$result"; then
                log "channel=$client accept-when-ringing already active; accept was not sent again"
                return
            fi
            if status_is_terminal_or_failed "$result"; then
                fail "channel=$client accept-when-ringing observed terminal/failed status: $result"
            fi
        fi

        pause_for_poll_interval
    done

    fail "Timed out waiting for channel=$client incomingRinging or active status"
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
     accept-when-ringing B
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
            log_livekit_environment_summary
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
        wait-status)
            require_host_tools
            require_common_environment
            [[ $# -eq 3 ]] || fail "Usage: $SCRIPT_NAME wait-status A|B incomingRinging"
            wait_for_status "$2" "$3"
            ;;
        accept-when-ringing)
            require_host_tools
            require_common_environment
            [[ $# -eq 2 ]] || fail "Usage: $SCRIPT_NAME accept-when-ringing A|B"
            accept_when_ringing "$2"
            ;;
        *)
            usage
            fail "Unknown action: $action"
            ;;
    esac
}

main "$@"
