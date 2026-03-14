#!/usr/bin/env python3
from pathlib import Path
from datetime import datetime
import shutil
import re
import sys

TARGET = Path("ElementX/Sources/FlowCoordinators/UserSessionFlowCoordinator.swift")

if not TARGET.exists():
    print(f"[FAIL] file not found: {TARGET}")
    sys.exit(1)

src = TARGET.read_text()
original = src

def fail(msg: str):
    print(f"[FAIL] {msg}")
    sys.exit(1)

def sub_once(desc: str, pattern: str, repl: str, flags=re.M | re.S):
    global src
    new, n = re.subn(pattern, repl, src, count=1, flags=flags)
    if n != 1:
        fail(f"{desc}: expected 1 match, got {n}")
    src = new
    print(f"[OK] {desc}")

def sub_all(desc: str, pattern: str, repl: str, minimum: int = 1, flags=re.M | re.S):
    global src
    new, n = re.subn(pattern, repl, src, flags=flags)
    if n < minimum:
        fail(f"{desc}: expected at least {minimum} matches, got {n}")
    src = new
    print(f"[OK] {desc}: {n} replacement(s)")

# 1) HomeTab
sub_once(
    "HomeTab enum",
    r'enum\s+HomeTab:\s+Hashable\s*\{\s*case\s+chats\s*,\s*spaces\s*\}',
    '''enum HomeTab: Hashable {
        case chats, settings
    }'''
)

# 2) Tab properties
sub_once(
    "tab properties",
    r'''private let chatsTabFlowCoordinator: ChatsTabFlowCoordinator\s*
\s*private let chatsTabDetails: NavigationTabCoordinator(?:<HomeTab>)?\.TabDetails\s*
\s*private let spacesTabFlowCoordinator: SpacesTabFlowCoordinator\s*
\s*private let spacesTabDetails: NavigationTabCoordinator(?:<HomeTab>)?\.TabDetails''',
    '''private let chatsTabFlowCoordinator: ChatsTabFlowCoordinator
    private let chatsTabDetails: NavigationTabCoordinator.TabDetails
    private let settingsTabNavigationStackCoordinator: NavigationStackCoordinator
    private let settingsTabDetails: NavigationTabCoordinator.TabDetails'''
)

# 3) Replace spaces tab construction block with settings tab construction
sub_once(
    "spaces block -> settings block",
    r'''let\s+spacesSplitCoordinator\s*=\s*NavigationSplitCoordinator\b.*?spacesTabDetails\.navigationSplitCoordinator\s*=\s*spacesSplitCoordinator''',
    '''settingsTabNavigationStackCoordinator = NavigationStackCoordinator()
        settingsTabDetails = .init(tag: HomeTab.settings,
                                   title: L10n.commonSettings,
                                   icon: \\.settings,
                                   selectedIcon: \\.settings)
        settingsFlowCoordinator = SettingsFlowCoordinator(appLockService: appLockService,
                                                          navigationStackCoordinator: settingsTabNavigationStackCoordinator,
                                                          flowParameters: flowParameters)'''
)

# 4) Replace the second bottom tab entry
sub_once(
    "replace second tab entry",
    r'\.init\(coordinator:\s*spacesSplitCoordinator,\s*details:\s*spacesTabDetails\)',
    '.init(coordinator: settingsTabNavigationStackCoordinator, details: settingsTabDetails)'
)

# 5) Route settings/backup settings into bottom Settings tab instead of sheet state
sub_once(
    "settings route handling",
    r'''case\s+\.settings,\s*\.chatBackupSettings:\s*
\s*if\s+stateMachine\.state\s*!=\s*\.settingsScreen\s*\{\s*
\s*stateMachine\.tryEvent\(\.showSettingsScreen\)\s*
\s*\}\s*
\s*settingsFlowCoordinator\?\.handleAppRoute\(appRoute,\s*animated:\s*animated\)''',
    '''case .settings, .chatBackupSettings:
            clearPresentedSheets(animated: animated)
            if navigationTabCoordinator.selectedTab != .settings {
                navigationTabCoordinator.selectedTab = .settings
            }
            settingsFlowCoordinator?.handleAppRoute(appRoute, animated: animated)'''
)

# 6) On start, prepare Settings root instead of starting Spaces tab
sub_once(
    "startup prepare settings tab",
    r'spacesTabFlowCoordinator\.start\(\)',
    'settingsFlowCoordinator?.handleAppRoute(.settings, animated: false)'
)

# 7) Remove spaces observer
sub_once(
    "remove spaces observer",
    r'''\n\s*spacesTabFlowCoordinator\.actionsPublisher
\s*\.sink\s*\{\s*\[weak self\]\s*action in
.*?
\s*\.store\(in:\s*&cancellables\)\n''',
    '\n'
)

# 8) Add observer for persistent Settings tab coordinator
sub_once(
    "insert settings observer",
    r'''(\n\s*chatsTabFlowCoordinator\.actionsPublisher
\s*\.sink\s*\{\s*\[weak self\]\s*action in
.*?
\s*\.store\(in:\s*&cancellables\)\n)''',
    r'''\1
        if let settingsFlowCoordinator {
            settingsFlowCoordinator.actions
                .sink { [weak self] action in
                    guard let self else { return }

                    switch action {
                    case .dismiss:
                        navigationTabCoordinator.selectedTab = .chats
                    case .clearCache:
                        actionsSubject.send(.clearCache)
                    case .runLogoutFlow:
                        Task { await self.runLogoutFlow() }
                    case .forceLogout:
                        actionsSubject.send(.forceLogout)
                    }
                }
                .store(in: &cancellables)
        }
'''
)

# 9) Backup settings from logout alerts should go to the new settings tab
sub_all(
    "reroute logout backup settings closures",
    r'self\?\.chatsTabFlowCoordinator\.handleAppRoute\(\.chatBackupSettings,\s*animated:\s*true\)',
    'self?.handleAppRoute(.chatBackupSettings, animated: true)',
    minimum=2
)

# 10) Backup settings from secure-backup confirmation sheet
sub_once(
    "reroute secure backup confirmation settings action",
    r'''case\s+\.settings:\s*
\s*chatsTabFlowCoordinator\.handleAppRoute\(\.chatBackupSettings,\s*animated:\s*true\)\s*
\s*navigationTabCoordinator\.setSheetCoordinator\(nil\)''',
    '''case .settings:
                    navigationTabCoordinator.setSheetCoordinator(nil)
                    handleAppRoute(.chatBackupSettings, animated: true)'''
)

# 11) Sanity checks
leftovers = [
    "spacesTabFlowCoordinator",
    "spacesTabDetails",
    "HomeTab.spaces",
    "spacesSplitCoordinator"
]
bad = [x for x in leftovers if x in src]
if bad:
    fail("leftover references remain: " + ", ".join(bad))

required = [
    "HomeTab.settings",
    "settingsTabNavigationStackCoordinator",
    "settingsTabDetails",
    "navigationTabCoordinator.selectedTab = .settings"
]
missing = [x for x in required if x not in src]
if missing:
    fail("required replacements missing: " + ", ".join(missing))

if src == original:
    fail("file unchanged")

backup = TARGET.with_suffix(TARGET.suffix + ".bak." + datetime.now().strftime("%Y%m%d-%H%M%S"))
shutil.copy2(TARGET, backup)
TARGET.write_text(src)

print(f"[DONE] patched: {TARGET}")
print(f"[DONE] backup : {backup}")
