//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

@MainActor
final class DirectCallProductionKeyWrappingTests {
    private let callID = "call-a"
    private let roomID = "!room:example.com"
    private let peerUserID = "@peer:example.com"
    private let ownUserID = "@me:example.com"

    @Test
    func failClosedMediaKeyWrapperCannotWrapOrUnwrap() async {
        let wrapper = FailClosedDirectCallMediaKeyWrapper()
        let wrapRequest = DirectCallMediaKeyWrapRequest(callID: callID,
                                                        roomID: roomID,
                                                        senderUserID: ownUserID,
                                                        recipientUserID: peerUserID,
                                                        senderDeviceID: "DEVICE",
                                                        intent: .audio,
                                                        expiresAt: .now,
                                                        keyID: "key-a")
        let envelope = DirectCallWrappedMediaKeyEnvelope(algorithm: "test",
                                                         callID: callID,
                                                         roomID: roomID,
                                                         senderUserID: ownUserID,
                                                         recipientUserID: peerUserID,
                                                         senderDeviceID: "DEVICE",
                                                         intent: .audio,
                                                         expiresAt: .now,
                                                         keyID: "key-a",
                                                         opaqueEnvelope: "opaque-envelope")
        let unwrapRequest = DirectCallMediaKeyUnwrapRequest(expectedCallID: callID,
                                                            expectedRoomID: roomID,
                                                            expectedSenderUserID: peerUserID,
                                                            recipientUserID: ownUserID,
                                                            recipientDeviceID: "DEVICE",
                                                            intent: .audio,
                                                            receivedAt: .now)

        #expect(await wrapper.wrapMediaKey("sensitive-media-material", request: wrapRequest) == .failure(.e2eeUnavailable))
        #expect(await wrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) == .failure(.e2eeUnavailable))
        #expect(String(describing: wrapper).contains("sensitive-media-material") == false)
        #expect(String(describing: wrapRequest).contains(roomID) == false)
        #expect(String(describing: envelope).contains("opaque-envelope") == false)
    }

    @Test
    func productionEncryptionWithFailClosedWrapperDoesNotPopulateKeyStore() async {
        let keyStore = DirectCallLiveKitMediaKeyStore { "key-a" }
        let service = ProductionDirectCallEncryptionService(keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.e2eeUnavailable))
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionWithFakeWrapperStoresGeneratedKeyInSharedStore() async throws {
        let keyStore = DirectCallLiveKitMediaKeyStore { "unused-key" }
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            now: { Date(timeIntervalSince1970: 0) },
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)
        let generated = try result.get()

        #expect(generated.keyHandle == .init(callID: callID, keyID: "key-a"))
        #expect(generated.payload.encryptedPayload == "opaque-key-a")
        #expect(wrapper.wrappedMediaKeys == ["sensitive-media-material"])
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(String(describing: generated.payload).contains("opaque-key-a") == false)
        #expect(String(describing: wrapper.wrappedRequests[0]).contains(roomID) == false)
    }

    @Test
    func productionEncryptionWithFakeWrapperConsumesKeyIntoSharedStore() async throws {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy(unwrappedMediaKey: "sensitive-peer-media-material")
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE") {
            Date(timeIntervalSince1970: 0)
        }
        let payload = DirectCallEncryptedKeyExchangePayload(callID: callID,
                                                            roomID: roomID,
                                                            senderUserID: peerUserID,
                                                            keyID: "key-a",
                                                            encryptedPayload: "opaque-key-a")

        let result = await service.consumeRemoteEncryptedKey(payload,
                                                             expectedCallID: callID,
                                                             expectedRoomID: roomID,
                                                             expectedSenderUserID: peerUserID)
        let keyHandle = try result.get()

        #expect(keyHandle == .init(callID: callID, keyID: "key-a"))
        #expect(wrapper.unwrappedEnvelopes.map(\.opaqueEnvelope) == ["opaque-key-a"])
        #expect(keyStore.makeKeyProvider(for: keyHandle) != nil)
        #expect(String(describing: DirectCallUnwrappedMediaKey(mediaKey: "sensitive-peer-media-material", keyID: "key-a")).contains("sensitive-peer-media-material") == false)
    }

    @Test
    func productionEncryptionRejectsMismatchedWrappedMetadata() async {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy(envelopeOverride: .init(algorithm: "test",
                                                                 callID: "other-call",
                                                                 roomID: roomID,
                                                                 senderUserID: ownUserID,
                                                                 recipientUserID: peerUserID,
                                                                 intent: .audio,
                                                                 expiresAt: .now,
                                                                 keyID: "key-a",
                                                                 opaqueEnvelope: "opaque-key-a"))
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.keyMismatch))
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionCleanupClearsSharedKeyStoreIdempotently() async throws {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })
        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)

        service.clearPerCallKey(callID: callID)
        service.clearPerCallKey(callID: callID)

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) == nil)
    }

    @Test
    func productionDependenciesFactoryCanShareMediaKeyStoreWithEncryptionService() async throws {
        let endpointURL = try #require(URL(string: "https://call-service.example.com/direct-calls"))
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy()
        let configuration = NativeDirectCallProductionConfiguration(isEnabled: true,
                                                                    liveKitConfiguration: .init(tokenEndpointURL: endpointURL))
        let factory = NativeDirectCallProductionDependenciesFactory(configuration: configuration,
                                                                    liveKitClient: ProductionKeyWrappingLiveKitClientSpy(),
                                                                    keyWrapper: wrapper,
                                                                    mediaKeyStore: keyStore,
                                                                    ownUserID: ownUserID,
                                                                    senderDeviceID: "DEVICE")
        let dependencies = factory.makeDependencies()
        let service = try #require(dependencies.encryptionService)

        let generated = try await service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(dependencies.hasMediaEngineFactory)
    }

    @Test
    func matrixSDKWrapperFailsClosedWithoutSDKDependency() async {
        let wrapper = MatrixSDKDirectCallMediaKeyWrapper()
        let wrapRequest = makeWrapRequest()
        let envelope = makeWrappedEnvelope()
        let unwrapRequest = makeUnwrapRequest()

        #expect(await wrapper.wrapMediaKey("sensitive-media-material", request: wrapRequest) == .failure(.e2eeUnavailable))
        #expect(await wrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) == .failure(.e2eeUnavailable))
        #expect(String(describing: wrapper).contains("sensitive-media-material") == false)
        #expect(String(reflecting: wrapper).contains("sensitive-media-material") == false)
    }

    @Test
    func matrixSDKWrapperMapsWrapRequestAndEnvelopeWithoutLeakingKeyMaterial() async throws {
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapEnvelope: makeSDKEnvelope())
        let wrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: sdk, trustRequirement: .allDevices)
        let request = makeWrapRequest(expiresAt: Date(timeIntervalSince1970: 2))

        let result = await wrapper.wrapMediaKey("sensitive-media-material", request: request)
        let envelope = try result.get()

        let sdkInfo = try #require(sdk.wrapInfos.first)
        #expect(sdkInfo.roomId == roomID)
        #expect(sdkInfo.callId == callID)
        #expect(sdkInfo.recipientUserId == peerUserID)
        #expect(sdkInfo.intent == DirectCallIntent.audio.rawValue)
        #expect(sdkInfo.keyId == "key-a")
        #expect(sdkInfo.expiresAtMs == 2000)
        #expect(sdkInfo.mediaKey == "sensitive-media-material")
        #expect(sdkInfo.trustRequirement == .allDevices)
        #expect(envelope.callID == callID)
        #expect(envelope.roomID == roomID)
        #expect(envelope.senderUserID == ownUserID)
        #expect(envelope.recipientUserID == peerUserID)
        #expect(envelope.opaqueEnvelope == "sdk-opaque-envelope")
        #expect(String(describing: envelope).contains("sdk-opaque-envelope") == false)
    }

    @Test
    func matrixSDKWrapperMapsUnwrapRequestAndResultWithoutLeakingKeyMaterial() async throws {
        let sdk = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(unwrapResult: .init(keyId: "key-a",
                                                                                    mediaKey: "sensitive-peer-media-material",
                                                                                    senderUserId: peerUserID,
                                                                                    senderDeviceId: "PEER_DEVICE"))
        let wrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: sdk)
        let envelope = makeWrappedEnvelope(senderUserID: peerUserID,
                                           recipientUserID: ownUserID,
                                           opaqueEnvelope: "sdk-opaque-envelope")
        let request = makeUnwrapRequest(receivedAt: Date(timeIntervalSince1970: 3))

        let result = await wrapper.unwrapMediaKeyEnvelope(envelope, request: request)
        let unwrapped = try result.get()

        let sdkInfo = try #require(sdk.unwrapInfos.first)
        let sdkEnvelope = try #require(sdk.unwrapEnvelopes.first)
        #expect(sdkInfo.roomId == roomID)
        #expect(sdkInfo.callId == callID)
        #expect(sdkInfo.expectedSenderUserId == peerUserID)
        #expect(sdkInfo.expectedRecipientUserId == ownUserID)
        #expect(sdkInfo.intent == DirectCallIntent.audio.rawValue)
        #expect(sdkInfo.keyId == "key-a")
        #expect(sdkInfo.receivedAtMs == 3000)
        #expect(sdkEnvelope.opaqueCiphertext == "sdk-opaque-envelope")
        #expect(unwrapped.keyID == "key-a")
        #expect(unwrapped.mediaKey == "sensitive-peer-media-material")
        #expect(String(describing: unwrapped).contains("sensitive-peer-media-material") == false)
    }

    @Test
    func matrixSDKWrapperMapsSDKFailuresToFailClosedReasons() async {
        let trustFailureSDK = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(wrapError: DirectCallMediaKeyEnvelopeError.TrustViolation)
        let metadataFailureSDK = MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy(unwrapError: DirectCallMediaKeyEnvelopeError.MalformedEnvelope)
        let wrappingWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: trustFailureSDK)
        let unwrappingWrapper = MatrixSDKDirectCallMediaKeyWrapper(envelopeWrapper: metadataFailureSDK)

        #expect(await wrappingWrapper.wrapMediaKey("sensitive-media-material",
                                                   request: makeWrapRequest()) == .failure(.e2eeUnavailable))
        #expect(await unwrappingWrapper.unwrapMediaKeyEnvelope(makeWrappedEnvelope(),
                                                               request: makeUnwrapRequest()) == .failure(.invalidMetadata))
    }

    private func makeWrapRequest(expiresAt: Date = Date(timeIntervalSince1970: 1)) -> DirectCallMediaKeyWrapRequest {
        .init(callID: callID,
              roomID: roomID,
              senderUserID: ownUserID,
              recipientUserID: peerUserID,
              senderDeviceID: "DEVICE",
              intent: .audio,
              expiresAt: expiresAt,
              keyID: "key-a")
    }

    private func makeUnwrapRequest(receivedAt: Date = Date(timeIntervalSince1970: 1)) -> DirectCallMediaKeyUnwrapRequest {
        .init(expectedCallID: callID,
              expectedRoomID: roomID,
              expectedSenderUserID: peerUserID,
              recipientUserID: ownUserID,
              recipientDeviceID: "DEVICE",
              intent: .audio,
              receivedAt: receivedAt)
    }

    private func makeWrappedEnvelope(senderUserID: String? = nil,
                                     recipientUserID: String? = nil,
                                     opaqueEnvelope: String = "opaque-key-a") -> DirectCallWrappedMediaKeyEnvelope {
        .init(algorithm: "salemx.native_direct_call.media_key.v1",
              callID: callID,
              roomID: roomID,
              senderUserID: senderUserID ?? ownUserID,
              recipientUserID: recipientUserID ?? peerUserID,
              senderDeviceID: "DEVICE",
              intent: .audio,
              expiresAt: Date(timeIntervalSince1970: 1),
              keyID: "key-a",
              opaqueEnvelope: opaqueEnvelope)
    }

    private func makeSDKEnvelope() -> MatrixRustSDK.DirectCallMediaKeyEnvelope {
        .init(version: 1,
              algorithm: "salemx.native_direct_call.media_key.v1",
              roomId: roomID,
              callId: callID,
              senderUserId: ownUserID,
              recipientUserId: peerUserID,
              intent: DirectCallIntent.audio.rawValue,
              keyId: "key-a",
              expiresAtMs: 1000,
              opaqueCiphertext: "sdk-opaque-envelope")
    }
}

private final class MatrixSDKDirectCallMediaKeyEnvelopeWrapperSpy: MatrixSDKDirectCallMediaKeyEnvelopeWrappingProtocol {
    private let wrapEnvelope: MatrixRustSDK.DirectCallMediaKeyEnvelope
    private let unwrapResult: MatrixRustSDK.DirectCallMediaKeyUnwrapResult
    private let wrapError: Error?
    private let unwrapError: Error?

    private(set) var wrapInfos = [MatrixRustSDK.DirectCallMediaKeyWrapInfo]()
    private(set) var unwrapInfos = [MatrixRustSDK.DirectCallMediaKeyUnwrapInfo]()
    private(set) var unwrapEnvelopes = [MatrixRustSDK.DirectCallMediaKeyEnvelope]()

    init(wrapEnvelope: MatrixRustSDK.DirectCallMediaKeyEnvelope? = nil,
         unwrapResult: MatrixRustSDK.DirectCallMediaKeyUnwrapResult? = nil,
         wrapError: Error? = nil,
         unwrapError: Error? = nil) {
        self.wrapEnvelope = wrapEnvelope ?? .init(version: 1,
                                                  algorithm: "salemx.native_direct_call.media_key.v1",
                                                  roomId: "!room:example.com",
                                                  callId: "call-a",
                                                  senderUserId: "@me:example.com",
                                                  recipientUserId: "@peer:example.com",
                                                  intent: DirectCallIntent.audio.rawValue,
                                                  keyId: "key-a",
                                                  expiresAtMs: 1000,
                                                  opaqueCiphertext: "sdk-opaque-envelope")
        self.unwrapResult = unwrapResult ?? .init(keyId: "key-a",
                                                  mediaKey: "sensitive-media-material",
                                                  senderUserId: "@peer:example.com",
                                                  senderDeviceId: "PEER_DEVICE")
        self.wrapError = wrapError
        self.unwrapError = unwrapError
    }

    func wrapDirectCallMediaKey(info: MatrixRustSDK.DirectCallMediaKeyWrapInfo) async throws -> MatrixRustSDK.DirectCallMediaKeyEnvelope {
        wrapInfos.append(info)

        if let wrapError {
            throw wrapError
        }

        return wrapEnvelope
    }

    func unwrapDirectCallMediaKeyEnvelope(info: MatrixRustSDK.DirectCallMediaKeyUnwrapInfo,
                                          envelope: MatrixRustSDK.DirectCallMediaKeyEnvelope) async throws -> MatrixRustSDK.DirectCallMediaKeyUnwrapResult {
        unwrapInfos.append(info)
        unwrapEnvelopes.append(envelope)

        if let unwrapError {
            throw unwrapError
        }

        return unwrapResult
    }
}

@MainActor
private final class MediaKeyWrapperSpy: DirectCallMediaKeyWrappingProtocol {
    private let envelopeOverride: DirectCallWrappedMediaKeyEnvelope?
    private let wrapFailure: DirectCallMediaKeyWrappingFailureReason?
    private let unwrapFailure: DirectCallMediaKeyWrappingFailureReason?
    private let unwrappedMediaKey: String

    private(set) var wrappedMediaKeys = [String]()
    private(set) var wrappedRequests = [DirectCallMediaKeyWrapRequest]()
    private(set) var unwrappedEnvelopes = [DirectCallWrappedMediaKeyEnvelope]()
    private(set) var unwrappedRequests = [DirectCallMediaKeyUnwrapRequest]()

    init(envelopeOverride: DirectCallWrappedMediaKeyEnvelope? = nil,
         wrapFailure: DirectCallMediaKeyWrappingFailureReason? = nil,
         unwrapFailure: DirectCallMediaKeyWrappingFailureReason? = nil,
         unwrappedMediaKey: String = "sensitive-media-material") {
        self.envelopeOverride = envelopeOverride
        self.wrapFailure = wrapFailure
        self.unwrapFailure = unwrapFailure
        self.unwrappedMediaKey = unwrappedMediaKey
    }

    func wrapMediaKey(_ mediaKey: String,
                      request: DirectCallMediaKeyWrapRequest) async -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason> {
        wrappedMediaKeys.append(mediaKey)
        wrappedRequests.append(request)

        if let wrapFailure {
            return .failure(wrapFailure)
        }

        if let envelopeOverride {
            return .success(envelopeOverride)
        }

        return .success(.init(algorithm: "test",
                              callID: request.callID,
                              roomID: request.roomID,
                              senderUserID: request.senderUserID,
                              recipientUserID: request.recipientUserID,
                              senderDeviceID: request.senderDeviceID,
                              intent: request.intent,
                              expiresAt: request.expiresAt,
                              keyID: request.keyID,
                              opaqueEnvelope: "opaque-\(request.keyID)"))
    }

    func unwrapMediaKeyEnvelope(_ envelope: DirectCallWrappedMediaKeyEnvelope,
                                request: DirectCallMediaKeyUnwrapRequest) async -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason> {
        unwrappedEnvelopes.append(envelope)
        unwrappedRequests.append(request)

        if let unwrapFailure {
            return .failure(unwrapFailure)
        }

        return .success(.init(mediaKey: unwrappedMediaKey, keyID: envelope.keyID))
    }
}

@MainActor
private final class ProductionKeyWrappingLiveKitClientSpy: DirectCallLiveKitClientProtocol {
    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        .success(())
    }

    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        .success(())
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        .success(())
    }

    func disconnect() async { }

    func cleanup() async { }
}
