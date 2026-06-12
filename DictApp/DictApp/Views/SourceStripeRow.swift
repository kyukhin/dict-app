// SourceStripeRow.swift
// Shared per-source colour stripe (Issue #6), used by Search results and
// History rows. Bookmarks intentionally do NOT use it.

import SwiftUI

/// Resolves a per-source stripe colour from the Asset Catalog. Resolved 1:1
/// from the row's `source` column (no lookup table); unknown / custom-import
/// sources fall back to the neutral `Sources/default`. The palette is
/// **provisional** and lives only as colorset assets — tunable in the catalog
/// without code changes (design follow-up #6-design). Never hard-code hues here.
func sourceColor(_ source: String) -> Color {
    let name = "Sources/\(source)"
    return UIColor(named: name) != nil ? Color(name) : Color("Sources/default")
}

/// A leading colour stripe + content. The stripe is **decorative and never the
/// sole signal** (§4d): the source badge text remains the primary,
/// VoiceOver-spoken identity. The stripe carries only an XCUITest identifier
/// (`source_stripe_<source>`) and no spoken label. Apply
/// `.listRowInsets(EdgeInsets())` on the enclosing row so the stripe reaches the
/// leading edge; it auto-mirrors to the trailing edge under RTL (#9).
struct SourceStripeRow<Content: View>: View {
    let source: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(sourceColor(source))
                .frame(width: 5)
                .accessibilityIdentifier("source_stripe_\(source)")
            content
                .padding(.leading, 12)
                .padding(.vertical, 2)
        }
    }
}
