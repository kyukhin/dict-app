// DefinitionView.swift
// Detailed word view with Markdown rendering and TTS.

import SwiftUI
import StoreKit   // Issue #12: AppStore.requestReview(in:)
import UIKit      // Issue #12: UIWindowScene for the scene-based review request

struct DefinitionView: View {
    @StateObject private var vm: DefinitionViewModel

    init(entry: DictionaryEntry) {
        _vm = StateObject(wrappedValue: DefinitionViewModel(entry: entry))
    }

    /// The active foreground window scene — required by the scene-based review API.
    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
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
                    .accessibilityLabel(Text("definition.a11y.speakWord"))
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
                .accessibilityLabel(Text(vm.isBookmarked ? "definition.a11y.removeBookmark" : "definition.a11y.addBookmark"))
                .accessibilityIdentifier("bookmark_button")
            }
        }
        .task {
            await vm.onAppear()
            // Issue #12: viewing a definition is a "successful search". Bump the
            // counter, then prompt for a review if the heuristic is satisfied.
            let review = ReviewRequestService.shared
            review.recordDefinitionView()
            if review.shouldRequestReview() {
                // NOTE: SwiftUI's `@Environment(\.requestReview)` does NOT present
                // from a NavigationLink-pushed view (Apple-forum 739656; also flaky
                // on iOS 26.x). The scene-based StoreKit API does. Apple still
                // manages the actual presentation and its annual cap.
                // Only consume the attempt when the scene-resolved API is
                // actually invoked — a nil scene would otherwise burn the
                // latch without ever showing the prompt (#80 review).
                if let scene = Self.activeWindowScene {
                    review.markPromptFired()
                    AppStore.requestReview(in: scene)
                }
            }
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
