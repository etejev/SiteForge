import AppKit
import SwiftUI

enum WorkspaceChromeRegion: String, CaseIterable, Sendable {
    case titlebar
    case navigator
    case inspector
    case viewportControls
    case statusBar
    case recoveryBar
    case launchCard
}

enum WorkspaceChromePresentation: String, Equatable, Sendable {
    case translucent
    case opaque
}

enum WorkspaceNativeMaterial: String, Equatable, Sendable {
    case titlebar
    case sidebar
    case header
    case status
    case emphasized
    case launch
}

enum WorkspaceAppearanceMode: String, CaseIterable, Sendable {
    case light
    case dark
}

enum WorkspaceContrastMode: String, CaseIterable, Sendable {
    case standard
    case increased
}

enum WorkspaceWindowActivity: String, CaseIterable, Sendable {
    case active
    case inactive
}

struct WorkspaceMaterialEnvironment: Equatable, Sendable {
    var reduceTransparency: Bool
    var contrast: WorkspaceContrastMode
    var appearance: WorkspaceAppearanceMode
    var activity: WorkspaceWindowActivity
}

struct WorkspaceMaterialStyle: Equatable, Sendable {
    let region: WorkspaceChromeRegion
    let presentation: WorkspaceChromePresentation
    let material: WorkspaceNativeMaterial
    let separatorOpacity: Double
    let isEmphasized: Bool

    var accessibilityDescription: String {
        let surface = presentation == .translucent ? "Native translucent material" : "Opaque accessibility material"
        return "\(surface), \(region.rawValue)"
    }
}

enum WorkspaceMaterialPolicy {
    static let requirementIDs: Set<String> = [
        "SF-0201-002", "SF-0201-003", "SF-0201-006", "SF-0201-007", "SF-0201-008",
        "SF-1505-006", "SF-1505-007", "SF-1505-008",
        "SF-1605-002", "SF-1605-006", "SF-1605-007", "SF-1605-008",
    ]

    static func resolve(
        region: WorkspaceChromeRegion,
        environment: WorkspaceMaterialEnvironment
    ) -> WorkspaceMaterialStyle {
        let material: WorkspaceNativeMaterial = switch region {
        case .titlebar: .titlebar
        case .navigator, .inspector: .sidebar
        case .viewportControls: .header
        case .statusBar: .status
        case .recoveryBar: .emphasized
        case .launchCard: .launch
        }
        let strongerBoundary = environment.contrast == .increased || environment.reduceTransparency
        let inactive = environment.activity == .inactive
        return WorkspaceMaterialStyle(
            region: region,
            presentation: environment.reduceTransparency ? .opaque : .translucent,
            material: material,
            separatorOpacity: strongerBoundary ? 0.52 : (inactive ? 0.18 : 0.28),
            isEmphasized: region == .recoveryBar && !inactive
        )
    }

    static func preferredColorScheme(composition: DebugTestComposition = .current()) -> ColorScheme? {
        switch WorkspaceMaterialOverrides.current(composition: composition).appearance {
        case .light: .light
        case .dark: .dark
        case nil: nil
        }
    }

    static func preferredColorScheme(arguments: [String]) -> ColorScheme? {
        preferredColorScheme(composition: .current(arguments: arguments))
    }
}

private struct WorkspaceMaterialOverrides {
    let reduceTransparency: Bool?
    let increasedContrast: Bool?
    let appearance: WorkspaceAppearanceMode?
    let activity: WorkspaceWindowActivity?

    static func current(composition: DebugTestComposition = .current()) -> Self {
        Self(
            reduceTransparency: composition.boolValue(after: "-SiteForgeReduceTransparency"),
            increasedContrast: composition.boolValue(after: "-SiteForgeIncreaseContrast"),
            appearance: composition.value(after: "-SiteForgeAppearance").flatMap(WorkspaceAppearanceMode.init),
            activity: composition.boolValue(after: "-SiteForgeWindowInactive").map { $0 ? .inactive : .active }
        )
    }
}

private struct WorkspaceChromeModifier: ViewModifier {
    let region: WorkspaceChromeRegion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        let overrides = WorkspaceMaterialOverrides.current()
        let environment = WorkspaceMaterialEnvironment(
            reduceTransparency: overrides.reduceTransparency ?? reduceTransparency,
            contrast: overrides.increasedContrast.map { $0 ? .increased : .standard }
                ?? (contrast == .increased ? .increased : .standard),
            appearance: overrides.appearance ?? (colorScheme == .dark ? .dark : .light),
            activity: overrides.activity ?? (controlActiveState == .inactive ? .inactive : .active)
        )
        let style = WorkspaceMaterialPolicy.resolve(region: region, environment: environment)
        content
            .background(WorkspaceNativeMaterialView(style: style))
            .overlay {
                Rectangle()
                    .stroke(Color(nsColor: .separatorColor).opacity(style.separatorOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    func workspaceChrome(_ region: WorkspaceChromeRegion) -> some View {
        modifier(WorkspaceChromeModifier(region: region))
    }
}

private struct WorkspaceNativeMaterialView: NSViewRepresentable {
    let style: WorkspaceMaterialStyle

    func makeNSView(context: Context) -> PassthroughVisualEffectView {
        let view = PassthroughVisualEffectView()
        view.blendingMode = .withinWindow
        view.autoresizingMask = [.width, .height]
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PassthroughVisualEffectView, context: Context) {
        view.material = style.appKitMaterial
        view.state = style.presentation == .translucent ? .followsWindowActiveState : .inactive
        view.isEmphasized = style.isEmphasized
        view.wantsLayer = true
        view.layer?.backgroundColor = style.presentation == .opaque
            ? NSColor.controlBackgroundColor.cgColor
            : NSColor.clear.cgColor
    }
}

private final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private extension WorkspaceMaterialStyle {
    var appKitMaterial: NSVisualEffectView.Material {
        switch material {
        case .titlebar: .titlebar
        case .sidebar: .sidebar
        case .header: .headerView
        case .status: .underWindowBackground
        case .emphasized: .hudWindow
        case .launch: .popover
        }
    }
}

struct WorkspaceWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        if let requestedSize = WorkspaceMetrics.requestedWindowSize(),
           window.contentLayoutRect.size != requestedSize {
            window.setContentSize(requestedSize)
        }
        if WorkspaceMetrics.usesDeterministicUITestPlacement(),
           let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let frame = window.frame
            let origin = CGPoint(
                x: max(visibleFrame.minX, min(
                    visibleFrame.midX - frame.width / 2,
                    visibleFrame.maxX - frame.width
                )),
                y: max(visibleFrame.minY, min(
                    visibleFrame.midY - frame.height / 2,
                    visibleFrame.maxY - frame.height
                ))
            )
            window.setFrameOrigin(origin)
        }
    }
}
