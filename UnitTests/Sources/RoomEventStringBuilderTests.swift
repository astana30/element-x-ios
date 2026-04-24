//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

struct RoomEventStringBuilderTests {
    private let ownUserID: String
    private let stringBuilder: RoomEventStringBuilder
    
    init() {
        ownUserID = "@alice:matrix.org"
        let stateEventStringBuilder = RoomStateEventStringBuilder(userID: ownUserID)
        let attributedStringBuilder = AttributedStringBuilder(mentionBuilder: MentionBuilder())
        
        stringBuilder = RoomEventStringBuilder(stateEventStringBuilder: stateEventStringBuilder,
                                               messageEventStringBuilder: RoomMessageEventStringBuilder(attributedStringBuilder: attributedStringBuilder,
                                                                                                        destination: .roomList),
                                               shouldDisambiguateDisplayNames: true,
                                               shouldPrefixSenderName: true)
    }
    
    @Test
    func senderPrefix() {
        let ownMessageString = buildAttributedString(for: makeMessageContent(message: "Hello, World!"),
                                                     senderID: ownUserID,
                                                     senderDisplayName: "Alice")
        #expect(ownMessageString?.string == "\(L10n.commonYou): Hello, World!", "Your own messages should be prefixed with 'You'")
        
        let otherMessageString = buildAttributedString(for: makeMessageContent(message: "Hello, World!"),
                                                       senderID: "@bob:matrix.org",
                                                       senderDisplayName: "Bob")
        #expect(otherMessageString?.string == "Bob: Hello, World!", "Everyone else's messages should be prefixed with their display name.")
        
        let ambiguousMessageString = buildAttributedString(for: makeMessageContent(message: "Hello, World!"),
                                                           senderID: "@charlie:matrix.org",
                                                           senderDisplayName: "Charlie",
                                                           senderDisplayNameAmbiguous: true)
        #expect(ambiguousMessageString?.string == "Charlie (@charlie:matrix.org): Hello, World!",
                "Messages from senders with ambiguous display names should include their user ID in the prefix.")
        
        let ownEmoteString = buildAttributedString(for: makeEmoteContent(message: "laughs"),
                                                   senderID: ownUserID,
                                                   senderDisplayName: "Alice")
        #expect(ownEmoteString?.string == L10n.commonEmote("Alice", "laughs"), "Your own emotes shouldn't contain 'You'")
        
        let otherEmoteString = buildAttributedString(for: makeEmoteContent(message: "sighs"),
                                                     senderID: "@bob:matrix.org",
                                                     senderDisplayName: "Bob")
        #expect(otherEmoteString?.string == L10n.commonEmote("Bob", "sighs"), "Everyone else's emotes should contain their display name.")
        
        let ownPollString = buildAttributedString(for: makePollContent(question: "Which is better?"),
                                                  senderID: ownUserID,
                                                  senderDisplayName: "Alice")
        #expect(ownPollString?.string == "\(L10n.commonYou): \(L10n.commonPollSummary("Which is better?"))", "Your own polls should be prefixed with 'You'")
        
        let otherPollString = buildAttributedString(for: makePollContent(question: "Which is better?"),
                                                    senderID: "@bob:matrix.org",
                                                    senderDisplayName: "Bob")
        #expect(otherPollString?.string == "Bob: \(L10n.commonPollSummary("Which is better?"))", "Everyone else's polls should be prefixed with their display name.")
    }

    @Test
    func callStatusStrings() {
        let ownAnsweredCallString = buildAttributedString(for: makeCallContent(eventType: .callAnswer),
                                                          senderID: ownUserID,
                                                          senderDisplayName: "Alice")
        #expect(ownAnsweredCallString?.string == "\(L10n.commonYou): \(UntranslatedL10n.commonCallAnswered)",
                "Answered calls should use a natural full status string.")

        let ownDeclinedCallString = buildAttributedString(for: makeCallContent(eventType: .callReject),
                                                          senderID: ownUserID,
                                                          senderDisplayName: "Alice")
        #expect(ownDeclinedCallString?.string == "\(L10n.commonYou): \(UntranslatedL10n.commonDeclinedCall)",
                "Your own declined calls should stay declined.")

        let otherMissedCallString = buildAttributedString(for: makeCallContent(eventType: .callReject),
                                                          senderID: "@bob:matrix.org",
                                                          senderDisplayName: "Bob")
        #expect(otherMissedCallString?.string == "Bob: \(UntranslatedL10n.commonMissedCall)",
                "Remote decline should read as a missed call for the caller.")
    }
    
    // MARK: - Helpers

    private func buildAttributedString(for content: TimelineItemContent,
                                       senderID: String,
                                       senderDisplayName: String? = nil,
                                       senderDisplayNameAmbiguous: Bool = false) -> AttributedString? {
        stringBuilder.buildAttributedString(for: content,
                                            sender: .init(senderID: senderID,
                                                          senderProfile: .ready(displayName: senderDisplayName,
                                                                                displayNameAmbiguous: senderDisplayNameAmbiguous,
                                                                                avatarUrl: nil)),
                                            isOutgoing: senderID == ownUserID)
    }

    private func makeMessageContent(message: String) -> TimelineItemContent {
        .msgLike(content: .init(kind: .message(content: .init(msgType: .text(content: .init(body: message, formatted: nil)),
                                                              body: message,
                                                              isEdited: false,
                                                              mentions: nil)),
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }
    
    private func makeEmoteContent(message: String) -> TimelineItemContent {
        .msgLike(content: .init(kind: .message(content: .init(msgType: .emote(content: .init(body: message, formatted: nil)),
                                                              body: message,
                                                              isEdited: false,
                                                              mentions: nil)),
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }
    
    private func makePollContent(question: String) -> TimelineItemContent {
        .msgLike(content: .init(kind: .poll(question: question,
                                            kind: .disclosed,
                                            maxSelections: 1,
                                            answers: [],
                                            votes: [:],
                                            endTime: nil,
                                            hasBeenEdited: false),
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }

    private func makeCallContent(eventType: MessageLikeEventType) -> TimelineItemContent {
        .msgLike(content: .init(kind: .other(eventType: eventType),
                                reactions: [],
                                inReplyTo: nil,
                                threadRoot: nil,
                                threadSummary: nil))
    }
}
