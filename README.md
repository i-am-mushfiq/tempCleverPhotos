# Album Curator — Non-Destructive Photo Album Curator (iOS)

**Album Curator** is a native iOS photo-management application built specifically to operate at the **Photos album level**.

It analyzes photos contained within a selected album, groups visually and temporally similar shots, determines the strongest photograph using technical and aesthetic quality signals, and presents high-confidence recommendations for rapid review and removal **from that album only** — without deleting underlying photos from the user's Photos Library.

---

## Core Product Promise

> **Clean up your albums in minutes, without deleting your photos.**

---

## Key Features

1. **Non-Destructive by Architecture**:
   - The application has **zero photo-deletion capability** (`PHAssetChangeRequest.deleteAssets` is intentionally absent).
   - Only modifies album membership (`removeAssets`). Photos remain 100% safe in the global Photos Library.

2. **On-Device Vision Analysis Engine**:
   - 100% private, on-device image processing using Apple's Vision framework.
   - Multi-stage pipeline: Timestamp Filtering → Perceptual dHash → Vision FeaturePrints → Sharpness (Laplacian variance), Exposure, Face Landmark & Aesthetic Signals → Multi-Keeper Clustering → Confidence Scoring.

3. **Configurable Similarity Modes**:
   - **Conservative**: Burst-like sequences and near-identical shots (30s time window).
   - **Balanced** (Default): Similar shots of the same moment or scene (3 min time window).
   - **Aggressive**: Visually similar shots across broader timeframes (10 min time window).

4. **Multi-Keeper & Manual Overrides**:
   - Supports keeping multiple photos in a cluster if quality scores are close or subjects differ.
   - Users can manually override any recommendation, skip clusters, or accept all high-confidence recommendations in bulk.

5. **Single-Tap Undo & Local Persistence**:
   - Records an immutable transaction log of album cleanups.
   - Restores removed photos back to their original albums with a single tap.
   - Incremental local JSON caching speeds up subsequent scans.

6. **No-Mac Sideloading CI/CD Workflow**:
   - Complete `.github/workflows/build-and-test.yml` GitHub Actions pipeline for compiling and executing automated tests via macOS runners.
   - By default (no signing secrets configured) it produces an **unsigned** `.ipa` — you re-sign it yourself (e.g. via [Sideloadly](https://sideloadly.io/) with a personal Apple ID) before installing on a device. If you add your own personal Apple Developer certificate + provisioning profile as repo secrets, CI hands you back an already-**signed**, installable `.ipa` directly. See [CI/CD Pipeline](#github-actions-cicd-pipeline) below for the required secret names.

---

## Project Structure

```text
tempCleverPhotos/
├── Package.swift
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── build-and-test.yml
├── Sources/
│   └── AlbumCuratorApp/
│       ├── AlbumCuratorApp.swift
│       ├── Models/
│       │   ├── PhotoAsset.swift
│       │   ├── PhotoAnalysis.swift
│       │   ├── PhotoCluster.swift
│       │   ├── SimilarityMode.swift
│       │   └── MutationTransaction.swift
│       ├── Services/
│       │   ├── PhotoKitService.swift
│       │   ├── MockPhotoKitService.swift
│       │   ├── VisionAnalysisEngine.swift
│       │   ├── LocalPersistenceService.swift
│       │   └── TransactionManager.swift
│       ├── ViewModels/
│       │   └── AlbumCuratorViewModel.swift
│       └── Views/
│           ├── OnboardingView.swift
│           ├── AlbumListView.swift
│           ├── ScanningView.swift
│           ├── ResultsSummaryView.swift
│           ├── GroupReviewView.swift
│           ├── ConfirmationModal.swift
│           ├── CompletionView.swift
│           ├── TransactionHistoryView.swift
│           ├── SettingsView.swift
│           └── Components/
│               ├── ConfidenceBadge.swift
│               ├── PhotoThumbnailView.swift
│               └── CardContainer.swift
└── Tests/
    └── AlbumCuratorTests/
        ├── PhotoKitSafetyTests.swift
        ├── VisionEngineTests.swift
        ├── TransactionManagerTests.swift
        └── PersistenceTests.swift
```

---

## Building and Running Tests

### Automated Testing (Swift PM)

`swift test` runs against the **macOS host** toolchain by default, but two source files
(`PHAssetImageView.swift`, `ColorExtensions.swift`) import `UIKit`, which isn't available
outside iOS/Mac Catalyst — so a plain `swift test` invocation will fail to compile on a
Mac that isn't running Catalyst. Instead, build and run the suite against the iOS
Simulator SDK:

```bash
xcodebuild test -scheme AlbumCurator -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest'
```

### GitHub Actions CI/CD Pipeline

Pushing changes to `main` triggers `.github/workflows/build-and-test.yml` on a GitHub-hosted `macos-14` runner which:
1. Builds and runs the full XCTest suite against the iOS Simulator SDK (this is the real test gate — a failing or non-compiling test fails the job).
2. Compiles the app target via `xcodegen` + `xcodebuild` against the iOS Simulator SDK.
3. Verifies the safety invariant using static analysis (`grep -rn "deleteAssets" Sources/`).
4. Verifies the real Vision engine is wired in (`grep -rn "VNGenerateImageFeaturePrintRequest" Sources/`).
5. Builds a release `.ipa` for `iphoneos`:
   - **Unsigned** by default — you re-sign it yourself before installing (e.g. via Sideloadly + a personal Apple ID).
   - **Signed**, if you add these repository secrets from your own Apple Developer account:

     | Secret | Description |
     |---|---|
     | `IOS_DIST_CERTIFICATE_BASE64` | Your distribution/development `.p12` certificate, base64-encoded (`base64 -i cert.p12`). |
     | `IOS_DIST_CERTIFICATE_PASSWORD` | Password protecting that `.p12`. |
     | `IOS_PROVISIONING_PROFILE_BASE64` | Your `.mobileprovision` file, base64-encoded. |
     | `IOS_DEVELOPMENT_TEAM` | Your 10-character Apple Developer Team ID. |
     | `IOS_CODE_SIGN_IDENTITY` | e.g. `Apple Development` or `iPhone Distribution`. |
     | `IOS_PROVISIONING_PROFILE_NAME` | The profile's name (as shown in the profile itself), used as `PROVISIONING_PROFILE_SPECIFIER`. |
     | `IOS_KEYCHAIN_PASSWORD` *(optional)* | Password for the temporary CI keychain; a random one is generated per run if omitted. |

   The resulting artifact is uploaded as `AlbumCurator-IPA-signed` or `AlbumCurator-IPA-unsigned` depending on which path ran.
