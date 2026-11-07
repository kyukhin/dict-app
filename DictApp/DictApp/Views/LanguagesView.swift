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
        switch state {
        case .waiting:
            progress(0, text: SettingsViewModel.localizedString("languages.waiting", locale: locale))
        case .downloading(let received, let total):
            progress(total > 0 ? Double(received) / Double(total) : 0,
                     text: PackTexts.progress(received: received, total: total, locale: locale))
        case .installing:
            progress(1, text: SettingsViewModel.localizedString("languages.installing", locale: locale))
        case .failed(let error):
            if let reason = PackTexts.error(error, name: row.name, space: row.downloadSize + row.installedSize,
                                            locale: locale) {
                Text(verbatim: reason)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pack_error_\(id)")
            }
        case nil, .notInstalled, .installed, .updateAvailable, .updateRequired:
            EmptyView()
        }
    }

    /// The bar, with its text under it; VoiceOver reads the text as the
    /// bar's value.
    private func progress(_ fraction: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: min(max(fraction, 0), 1))
                .accessibilityLabel(Text(verbatim: row.name))
                .accessibilityValue(Text(verbatim: text))
                .accessibilityIdentifier("pack_progress_\(id)")
            Text(verbatim: text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityHidden(true)
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
