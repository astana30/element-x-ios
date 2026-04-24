//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AuthenticationStartScreenViewModelType = StateStoreViewModelV2<AuthenticationStartScreenViewState, AuthenticationStartScreenViewAction>

class AuthenticationStartScreenViewModel: AuthenticationStartScreenViewModelType, AuthenticationStartScreenViewModelProtocol {
    private let authenticationService: AuthenticationServiceProtocol
    private let provisioningParameters: AccountProvisioningParameters?
    private let appSettings: AppSettings
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let canReportProblem: Bool
    
    private var actionsSubject: PassthroughSubject<AuthenticationStartScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<AuthenticationStartScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(authenticationService: AuthenticationServiceProtocol,
         provisioningParameters: AccountProvisioningParameters?,
         isBugReportServiceEnabled: Bool,
         appSettings: AppSettings,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.authenticationService = authenticationService
        self.provisioningParameters = provisioningParameters
        self.appSettings = appSettings
        self.userIndicatorController = userIndicatorController
        canReportProblem = isBugReportServiceEnabled
        
        let initialViewState = AuthenticationStartScreenViewState(serverName: nil,
                                                                  showCreateAccountButton: false,
                                                                  showQRCodeLoginButton: false,
                                                                  hideBrandChrome: appSettings.hideBrandChrome)
        
        super.init(initialViewState: initialViewState)
    }

    override func process(viewAction: AuthenticationStartScreenViewAction) {
        switch viewAction {
        case .updateWindow(let window):
            guard state.window != window else { return }
            state.window = window
        case .loginWithQR:
            actionsSubject.send(.loginWithQR)
        case .login:
            Task { await login() }
        case .register:
            actionsSubject.send(.register)
        case .reportProblem:
            if canReportProblem {
                actionsSubject.send(.reportProblem)
            }
        }
    }
    
    // MARK: - Private
    
    private func login() async {
        if let provisioningParameters {
            await configureAccountProvider(provisioningParameters.accountProvider,
                                           loginHint: provisioningParameters.loginHint)
            return
        }
        
        if !appSettings.allowOtherAccountProviders,
           let accountProvider = appSettings.accountProviders.first,
           appSettings.accountProviders.count == 1 {
            await configureAccountProvider(accountProvider)
            return
        }
        
        actionsSubject.send(.login)
    }
    
    private func configureAccountProvider(_ accountProvider: String, loginHint: String? = nil) async {
        startLoading()
        defer { stopLoading() }
        
        guard case .success = await authenticationService.configure(for: accountProvider, flow: .login) else {
            // As the server was provisioned, we don't worry about the specifics and show a generic error to the user.
            displayError()
            return
        }
        
        guard authenticationService.homeserver.value.loginMode.supportsOIDCFlow else {
            actionsSubject.send(.loginDirectlyWithPassword(loginHint: loginHint))
            return
        }
        
        guard let window = state.window else {
            displayError()
            return
        }
        
        switch await authenticationService.urlForOIDCLogin(loginHint: loginHint) {
        case .success(let oidcData):
            actionsSubject.send(.loginDirectlyWithOIDC(data: oidcData, window: window))
        case .failure:
            displayError()
        }
    }
    
    private let loadingIndicatorID = "\(AuthenticationStartScreenViewModel.self)-Loading"
    
    private func startLoading() {
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorID,
                                                              type: .modal,
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func stopLoading() {
        userIndicatorController.retractIndicatorWithId(loadingIndicatorID)
    }
    
    private func displayError() {
        state.bindings.alertInfo = AlertInfo(id: .genericError)
    }
}
