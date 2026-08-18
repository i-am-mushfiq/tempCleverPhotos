import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: AlbumCuratorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cacheClearedMessage = false
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Grouping Aggressiveness", selection: $viewModel.similarityMode) {
                        ForEach(SimilarityMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text(viewModel.similarityMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Similarity Engine Settings")
                } footer: {
                    Text("Conservative groups only near-identical burst shots. Aggressive groups visually similar shots across longer timeframes.")
                }
                
                Section {
                    Button(role: .destructive, action: {
                        viewModel.persistenceService.clearCache()
                        cacheClearedMessage = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Analysis Cache")
                        }
                    }
                    if cacheClearedMessage {
                        Text("Local analysis cache successfully cleared.")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Storage & Cache")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Your Photos Stay on Your Device")
                                .font(.headline)
                        }
                        Text("Album Curator performs all photo analysis locally on your iPhone using Apple's Vision framework. We do not operate cloud servers, upload photos, or track telemetry.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Privacy Commitment")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
