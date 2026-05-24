import SwiftUI
import DesignSystem

/// Per-check outcome for the M9 accessibility audit. Audits are layered so
/// the integrator can run them à la carte: the Dynamic Type pass checks
/// rendering, the contrast pass is pure math, the hit-target pass walks
/// view geometry.
public struct AuditFinding: Sendable, Equatable {
    public let surface: String
    public let kind: AuditKind
    public let detail: String

    public init(surface: String, kind: AuditKind, detail: String) {
        self.surface = surface
        self.kind = kind
        self.detail = detail
    }
}

public enum AuditKind: String, Sendable, Equatable {
    case dynamicTypeOverflow
    case contrastBelowAA
    case hitTargetTooSmall
    case missingAccessibilityLabel
}

public struct AuditResult: Sendable, Equatable {
    public let surface: String
    public let findings: [AuditFinding]

    public init(surface: String, findings: [AuditFinding]) {
        self.surface = surface
        self.findings = findings
    }

    public var passed: Bool { findings.isEmpty }
}

/// WCAG 2.1 AA threshold for normal-weight body text. Large text gets a
/// looser 3.0:1 cutoff but we hold the whole token set to the stricter bar
/// because most callers are not large text.
public let wcagAANormalText: Double = 4.5

/// WCAG AA threshold for non-text UI affordances (focus rings, icon-only
/// controls). The Apple HIG also lands here.
public let wcagAANonText: Double = 3.0

/// Minimum hit-target dimension per Apple HIG — used for both the iOS
/// 44pt rule and the macOS minimum control height.
public let minimumHitTargetPoints: Double = 44.0

public enum AccessibilityAudit {

    // MARK: - Dynamic Type

    /// Render `view` at every supplied `DynamicTypeSize` and flag the surface
    /// if the rendered image clips or its intrinsic size collapses. This is
    /// a best-effort heuristic — full overlap detection requires walking the
    /// view hierarchy with `Accessibility` APIs that are not available in a
    /// test process. The compromise is: we render, measure, and fail when
    /// the rendered image has zero area.
    @MainActor
    public static func auditDynamicType(
        surface: String,
        view: AnyView,
        sizes: [DynamicTypeSize] = [.xSmall, .medium, .xxxLarge, .accessibility3]
    ) -> AuditResult {
        var findings: [AuditFinding] = []
        for size in sizes {
            let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, size))
            renderer.proposedSize = ProposedViewSize(width: 1024, height: 768)
            let area: Double
            #if os(macOS)
            if let nsImage = renderer.nsImage {
                area = Double(nsImage.size.width * nsImage.size.height)
            } else {
                area = 0
            }
            #else
            if let uiImage = renderer.uiImage {
                area = Double(uiImage.size.width * uiImage.size.height)
            } else {
                area = 0
            }
            #endif
            if area == 0 {
                findings.append(AuditFinding(
                    surface: surface,
                    kind: .dynamicTypeOverflow,
                    detail: "Render at \(size) produced an empty image."
                ))
            }
        }
        return AuditResult(surface: surface, findings: findings)
    }

    // MARK: - Contrast

    /// Walk every (background, foreground) token pair on a theme in both
    /// modes and flag the ones below `wcagAANormalText`. The `accent`
    /// token is checked at the looser `wcagAANonText` cutoff because it's
    /// usually iconography or focus rings.
    public static func auditContrast(theme: Theme, surface: String) -> AuditResult {
        var findings: [AuditFinding] = []
        for scheme in [ColorScheme.light, .dark] {
            let tokens = theme.tokens(for: scheme)
            check(
                bg: tokens.background, fg: tokens.foregroundPrimary,
                threshold: wcagAANormalText, label: "background ↔ foregroundPrimary",
                surface: surface, scheme: scheme, into: &findings
            )
            check(
                bg: tokens.background, fg: tokens.foregroundSecondary,
                threshold: wcagAANormalText, label: "background ↔ foregroundSecondary",
                surface: surface, scheme: scheme, into: &findings
            )
            check(
                bg: tokens.surface, fg: tokens.foregroundPrimary,
                threshold: wcagAANormalText, label: "surface ↔ foregroundPrimary",
                surface: surface, scheme: scheme, into: &findings
            )
            check(
                bg: tokens.surface, fg: tokens.foregroundSecondary,
                threshold: wcagAANormalText, label: "surface ↔ foregroundSecondary",
                surface: surface, scheme: scheme, into: &findings
            )
            check(
                bg: tokens.background, fg: tokens.accent,
                threshold: wcagAANonText, label: "background ↔ accent",
                surface: surface, scheme: scheme, into: &findings
            )
            check(
                bg: tokens.background, fg: tokens.gainAccent,
                threshold: wcagAANonText, label: "background ↔ gainAccent",
                surface: surface, scheme: scheme, into: &findings
            )
            check(
                bg: tokens.background, fg: tokens.lossAccent,
                threshold: wcagAANonText, label: "background ↔ lossAccent",
                surface: surface, scheme: scheme, into: &findings
            )
        }
        return AuditResult(surface: surface, findings: findings)
    }

    private static func check(
        bg: ColorToken,
        fg: ColorToken,
        threshold: Double,
        label: String,
        surface: String,
        scheme: ColorScheme,
        into findings: inout [AuditFinding]
    ) {
        let ratio = contrastRatio(bg, fg)
        if ratio < threshold {
            let schemeName = scheme == .dark ? "dark" : "light"
            findings.append(AuditFinding(
                surface: surface,
                kind: .contrastBelowAA,
                detail: "[\(schemeName)] \(label) ratio=\(String(format: "%.2f", ratio)) < \(threshold)"
            ))
        }
    }

    // MARK: - Hit targets

    /// Pure-function check: returns a finding when the supplied bounding
    /// box is below the 44pt minimum on either axis. Callers feed in the
    /// resolved frames from the view layer; this audit refuses to walk
    /// the view tree because doing so reliably requires `_overrideSizeThatFits`
    /// SPI we will not depend on.
    public static func auditHitTarget(
        surface: String,
        label: String,
        width: Double,
        height: Double
    ) -> AuditResult {
        var findings: [AuditFinding] = []
        if width < minimumHitTargetPoints || height < minimumHitTargetPoints {
            findings.append(AuditFinding(
                surface: surface,
                kind: .hitTargetTooSmall,
                detail: "\(label) is \(width)×\(height); minimum is \(minimumHitTargetPoints)pt."
            ))
        }
        return AuditResult(surface: surface, findings: findings)
    }

    /// Aggregate a batch of hit-target checks into one result. Lets
    /// surface-level tests express "every interactive element on this
    /// screen must pass" as a single assertion.
    public static func auditHitTargets(
        surface: String,
        elements: [(label: String, width: Double, height: Double)]
    ) -> AuditResult {
        var findings: [AuditFinding] = []
        for element in elements {
            let result = auditHitTarget(
                surface: surface,
                label: element.label,
                width: element.width,
                height: element.height
            )
            findings.append(contentsOf: result.findings)
        }
        return AuditResult(surface: surface, findings: findings)
    }

    /// Combine multiple results into a single roll-up. Empty findings on
    /// all = passed.
    public static func combine(_ results: [AuditResult], surface: String) -> AuditResult {
        AuditResult(
            surface: surface,
            findings: results.flatMap(\.findings)
        )
    }
}
