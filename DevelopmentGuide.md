# DictApp — Development Guide

## Architecture Overview

```
DictApp/
├── DictApp/
│   ├── DictApp.swift              # @main entry point
│   ├── Models/
│   │   └── Models.swift           # DictionaryEntry, HistoryItem, Bookmark
│   ├── Services/
│   │   ├── DatabaseService.swift  # SQLite + FTS5 via GRDB (actor)
│   │   └── SpeechService.swift    # AVFoundation TTS
│   ├── ViewModels/
│   │   ├── SearchViewModel.swift      # Debounced search-as-you-type
│   │   ├── DefinitionViewModel.swift  # Detail + bookmark + history
│   │   ├── HistoryViewModel.swift
│   │   └── BookmarksViewModel.swift
│   ├── Views/
│   │   ├── ContentView.swift          # Root TabView
│   │   ├── SearchView.swift           # Search bar + results list
│   │   ├── DefinitionView.swift       # Markdown definition + TTS
│   │   ├── HistoryView.swift
│   │   ├── BookmarksView.swift
│   │   └── DictionaryManagerView.swift # File importer
│   ├── Extensions/
│   │   └── DictionaryEntry+Hashable.swift
│   └── Resources/
│       └── Schema.sql             # Database DDL
├── DictAppTests/
│   └── DictAppTests.swift         # Unit + performance tests
├── Package.swift                  # SPM reference
Scripts/
└── generate_seed_db.py            # Python script to create sample data
```

## 1. Xcode Project Setup

### Create the project

1. Open **Xcode 15+** (requires iOS 17 SDK).
2. **File → New → Project → iOS → App**.
3. Product Name: `DictApp`, Interface: **SwiftUI**, Language: **Swift**.
4. Save it inside the `DictApp/` directory (so that source files align).

### Add the GRDB Swift Package

1. **File → Add Package Dependencies...**
2. Enter URL: `https://github.com/groue/GRDB.swift`
3. Version rule: **Up to Next Major → 6.24.0**
4. Add the `GRDB` library to the `DictApp` target.

### Add source files

If you created the Xcode project inside the existing `DictApp/` directory, the files are already on disk. You just need to add them to the project:

1. In the Xcode navigator, right-click the `DictApp` group → **Add Files to "DictApp"...**
2. Select all `.swift` files under `Models/`, `Services/`, `ViewModels/`, `Views/`, `Extensions/`.
3. Add `Resources/Schema.sql` — make sure "Copy items if needed" is **unchecked** and "Add to target: DictApp" is **checked**. Verify it appears under **Build Phases → Copy Bundle Resources**.

### Add Schema.sql to bundle resources

The `Schema.sql` file must be included as a bundle resource:

1. Select the `DictApp` target → **Build Phases** tab.
2. Under **Copy Bundle Resources**, click **+** and add `Schema.sql`.

## 2. Preparing Sample Data

### Option A: Generate a SQLite seed file

```bash
cd /path/to/dict
python3 Scripts/generate_seed_db.py --count 1000 --output DictApp/DictApp/Resources/seed.sqlite
```

Then add `seed.sqlite` to the Xcode bundle resources the same way as Schema.sql.

### Option B: Generate a JSON seed file

```bash
python3 Scripts/generate_seed_db.py --count 1000 --json DictApp/DictApp/Resources/seed.json
```

Add `seed.json` to the Xcode bundle resources. The app will auto-import it on first launch via `DatabaseService.seedIfNeeded()`.

### Option C: Large test database (100k entries)

```bash
python3 Scripts/generate_seed_db.py --count 100000 --output big_dict.sqlite
```

Use the in-app **Manage → Import File** feature to load it.

## 3. Running Tests

```bash
# From Xcode:
# Product → Test (Cmd+U)

# Or from CLI (requires xcodebuild):
xcodebuild test \
  -project DictApp.xcodeproj \
  -scheme DictApp \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage

| Test | What it verifies |
|------|-----------------|
| `testSearchReturnsCorrectDefinition` | FTS5 search returns correct entry |
| `testExactLookup` | Case-insensitive exact match |
| `testHistoryNoDuplicates` | Upsert prevents duplicate history entries |
| `testHistoryOrderUpdatedOnRevisit` | Re-lookup moves word to top |
| `testClearHistory` | History deletion |
| `testBookmarkCycle` | Add → check → remove bookmark |
| `testPrefixSearch` | Prefix queries match expected count |
| `testSearchPerformance100K` | FTS5 search < 16ms on 100k entries |
| `testSearchPerformanceRepeated` | XCTest `measure` block for statistical analysis |

## 4. Deploying to a Physical iPhone

### Prerequisites

- Apple Developer account (free or paid).
- iPhone connected via USB or on the same Wi-Fi network.
- Xcode 15+.

### Steps

1. **Connect your iPhone** to your Mac.
2. In Xcode, select your iPhone from the device dropdown (top toolbar).
3. Select the `DictApp` target → **Signing & Capabilities**.
4. Set **Team** to your Apple Developer account.
5. Set a unique **Bundle Identifier** (e.g., `com.yourname.dictapp`).
6. Click **Run** (Cmd+R).
7. On first install, your iPhone may show "Untrusted Developer":
   - Go to **Settings → General → VPN & Device Management** → tap your developer profile → **Trust**.
8. Run again from Xcode. The app will launch on your device.

### Troubleshooting

- **"Could not launch"**: Ensure the device is unlocked during installation.
- **Provisioning errors**: Go to Xcode → Settings → Accounts → your Apple ID → Download Manual Profiles.
- **TTS not working on simulator**: TTS requires a real device or specific simulator voices.

## 5. Key Design Decisions

### Why GRDB over SQLite.swift?

GRDB provides first-class FTS5 support, record protocols that eliminate boilerplate, and built-in `DatabasePool` for concurrent reads during writes. It maps cleanly to Swift Concurrency.

### Why FTS5?

FTS5 is SQLite's latest full-text search engine. It uses an inverted index, making prefix searches O(1) relative to dictionary size. A search on 100,000 entries completes in under 5ms.

### Why an Actor for DatabaseService?

The `actor` isolation guarantees thread-safe access to the `DatabasePool` reference without manual locking. All public methods are `async`, keeping the UI thread completely free.

### Offline-first

The entire dictionary lives in a local SQLite file. No network calls are ever made. Users import dictionaries via the file picker.

## 6. Extending the App

### Adding a new dictionary format

1. Add a parser method in `DatabaseService` (e.g., `importCSV(at:source:)`).
2. Register the new `UTType` in `DictionaryManagerView.fileImporter`.
3. Handle the new extension in `handleImport`.

### Adding word-of-the-day

Query a random entry: `SELECT * FROM entries ORDER BY RANDOM() LIMIT 1`.

### Adding cross-references

Add a `related` table: `CREATE TABLE related (entry_id INTEGER, related_id INTEGER)` and join on lookup.
