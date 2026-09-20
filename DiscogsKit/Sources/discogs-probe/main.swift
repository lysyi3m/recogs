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

do {
    print("User-Agent: \(configuration.userAgent)")
    print("\n== GET /oauth/identity ==")
    let identity = try await client.identity()
    print("  username: \(identity.username)")
    print("  user id:  \(identity.id)")
    await printRateLimit("identity")

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
    }

    if pagination.pages > 1 {
        print("\n  \(pagination.pages - 1) further page(s) available; the client pages them via collectionPages(user:).")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
