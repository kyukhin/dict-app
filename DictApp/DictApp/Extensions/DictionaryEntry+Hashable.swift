// DictionaryEntry+Hashable.swift
// Hashable conformance needed for NavigationLink(value:).

import Foundation

extension DictionaryEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(word)
    }
}
