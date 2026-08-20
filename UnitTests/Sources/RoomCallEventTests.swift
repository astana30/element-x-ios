//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import MatrixRustSDK
import Testing

struct RoomCallEventTests {
    @Test
    func titleIncludesCallTypeForKnownIntent() {
        let event = RoomCallEvent(state: .missed, intent: .video)

        #expect(event.title == "\(UntranslatedL10n.commonMissedCall) · \(L10n.commonAudio)")
        #expect(event.kindLabel == L10n.commonAudio)
    }

    @Test
    func titleKeepsBaseStringForUnknownIntent() {
        let event = RoomCallEvent(state: .answered, intent: .unknown)

        #expect(event.title == UntranslatedL10n.commonCallAnswered)
    }

    @Test
    func statusTitleKeepsTheCallStateOnly() {
        let event = RoomCallEvent(state: .missed, intent: .video)

        #expect(event.statusTitle == UntranslatedL10n.commonMissedCall)
    }

    @Test
    func callRejectUsesTheLocalPerspective() {
        let declinedCall = RoomCallEventParser.parse(content: makeCallContent(eventType: .callReject),
                                                     isOutgoing: true)
        #expect(declinedCall?.statusTitle == UntranslatedL10n.commonDeclinedCall)

        let missedCall = RoomCallEventParser.parse(content: makeCallContent(eventType: .callReject),
                                                   isOutgoing: false)
        #expect(missedCall?.statusTitle == UntranslatedL10n.commonMissedCall)
    }

    @Test
    func rawJsonPreservesVideoIntentForCallEvents() {
        let event = RoomCallEventParser.parse(content: makeCallContent(eventType: .callHangup),
                                              rawJSONString: makeCallJSON(callIntent: "video"),
                                              isOutgoing: true)

        #expect(event?.intent == .video)
        #expect(event?.statusTitle == UntranslatedL10n.commonCallEnded)
    }

    private func makeCallContent(eventType: MessageLikeEventType) -> TimelineItemContent {
        .msgLike(content: .init(kind: .other(eventType: eventType),
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }

    private func makeCallJSON(callIntent: String) -> String {
        """
        {
          "content": {
            "call_intent": "\(callIntent)"
          }
        }
        """
    }
}
