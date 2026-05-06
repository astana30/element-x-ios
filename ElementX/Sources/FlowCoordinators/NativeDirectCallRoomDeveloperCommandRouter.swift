//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

struct NativeDirectCallRoomDeveloperCommandConfiguration: Equatable {
    let isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

enum NativeDirectCallRoomDeveloperCommandError: Error, Equatable {
    case disabled
    case unavailable
    case owner(NativeDirectCallRoomFlowOwnerError)
}

@MainActor
protocol NativeDirectCallRoomDeveloperCommanding: AnyObject {
    var isListenerStarted: Bool { get }
    var activeSession: DirectCallSession? { get }

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError>
    func startListener() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError>
    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError>
    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError>
    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError>
    func stop() -> Result<Void, NativeDirectCallRoomDeveloperCommandError>
    func reset() async -> Result<Void, NativeDirectCallRoomDeveloperCommandError>
}

@MainActor
final class NativeDirectCallRoomDeveloperCommandRouter: NativeDirectCallRoomDeveloperCommanding {
    private let configuration: NativeDirectCallRoomDeveloperCommandConfiguration
    private let ownerProvider: () -> NativeDirectCallRoomFlowOwning?

    var isListenerStarted: Bool {
        guard configuration.isEnabled, let owner = ownerProvider() else {
            return false
        }

        return owner.isListenerStarted
    }

    var activeSession: DirectCallSession? {
        guard configuration.isEnabled, let owner = ownerProvider() else {
            return nil
        }

        return owner.activeSession
    }

    init(configuration: NativeDirectCallRoomDeveloperCommandConfiguration = .init(),
         ownerProvider: @escaping () -> NativeDirectCallRoomFlowOwning?) {
        self.configuration = configuration
        self.ownerProvider = ownerProvider
    }

    func prepare() -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return owner.prepare()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func startListener() async -> Result<NativeDirectCallComposition, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.startListener()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func startOutgoingAudioCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.startOutgoingAudioCall()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func acceptIncomingCall() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.acceptIncomingCall()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func hangup() async -> Result<DirectCallSession, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            return await owner.hangup()
                .mapError { .owner($0) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func stop() -> Result<Void, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            owner.stop()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func reset() async -> Result<Void, NativeDirectCallRoomDeveloperCommandError> {
        switch makeOwner() {
        case .success(let owner):
            await owner.reset()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    private func makeOwner() -> Result<NativeDirectCallRoomFlowOwning, NativeDirectCallRoomDeveloperCommandError> {
        guard configuration.isEnabled else {
            return .failure(.disabled)
        }

        guard let owner = ownerProvider() else {
            return .failure(.unavailable)
        }

        return .success(owner)
    }
}
