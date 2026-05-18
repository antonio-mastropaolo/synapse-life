import Foundation
import SwiftUI
import CryptoKit

/// Resolves merchant strings ("ANTHROPIC", "NETFLIX.COM", "amzn mktp
/// us *m27p9") to a remote logo URL + an on-disk cache key. Two-stage
/// pipeline:
///
///   1. **Normalise** the raw merchant string — strip common bank-feed
///      noise (`*`, `#NNN`, trailing 4-digit suffixes, leading "Sample"
///      placeholders), uppercase, take the meaningful token.
///   2. **Map to a domain.** A curated table covers the ~30 brands that
///      show up most in personal finance feeds. Fallback: try the
///      token as `<token>.com` if it looks plausibly like a domain
///      stem. Unmatched merchants return `nil` and the view falls
///      back to its initial-letter swatch.
///
/// We delegate the actual fetch to Clearbit's Logo API
/// (`https://logo.clearbit.com/<domain>`) — free, no API key required,
/// returns a transparent PNG at ~128px. Per-domain results are cached
/// on disk under `~/Library/Caches/MerchantIcons/<hash>.png` so the
/// dashboard doesn't re-fetch on every render.
///
/// Domains kept in code rather than shipping as a separate JSON
/// because the table is tiny and editing it requires a recompile
/// anyway (the matcher is regex-tuned per row).
public enum MerchantLogoResolver {

    // MARK: - Public API

    /// Best-effort domain for a raw merchant string. `nil` means the
    /// view should fall back to the letter-swatch path.
    public static func domain(for merchant: String) -> String? {
        let token = normalise(merchant)
        if token.isEmpty { return nil }

        // Sample/demo placeholders short-circuit to nil — we never
        // want to resolve "Sample Coffee Shop" to a real brand.
        if merchant.lowercased().contains("sample") { return nil }
        if merchant.lowercased().hasPrefix("demo ") { return nil }

        // Curated table — most-specific patterns first.
        for entry in table {
            for pattern in entry.patterns {
                if token.contains(pattern) {
                    return entry.domain
                }
            }
        }
        return nil
    }

    /// Remote URL for the given domain. Clearbit hosts a free
    /// pass-through logo CDN — no API key needed.
    public static func url(for domain: String) -> URL? {
        URL(string: "https://logo.clearbit.com/\(domain)?size=128")
    }

    /// Disk-cache file path for a domain. Returns nil if the caches
    /// directory can't be resolved (sandbox issue).
    public static func cacheURL(for domain: String) -> URL? {
        let fm = FileManager.default
        guard let cachesDir = fm.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = cachesDir.appendingPathComponent("MerchantIcons", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = sha256(domain.lowercased())
        return dir.appendingPathComponent("\(key).png")
    }

    /// Fetch + cache the logo for a domain. Returns the on-disk URL
    /// once the bytes are persisted, or throws. Idempotent — if the
    /// file already exists, returns immediately without re-fetching.
    @discardableResult
    public static func ensureCached(domain: String) async throws -> URL {
        guard let dest = cacheURL(for: domain) else {
            throw FetchError.cacheUnavailable
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        guard let url = url(for: domain) else {
            throw FetchError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FetchError.httpStatus(http.statusCode)
        }
        try data.write(to: dest, options: .atomic)
        return dest
    }

    public enum FetchError: Error, Sendable {
        case cacheUnavailable
        case invalidURL
        case httpStatus(Int)
    }

    // MARK: - Curated table

    private struct Entry {
        let domain: String
        /// Uppercase substring patterns. The first match wins; order
        /// the array so more-specific patterns come first.
        let patterns: [String]
    }

    /// ~30 brands covering the long tail of US personal finance
    /// transaction feeds. Add to this table as new merchants appear —
    /// each row is one edit.
    private static let table: [Entry] = [
        // AI / dev tools
        .init(domain: "anthropic.com",   patterns: ["ANTHROPIC", "CLAUDE"]),
        .init(domain: "openai.com",      patterns: ["OPENAI", "CHATGPT"]),
        .init(domain: "github.com",      patterns: ["GITHUB"]),
        .init(domain: "cursor.sh",       patterns: ["CURSOR"]),
        // Streaming / media
        .init(domain: "netflix.com",     patterns: ["NETFLIX"]),
        .init(domain: "spotify.com",     patterns: ["SPOTIFY"]),
        .init(domain: "hulu.com",        patterns: ["HULU"]),
        .init(domain: "disneyplus.com",  patterns: ["DISNEY"]),
        .init(domain: "hbomax.com",      patterns: ["HBO MAX", "MAX.COM"]),
        .init(domain: "nytimes.com",     patterns: ["NYTIMES", "NEW YORK TIMES", "NYT "]),
        .init(domain: "youtube.com",     patterns: ["YOUTUBE PREMIUM", "YT PREMIUM"]),
        // Subscriptions / cloud
        .init(domain: "apple.com",       patterns: ["APPLE.COM/BILL", "ICLOUD", "APPLE INC"]),
        .init(domain: "adobe.com",       patterns: ["ADOBE"]),
        .init(domain: "dropbox.com",     patterns: ["DROPBOX"]),
        // Shopping
        .init(domain: "amazon.com",      patterns: ["AMAZON", "AMZN"]),
        .init(domain: "ebay.com",        patterns: ["EBAY"]),
        .init(domain: "etsy.com",        patterns: ["ETSY"]),
        .init(domain: "target.com",      patterns: ["TARGET"]),
        .init(domain: "walmart.com",     patterns: ["WALMART", "WAL-MART"]),
        // Food / coffee / fast casual
        .init(domain: "starbucks.com",   patterns: ["STARBUCKS"]),
        .init(domain: "chipotle.com",    patterns: ["CHIPOTLE"]),
        .init(domain: "panerabread.com", patterns: ["PANERA"]),
        .init(domain: "wholefoodsmarket.com", patterns: ["WHOLE FOODS", "WHOLEFDS"]),
        .init(domain: "traderjoes.com",  patterns: ["TRADER JOE"]),
        .init(domain: "wegmans.com",     patterns: ["WEGMANS"]),
        .init(domain: "kroger.com",      patterns: ["KROGER"]),
        .init(domain: "doordash.com",    patterns: ["DOORDASH", "DASHPASS"]),
        .init(domain: "ubereats.com",    patterns: ["UBER EATS", "UBEREATS"]),
        // Transport
        .init(domain: "uber.com",        patterns: ["UBER TRIP", "UBER B.V.", "UBER *"]),
        .init(domain: "lyft.com",        patterns: ["LYFT"]),
        // Finance
        .init(domain: "affirm.com",      patterns: ["AFFIRM"]),
        .init(domain: "klarna.com",      patterns: ["KLARNA"]),
        .init(domain: "zelle.com",       patterns: ["ZELLE"]),
        .init(domain: "venmo.com",       patterns: ["VENMO"]),
        .init(domain: "paypal.com",      patterns: ["PAYPAL"]),
        .init(domain: "cash.app",        patterns: ["CASH APP", "CASH.APP"]),
        // Telecom / utilities
        .init(domain: "verizon.com",     patterns: ["VERIZON"]),
        .init(domain: "att.com",         patterns: ["AT&T", "ATT MOBILITY"]),
        .init(domain: "tmobile.com",     patterns: ["T-MOBILE", "TMOBILE"]),
        // Gyms / wellness
        .init(domain: "equinox.com",     patterns: ["EQUINOX"]),
        .init(domain: "goldsgym.com",    patterns: ["GOLDS GYM"]),
        // Misc retail
        .init(domain: "nike.com",        patterns: ["NIKE"]),
        .init(domain: "adidas.com",      patterns: ["ADIDAS"]),
        .init(domain: "uniqlo.com",      patterns: ["UNIQLO"]),
        .init(domain: "zara.com",        patterns: ["ZARA"])
    ]

    // MARK: - Normalisation

    private static func normalise(_ raw: String) -> String {
        var s = raw.uppercased()
        // Strip the common "PURCHASE X #1234" / "ORDER 112-..." noise.
        s = s.replacingOccurrences(of: "PURCHASE ", with: "")
        s = s.replacingOccurrences(of: " ORDER ", with: " ")
        // Drop trailing "#NNN" receipt fragments.
        if let range = s.range(of: #" #\d+"#, options: .regularExpression) {
            s = String(s[..<range.lowerBound])
        }
        // Collapse runs of whitespace.
        s = s.replacingOccurrences(of: "  ", with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SwiftUI helper

/// View that resolves a merchant string to an icon image. Three
/// paths, picked at render time:
///
///   1. **Cached on disk** — load synchronously from the cache file.
///   2. **Resolvable but not cached** — kick off an async fetch in
///      `.task`, show the fallback in the meantime.
///   3. **No domain mapping** — paint the initial-letter swatch.
///
/// The fallback color and the fallback letter are passed in by the
/// parent so the icon visually matches the transaction's category
/// even before the network lands.
@MainActor
struct MerchantLogoView: View {
    let merchant: String
    let fallbackColor: Color
    let size: CGFloat

    @State private var localPath: URL?
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let localPath, let img = loadCached(localPath) {
                img
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            } else {
                fallback
            }
        }
        .task(id: merchant) {
            await resolve()
        }
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(fallbackColor.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .stroke(fallbackColor.opacity(0.40), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .overlay(
                Text(String(merchant.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .default))
                    .foregroundStyle(fallbackColor)
            )
    }

    private func resolve() async {
        guard let domain = MerchantLogoResolver.domain(for: merchant) else {
            return
        }
        // Cache check first.
        if let cache = MerchantLogoResolver.cacheURL(for: domain),
           FileManager.default.fileExists(atPath: cache.path) {
            self.localPath = cache
            return
        }
        do {
            let url = try await MerchantLogoResolver.ensureCached(domain: domain)
            self.localPath = url
        } catch {
            self.loadFailed = true
        }
    }

    private func loadCached(_ url: URL) -> Image? {
        #if os(macOS)
        guard let data = try? Data(contentsOf: url),
              let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #else
        guard let data = try? Data(contentsOf: url),
              let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #endif
    }
}

#if !os(macOS)
import UIKit
#endif
