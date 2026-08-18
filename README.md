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
   - Complete `.github/workflows/build-and-test.yml` GitHub Actions pipeline for compiling, executing automated tests, and signing binaries via macOS runners for personal sideloading on iPhone.

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

Run unit tests directly:

```bash
swift test
```

### GitHub Actions CI/CD Pipeline

Pushing changes to `main` triggers `.github/workflows/build-and-test.yml` on a GitHub-hosted `macos-14` runner which:
1. Compiles the Swift package.
2. Executes the full XCTest suite.
3. Verifies the safety invariant using static analysis (`grep -rn "deleteAssets" Sources/`).
4. Generates signed iOS builds for personal sideloading.
