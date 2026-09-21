# Recogs — working rules for Claude Code

Native macOS + iOS SwiftUI app for managing a personal vinyl collection via the Discogs API.

## Stack
- SwiftUI multiplatform, macOS 26+ / iOS 26+. One shared feature layer; platform-specific code only where
  the platforms genuinely differ.
- `DiscogsKit`: local Swift package (URLSession + async/await, Codable models, header-aware rate limiter).
- SwiftData for the metadata cache; on-disk image cache. No backend, no iCloud, no third-party dependencies.

## Discogs API
- Base `https://api.discogs.com`. Auth: Personal Access Token — `Authorization: Discogs token=<PAT>`.
- Required `User-Agent: Recogs/1.0 +<contact>`; generic agents get throttled harder.
- Rate limit: 60 req/min authenticated. Route every request through one central throttle that reads the
  `X-Discogs-Ratelimit*` headers, keeps a safety margin, and backs off on 429.
- A copy you own is an **instance** (`instance_id`) of a `release_id` in a `folder_id`. The remove flow keys
  off `instance_id`, not `release_id`.

## Caching
- Cache images permanently on disk, keyed by release id and size. The grid and the record page both
  draw `cover_image` (600px, quality 90); the 150px thumb is a fallback and a row icon. Never re-fetch.
- SwiftData holds every collection item so the collection is browsable offline.

## Secrets — never commit
- The Discogs PAT lives in `.env` (git-ignored) for local testing only, and in the Keychain in the shipping
  app. Never hard-code it, never log it, never add it as a release fallback, never commit `.env`.
