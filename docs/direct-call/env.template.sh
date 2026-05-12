#!/usr/bin/env bash

# Native direct-call local environment template.
#
# Copy this file outside the repository or source it after replacing only local
# placeholders. Do not commit filled-in copies. This template intentionally does
# not contain passwords, Matrix access tokens, LiveKit participant tokens,
# diagnostic secrets, API secrets, raw keys, or homeserver private values.
#
# Example:
#   cp docs/direct-call/env.template.sh /tmp/salemx-directcall-env.sh
#   chmod 600 /tmp/salemx-directcall-env.sh
#   ${EDITOR:-vi} /tmp/salemx-directcall-env.sh
#   source /tmp/salemx-directcall-env.sh

# Debug app built by Xcode.
export SALEMX_APP_PATH="/path/to/DerivedData/Build/Products/Debug-iphonesimulator/SalemX.app"

# Two booted simulator UDIDs.
export SIMULATOR_UDID_A="SIMULATOR-UDID-A"
export SIMULATOR_UDID_B="SIMULATOR-UDID-B"

# Matrix integration-test accounts. Keep passwords out of this template.
export INTEGRATION_TESTS_HOST="https://your-homeserver.example"
export INTEGRATION_TESTS_USERNAME_A="@direct-call-a:example.org"
export INTEGRATION_TESTS_USERNAME_B="@direct-call-b:example.org"
# read -r -s -p "Client A password: " INTEGRATION_TESTS_PASSWORD_A; echo; export INTEGRATION_TESTS_PASSWORD_A
# read -r -s -p "Client B password: " INTEGRATION_TESTS_PASSWORD_B; echo; export INTEGRATION_TESTS_PASSWORD_B

# Diagnostic-only native direct-call gates. These are not production settings.
export NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION="1"
# read -r -s -p "Diagnostic encryption secret: " NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET; echo; export NATIVE_DIRECT_CALL_DIAGNOSTIC_ENCRYPTION_SECRET

# Optional diagnostic-only LiveKit media proof settings. Do not use production
# LiveKit API secrets in the app or in this file.
# export NATIVE_DIRECT_CALL_DIAGNOSTIC_LIVEKIT="1"
# export NATIVE_DIRECT_CALL_LIVEKIT_URL="wss://your-livekit-server.example"
# read -r -s -p "LiveKit token A: " NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A; echo; export NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_A
# read -r -s -p "LiveKit token B: " NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B; echo; export NATIVE_DIRECT_CALL_LIVEKIT_TOKEN_B
# export NATIVE_DIRECT_CALL_LIVEKIT_ROOM="optional-room-name"

# Verification helper defaults. Override when using another simulator.
export DIRECT_CALL_TEST_DESTINATION="platform=iOS Simulator,id=${SIMULATOR_UDID_A}"
