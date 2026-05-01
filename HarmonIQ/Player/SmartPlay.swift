import Foundation

enum SmartPlayMode: String, CaseIterable, Identifiable {
    case pureRandom
    case artistRoulette
    case genreJourney
    case albumWalk
    case decadeShuffle
    case freshlyAdded
    case quickHits
    case longPlayer
    case discoveryMix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pureRandom:     return "Pure Random"
        case .artistRoulette: return "Artist Roulette"
        case .genreJourney:   return "Genre Journey"
        case .albumWalk:      return "Album Walk"
        case .decadeShuffle:  return "Decade Shuffle"
        case .freshlyAdded:   return "Freshly Added"
        case .quickHits:      return "Quick Hits"
        case .longPlayer:     return "Long Player"
        case .discoveryMix:   return "Discovery Mix"
        }
    }

    var subtitle: String {
        switch self {
        case .pureRandom:     return "Every track in the library, in a fresh random order."
        case .artistRoulette: return "One artist at a time, then jump — never the same artist twice in a row."
        case .genreJourney:   return "Group by genre, drift across genres in one sitting."
        case .albumWalk:      return "One album, in order. Then the next album. No interruptions."
        case .decadeShuffle:  return "Walk decade by decade — '70s, '80s, '90s — shuffled within each."
        case .freshlyAdded:   return "Newest indexed tracks first."
        case .quickHits:      return "Only tracks under 3 minutes, shuffled."
        case .longPlayer:     return "Tracks 6 minutes and longer, shuffled."
        case .discoveryMix:   return "Weighted toward tracks you haven't heard recently in this session."
        }
    }

    var systemImage: String {
        switch self {
        case .pureRandom:     return "shuffle"
        case .artistRoulette: return "person.2"
        case .genreJourney:   return "music.note.list"
        case .albumWalk:      return "square.stack"
        case .decadeShuffle:  return "calendar"
        case .freshlyAdded:   return "sparkles"
        case .quickHits:      return "bolt.fill"
        case .longPlayer:     return "infinity"
        case .discoveryMix:   return "wand.and.stars"
        }
    }
}

enum SmartPlayBuilder {
    /// Build a queue ordered according to `mode` from the given pool.
    /// `recentlyPlayed` is a Set of stableIDs known to have played in the current session — used by `discoveryMix`.
    static func buildQueue(mode: SmartPlayMode, from pool: [Track], recentlyPlayed: Set<String> = []) -> [Track] {
        guard !pool.isEmpty else { return [] }

        switch mode {
        case .pureRandom:
            return pool.shuffled()

        case .artistRoulette:
            let grouped = Dictionary(grouping: pool, by: { $0.displayArtist })
            var buckets = grouped.mapValues { $0.shuffled() }
            var result: [Track] = []
            result.reserveCapacity(pool.count)
            var lastArtist: String? = nil
            // Round-robin pull, but never twice in a row from the same artist when an alternative exists.
            while !buckets.isEmpty {
                let candidates = buckets.keys.filter { $0 != lastArtist }
                let pickKey = (candidates.isEmpty ? buckets.keys.shuffled().first : candidates.shuffled().first)!
                if var arr = buckets[pickKey], let next = arr.first {
                    result.append(next)
                    arr.removeFirst()
                    if arr.isEmpty { buckets.removeValue(forKey: pickKey) } else { buckets[pickKey] = arr }
                    lastArtist = pickKey
                } else {
                    buckets.removeValue(forKey: pickKey)
                }
            }
            return result

        case .genreJourney:
            // Group by genre (Unknown when missing), shuffle within group, then chain groups in random order.
            let grouped = Dictionary(grouping: pool, by: { ($0.genre?.nilIfBlank) ?? "Unknown" })
            let orderedKeys = grouped.keys.shuffled()
            return orderedKeys.flatMap { (grouped[$0] ?? []).shuffled() }

        case .albumWalk:
            // Whole albums in order, albums themselves in random order.
            struct Key: Hashable { let artist: String; let album: String }
            let grouped = Dictionary(grouping: pool, by: { Key(artist: $0.displayArtist, album: $0.displayAlbum) })
            let orderedKeys = grouped.keys.shuffled()
            return orderedKeys.flatMap { key in
                (grouped[key] ?? []).sorted { lhs, rhs in
                    if let l = lhs.discNumber, let r = rhs.discNumber, l != r { return l < r }
                    if let l = lhs.trackNumber, let r = rhs.trackNumber, l != r { return l < r }
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }
            }

        case .decadeShuffle:
            // Group by decade (e.g. 1970, 1980). Tracks without a year go to "Unknown" at the end.
            let grouped = Dictionary(grouping: pool) { track -> Int? in
                guard let y = track.year, y > 0 else { return nil }
                return (y / 10) * 10
            }
            let knownDecades = grouped.keys.compactMap { $0 }.sorted()
            var queue: [Track] = []
            for decade in knownDecades {
                queue.append(contentsOf: (grouped[decade] ?? []).shuffled())
            }
            if let unknowns = grouped[nil] {
                queue.append(contentsOf: unknowns.shuffled())
            }
            return queue

        case .freshlyAdded:
            // Newest = highest stableID in our index? We don't store an addedAt, so approximate
            // by reverse-sorting on the path string; falls back to title.
            // (Indexer appends new tracks at the end of `tracks`, so reverse keeps newer first.)
            return Array(pool.reversed())

        case .quickHits:
            return pool.filter { $0.duration > 0 && $0.duration < 180 }.shuffled()

        case .longPlayer:
            return pool.filter { $0.duration >= 360 }.shuffled()

        case .discoveryMix:
            // Tracks not in recentlyPlayed first (shuffled), then everything else (also shuffled).
            let unheard = pool.filter { !recentlyPlayed.contains($0.stableID) }.shuffled()
            let heard = pool.filter { recentlyPlayed.contains($0.stableID) }.shuffled()
            return unheard + heard
        }
    }
}
