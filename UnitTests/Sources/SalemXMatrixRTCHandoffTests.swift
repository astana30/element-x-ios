//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
final class SalemXMatrixRTCHandoffTests {
    @Test
    func claimedJoinedDMRoomHandsOffToAudioElementCall() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .handedOff(.readyToPresent(.audio(roomID: roomID, intent: .startNew))))
        #expect(elementCallHandoff.calls == [.init(roomID: roomID, intent: .startNew)])
        #expect(clientProxy.roomForIdentifierReceivedIdentifier == roomID)
        #expect(room.getMemberUserIDReceivedInvocations == [localUserID, peerUserID])
    }

    @Test
    func incomingJoinPreservesUnsupportedJoinSemantics() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy { roomID, intent in
            .unsupportedIncomingJoin(.audio(roomID: roomID, intent: intent))
        }
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(direction: .incoming),
                                                    intent: .joinExisting)

        #expect(result == .handedOff(.unsupportedIncomingJoin(.audio(roomID: roomID, intent: .joinExisting))))
        #expect(elementCallHandoff.calls == [.init(roomID: roomID, intent: .joinExisting)])
    }

    @Test
    func malformedClaimedMetadataBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy()
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(peerDeviceID: " "),
                                                    intent: .startNew)

        #expect(result == .blocked(.malformedClaimedMetadata))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func unauthenticatedSessionBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy(userID: "")
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.unauthenticatedSession))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func authenticatedUserMismatchBlocksBeforeRoomLookup() async {
        let clientProxy = makeClientProxy(userID: "@other:matrix.org")
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.authenticatedUserMismatch))
        #expect(clientProxy.roomForIdentifierCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func unjoinedRoomBlocksBeforeHandoff() async {
        let clientProxy = makeClientProxy()
        clientProxy.roomForIdentifierClosure = { _ in .left }
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotJoined))
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func nonDirectRoomBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: false,
                                             members: [.mockMe, .mockAlice]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotDirectOneToOne))
        #expect(room.getMemberUserIDCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func roomWithMoreThanTwoActiveMembersBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockAlice, .mockBob]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.roomNotDirectOneToOne))
        #expect(room.getMemberUserIDCallsCount == 0)
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func peerOutsideRoomBlocksBeforeHandoff() async {
        let room = JoinedRoomProxyMock(.init(id: roomID,
                                             isDirect: true,
                                             members: [.mockMe, .mockBob]))
        let clientProxy = makeClientProxy(roomProxy: room)
        let elementCallHandoff = ElementCallHandoffSpy()
        let handoff = SalemXAuthenticatedMatrixRTCHandoff(clientProxy: clientProxy,
                                                          elementCallHandoff: elementCallHandoff)

        let result = await handoff.prepareAudioCall(claimedMetadata: claimedMetadata(),
                                                    intent: .startNew)

        #expect(result == .blocked(.peerUserNotMember))
        #expect(room.getMemberUserIDReceivedInvocations == [localUserID, peerUserID])
        #expect(elementCallHandoff.calls.isEmpty)
    }

    @Test
    func claimedMetadataDescriptionIsRedacted() {
        let metadata = claimedMetadata()
        let description = String(describing: metadata)

        #expect(!description.contains(roomID))
        #expect(!description.contains(localUserID))
        #expect(!description.contains(peerUserID))
        #expect(!description.contains(peerDeviceID))
        #expect(description.contains("direction: outgoing"))
    }

    @Test
    func handoffResultDescriptionIsRedacted() {
        let result = SalemXMatrixRTCHandoffResult.handedOff(.readyToPresent(.audio(roomID: roomID, intent: .startNew)))
        let description = String(describing: result)

        #expect(!description.contains(roomID))
        #expect(description.contains("readyToPresent"))
    }

    private let roomID = "!room:matrix.org"
    private let localUserID = "@me:matrix.org"
    private let peerUserID = "@alice:matrix.org"
    private let peerDeviceID = "ALICEDEVICE"

    private func claimedMetadata(peerDeviceID: String? = nil,
                                 direction: SalemXMatrixRTCHandoffDirection = .outgoing) -> SalemXMatrixRTCClaimedMetadata {
        .init(roomID: roomID,
              localUserID: localUserID,
              peerUserID: peerUserID,
              peerDeviceID: peerDeviceID ?? self.peerDeviceID,
              direction: direction)
    }

    private func makeClientProxy(userID: String? = nil,
                                 roomProxy: JoinedRoomProxyProtocol? = nil) -> ClientProxyMock {
        let clientProxy = ClientProxyMock(.init(userID: userID ?? localUserID))
        clientProxy.roomForIdentifierClosure = { requestedRoomID in
            guard requestedRoomID == roomID, let roomProxy else {
                return nil
            }

            return .joined(roomProxy)
        }
        return clientProxy
    }

    private struct ElementCallHandoffCall: Equatable {
        let roomID: String
        let intent: EmbeddedElementCallHandoffIntent
    }

    private final class ElementCallHandoffSpy: EmbeddedElementCallHandoff {
        private let result: (String, EmbeddedElementCallHandoffIntent) -> EmbeddedElementCallHandoffResult
        private(set) var calls = [ElementCallHandoffCall]()

        init(result: @escaping (String, EmbeddedElementCallHandoffIntent) -> EmbeddedElementCallHandoffResult = { roomID, intent in
            .readyToPresent(.audio(roomID: roomID, intent: intent))
        }) {
            self.result = result
        }

        func prepareAudioCall(roomID: String, intent: EmbeddedElementCallHandoffIntent) async -> EmbeddedElementCallHandoffResult {
            calls.append(.init(roomID: roomID, intent: intent))
            return result(roomID, intent)
        }
    }
}
