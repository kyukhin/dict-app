// LanguagesView.swift
// Settings → Dictionaries → Languages (Issue #243, docs/specs/0237-downloads.md,
// "Settings → Dictionaries"): every language the app knows, English first,
// then by name, each downloadable, cancellable and removable. `PackRow` is
// the row the first-launch sheet shares (#245).

import SwiftUI

struct LanguagesView: View {
    @StateObject private var viewModel = LanguagesViewModel()
    // Its own edit mode: pushed from Dictionary Order, it must not inherit
    // that list's forced `.active`.
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            ForEach(viewModel.rows) { row in
                PackRow(row: row, state: viewModel.state(of: row), locale: viewModel.locale,
                        install: { if let id = row.pack { viewModel.install(id) } },
                        cancel: { if let id = row.pack { viewModel.cancel(id) } })
                    .deleteDisabled(!viewModel.canRemove(row))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if viewModel.canRemove(row), let id = row.pack {
                            // Not `.destructive`: the row stays (it shows
                            // Download again), and the alert asks first.
                            Button {
                                viewModel.requestRemove(id)
                            } label: {
                                Text("languages.remove")
                            }
                            .tint(.red)
                            .accessibilityIdentifier("pack_remove_\(id.rawValue)")
                        }
                    }
            }
            // Edit mode's delete buttons; a swipe shows "Remove" above.
            .onDelete { offsets in
                if let index = offsets.first, let id = viewModel.rows[index].pack {
                    viewModel.requestRemove(id)
                }
            }
        }
        .accessibilityIdentifier("languages_screen")
        .navigationTitle("languages.title")
        .toolbar {
            if viewModel.hasRemovable || editMode.isEditing {
                // Not `EditButton`: its Edit / Done follow the device
                // language, not the in-app one. Dictionary Order and Manage
                // Dictionaries have no Edit button to follow.
                Button {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                } label: {
                    if editMode.isEditing {
                        Text("languages.done").fontWeight(.semibold)
                    } else {
                        Text("languages.edit")
                    }
                }
                .accessibilityIdentifier("languages_edit")
            }
        }
        .environment(\.editMode, $editMode)
        .onChange(of: viewModel.hasRemovable) { _, removable in
            if !removable {
                editMode = .inactive
            }
        }
        .alert(viewModel.removal?.title ?? "", isPresented: Binding(
            get: { viewModel.removal != nil },
            set: { if !$0 { viewModel.removal = nil } }
        ), presenting: viewModel.removal) { removal in
            Button(role: .destructive) {
                viewModel.confirmRemove(removal)
            } label: {
                Text("languages.remove")
            }
            Button(role: .cancel) {
                viewModel.removal = nil
            } label: {
                Text("languages.cancel")
            }
        } message: { removal in
            Text(verbatim: removal.message)
        }
        .task { await viewModel.refresh() }
    }
}

// MARK: - A pack's row

/// One language and its `PackState` (0237, "Settings → Dictionaries"): the
/// name and contents, then the state's line (a progress bar, or the reason
/// a download failed, in red) and its action. `state` nil: the bundled
/// English, "Included". Mirrors in Arabic.
struct PackRow: View {
    let row: LanguageRow
    let state: PackState?
    let locale: Locale
    let install: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.name)
                    .font(.body)
                    // On the label, not the row: a row-level identifier
                    // would shadow the buttons' own (Issue #6).
                    .accessibilityIdentifier("pack_row_\(row.id)")
                if let contents = row.contents {
                    Text(verbatim: contents)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                statusLine
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.vertical, 2)
    }

    private var id: String { row.id }

    @ViewBuilder
    private var statusLine: some View {
        if let state, let line = PackTexts.progressLine(state, locale: locale) {
            PackProgressBar(fraction: line.fraction, text: line.text, name: row.name, id: id)
        } else if case .failed(let error) = state,
                  let reason = PackTexts.error(error, name: row.name, space: row.downloadSize + row.installedSize,
                                               locale: locale) {
            PackErrorText(reason: reason, id: id)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case nil:
            Text("languages.included")
                .foregroundStyle(.secondary)
        case .notInstalled:
            button(PackTexts.download(row.downloadSize, locale: locale), id: "pack_download_\(id)", run: install)
        case .waiting, .downloading, .installing:
            Button(action: cancel) {
                Text("languages.cancel")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("pack_cancel_\(id)")
        case .installed:
            Text(verbatim: PackTexts.installed(row.installedSize, locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityIdentifier("pack_installed_\(id)")
        case .updateAvailable:
            button(PackTexts.update(row.downloadSize, locale: locale), id: "pack_update_\(id)", run: install)
        case .updateRequired:
            button(PackTexts.updateRequired(row.downloadSize, locale: locale), id: "pack_update_\(id)", run: install)
        case .failed:
            Button(action: install) {
                Text("languages.retry")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("pack_retry_\(id)")
        }
    }

    /// Borderless, so only the button takes the tap and the row still swipes.
    private func button(_ title: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(verbatim: title)
                .font(.subheadline)
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityIdentifier(id)
    }
}

/// A pack's progress bar with its text under it ("3.1 of 6.9 MB",
/// "Waiting"); VoiceOver reads the text as the bar's value.
struct PackProgressBar: View {
    let fraction: Double
    let text: String
    /// The language, VoiceOver's label of the bar.
    let name: String
    /// The pack's id, for `pack_progress_<id>`.
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(max(fraction, 0), 1))
                .accessibilityLabel(Text(verbatim: name))
                .accessibilityValue(Text(verbatim: text))
                .accessibilityIdentifier("pack_progress_\(id)")
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
        }
    }
}

/// Why a pack's download failed, in red (0237, "Offline and errors").
struct PackErrorText: View {
    let reason: String
    let id: String

    var body: some View {
        Text(verbatim: reason)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("pack_error_\(id)")
    }
}

// MARK: - The first-launch sheet (#245)

/// The first-launch sheet (0237, "First launch"): what is included, one
/// row per language to download, checked or not, then Download (the
/// checked total) or Continue, and Not now; a link pushes Manage
/// Dictionaries to import one's own. After Download it shows each chosen
/// language's progress, with Done; the downloads go on when it closes.
/// Swiping it down is Not now. A form sheet on iPad.
struct WelcomeSheet: View {
    @ObservedObject var model: WelcomeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("welcome.title")
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: model.message)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                }
                Section {
                    ForEach(model.shownRows) { row in
                        if model.downloading == nil && model.canCheck(row) {
                            WelcomeLanguageRow(row: row, caption: PackTexts.caption(row, locale: model.locale),
                                               isChecked: model.isChecked(row)) {
                                model.toggle(row)
                            }
                        } else {
                            PackRow(row: row, state: model.state(of: row), locale: model.locale,
                                    install: { if let id = row.pack { model.install(id) } },
                                    cancel: { if let id = row.pack { model.cancel(id) } })
                        }
                    }
                }
                if model.downloading == nil {
                    Section {
                        NavigationLink {
                            ManageDictionariesView()
                        } label: {
                            Text("welcome.import")
                        }
                        .accessibilityIdentifier("welcome_import")
                    }
                }
            }
            .accessibilityIdentifier("welcome_sheet")
            // The title is the first row, where it wraps; Manage
            // Dictionaries' back button still names it.
            .navigationTitle("welcome.title")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                buttons
            }
        }
        .modifier(FormSheetSizing())
        .onDisappear { model.closed() }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if model.downloading == nil {
                Button {
                    if model.download() {
                        dismiss()
                    }
                } label: {
                    Text(verbatim: model.primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("welcome_download")
                Button {
                    model.notNow()
                    dismiss()
                } label: {
                    Text("welcome.notNow")
                }
                .accessibilityIdentifier("welcome_not_now")
            } else {
                Button {
                    dismiss()
                } label: {
                    Text("welcome.done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("welcome_done")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// A language to check in the first-launch sheet: its name, what it holds
/// and its size, and a checkmark. VoiceOver reads a checked row as selected.
/// Mirrors in Arabic.
private struct WelcomeLanguageRow: View {
    let row: LanguageRow
    let caption: String
    let isChecked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                // Colours, not `.primary`: inside a button that resolves
                // to the button's tint.
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: row.name)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isChecked ? .isSelected : [])
        .accessibilityIdentifier("welcome_language_\(row.id)")
    }
}

/// A form sheet on iPad (0237, "UI"); iOS 17 shows one there by default.
private struct FormSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.presentationSizing(.form)
        } else {
            content
        }
    }
}

// MARK: - Not downloaded (#245)

/// The Download of a pack that is not installed (0237, the "not downloaded"
/// view and the Search hint): "Download Greek · 10.7 MB", then its progress
/// with Cancel, or why it failed with Try again. Empty once the pack is
/// installed: the caller then shows the word or the results.
struct PackDownloadPrompt: View {
    let pack: CatalogPack
    @ObservedObject private var status = PackStatusModel.shared
    @Environment(\.locale) private var locale

    var body: some View {
        let state = status.state(of: pack.id)
        VStack(spacing: 8) {
            if let line = PackTexts.progressLine(state, locale: locale) {
                PackProgressBar(fraction: line.fraction, text: line.text, name: name, id: pack.id.rawValue)
                    .frame(maxWidth: 280)
                Button {
                    let id = pack.id
                    Task { await PackService.shared.cancel(id) }
                } label: {
                    Text("languages.cancel")
                }
                .accessibilityIdentifier("pack_cancel_\(pack.id.rawValue)")
            } else if !NotDownloaded.isAvailable(state) {
                if case .failed(let error) = state,
                   let reason = PackTexts.error(error, name: name, space: pack.size + pack.fileSize, locale: locale) {
                    PackErrorText(reason: reason, id: pack.id.rawValue)
                        .multilineTextAlignment(.center)
                }
                Button {
                    let id = pack.id
                    Task { try? await PackService.shared.install(id) }
                } label: {
                    if case .failed = state {
                        Text("languages.retry")
                    } else {
                        Text(verbatim: PackTexts.notDownloadedDownload(pack, locale: locale))
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("not_downloaded_download")
            }
        }
    }

    private var name: String { PackTexts.languageName(pack.lang, locale: locale) }
}

/// A History row or a My words word whose dictionary's pack is not
/// installed (0237, "Update from 1.x"): "This word is in the Greek
/// dictionaries." and its Download. `EntryDestination` opens the word once
/// the pack is installed.
struct NotDownloadedView: View {
    let word: String
    let pack: CatalogPack
    @Environment(\.locale) private var locale

    var body: some View {
        ContentUnavailableView {
            Label(word, systemImage: "arrow.down.circle")
        } description: {
            Text(verbatim: PackTexts.notDownloadedMessage(pack, locale: locale))
        } actions: {
            PackDownloadPrompt(pack: pack)
        }
        .navigationTitle(word)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Search hint under "No results" (0237, "Offline and errors"): a query
/// in the script of a language that is not downloaded (Greek, Cyrillic,
/// Arabic) names it, with its Download. Hidden once the pack is installed.
struct NotDownloadedHint: View {
    let pack: CatalogPack
    @ObservedObject private var status = PackStatusModel.shared
    @Environment(\.locale) private var locale

    var body: some View {
        if !NotDownloaded.isAvailable(status.state(of: pack.id)) {
            VStack(spacing: 12) {
                Text(verbatim: PackTexts.notDownloadedSearch(pack, locale: locale))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    // On the text, not the row: a row identifier would
                    // shadow the button's (Issue #6).
                    .accessibilityIdentifier("search_not_downloaded")
                PackDownloadPrompt(pack: pack)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
