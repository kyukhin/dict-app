// DefinitionView.swift
// Detailed word view with Markdown rendering and TTS.

import SwiftUI

struct DefinitionView: View {
    @StateObject private var vm: DefinitionViewModel

    init(entry: DictionaryEntry) {
        _vm = StateObject(wrappedValue: DefinitionViewModel(entry: entry))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Word header
                HStack(alignment: .firstTextBaseline) {
                    Text(vm.entry.word)
                        .font(.largeTitle.bold())

                    Spacer()

                    Button {
                        vm.speak()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("Speak word")
                }

                // Phonetic
                if !vm.entry.phonetic.isEmpty {
                    Text(vm.entry.phonetic)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Part of speech
                if !vm.entry.pos.isEmpty {
                    Text(vm.entry.pos)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Definition with Markdown rendering
                Text(markdownDefinition)
                    .font(.body)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("definition_content")
            }
            .padding()
        }
        .accessibilityIdentifier("definition_view")
        .navigationTitle(vm.entry.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.toggleBookmark() }
                } label: {
                    Image(systemName: vm.isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(vm.isBookmarked ? "Remove bookmark" : "Add bookmark")
                .accessibilityIdentifier("bookmark_button")
            }
        }
        .task {
            await vm.onAppear()
        }
    }

    /// Parse the definition string as Markdown so **bold**, *italic*, and
    /// numbered lists render properly instead of showing raw syntax.
    private var markdownDefinition: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: vm.entry.definition, options: options) {
            return parsed
        }
        return AttributedString(vm.entry.definition)
    }
}
