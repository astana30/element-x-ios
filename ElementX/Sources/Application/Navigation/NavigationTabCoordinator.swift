//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI
import UIKit

/// Class responsible for displaying an arbitrary number of coordinators within the tab bar.
@Observable class NavigationTabCoordinator<Tag: Hashable>: CoordinatorProtocol, CustomStringConvertible {
    struct Tab {
        let coordinator: CoordinatorProtocol
        let details: TabDetails
        var dismissalCallback: (() -> Void)?
    }
    
    @MainActor
    @Observable class TabDetails {
        /// A unique tab that identifies the tab for selection.
        let tag: Tag
        let title: String
        let icon: KeyPath<CompoundIcons, Image>
        let selectedIcon: KeyPath<CompoundIcons, Image>
        var badgeCount = 0
        
        /// Provide the tab's split coordinator in here to have the tab bar automatically hidden
        /// when pushing a child into the split view's details on iPhone/compact iPad.
        weak var navigationSplitCoordinator: NavigationSplitCoordinator?
        
        init(tag: Tag, title: String, icon: KeyPath<CompoundIcons, Image>, selectedIcon: KeyPath<CompoundIcons, Image>) {
            self.tag = tag
            self.title = title
            self.icon = icon
            self.selectedIcon = selectedIcon
        }
        
        func barVisibility(in horizontalSizeClass: UserInterfaceSizeClass?) -> Visibility {
            if horizontalSizeClass == .compact, navigationSplitCoordinator?.detailCoordinator != nil {
                // Whilst we support pushing screens on the stack in the sidebarCoordinator, in practice
                // we never do that, so simply checking that the detailCoordinator exists is enough.
                .hidden
            } else {
                .automatic
            }
        }
    }
    
    // MARK: Tabs
    
    fileprivate struct TabModule: Identifiable {
        let module: NavigationModule
        let details: TabDetails
        
        var id: ObjectIdentifier {
            module.id
        }

        @MainActor var coordinator: CoordinatorProtocol? {
            module.coordinator
        }
    }
    
    fileprivate var tabModules = [TabModule]() {
        didSet {
            let diffs = tabModules.map(\.module).difference(from: oldValue.map(\.module))
            diffs.forEach { change in
                switch change {
                case .insert(_, let module, _):
                    logPresentationChange("Set tab", module)
                    module.coordinator?.start()
                case .remove(_, let module, _):
                    logPresentationChange("Remove tab", module)
                    module.tearDown()
                }
            }
        }
    }
    
    /// The current set of coordinators displayed by the tabs.
    var tabCoordinators: [any CoordinatorProtocol] {
        tabModules.compactMap(\.module.coordinator)
    }
    
    /// Updates the displayed tabs with the provided array.
    func setTabs(_ tabs: [Tab], animated: Bool = true) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            tabModules = tabs.map { TabModule(module: .init($0.coordinator, dismissalCallback: $0.dismissalCallback), details: $0.details) }
        }
        
        selectedTab = tabModules.first?.details.tag
    }
    
    /// The currently selected tab's tag.
    var selectedTab: Tag?
    
    // MARK: Sheets
    
    fileprivate var sheetModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove sheet", oldValue)
                oldValue.tearDown()
            }
            
            if let sheetModule {
                logPresentationChange("Set sheet", sheetModule)
                sheetModule.coordinator?.start()
            }
        }
    }
    
    var presentationDetents: Set<PresentationDetent> = []
    
    /// The currently presented sheet coordinator.
    var sheetCoordinator: (any CoordinatorProtocol)? {
        sheetModule?.coordinator
    }
    
    /// Present a sheet on top of the stack. If this NavigationStackCoordinator is embedded within a NavigationSplitCoordinator
    /// then the presentation will be proxied to the split
    /// - Parameters:
    ///   - coordinator: the coordinator to display
    ///   - animated: whether to animate the transition or not. Default is true
    ///   - dismissalCallback: called when the sheet has been dismissed, programatically or otherwise
    func setSheetCoordinator(_ coordinator: (any CoordinatorProtocol)?, animated: Bool = true, dismissalCallback: (() -> Void)? = nil) {
        guard let coordinator else {
            sheetModule = nil
            return
        }
        
        if sheetModule?.coordinator === coordinator {
            fatalError("Cannot use the same coordinator more than once")
        }

        var transaction = Transaction()
        transaction.disablesAnimations = !animated

        withTransaction(transaction) {
            sheetModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    // MARK: Full Screen Cover
    
    fileprivate var fullScreenCoverModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove fullscreen cover", oldValue)
                oldValue.tearDown()
            }
            
            if let fullScreenCoverModule {
                logPresentationChange("Set fullscreen cover", fullScreenCoverModule)
                fullScreenCoverModule.coordinator?.start()
            }
        }
    }
    
    /// The currently presented fullscreen cover coordinator
    /// Fullscreen covers will be presented through the NavigationSplitCoordinator if provided
    var fullScreenCoverCoordinator: (any CoordinatorProtocol)? {
        fullScreenCoverModule?.coordinator
    }
    
    /// Present a fullscreen cover on top of the stack. If this NavigationStackCoordinator is embedded within a NavigationSplitCoordinator
    /// then the presentation will be proxied to the split
    /// - Parameters:
    ///   - coordinator: the coordinator to display
    ///   - animated: whether to animate the transition or not. Default is true
    ///   - dismissalCallback: called when the fullscreen cover has been dismissed, programatically or otherwise
    func setFullScreenCoverCoordinator(_ coordinator: (any CoordinatorProtocol)?, animated: Bool = true, dismissalCallback: (() -> Void)? = nil) {
        guard let coordinator else {
            fullScreenCoverModule = nil
            return
        }
        
        if fullScreenCoverModule?.coordinator === coordinator {
            fatalError("Cannot use the same coordinator more than once")
        }

        var transaction = Transaction()
        transaction.disablesAnimations = !animated

        withTransaction(transaction) {
            fullScreenCoverModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    // MARK: - Overlay
    
    fileprivate var overlayModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove overlay", oldValue)
                oldValue.tearDown()
            }
            
            if let overlayModule {
                logPresentationChange("Set overlay", overlayModule)
                overlayModule.coordinator?.start()
            }
        }
    }
    
    /// The currently displayed overlay coordinator
    var overlayCoordinator: (any CoordinatorProtocol)? {
        overlayModule?.coordinator
    }
    
    enum OverlayPresentationMode { case fullScreen, minimized }
    fileprivate var overlayPresentationMode: OverlayPresentationMode = .minimized
    
    /// Present an overlay on top of the tab view
    /// - Parameters:
    ///   - coordinator: the coordinator to display
    ///   - presentationMode: how the coordinator should be presented
    ///   - animated: whether the transition should be animated
    ///   - dismissalCallback: called when the overlay has been dismissed, programatically or otherwise
    func setOverlayCoordinator(_ coordinator: (any CoordinatorProtocol)?,
                               presentationMode: OverlayPresentationMode = .fullScreen,
                               animated: Bool = true,
                               dismissalCallback: (() -> Void)? = nil) {
        guard let coordinator else {
            overlayModule = nil
            return
        }
        
        if overlayModule?.coordinator === coordinator {
            fatalError("Cannot use the same coordinator more than once")
        }

        var transaction = Transaction()
        transaction.disablesAnimations = !animated

        withTransaction(transaction) {
            overlayPresentationMode = presentationMode
            overlayModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    /// Updates the presentation of the overlay coordinator.
    /// - Parameters:
    ///   - mode: The type of presentation to use.
    ///   - animated: whether the transition should be animated
    func setOverlayPresentationMode(_ mode: OverlayPresentationMode, animated: Bool = true) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            overlayPresentationMode = mode
        }
    }
    
    // MARK: - CoordinatorProtocol
    
    /// No idea if this is particuarly needed for the TabView but we do this for the NavigationStackCoordinator and NavigationSplitCoordinator so it
    /// doesn't seem to harm to also do it here.
    func stop() {
        tabModules.forEach { $0.module.tearDown() }
    }
    
    func toPresentable() -> AnyView {
        AnyView(NavigationTabCoordinatorView(navigationTabCoordinator: self))
    }
    
    // MARK: - CustomStringConvertible
    
    var description: String {
        guard !tabModules.isEmpty else { return "NavigationTabCoordinator(Empty)" }
        return "NavigationTabCoordinator(\(tabCoordinators)"
    }
    
    // MARK: - Private
    
    private func logPresentationChange(_: String, _: NavigationModule) { }
}

private struct NavigationTabCoordinatorView<Tag: Hashable>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Bindable var navigationTabCoordinator: NavigationTabCoordinator<Tag>
    
    @State private var standardAppearance = UITabBarAppearance()
    
    var body: some View {
        TabView(selection: $navigationTabCoordinator.selectedTab) {
            ForEach(navigationTabCoordinator.tabModules) { module in
                module.coordinator?.toPresentable()
                    .id(module.id)
                    .tabItem {
                        Label {
                            Text(module.details.title)
                        } icon: {
                            CompoundIcon(module.details.tag == navigationTabCoordinator.selectedTab ? module.details.selectedIcon : module.details.icon)
                        }
                    }
                    .tag(module.details.tag)
                    .badge(module.details.badgeCount)
                    .toolbar(module.details.barVisibility(in: horizontalSizeClass), for: .tabBar)
            }
        }
        .backportTabBarMinimizeBehaviorOnScrollDown()
        .introspect(.tabView, on: .supportedVersions, customize: configureAppearance)
        .sheet(item: $navigationTabCoordinator.sheetModule) { module in
            module.coordinator?.toPresentable()
                .id(module.id)
        }
        .fullScreenCover(item: $navigationTabCoordinator.fullScreenCoverModule) { module in
            module.coordinator?.toPresentable()
                .id(module.id)
        }
        .accessibilityHidden(navigationTabCoordinator.overlayModule?.coordinator != nil && navigationTabCoordinator.overlayPresentationMode == .fullScreen)
        .overlay {
            Group {
                if let coordinator = navigationTabCoordinator.overlayModule?.coordinator {
                    coordinator.toPresentable()
                        .opacity(navigationTabCoordinator.overlayPresentationMode == .minimized ? 0 : 1)
                        .transition(.opacity)
                }
            }
            .animation(.elementDefault, value: navigationTabCoordinator.overlayPresentationMode)
            .animation(.elementDefault, value: navigationTabCoordinator.overlayModule)
        }
    }
    
    private func configureAppearance(_ tabBarController: UITabBarController) {
        standardAppearance.configureWithTransparentBackground()
        standardAppearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterialDark)
        standardAppearance.backgroundColor = UIColor(red: 0.03, green: 0.08, blue: 0.10, alpha: 0.76)
        standardAppearance.shadowColor = UIColor(SalemBrandPalette.glow).withAlphaComponent(0.34)

        let selectedColor = UIColor(SalemBrandPalette.sky)
        let normalColor = UIColor(red: 0.55, green: 0.62, blue: 0.66, alpha: 1.0)

        let stacked = standardAppearance.stackedLayoutAppearance
        stacked.normal.iconColor = normalColor
        stacked.normal.titleTextAttributes = [.foregroundColor: normalColor]
        stacked.selected.iconColor = selectedColor
        stacked.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        stacked.normal.badgeBackgroundColor = .compound.iconAccentPrimary
        stacked.selected.badgeBackgroundColor = .compound.iconAccentPrimary

        let compactInline = standardAppearance.compactInlineLayoutAppearance
        compactInline.normal.iconColor = normalColor
        compactInline.normal.titleTextAttributes = [.foregroundColor: normalColor]
        compactInline.selected.iconColor = selectedColor
        compactInline.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        compactInline.normal.badgeBackgroundColor = .compound.iconAccentPrimary
        compactInline.selected.badgeBackgroundColor = .compound.iconAccentPrimary

        let inline = standardAppearance.inlineLayoutAppearance
        inline.normal.iconColor = normalColor
        inline.normal.titleTextAttributes = [.foregroundColor: normalColor]
        inline.selected.iconColor = selectedColor
        inline.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        inline.normal.badgeBackgroundColor = .compound.iconAccentPrimary
        inline.selected.badgeBackgroundColor = .compound.iconAccentPrimary

        let tabBar = tabBarController.tabBar
        tabBar.standardAppearance = standardAppearance
        tabBar.scrollEdgeAppearance = standardAppearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
        tabBar.isTranslucent = true
        tabBar.selectionIndicatorImage = makeSelectionIndicatorImage(in: tabBar)

        tabBar.layer.masksToBounds = false
        tabBar.layer.cornerRadius = 22
        tabBar.layer.cornerCurve = .continuous
        tabBar.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tabBar.layer.shadowColor = UIColor(SalemBrandPalette.sky).withAlphaComponent(0.55).cgColor
        tabBar.layer.shadowOpacity = 0.22
        tabBar.layer.shadowOffset = CGSize(width: 0, height: -2)
        tabBar.layer.shadowRadius = 14
    }

    private func makeSelectionIndicatorImage(in tabBar: UITabBar) -> UIImage? {
        guard let items = tabBar.items,
              !items.isEmpty else {
            return nil
        }

        let itemWidth = tabBar.bounds.width / CGFloat(items.count)
        guard itemWidth > 0 else {
            return nil
        }

        let size = CGSize(width: itemWidth, height: tabBar.bounds.height)
        let indicatorWidth = max(56, itemWidth - 18)
        let indicatorHeight: CGFloat = 34
        let xInset = (itemWidth - indicatorWidth) / 2
        let yInset: CGFloat = 6

        return UIGraphicsImageRenderer(size: size).image { _ in
            let indicatorRect = CGRect(x: xInset,
                                       y: yInset,
                                       width: indicatorWidth,
                                       height: indicatorHeight)
            let indicatorPath = UIBezierPath(roundedRect: indicatorRect, cornerRadius: 14)
            UIColor(red: 0.27, green: 0.70, blue: 0.98, alpha: 0.20).setFill()
            indicatorPath.fill()

            UIColor(red: 0.66, green: 0.89, blue: 1.00, alpha: 0.38).setStroke()
            indicatorPath.lineWidth = 1
            indicatorPath.stroke()
        }
    }
}
