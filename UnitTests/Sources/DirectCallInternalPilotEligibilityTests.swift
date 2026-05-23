//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
final class DirectCallInternalPilotEligibilityTests {
    init() async throws {
        AppSettings.resetAllSettings()
    }

    deinit {
        AppSettings.resetAllSettings()
    }

    @Test
    func failClosedInternalPilotEligibilityProviderIsDisabledByDefault() async {
        let provider = FailClosedNativeDirectCallInternalPilotEligibilityProvider()

        let eligibility = await provider.nativeDirectCallInternalPilotEligibility()

        #expect(eligibility == .disabled)
        #expect(eligibility.isEligible == false)
        assertEligibilityOutputIsRedacted(eligibility)
        #expect(String(describing: provider).contains("directOneToOneCallsEnabled") == false)
    }

    @Test
    func directOneToOneCallsSettingDoesNotEnableInternalPilotEligibility() async {
        let appSettings = AppSettings()
        appSettings.directOneToOneCallsEnabled = true
        let provider = FailClosedNativeDirectCallInternalPilotEligibilityProvider()

        let eligibility = await provider.nativeDirectCallInternalPilotEligibility()

        #expect(appSettings.directOneToOneCallsEnabled)
        #expect(eligibility == .disabled)
        #expect(eligibility.isEligible == false)
    }

    @Test
    func internalPilotEligibilityPayloadDecodesRedactedStates() throws {
        let decoder = NativeDirectCallInternalPilotEligibilityPayloadDecoder()
        let eligiblePayload = try JSONEncoder().encode(NativeDirectCallInternalPilotEligibilityPayload(state: .eligible,
                                                                                                       accountEligible: true,
                                                                                                       peerEligible: true,
                                                                                                       roomEligible: true,
                                                                                                       trustReady: true,
                                                                                                       serviceAvailable: true,
                                                                                                       clientSupported: true))

        let eligibility = decoder.decodeEligibility(from: eligiblePayload)

        #expect(eligibility == .eligible)
        #expect(eligibility.isEligible)
        assertEligibilityOutputIsRedacted(eligibility)
        #expect(String(describing: decoder).contains("redacted: true"))
    }

    @Test
    func internalPilotEligibilityPayloadDecodesUnavailableReasons() {
        let decoder = NativeDirectCallInternalPilotEligibilityPayloadDecoder()
        let cases: [(String, NativeDirectCallInternalPilotEligibility)] = [
            (#"{"state":"unavailable","reason":"accountNotEligible","account_eligible":false}"#, .unavailable(reason: .accountNotEligible)),
            (#"{"state":"unavailable","reason":"peerNotEligible","peer_eligible":false}"#, .unavailable(reason: .peerNotEligible)),
            (#"{"state":"unavailable","reason":"roomNotEligible","room_eligible":false}"#, .unavailable(reason: .roomNotEligible)),
            (#"{"state":"unavailable","reason":"trustNotReady","trust_ready":false}"#, .unavailable(reason: .trustNotReady)),
            (#"{"state":"unavailable","reason":"serviceUnavailable","service_available":false}"#, .unavailable(reason: .serviceUnavailable)),
            (#"{"state":"unavailable","reason":"capabilityMissing"}"#, .unavailable(reason: .capabilityMissing)),
            (#"{"state":"unavailable","reason":"unsupportedClient","client_supported":false}"#, .unavailable(reason: .unsupportedClient)),
            (#"{"state":"unavailable"}"#, .unavailable(reason: .unknown)),
            (#"{"state":"disabled"}"#, .disabled),
            (#"{"state":"unsupported"}"#, .unsupported),
            (#"{"state":"failClosed"}"#, .failClosed)
        ]

        for (payload, expectedEligibility) in cases {
            let eligibility = decoder.decodeEligibility(from: Data(payload.utf8))

            #expect(eligibility == expectedEligibility)
            #expect(eligibility.isEligible == false)
            assertEligibilityOutputIsRedacted(eligibility)
        }
    }

    @Test
    func missingOrMalformedInternalPilotEligibilityFailsClosed() {
        let decoder = NativeDirectCallInternalPilotEligibilityPayloadDecoder()
        let cases = [
            Data(),
            Data("{}".utf8),
            Data(#"{"state":true}"#.utf8),
            Data(#"{"state":"unavailable","reason":"@alice:example.com"}"#.utf8)
        ]

        for payload in cases {
            let eligibility = decoder.decodeEligibility(from: payload)

            #expect(eligibility == .failClosed)
            #expect(eligibility.isEligible == false)
        }
    }

    @Test
    func internalPilotUnavailableReasonsMapToUserSafeCardCopy() {
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.accountNotEligible) == .accountNotEligible)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.peerNotEligible) == .peerNotEligible)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.roomNotEligible) == .roomNotOneToOne)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.trustNotReady) == .peerTrustUnavailable)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.serviceUnavailable) == .callServiceUnavailable)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.capabilityMissing) == .serverUnsupported)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.unsupportedClient) == .serverUnsupported)
        #expect(NativeDirectCallUserSafeReasonMapper.unavailableReason(.unknown) == .unknown)

        let accountState = NativeDirectCallRoomCardState.unavailable(reason: .accountNotEligible)
        let peerState = NativeDirectCallRoomCardState.unavailable(reason: .peerNotEligible)
        #expect(accountState.displayText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHere)
        #expect(accountState.detailText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHereDetail)
        #expect(peerState.displayText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHere)
        #expect(peerState.detailText == UntranslatedL10n.screenRoomNativeDirectCallNotAvailableHereDetail)
    }

    #if DEBUG
    @Test
    func productUIGateAloneDoesNotEnablePrivateDogfoodOrProductionStart() {
        let productOnlyEnvironment = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCT_UI_ENABLED": "1"
        ]

        #expect(ProcessInfo.isNativeDirectCallProductUIEnabled(environment: productOnlyEnvironment))
        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: productOnlyEnvironment) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: productOnlyEnvironment) == false)
    }

    @Test
    func privateDogfoodGateRequiresDebugIntegrationHarness() {
        let dogfoodWithoutHarness = [
            "NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED": "1"
        ]
        let dogfoodWithHarness = [
            "IS_RUNNING_INTEGRATION_TESTS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS": "1",
            "NATIVE_DIRECT_CALL_DIAGNOSTICS_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRIVATE_DOGFOOD_ENABLED": "1",
            "NATIVE_DIRECT_CALL_PRODUCTION_START_ENABLED": "1"
        ]

        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: dogfoodWithoutHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: dogfoodWithoutHarness) == false)
        #expect(ProcessInfo.isNativeDirectCallPrivateDogfoodEnabled(environment: dogfoodWithHarness))
        #expect(ProcessInfo.isNativeDirectCallProductionStartEnabled(environment: dogfoodWithHarness))
    }
    #endif

    private func assertEligibilityOutputIsRedacted(_ eligibility: NativeDirectCallInternalPilotEligibility) {
        let description = String(describing: eligibility)
        let forbiddenFragments = [
            "!room",
            "@alice",
            "device",
            "participant_" + "token",
            "access_" + "token",
            "bearer",
            "j" + "wt",
            "livekit",
            "room_name",
            "raw " + "key",
            "matrix.example.com",
            "redis://"
        ]

        for fragment in forbiddenFragments {
            #expect(description.localizedCaseInsensitiveContains(fragment) == false)
        }
    }
}
