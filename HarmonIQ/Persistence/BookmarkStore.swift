import Foundation

enum BookmarkError: Error {
    case stale
    case resolveFailed
    case startAccessFailed
}

/// Helpers for security-scoped bookmarks (USB drives, iCloud Drive, external folders picked via UIDocumentPicker).
enum BookmarkStore {
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveURL(from bookmark: Data) throws -> (URL, Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    /// Starts security-scoped access for the URL and runs the closure with it. Caller is NOT responsible for stopping access — done here.
    static func withAccess<T>(to bookmark: Data, _ body: (URL) throws -> T) throws -> T {
        let (url, _) = try resolveURL(from: bookmark)
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// Variant returning whether the bookmark was stale so the caller can re-create it.
    static func withAccessReportingStale<T>(to bookmark: Data, _ body: (URL, _ isStale: Bool) throws -> T) throws -> T {
        let (url, stale) = try resolveURL(from: bookmark)
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url, stale)
    }
}
