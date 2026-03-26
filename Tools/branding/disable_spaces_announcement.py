from pathlib import Path
import sys

path = Path("/Users/aibattt/Movies/element-x-ios/ElementX/Sources/Application/Settings/AppSettings.swift")
text = path.read_text(encoding="utf-8")

old = '@UserPreference(key: UserDefaultsKeys.hasSeenSpacesAnnouncement, defaultValue: false, storageType: .userDefaults(store))'
new = '@UserPreference(key: UserDefaultsKeys.hasSeenSpacesAnnouncement, defaultValue: true, storageType: .userDefaults(store))'

if new in text:
    print("Already patched: Spaces announcement default is already true.")
    sys.exit(0)

if old not in text:
    print("ERROR: Expected pattern not found.")
    sys.exit(1)

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Patched AppSettings.swift successfully.")
