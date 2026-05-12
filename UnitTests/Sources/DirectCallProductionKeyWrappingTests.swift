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
final class DirectCallProductionKeyWrappingTests {
    private let callID = "call-a"
    private let roomID = "!room:example.com"
    private let peerUserID = "@peer:example.com"
    private let ownUserID = "@me:example.com"

    @Test
    func failClosedMediaKeyWrapperCannotWrapOrUnwrap() {
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

        #expect(wrapper.wrapMediaKey("sensitive-media-material", request: wrapRequest) == .failure(.e2eeUnavailable))
        #expect(wrapper.unwrapMediaKeyEnvelope(envelope, request: unwrapRequest) == .failure(.e2eeUnavailable))
        #expect(String(describing: wrapper).contains("sensitive-media-material") == false)
        #expect(String(describing: wrapRequest).contains(roomID) == false)
        #expect(String(describing: envelope).contains("opaque-envelope") == false)
    }

    @Test
    func productionEncryptionWithFailClosedWrapperDoesNotPopulateKeyStore() {
        let keyStore = DirectCallLiveKitMediaKeyStore { "key-a" }
        let service = ProductionDirectCallEncryptionService(keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.e2eeUnavailable))
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionWithFakeWrapperStoresGeneratedKeyInSharedStore() throws {
        let keyStore = DirectCallLiveKitMediaKeyStore { "unused-key" }
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            senderDeviceID: "DEVICE",
                                                            now: { Date(timeIntervalSince1970: 0) },
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })

        let result = service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)
        let generated = try result.get()

        #expect(generated.keyHandle == .init(callID: callID, keyID: "key-a"))
        #expect(generated.payload.encryptedPayload == "opaque-key-a")
        #expect(wrapper.wrappedMediaKeys == ["sensitive-media-material"])
        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(String(describing: generated.payload).contains("opaque-key-a") == false)
        #expect(String(describing: wrapper.wrappedRequests[0]).contains(roomID) == false)
    }

    @Test
    func productionEncryptionWithFakeWrapperConsumesKeyIntoSharedStore() throws {
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

        let result = service.consumeRemoteEncryptedKey(payload,
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
    func productionEncryptionRejectsMismatchedWrappedMetadata() {
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

        let result = service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID)

        #expect(result == .failure(.keyMismatch))
        #expect(keyStore.makeKeyProvider(for: .init(callID: callID, keyID: "key-a")) == nil)
    }

    @Test
    func productionEncryptionCleanupClearsSharedKeyStoreIdempotently() throws {
        let keyStore = DirectCallLiveKitMediaKeyStore()
        let wrapper = MediaKeyWrapperSpy()
        let service = ProductionDirectCallEncryptionService(keyWrapper: wrapper,
                                                            keyStore: keyStore,
                                                            ownUserID: ownUserID,
                                                            keyIDProvider: { "key-a" },
                                                            mediaKeyProvider: { "sensitive-media-material" })
        let generated = try service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)

        service.clearPerCallKey(callID: callID)
        service.clearPerCallKey(callID: callID)

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) == nil)
    }

    @Test
    func productionDependenciesFactoryCanShareMediaKeyStoreWithEncryptionService() throws {
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

        let generated = try service.generatePerCallKey(callID: callID, roomID: roomID, peerUserID: peerUserID).get()

        #expect(keyStore.makeKeyProvider(for: generated.keyHandle) != nil)
        #expect(dependencies.hasMediaEngineFactory)
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
                      request: DirectCallMediaKeyWrapRequest) -> Result<DirectCallWrappedMediaKeyEnvelope, DirectCallMediaKeyWrappingFailureReason> {
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
                                request: DirectCallMediaKeyUnwrapRequest) -> Result<DirectCallUnwrappedMediaKey, DirectCallMediaKeyWrappingFailureReason> {
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
