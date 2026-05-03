import Foundation

/// Language bucket used by the Library → Language browse view (issue #86).
///
/// Classification is heuristic — based on the characters in `title + artist`.
/// Computed once at index time and persisted on `Track.language`. Tradeoffs
/// documented on `classify(title:artist:)` below.
enum TrackLanguage: String, CaseIterable, Codable, Hashable {
    /// Title or artist contains any character in the CJK Unified Ideographs
    /// blocks. Known v1 limitation: this conflates Japanese kanji and
    /// Korean hanja with Chinese — files written in those scripts ALSO
    /// land here. Sub-bucketing is explicitly out of scope.
    case chinese
    /// All letters in `title + artist` are basic Latin (a-z / A-Z), with
    /// digits and punctuation tolerated. The default bucket for English-
    /// language tracks.
    case english
    /// Everything else: Cyrillic, Arabic, Thai, hiragana/katakana-only,
    /// hangul-only, accented Latin (French / Spanish / German), and
    /// instrumental tracks whose title is empty / numeric / symbol-only.
    case others

    /// Sort order on the Language hub. Chinese first, English second,
    /// Others last — matches the order in the issue body.
    static let displayOrder: [TrackLanguage] = [.chinese, .english, .others]

    var displayName: String {
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .others:  return "Others"
        }
    }

    /// SF Symbol for the Library row. Picked to be visually distinct
    /// from other Browse rows (artists, albums, folders).
    var iconName: String {
        switch self {
        case .chinese: return "character.book.closed"
        case .english: return "textformat"
        case .others:  return "globe"
        }
    }

    /// Heuristic classification. Pure function — safe to call from any
    /// actor. Empty/whitespace-only and symbol-only inputs (i.e.
    /// instrumentals where neither tag was set) classify as `.others`,
    /// which the issue spec calls out by name.
    static func classify(title: String?, artist: String?) -> TrackLanguage {
        let combined = ((title ?? "") + " " + (artist ?? ""))
        // Strip whitespace; the rule "all letters basic Latin → English"
        // would otherwise be skewed by stray whitespace that contains
        // no letters.
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)

        if containsCJK(trimmed) { return .chinese }

        // After excluding CJK, decide if there's enough Latin signal to
        // call it English. We look at letters only (ignoring digits and
        // punctuation): if at least one letter exists AND every letter
        // is basic Latin a-z / A-Z, it's English. This means a track
        // whose title is "01 - Untitled" (no letters, just digits +
        // dashes) lands in Others, which matches the issue's
        // "pure music … instrumental" intent.
        var hasLetter = false
        var allBasicLatin = true
        for scalar in trimmed.unicodeScalars {
            if isLetter(scalar) {
                hasLetter = true
                if !isBasicLatinLetter(scalar) {
                    allBasicLatin = false
                    break
                }
            }
        }
        if hasLetter && allBasicLatin { return .english }
        return .others
    }

    // MARK: - Character class helpers

    /// CJK Unified Ideographs blocks. The list here is the practical set
    /// of ranges actually used by Chinese / Japanese kanji / Korean
    /// hanja text — Extension B+ (the Plane 2 ranges) are rare enough
    /// that omitting them costs nothing and keeps this fast.
    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x3400...0x4DBF,    // CJK Unified Ideographs Extension A
        0x4E00...0x9FFF,    // CJK Unified Ideographs (the common one)
        0xF900...0xFAFF,    // CJK Compatibility Ideographs
        0x20000...0x2A6DF,  // Extension B
        0x2A700...0x2B73F,  // Extension C
        0x2B740...0x2B81F,  // Extension D
    ]

    private static func containsCJK(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            for r in cjkRanges where r.contains(v) { return true }
        }
        return false
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic
    }

    private static func isBasicLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
    }
}
