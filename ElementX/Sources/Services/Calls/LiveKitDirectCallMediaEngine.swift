//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation

@MainActor
protocol DirectCallLiveKitClientProtocol {
    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError>
    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError>
    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError>
    func remoteParticipantSnapshot() async -> DirectCallRemoteParticipantSnapshot
    func disconnect() async
    func cleanup() async
}

struct DirectCallRemoteParticipantSnapshot: Equatable {
    static let empty = DirectCallRemoteParticipantSnapshot(participantSeen: false,
                                                           countBucket: "0",
                                                           identityFilterApplied: false,
                                                           identityFilterResult: "not_applied_redacted")

    let participantSeen: Bool
    let countBucket: String
    let identityFilterApplied: Bool
    let identityFilterResult: String
}

extension DirectCallLiveKitClientProtocol {
    func remoteParticipantSnapshot() async -> DirectCallRemoteParticipantSnapshot {
        .empty
    }
}

@MainActor
protocol DirectCallMediaE2EEContextProtocol: AnyObject {
    func cleanup()
}

@MainActor
protocol DirectCallMediaE2EEContextProviderProtocol {
    func context(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) -> Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError>
    func clearContext(callID: String)
}

@MainActor
final class UnavailableDirectCallLiveKitClient: DirectCallLiveKitClientProtocol {
    func connect(connectionInfo: DirectCallMediaConnectionInfo, e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        .failure(.mediaSetupUnavailable)
    }

    func setMicrophoneEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        .failure(.mediaSetupUnavailable)
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool) async -> Result<Void, DirectCallMediaError> {
        isEnabled ? .failure(.mediaSetupUnavailable) : .success(())
    }

    func disconnect() async { }

    func cleanup() async { }
}

@MainActor
final class UnavailableDirectCallMediaE2EEContextProvider: DirectCallMediaE2EEContextProviderProtocol {
    func context(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) -> Result<any DirectCallMediaE2EEContextProtocol, DirectCallMediaError> {
        .failure(.e2eeContextUnavailable)
    }

    func clearContext(callID: String) { }
}

struct DirectCallLiveKitConnectExecutorModel: Equatable {
    let present: Bool
    let debugOnly: Bool
    let receiverExecutorShared: Bool
    let senderExecutorShared: Bool
    let sameConnectOptionsShape: Bool
    let sameRoomRetentionModel: Bool
    let sameDelegateRetentionModel: Bool
    let sameStateObserverModel: Bool
    let sameBoundedWaitModel: Bool
    let audioOnly: Bool
    let videoAllowed: Bool
    let matrixEventsAllowed: Bool
    let rawURLLogged: Bool
    let rawTokenLogged: Bool
    let rawRoomLogged: Bool
    let rawIdentityLogged: Bool
}

struct DirectCallLiveKitConnectExecutor {
    static let provenAudioModel = DirectCallLiveKitConnectExecutorModel(present: true,
                                                                        debugOnly: true,
                                                                        receiverExecutorShared: true,
                                                                        senderExecutorShared: true,
                                                                        sameConnectOptionsShape: true,
                                                                        sameRoomRetentionModel: true,
                                                                        sameDelegateRetentionModel: true,
                                                                        sameStateObserverModel: true,
                                                                        sameBoundedWaitModel: true,
                                                                        audioOnly: true,
                                                                        videoAllowed: false,
                                                                        matrixEventsAllowed: false,
                                                                        rawURLLogged: false,
                                                                        rawTokenLogged: false,
                                                                        rawRoomLogged: false,
                                                                        rawIdentityLogged: false)

    private let liveKitClient: DirectCallLiveKitClientProtocol

    @MainActor
    init(liveKitClient: DirectCallLiveKitClientProtocol) {
        self.liveKitClient = liveKitClient
    }

    @MainActor
    func connectAudio(connectionInfo: DirectCallMediaConnectionInfo,
                      e2eeContext: any DirectCallMediaE2EEContextProtocol) async -> Result<Void, DirectCallMediaError> {
        await liveKitClient.connect(connectionInfo: connectionInfo, e2eeContext: e2eeContext)
    }
}

@MainActor
final class LiveKitDirectCallMediaEngine: DirectCallMediaEngineProtocol {
    private let mediaStateSubject = CurrentValueSubject<DirectCallMediaState, Never>(.idle)
    private let tokenProvider: DirectCallMediaTokenProviderProtocol
    private let audioRouteController: DirectCallAudioRouteControllerProtocol
    private let encryptionService: DirectCallEncryptionServiceProtocol
    private let e2eeContextProvider: DirectCallMediaE2EEContextProviderProtocol
    private let liveKitClient: DirectCallLiveKitClientProtocol
    private let liveKitConnectExecutor: DirectCallLiveKitConnectExecutor
    private var clearedCallIDs = Set<String>()
    private var disconnectedCallIDs = Set<String>()
    private var cleanedCallIDs = Set<String>()

    #if DEBUG
    private var diagnosticState = DirectCallDiagnosticSnapshot()

    var diagnosticSnapshot: DirectCallDiagnosticSnapshot {
        var snapshot = diagnosticState
        if let tokenDiagnostics = tokenProvider as? DirectCallMediaDiagnosticSnapshotProviding {
            snapshot.mergeReceiveDiagnostics(from: tokenDiagnostics.diagnosticSnapshot)
        }
        if let e2eeDiagnostics = e2eeContextProvider as? DirectCallMediaDiagnosticSnapshotProviding {
            snapshot.mergeReceiveDiagnostics(from: e2eeDiagnostics.diagnosticSnapshot)
        }
        return snapshot
    }
    #endif

    var mediaStatePublisher: CurrentValuePublisher<DirectCallMediaState, Never> {
        mediaStateSubject.asCurrentValuePublisher()
    }

    init(tokenProvider: DirectCallMediaTokenProviderProtocol? = nil,
         audioRouteController: DirectCallAudioRouteControllerProtocol? = nil,
         encryptionService: DirectCallEncryptionServiceProtocol? = nil,
         e2eeContextProvider: DirectCallMediaE2EEContextProviderProtocol? = nil,
         liveKitClient: DirectCallLiveKitClientProtocol? = nil) {
        self.tokenProvider = tokenProvider ?? NoOpDirectCallMediaTokenProvider()
        self.audioRouteController = audioRouteController ?? NoOpDirectCallAudioRouteController()
        self.encryptionService = encryptionService ?? NoOpDirectCallEncryptionService()
        self.e2eeContextProvider = e2eeContextProvider ?? UnavailableDirectCallMediaE2EEContextProvider()
        self.liveKitClient = liveKitClient ?? UnavailableDirectCallLiveKitClient()
        liveKitConnectExecutor = DirectCallLiveKitConnectExecutor(liveKitClient: self.liveKitClient)
        #if DEBUG
        diagnosticState.mediaFactoryInjected = true
        diagnosticState.mediaCredentialProviderAvailable = tokenProvider != nil
        diagnosticState.mediaE2EEProviderAvailable = e2eeContextProvider != nil
        #endif
    }

    func prepareAudioSession(for session: DirectCallSession) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        guard session.isValidForDirectAudioPreparation else {
            return fail(callID: session.callID, error: session.intent == .audio ? .invalidSession : .unsupportedIntent)
        }

        guard case .success = audioRouteController.configureDefaultAudioRoute(for: session) else {
            return fail(callID: session.callID, error: .audioRouteFailed)
        }

        let state = DirectCallMediaState(callID: session.callID,
                                         phase: .preparingAudio,
                                         isMicrophoneEnabled: false,
                                         isSpeakerEnabled: false,
                                         isE2EEReady: session.encryptionState == .ready)
        mediaStateSubject.send(state)
        return .success(state)
    }

    func requestMediaCredentials(for session: DirectCallSession) async -> Result<DirectCallMediaConnectionInfo, DirectCallMediaError> {
        await tokenProvider.connectionInfo(for: session)
    }

    func connectAudio(for session: DirectCallSession, keyHandle: DirectCallMediaKeyHandle) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        #if DEBUG
        diagnosticState.mediaConnectAttempted = true
        diagnosticState.mediaKeyHandleAvailable = !keyHandle.keyID.isEmpty && keyHandle.callID == session.callID
        diagnosticState.mediaFailureReason = .none
        diagnosticState.liveKitFailureReason = .none
        #endif

        let preparingState = DirectCallMediaState(callID: session.callID,
                                                  phase: .preparingAudio,
                                                  isMicrophoneEnabled: false,
                                                  isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                                  isE2EEReady: false)
        mediaStateSubject.send(preparingState)

        if let error = session.directAudioConnectionError(keyHandle: keyHandle) {
            return fail(callID: session.callID, error: error)
        }

        let e2eeContext: any DirectCallMediaE2EEContextProtocol
        switch e2eeContextProvider.context(for: session, keyHandle: keyHandle) {
        case .success(let context):
            e2eeContext = context
        case .failure(let error):
            return fail(callID: session.callID, error: error)
        }

        switch await tokenProvider.connectionInfo(for: session) {
        case .success(let connectionInfo):
            guard case .success = audioRouteController.configureDefaultAudioRoute(for: session) else {
                return fail(callID: session.callID, error: .audioRouteFailed)
            }

            let connectingState = DirectCallMediaState(callID: session.callID,
                                                       phase: .connectingAudio,
                                                       isMicrophoneEnabled: false,
                                                       isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                                       isE2EEReady: true)
            mediaStateSubject.send(connectingState)

            #if DEBUG
            diagnosticState.liveKitClientConnectAttempted = true
            #endif

            switch await liveKitConnectExecutor.connectAudio(connectionInfo: connectionInfo, e2eeContext: e2eeContext) {
            case .success:
                let activeState = DirectCallMediaState(callID: session.callID,
                                                       phase: .activeAudio,
                                                       isMicrophoneEnabled: false,
                                                       isSpeakerEnabled: connectingState.isSpeakerEnabled,
                                                       isE2EEReady: true)
                disconnectedCallIDs.remove(session.callID)
                mediaStateSubject.send(activeState)
                return .success(activeState)
            case .failure(let error):
                #if DEBUG
                let failureReason: DirectCallDiagnosticMediaFailureReason = error == .mediaSetupUnavailable ? .liveKitConnectFailed : .init(error)
                diagnosticState.liveKitFailureReason = failureReason
                diagnosticState.mediaFailureReason = failureReason
                #endif
                return fail(callID: session.callID, error: error)
            }
        case .failure(let error):
            return fail(callID: session.callID, error: error)
        }
    }

    func setMicrophoneEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        var state = mediaStateSubject.value
        guard state.callID == callID else {
            return fail(callID: callID, error: .invalidSession)
        }

        if isEnabled {
            guard state.canPublishMicrophone else {
                return fail(callID: callID, error: .e2eeNotReady)
            }
        }

        switch await liveKitClient.setMicrophoneEnabled(isEnabled) {
        case .success:
            state.isMicrophoneEnabled = isEnabled
            mediaStateSubject.send(state)
            return .success(state)
        case .failure(let error):
            return fail(callID: callID, error: error)
        }
    }

    func setRemoteAudioPlaybackEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        let state = mediaStateSubject.value

        guard isEnabled else {
            guard state.callID == nil || state.callID == callID else {
                return .success(state)
            }

            switch await liveKitClient.setRemoteAudioPlaybackEnabled(false) {
            case .success:
                return .success(state)
            case .failure(let error):
                return fail(callID: callID, error: error)
            }
        }

        guard state.callID == callID else {
            return fail(callID: callID, error: .invalidSession)
        }

        guard state.canPlayRemoteAudio else {
            return fail(callID: callID, error: .e2eeNotReady)
        }

        switch await liveKitClient.setRemoteAudioPlaybackEnabled(true) {
        case .success:
            return .success(state)
        case .failure(let error):
            return fail(callID: callID, error: error)
        }
    }

    func setSpeakerEnabled(_ isEnabled: Bool, callID: String) async -> Result<DirectCallMediaState, DirectCallMediaError> {
        switch audioRouteController.setSpeakerEnabled(isEnabled) {
        case .success:
            var state = mediaStateSubject.value
            state.isSpeakerEnabled = isEnabled
            mediaStateSubject.send(state)
            return .success(state)
        case .failure:
            return fail(callID: callID, error: .audioRouteFailed)
        }
    }

    func disconnect(callID: String) async {
        #if DEBUG
        diagnosticState.mediaDisconnectAttempted = true
        #endif

        guard !callID.isEmpty, !disconnectedCallIDs.contains(callID) else {
            return
        }

        var state = mediaStateSubject.value
        if state.callID == callID {
            state.phase = .disconnecting
            state.isMicrophoneEnabled = false
            mediaStateSubject.send(state)
        }

        _ = await liveKitClient.setRemoteAudioPlaybackEnabled(false)
        _ = await liveKitClient.setMicrophoneEnabled(false)
        await liveKitClient.disconnect()
        audioRouteController.deactivateAudioSession()
        clearPerCallKeyIfNeeded(callID: callID)
        disconnectedCallIDs.insert(callID)

        if state.callID == callID {
            state.phase = .disconnected
            state.isSpeakerEnabled = false
            state.isE2EEReady = false
            mediaStateSubject.send(state)
        }
    }

    func cleanup(callID: String) async {
        #if DEBUG
        diagnosticState.mediaCleanupAttempted = true
        #endif

        await disconnect(callID: callID)
        if !callID.isEmpty, !cleanedCallIDs.contains(callID) {
            await liveKitClient.cleanup()
            cleanedCallIDs.insert(callID)
        }
        if mediaStateSubject.value.callID == callID {
            mediaStateSubject.send(.idle)
        }
    }

    private func fail(callID: String, error: DirectCallMediaError) -> Result<DirectCallMediaState, DirectCallMediaError> {
        #if DEBUG
        if diagnosticState.mediaFailureReason == .none {
            diagnosticState.mediaFailureReason = .init(error)
        }
        #endif

        let state = DirectCallMediaState(callID: callID.isEmpty ? nil : callID,
                                         phase: .failed(error),
                                         isMicrophoneEnabled: false,
                                         isSpeakerEnabled: mediaStateSubject.value.isSpeakerEnabled,
                                         isE2EEReady: false)
        mediaStateSubject.send(state)
        return .failure(error)
    }

    private func clearPerCallKeyIfNeeded(callID: String) {
        guard !callID.isEmpty, !clearedCallIDs.contains(callID) else {
            return
        }

        encryptionService.clearPerCallKey(callID: callID)
        e2eeContextProvider.clearContext(callID: callID)
        clearedCallIDs.insert(callID)
    }
}

extension LiveKitDirectCallMediaEngine: DirectCallMediaCredentialsBoundaryRequesting { }

#if DEBUG
extension LiveKitDirectCallMediaEngine: DirectCallMediaDiagnosticSnapshotProviding { }
#endif
