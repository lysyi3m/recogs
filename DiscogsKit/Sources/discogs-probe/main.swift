import DevSupport
import DiscogsKit
import Foundation

// Dev-only smoke test: resolve the identity behind DISCOGS_PAT and print the first page of the
// collection, so DiscogsKit is validated against the real API before any UI exists.

let environment = ProcessInfo.processInfo.environment
let dotEnv = DotEnv.load()

func value(_ key: String) -> String? {
    let raw = environment[key] ?? dotEnv[key]
    guard let raw, !raw.isEmpty else { return nil }
    return raw
}

guard let token = value("DISCOGS_PAT") else {
    FileHandle.standardError.write(Data("""
    error: DISCOGS_PAT not found.
    Set it in .env at the repository root, or export it in the environment.

    """.utf8))
    exit(1)
}

// Discogs throttles generic agents harder, so the User-Agent must carry a real contact.
let contact = value("DISCOGS_CONTACT") ?? DiscogsConfiguration.contact

let configuration = DiscogsConfiguration(
    userAgent: DiscogsConfiguration.userAgent(contact: contact)
)
let client = DiscogsClient(token: token, configuration: configuration)

func printRateLimit(_ label: String) async {
    let state = await client.rateLimiter.state
    let used = state.used.map(String.init) ?? "?"
    let remaining = state.remaining.map(String.init) ?? "?"
    print("  [rate limit after \(label)] limit=\(state.limit) used=\(used) remaining=\(remaining)")
}

let cdnCheckOnly = CommandLine.arguments.contains("--cdn-check")
let releaseOnly = CommandLine.arguments.contains("--release")
let searchQuery: String? = {
    guard let index = CommandLine.arguments.firstIndex(of: "--search") else { return nil }
    let next = CommandLine.arguments.index(after: index)
    return next < CommandLine.arguments.endIndex ? CommandLine.arguments[next] : "remain in light"
}()

do {
    print("User-Agent: \(configuration.userAgent)")
    print("\n== GET /oauth/identity ==")
    let identity = try await client.identity()
    print("  username: \(identity.username)")
    print("  user id:  \(identity.id)")
    await printRateLimit("identity")

    if let searchQuery {
        print("\n== GET /database/search?type=release&q=\(searchQuery) ==")
        let page = try await client.searchReleases(query: searchQuery, perPage: 8)
        print("  \(page.pagination.items) match(es), showing \(page.results.count)")
        for result in page.results {
            let year = result.year.map(String.init) ?? "----"
            print("  [\(result.id)] \(result.artistName ?? "?") — \(result.releaseTitle) (\(year))")
            print("       \(result.formatDisplayName) · \(result.label.first ?? "no label") \(result.catno ?? "")")
            print("       \(result.country ?? "?")")
        }
        await printRateLimit("search")
        exit(0)
    }

    if releaseOnly {
        let page = try await client.collectionPage(user: identity.username, page: 1, perPage: 1)
        guard let first = page.releases.first else {
            print("\n  collection is empty")
            exit(0)
        }
        print("\n== GET /releases/\(first.releaseID) ==")
        let release = try await client.release(id: first.releaseID)
        print("  \(release.artistDisplayName) — \(release.title)")
        print("  \(release.formatDisplayName)")
        print("  released \(release.released ?? "?") · country \(release.country ?? "?")")
        print("  primary image: \(release.primaryImage?.uri ?? "none")")
        print("  discogs page: \(release.uri ?? "none")")
        print("  tracklist (\(release.tracklist.filter(\.isTrack).count) tracks):")
        for track in release.tracklist {
            if track.isTrack {
                let duration = track.duration.isEmpty ? "" : "  (\(track.duration))"
                print("    \(track.position.isEmpty ? "-" : track.position)  \(track.title)\(duration)")
            } else {
                print("    [\(track.type)] \(track.title)")
            }
        }
        await printRateLimit("release")
        exit(0)
    }

    if cdnCheckOnly {
        print("")
        try await CDNCheck.run(client: client, identity: identity)
        exit(0)
    }

    print("\n== GET /users/\(identity.username)/collection/folders ==")
    let folders = try await client.folders(user: identity.username)
    for folder in folders {
        print("  [\(folder.id)] \(folder.name) — \(folder.count) item(s)")
    }
    await printRateLimit("folders")

    print("\n== GET collection folder 0, page 1 ==")
    let page = try await client.collectionPage(
        user: identity.username,
        folderID: DiscogsFolder.all,
        page: 1,
        sort: .added,
        order: .descending
    )
    let pagination = page.pagination
    print("  page \(pagination.page)/\(pagination.pages) · per_page \(pagination.perPage) · \(pagination.items) item(s) total")
    await printRateLimit("collection page 1")
    print("")

    for (index, item) in page.releases.enumerated() {
        let year = item.basicInformation.year.map(String.init) ?? "----"
        let added = item.dateAdded.map {
            $0.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        } ?? "unknown"
        print(String(format: "  %3d. %@ — %@ (%@)", index + 1, item.basicInformation.artistDisplayName, item.basicInformation.title, year))
        print("       instance \(item.instanceID) · release \(item.releaseID) · folder \(item.folderID) · added \(added)")
        print("       \(item.basicInformation.formatDisplayName)")
        if let label = item.basicInformation.labels.first {
            print("       label: \(label.name)\(label.catno.map { " — \($0)" } ?? "")")
        }
        print("       thumb: \(item.basicInformation.thumb ?? "none")")
        print("       cover: \(item.basicInformation.coverImage ?? "none")")
    }

    if pagination.pages > 1 {
        print("\n  \(pagination.pages - 1) further page(s) available; the client pages them via collectionPages(user:).")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
