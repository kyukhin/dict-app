// DictionaryDetailView.swift
// Detail view for a single dictionary source.

import SwiftUI

struct DictionaryDetailView: View {
    let source: String
    @State private var metadata: DictMetadata?
    @State private var entryCount: Int = 0

    var body: some View {
        List {
            if let meta = metadata {
                Section("General") {
                    LabeledContent("Full Name", value: meta.displayName)
                    LabeledContent("Source ID", value: meta.source)
                    if !meta.version.isEmpty {
                        LabeledContent("Version", value: meta.version)
                    }
                }

                Section("Statistics") {
                    LabeledContent("Word Count", value: entryCount.formatted())
                }

                if !meta.description.isEmpty {
                    Section("Description") {
                        Text(meta.description)
                            .font(.subheadline)
                    }
                }

                if !meta.license.isEmpty {
                    Section("License") {
                        Text(meta.license)
                            .font(.caption)
                    }
                }

                if !meta.url.isEmpty {
                    Section("Source URL") {
                        Link(meta.url, destination: URL(string: meta.url)!)
                            .font(.subheadline)
                    }
                }

                if let builtAt = meta.builtAt, !builtAt.isEmpty {
                    Section("Build Info") {
                        LabeledContent("Built At", value: builtAt)
                    }
                }
            } else {
                Section {
                    LabeledContent("Source", value: source)
                    LabeledContent("Word Count", value: entryCount.formatted())
                }
                Section {
                    Text("No detailed metadata available for this dictionary.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(metadata?.displayName ?? source.capitalized)
        .task {
            metadata = try? await DatabaseService.shared.fetchMetadata(source: source)
            entryCount = (try? await DatabaseService.shared.entryCount(source: source)) ?? 0
        }
    }
}
