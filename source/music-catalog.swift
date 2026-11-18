import Foundation
import SQLite3

// Music may retain a public catalog entry after its temporary playback ID expires.
// Treat both on-disk caches as optional. Only query the requested song, read-only.
struct CalendarCatalogSong {
    let songID: String
    let link: URL
    let artworkPath: String?

    private static func read(_ file: URL, sql: String, args: [String], row: (OpaquePointer) -> Void) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement = statement else { return }
        defer { sqlite3_finalize(statement) }
        for (index, value) in args.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    static func find(_ song: CalendarSong, library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) -> Self? {
        guard !song.title.isEmpty, !song.artist.isEmpty else { return nil }
        let root = library.appendingPathComponent("Application Support/com.apple.MediaPlayer/ServerObjectDatabases")
        guard let stores = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        let sql = """
        SELECT identifier, json_extract(payload,'$.attributes.url'), json_extract(payload,'$.attributes.artwork.url')
        FROM objects WHERE type='songs' AND json_valid(CAST(payload AS TEXT))
        AND json_extract(payload,'$.attributes.name')=? AND json_extract(payload,'$.attributes.artistName')=?
        AND (?='' OR json_extract(payload,'$.attributes.albumName')=?) LIMIT 2
        """
        var matches: [String: Self] = [:]
        for store in stores {
            read(store.appendingPathComponent("Database"), sql: sql, args: [song.title, song.artist, song.album, song.album]) { stmt in
                guard let id = sqlite3_column_text(stmt, 0), let url = sqlite3_column_text(stmt, 1) else { return }
                let songID = String(cString: id)
                guard var parts = URLComponents(string: String(cString: url)), parts.scheme == "https", parts.host == "music.apple.com",
                      !songID.isEmpty, songID.allSatisfy({ $0.isASCII && $0.isNumber }),
                      parts.queryItems?.contains(URLQueryItem(name: "i", value: songID)) == true ||
                        (parts.path.contains("/song/") && parts.path.hasSuffix("/" + songID)) else { return }
                parts.scheme = "music"
                guard let link = parts.url else { return }
                let template = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let prefix = template.flatMap { text -> String? in
                    guard let start = text.range(of: "/image/thumb/")?.lowerBound,
                          let end = text.lastIndex(of: "/"), end > start else { return nil }
                    return String(text[start...end])
                }
                matches[songID] = Self(songID: songID, link: link, artworkPath: prefix)
            }
        }
        return matches.count == 1 ? matches.values.first : nil
    }

    func artwork(library: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")) -> Data? {
        guard let path = artworkPath, path.count > "/image/thumb/".count else { return nil }
        let root = library.appendingPathComponent("Caches/com.apple.Music/MusicUIArtworkCache")
        let sql = """
        SELECT isDataOnFS,receiver_data FROM cfurl_cache_response JOIN cfurl_cache_receiver_data USING(entry_ID)
        WHERE instr(request_key,?)>0 AND length(receiver_data)<=32000000 ORDER BY isDataOnFS DESC LIMIT 24
        """
        var result: Data?
        Self.read(root.appendingPathComponent("Cache.db"), sql: sql, args: [path]) { stmt in
            guard result == nil else { return }
            if sqlite3_column_int(stmt, 0) != 0 {
                guard let text = sqlite3_column_text(stmt, 1) else { return }
                let name = String(cString: text)
                guard UUID(uuidString: name) != nil else { return }
                let file = root.appendingPathComponent("fsCachedData").appendingPathComponent(name)
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32_000_000,
                      let data = try? Data(contentsOf: file) else { return }
                result = CalendarArtwork.png(data)
            } else if let bytes = sqlite3_column_blob(stmt, 1) {
                result = CalendarArtwork.png(Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 1))))
            }
        }
        return result
    }
}
