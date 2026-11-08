// CreditsView.swift
// Static credits and acknowledgments view

import SwiftUI

struct CreditsView: View {
    var body: some View {
        List {
            Section("credits.app.section") {
                Text("credits.app.description")
            }
            // #180: every data source the app ships, in the bundle or in a
            // pack, installed or not, with its license and attribution.
            Section("credits.dataSources.section") {
                ForEach(Credits.dataSources) { line in
                    Text(LocalizedStringKey(line.key))
                        .accessibilityIdentifier(line.accessibilityID)
                }
            }
            // #180: the libraries the app links; a row opens its license.
            Section("credits.software.section") {
                ForEach(Credits.software) { software in
                    NavigationLink {
                        SoftwareLicenseView(software: software)
                    } label: {
                        Text(LocalizedStringKey(software.key))
                    }
                    .accessibilityIdentifier(software.accessibilityID)
                }
            }
            // #180: the licenses the lines name, untranslated, each a link
            // to its text.
            Section("credits.licenses.section") {
                ForEach(Credits.licenses) { license in
                    if let url = license.url {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: license.name)
                                Text(verbatim: license.address)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier(license.accessibilityID)
                    }
                }
            }
        }
        .navigationTitle("credits.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A library's license file, verbatim and untranslated (English legal
/// text), titled with the library's name.
private struct SoftwareLicenseView: View {
    let software: CreditSoftware

    var body: some View {
        List {
            // English text: left-aligned in a right-to-left UI too.
            Text(verbatim: software.licenseText)
                .font(.footnote)
                .textSelection(.enabled)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("credits_software_license_text")
        }
        .navigationTitle(Text(verbatim: software.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
