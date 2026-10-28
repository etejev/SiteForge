@preconcurrency import AppKit
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

enum WorkspaceMaterialBlending: String, Equatable, Sendable {
    case behindWindow
    case withinWindow
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

/// Shared editor presentation tokens distilled from the approved SiteForge
/// direction. They describe native semantic roles rather than a fixed mockup,
/// so light/dark appearance, increased contrast, and larger text continue to
/// be owned by AppKit and SwiftUI.
enum SiteForgeVisualSystem {
    // One 8-point-derived rhythm. Half/quarter steps exist only for compact
    // native chrome; feature views should consume these semantic roles.
    static let gridUnit: CGFloat = 8
    static let hairlineSpacing: CGFloat = 2
    static let tabStripInset: CGFloat = 3
    static let microSpacing: CGFloat = 4
    static let compactSpacing: CGFloat = 6
    static let controlInset: CGFloat = 8
    static let standardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 18
    static let panePadding: CGFloat = 12
    static let cardPadding: CGFloat = 18
    static let controlCornerRadius: CGFloat = 7
    static let cardCornerRadius: CGFloat = 14
    static let launchCardCornerRadius: CGFloat = 20
    static let rowCornerRadius: CGFloat = 6
    static let fieldCornerRadius: CGFloat = 7
    static let settingsSidebarWidth: CGFloat = 250
    static let settingsContentMaxWidth: CGFloat = 680
    static let launchOuterPadding: CGFloat = 40
    static let launchInnerPadding: CGFloat = 32
    static let launchSectionSpacing: CGFloat = 24
    static let toolbarGroupSpacing: CGFloat = 16
    static let settingsFormPadding: CGFloat = 24
    static let rowInset: CGFloat = 8
    static let inspectorBottomClearance: CGFloat = 80
    static let thumbnailSize: CGFloat = 48
    static let statusBarHeight: CGFloat = 36
    static let settingsHeaderIconSize: CGFloat = 32
    static let emptyHintMaximumWidth: CGFloat = 220
    static let launchShadowRadius: CGFloat = 24
    static let launchShadowOffset: CGFloat = 8
    static let compactControlHeight: CGFloat = 28
    static let tabStripHeight: CGFloat = 32
    static let sidePaneIdealWidth: CGFloat = 288
    static let navigatorIdealWidth: CGFloat = 344
    static let inspectorIdealWidth: CGFloat = 384
    static let settingsSidebarRowHeight: CGFloat = 44
    static let settingsIdealWidth: CGFloat = 970
    static let settingsIdealHeight: CGFloat = 740
    static let launchSurfaceNSColor = NSColor(name: "SiteForgeApprovedLaunchSurface") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.11, green: 0.125, blue: 0.15, alpha: 1)
            : NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.97, alpha: 1)
    }

    static let chromeSurfaceNSColor = NSColor(name: "SiteForgeChromeSurface") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.11, green: 0.125, blue: 0.15, alpha: 1)
            : NSColor(calibratedWhite: 0.965, alpha: 1)
    }
    static let elevatedSurfaceNSColor = NSColor(name: "SiteForgeElevatedSurface") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.15, green: 0.167, blue: 0.195, alpha: 1)
            : NSColor(calibratedWhite: 0.995, alpha: 1)
    }
    static let chromeSelectionNSColor = NSColor(name: "SiteForgeChromeSelection") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor.controlAccentColor.withAlphaComponent(0.20)
            : NSColor.controlAccentColor.withAlphaComponent(0.10)
    }

    /// Opaque editor workspace colors deliberately separate the infinite
    /// pasteboard from native chrome. Materials remain reserved for panes and
    /// headers, avoiding the gray-on-gray wash produced by nesting the same
    /// translucent surface throughout the shell.
    static let canvasPasteboardNSColor = NSColor(
        name: NSColor.Name("SiteForgeCanvasPasteboard")
    ) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if dark {
            return NSColor(
                srgbRed: increased ? 0.18 : 0.205,
                green: increased ? 0.195 : 0.225,
                blue: increased ? 0.22 : 0.255,
                alpha: 1
            )
        }
        return NSColor(
            calibratedRed: increased ? 0.87 : 0.91,
            green: increased ? 0.87 : 0.91,
            blue: increased ? 0.88 : 0.915,
            alpha: 1
        )
    }
    static let artboardSurfaceNSColor = NSColor(
        name: NSColor.Name("SiteForgeArtboardSurface")
    ) { appearance in
        // The editor page surface is neutral paper in either chrome appearance;
        // authored page backgrounds remain the canonical renderer's responsibility.
        return NSColor(calibratedWhite: 0.995, alpha: 1)
    }
    static let artboardBoundaryNSColor = NSColor(
        name: NSColor.Name("SiteForgeArtboardBoundary")
    ) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return dark ? NSColor(calibratedWhite: 0.12, alpha: increased ? 1 : 0.75)
            : NSColor(calibratedWhite: 0.45, alpha: increased ? 1 : 0.45)
    }
    static let gridMinorNSColor = NSColor(
        name: NSColor.Name("SiteForgeGridMinor")
    ) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(calibratedWhite: 0.75, alpha: 0.10) : NSColor(calibratedWhite: 0.16, alpha: 0.11)
    }
    static let gridMajorNSColor = NSColor(
        name: NSColor.Name("SiteForgeGridMajor")
    ) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(calibratedWhite: 0.88, alpha: 0.22) : NSColor(calibratedWhite: 0.10, alpha: 0.24)
    }

    static var canvasPasteboard: Color { Color(nsColor: canvasPasteboardNSColor) }
    static var chromeSurface: Color { Color(nsColor: chromeSurfaceNSColor) }
    static var elevatedSurface: Color { Color(nsColor: elevatedSurfaceNSColor) }
    static var subduedSurface: Color { elevatedSurface.opacity(0.78) }
    static var selectionTint: Color { Color(nsColor: chromeSelectionNSColor) }
    static var selectionBoundary: Color { Color.accentColor.opacity(0.62) }
    static var quietBoundary: Color { Color(nsColor: .separatorColor).opacity(0.34) }
    static var tabStripSurface: Color { elevatedSurface.opacity(0.68) }
    static var fieldSurface: Color { Color(nsColor: .controlBackgroundColor) }
    static var hoverSurface: Color { Color.primary.opacity(0.055) }
    static var inactiveSelectionTint: Color { Color.secondary.opacity(0.13) }
    static var success: Color { Color(nsColor: .systemGreen) }
    static var warning: Color { Color(nsColor: .systemOrange) }
    static var danger: Color { Color(nsColor: .systemRed) }
}

struct SiteForgeSettingsHeader: View {
    let title: String
    let scope: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: SiteForgeVisualSystem.standardSpacing) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: SiteForgeVisualSystem.settingsHeaderIconSize, height: SiteForgeVisualSystem.settingsHeaderIconSize)
                .background(SiteForgeVisualSystem.selectionTint, in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SiteForgeVisualSystem.microSpacing) {
                Text(title).font(.title2.bold())
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

/// Owner clarification keeps Inspector groups compact and distinguishable;
/// Settings retains its separate, wider form-card role from render 12.
struct SiteForgeInspectorGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Divider().accessibilityHidden(true)
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .modifier(SiteForgeInspectorSectionSurface())
    }
}

struct SiteForgeInspectorSectionSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
        .padding(SiteForgeVisualSystem.panePadding)
        .background(SiteForgeVisualSystem.elevatedSurface.opacity(reduceTransparency ? 1 : 0.55),
                    in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: SiteForgeVisualSystem.controlCornerRadius)
                .strokeBorder(contrast == .increased ? Color.primary.opacity(0.5) : SiteForgeVisualSystem.quietBoundary, lineWidth: 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// A native Button makes the entire visible disclosure row its real pointer,
/// keyboard and accessibility action. The default macOS triangle's reported
/// frame can include an outdented gutter that is not actually clickable.
struct SiteForgeInspectorDisclosureStyle: DisclosureGroupStyle {
    let identifier: String
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: SiteForgeVisualSystem.compactSpacing) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).frame(width: 12).accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide this section")
            .accessibilityIdentifier(identifier)
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
                    configuration.content
                }
                    .disclosureGroupStyle(.automatic)
                    .modifier(SiteForgeInspectorSectionSurface())
            }
        }
    }
}

struct SiteForgeSettingsGroupStyle: GroupBoxStyle {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: SiteForgeVisualSystem.standardSpacing) {
            configuration.label.font(.headline).fixedSize(horizontal: false, vertical: true)
            Divider().accessibilityHidden(true)
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SiteForgeVisualSystem.cardPadding)
        .background(reduceTransparency ? SiteForgeVisualSystem.elevatedSurface : SiteForgeVisualSystem.elevatedSurface.opacity(0.96),
                    in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SiteForgeVisualSystem.cardCornerRadius, style: .continuous)
                .strokeBorder(contrast == .increased ? Color.primary.opacity(0.5) : SiteForgeVisualSystem.quietBoundary)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preference group")
        .accessibilityIdentifier("settings.card")
    }
}

struct SiteForgeRowSurface: ViewModifier {
    let selected: Bool
    @Environment(\.controlActiveState) private var activity
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .frame(minHeight: SiteForgeVisualSystem.compactControlHeight)
            .background(selected ? (activity == .inactive ? SiteForgeVisualSystem.inactiveSelectionTint : SiteForgeVisualSystem.selectionTint)
                        : (hovering ? SiteForgeVisualSystem.hoverSurface : .clear),
                        in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.rowCornerRadius, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: SiteForgeVisualSystem.rowCornerRadius, style: .continuous)
                        .strokeBorder(contrast == .increased ? Color.primary.opacity(0.6) : SiteForgeVisualSystem.selectionBoundary)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering = $0 }
    }
}

private struct SiteForgeCardModifier: ViewModifier {
    let emphasized: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(SiteForgeVisualSystem.cardPadding)
            .background(
                emphasized && !reduceTransparency ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(SiteForgeVisualSystem.elevatedSurface),
                in: RoundedRectangle(cornerRadius: SiteForgeVisualSystem.cardCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SiteForgeVisualSystem.cardCornerRadius, style: .continuous)
                    .strokeBorder(contrast == .increased ? Color.primary.opacity(0.5) : SiteForgeVisualSystem.quietBoundary, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
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
    let blending: WorkspaceMaterialBlending
    let separatorOpacity: Double
    let isEmphasized: Bool

    var accessibilityDescription: String {
        let surface = presentation == .translucent ? "Native translucent material" : "Opaque accessibility material"
        return "\(surface), \(region.rawValue)"
    }
}

enum WorkspaceMaterialPolicy {
    static let requirementIDs: Set<String> = [
        "SF-0201-002", "SF-0201-003", "SF-0201-006", "SF-0201-007", "SF-0201-008", "SF-0201-009",
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
            blending: !environment.reduceTransparency && (region == .navigator || region == .inspector)
                ? .behindWindow : .withinWindow,
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

/// Geometry for the explicit minimum-window development/test override. This
/// is intentionally separate from normal AppKit restoration: only callers
/// that already confirmed `-SiteForgeWindowSize minimum` may use it.
enum WorkspaceExplicitWindowPresentation {
    static func frame(
        requestedFrameSize: CGSize,
        currentOrigin: CGPoint,
        visibleFrame: CGRect
    ) -> CGRect {
        let maximumOrigin = CGPoint(
            x: max(visibleFrame.minX, visibleFrame.maxX - requestedFrameSize.width),
            y: max(visibleFrame.minY, visibleFrame.maxY - requestedFrameSize.height)
        )
        return CGRect(
            origin: CGPoint(
                x: min(max(currentOrigin.x, visibleFrame.minX), maximumOrigin.x),
                y: min(max(currentOrigin.y, visibleFrame.minY), maximumOrigin.y)
            ),
            size: requestedFrameSize
        )
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
            .background {
                ZStack {
                    WorkspaceNativeMaterialView(style: style)
                    if region != .launchCard {
                        SiteForgeVisualSystem.chromeSurface.opacity(style.presentation == .opaque ? 1 : 0.84)
                    }
                }.allowsHitTesting(false)
            }
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

    func siteForgeCard(emphasized: Bool = false) -> some View {
        modifier(SiteForgeCardModifier(emphasized: emphasized))
    }
}

private struct WorkspaceNativeMaterialView: NSViewRepresentable {
    let style: WorkspaceMaterialStyle

    func makeNSView(context: Context) -> PassthroughVisualEffectView {
        let view = PassthroughVisualEffectView()
        view.autoresizingMask = [.width, .height]
        view.setAccessibilityElement(false)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PassthroughVisualEffectView, context: Context) {
        view.material = style.appKitMaterial
        view.blendingMode = style.blending == .behindWindow ? .behindWindow : .withinWindow
        view.state = style.presentation == .translucent ? .followsWindowActiveState : .inactive
        view.isEmphasized = style.isEmphasized
        view.wantsLayer = true
        view.layer?.backgroundColor = style.presentation == .opaque
            ? (style.region == .launchCard ? SiteForgeVisualSystem.launchSurfaceNSColor : SiteForgeVisualSystem.chromeSurfaceNSColor).cgColor
            : NSColor.clear.cgColor
    }
}

final class PassthroughVisualEffectView: NSVisualEffectView {
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
    func makeNSView(context: Context) -> WorkspaceWindowConfigurationView {
        let view = WorkspaceWindowConfigurationView(frame: .zero)
        DispatchQueue.main.async { view.configureWindow() }
        return view
    }

    func updateNSView(_ view: WorkspaceWindowConfigurationView, context: Context) {
        DispatchQueue.main.async { view.configureWindow() }
    }

    static func dismantleNSView(
        _ view: WorkspaceWindowConfigurationView,
        coordinator: Void
    ) {
        view.detach()
    }
}

/// A workspace window is identified by a marker installed from the root of the
/// `WindowGroup`. AppKit also reports native colour panels, sheets, and other
/// auxiliary windows through the application's key/main-window notifications;
/// those windows must never inherit the document workspace's size or chrome.
@MainActor
enum WorkspaceWindowRolePolicy {
    static let workspaceIdentifier = NSUserInterfaceItemIdentifier("app.siteforge.workspace")
    static let didRegisterNotification = Notification.Name("SiteForgeWorkspaceWindowDidRegister")

    static func register(_ window: NSWindow) {
        window.identifier = workspaceIdentifier
        NotificationCenter.default.post(name: didRegisterNotification, object: window)
    }

    static func isWorkspaceDocumentWindow(_ window: NSWindow) -> Bool {
        window.identifier == workspaceIdentifier
            && !(window is NSPanel)
            && window.sheetParent == nil
            && window.parent == nil
    }
}

struct WorkspaceWindowRoleMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> WorkspaceWindowRoleMarkerView {
        WorkspaceWindowRoleMarkerView(frame: .zero)
    }

    func updateNSView(_ view: WorkspaceWindowRoleMarkerView, context: Context) {
        view.registerWindowIfNeeded()
    }
}

@MainActor
final class WorkspaceWindowRoleMarkerView: NSView {
    private weak var registeredWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerWindowIfNeeded()
    }

    func registerWindowIfNeeded() {
        guard let window, window !== registeredWindow else { return }
        registeredWindow = window
        WorkspaceWindowRolePolicy.register(window)
    }
}

@MainActor
final class WorkspaceWindowLifecycleOwner: NSObject {
    private var installed = false
    private var configured = Set<ObjectIdentifier>()
    private let diagnostics = UITestWindowLifecycleDiagnostics.current()

    override init() {
        super.init()
        diagnostics.record(phase: "owner-created", windows: [])
    }

    func install() {
        precondition(Thread.isMainThread)
        guard !installed else { return }
        installed = true
        diagnostics.record(phase: "observers-installed", windows: [])
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            center.addObserver(self, selector: #selector(windowDidBecomeUsable(_:)), name: name, object: nil)
        }
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeUsable(_:)),
            name: WorkspaceWindowRolePolicy.didRegisterNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidFinishLaunching(_:)),
            name: NSApplication.didFinishLaunchingNotification,
            object: nil
        )
        configureExistingWindows()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func windowDidBecomeUsable(_ notification: Notification) {
        precondition(Thread.isMainThread)
        guard let window = notification.object as? NSWindow else { return }
        diagnostics.record(phase: "window-became-usable", windows: [window])
        configure(window)
    }

    @objc private func applicationDidFinishLaunching(_ notification: Notification) {
        precondition(Thread.isMainThread)
        diagnostics.record(phase: "application-did-finish-launching", windows: NSApplication.shared.windows)
        configureExistingWindows()
    }

    private func configureExistingWindows() {
        precondition(Thread.isMainThread)
        NSApplication.shared.windows.forEach(configure)
    }

    private func configure(_ window: NSWindow) {
        precondition(Thread.isMainThread)
        guard WorkspaceWindowRolePolicy.isWorkspaceDocumentWindow(window) else {
            diagnostics.record(phase: "configuration-ignored-nonworkspace", windows: [window])
            return
        }
        guard window.isVisible, !configured.contains(ObjectIdentifier(window)) else {
            diagnostics.record(phase: "configuration-deferred", windows: [window])
            return
        }
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        let composition = DebugTestComposition.current()
        guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            diagnostics.record(phase: "configuration-no-visible-frame", windows: [window])
            return
        }
        let frameSize = WorkspaceMetrics.requestedWindowFrameSize(contentSize: WorkspaceMetrics.minimumWindowSize, currentFrameSize: window.frame.size, currentContentLayoutSize: window.contentLayoutRect.size)
        if let placement = WorkspaceMetrics.requestedUITestWindowPlacement(composition: composition) {
            window.minSize = WorkspaceMetrics.effectiveMinimumWindowSize(composition: composition)
            window.setFrame(WorkspaceMetrics.uiTestWindowFrame(windowFrame: .init(origin: window.frame.origin, size: frameSize), visibleFrame: visibleFrame, placement: placement), display: true, animate: false)
            configured.insert(ObjectIdentifier(window))
            diagnostics.record(phase: "configuration-succeeded-constrained", windows: [window])
            return
        }
        if WorkspaceMetrics.requestedWindowSize(composition: composition) != nil {
            // This explicit Debug/UI-test mode exercises the production
            // minimum content geometry. General UI tests continue to use the
            // normal visible-frame presentation below.
            window.setFrameAutosaveName("")
            window.minSize = WorkspaceMetrics.minimumWindowSize
            let desired = WorkspaceExplicitWindowPresentation.frame(
                requestedFrameSize: frameSize,
                currentOrigin: window.frame.origin,
                visibleFrame: visibleFrame
            )
            if !window.frame.isApproximatelyEqual(to: desired) {
                window.setFrame(desired, display: true, animate: false)
            }
            configured.insert(ObjectIdentifier(window))
            diagnostics.record(phase: "configuration-succeeded-minimum", windows: [window])
            return
        }
        window.minSize = WorkspaceMetrics.minimumWindowSize
        let genericTest = composition.boolValue(after: "-SiteForgeUITestMode") == true
        let restored: CGRect?
        if genericTest {
            window.setFrameAutosaveName("")
            restored = nil
        } else {
            window.setFrameAutosaveName(WorkspaceWindowPresentation.frameAutosaveName)
            restored = window.setFrameUsingName(WorkspaceWindowPresentation.frameAutosaveName) ? window.frame : nil
        }
        let desired = WorkspaceWindowPresentation.initialFrame(visibleFrame: visibleFrame, restoredFrame: restored, minimumFrameSize: frameSize)
        if !window.frame.isApproximatelyEqual(to: desired) { window.setFrame(desired, display: true, animate: false) }
        configured.insert(ObjectIdentifier(window))
        diagnostics.record(phase: "window-ready", windows: [window])
    }
}

/// Test-only launch evidence. It is deliberately file-backed because the
/// failure being diagnosed can occur before SwiftUI exposes an AX window.
/// Release builds ignore every argument and never create this file.
@MainActor
private final class UITestWindowLifecycleDiagnostics {
    private let path: URL?
    private let runIdentifier: String

    private init(path: URL?, runIdentifier: String) {
        self.path = path
        self.runIdentifier = runIdentifier
    }

    static func current() -> UITestWindowLifecycleDiagnostics {
#if DEBUG
        let composition = DebugTestComposition.current()
        guard composition.boolValue(after: "-SiteForgeUITestMode") == true,
              let rawPath = composition.value(after: "-SiteForgeUITestDiagnosticPath"),
              let runIdentifier = composition.value(after: "-SiteForgeUITestRunID") else {
            return UITestWindowLifecycleDiagnostics(path: nil, runIdentifier: "disabled")
        }
        return UITestWindowLifecycleDiagnostics(
            path: URL(fileURLWithPath: rawPath),
            runIdentifier: runIdentifier
        )
#else
        UITestWindowLifecycleDiagnostics(path: nil, runIdentifier: "disabled")
#endif
    }

    func record(phase: String, windows: [NSWindow]) {
        guard let path else { return }
        let frameSummary = windows.map { window in
            let frame = window.frame
            return "visible=\(window.isVisible);key=\(window.isKeyWindow);main=\(window.isMainWindow);frame={x=\(Int(frame.minX));y=\(Int(frame.minY));w=\(Int(frame.width));h=\(Int(frame.height))}"
        }.joined(separator: "|")
        let bundle = Bundle.main.bundleIdentifier ?? "unavailable"
        let executable = Bundle.main.executableURL?.path
            .components(separatedBy: "/SiteForge.app/").last
            .map { "SiteForge.app/\($0)" } ?? "unavailable"
        let line = "run=\(runIdentifier);phase=\(phase);pid=\(ProcessInfo.processInfo.processIdentifier);bundle=\(bundle);executable=\(executable);windowCount=\(windows.count);windows=\(frameSummary)\n"
        let existing = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        try? (existing + line).data(using: .utf8)?.write(to: path, options: .atomic)
    }
}

@MainActor
final class WorkspaceWindowConfigurationView: NSView {
    private weak var configuredWindow: NSWindow?
    private var observationTokens: [NSObjectProtocol] = []
    private var configurationScheduled = false
    private var originalWindowMinimumSize: CGSize?
    private var requestedWindowFrameSize: CGSize?
    private var didApplyNormalPresentation = false
    private var didApplyConstrainedPresentation = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if configuredWindow !== window {
            detach()
            configuredWindow = window
            originalWindowMinimumSize = window?.minSize
            if let window {
                WorkspaceWindowRolePolicy.register(window)
            }
            installPlacementObserversIfNeeded()
        }
        scheduleConfiguration()
    }

    func configureWindow(composition: DebugTestComposition = .current()) {
        guard let window else { return }
        // Scene-root configuration can attach before AppKit has ordered the
        // initial launch window. Deferring until it is visible avoids a
        // launch-time frame mutation that temporarily removes the AX window.
        guard window.isVisible else {
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let token = self?.observationTokens.first {
                        NotificationCenter.default.removeObserver(token)
                    }
                    self?.scheduleConfiguration()
                }
            }
            observationTokens.append(token)
            return
        }
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        if requestedWindowFrameSize == nil,
           let requestedSize = WorkspaceMetrics.requestedWindowSize(composition: composition) {
            requestedWindowFrameSize = WorkspaceMetrics.requestedWindowFrameSize(
                contentSize: requestedSize,
                currentFrameSize: window.frame.size,
                currentContentLayoutSize: window.contentLayoutRect.size
            )
        }
        if let placement = WorkspaceMetrics.requestedUITestWindowPlacement(composition: composition),
           let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            // Placement is an initial presentation policy, not a window lock.
            // Later view updates / AppKit move notifications must preserve
            // genuine user title-bar moves, including on narrow displays.
            guard !didApplyConstrainedPresentation else { return }
            let requestedFrame = CGRect(
                origin: window.frame.origin,
                size: requestedWindowFrameSize ?? window.frame.size
            )
            let frame = WorkspaceMetrics.uiTestWindowFrame(
                windowFrame: requestedFrame,
                visibleFrame: visibleFrame,
                placement: placement
            )
            window.minSize = WorkspaceMetrics.effectiveMinimumWindowSize(composition: composition)
            if !window.frame.isApproximatelyEqual(to: frame) {
                // setFrame is required here: setFrameOrigin can be constrained back to
                // the leading/top edge when a production-minimum window is larger than
                // a hosted test display.
                window.setFrame(frame, display: true, animate: false)
            }
            didApplyConstrainedPresentation = true
        } else if let requestedWindowFrameSize,
                  let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            // The scene-root configurator and lifecycle owner can run in
            // either order. Preserve the explicit minimum override here so a
            // later SwiftUI update cannot replace it with normal maximized
            // presentation.
            applyExplicitRequestedFrame(
                requestedWindowFrameSize,
                to: window,
                visibleFrame: visibleFrame
            )
        } else {
            // General UI-test composition deliberately shares the production
            // visible-frame policy. Only an explicit named safe-edge request
            // receives constrained geometry; test mode alone must not leave
            // a fresh workspace at arbitrary AppKit default dimensions.
            applyNormalPresentationIfNeeded(to: window)
        }
    }

    func detach() {
        if let configuredWindow, let originalWindowMinimumSize {
            configuredWindow.minSize = originalWindowMinimumSize
        }
        observationTokens.forEach(NotificationCenter.default.removeObserver)
        observationTokens.removeAll()
        configuredWindow = nil
        configurationScheduled = false
        originalWindowMinimumSize = nil
        requestedWindowFrameSize = nil
        didApplyNormalPresentation = false
        didApplyConstrainedPresentation = false
    }

    private func installPlacementObserversIfNeeded() {
        guard WorkspaceMetrics.usesDeterministicUITestPlacement(),
              let configuredWindow else { return }
        let center = NotificationCenter.default
        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
        ]
        observationTokens = windowNotifications.map { name in
            center.addObserver(
                forName: name,
                object: configuredWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleConfiguration() }
            }
        }
        observationTokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleConfiguration() }
        })
    }

    private func scheduleConfiguration() {
        guard !configurationScheduled else { return }
        configurationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configurationScheduled = false
            self.configureWindow()
        }
    }

    private func applyExplicitRequestedFrame(
        _ requestedFrameSize: CGSize,
        to window: NSWindow,
        visibleFrame: CGRect
    ) {
        window.setFrameAutosaveName("")
        window.minSize = WorkspaceMetrics.minimumWindowSize
        let desired = WorkspaceExplicitWindowPresentation.frame(
            requestedFrameSize: requestedFrameSize,
            currentOrigin: window.frame.origin,
            visibleFrame: visibleFrame
        )
        if !window.frame.isApproximatelyEqual(to: desired) {
            window.setFrame(desired, display: true, animate: false)
        }
    }

    private func applyNormalPresentationIfNeeded(to window: NSWindow) {
        guard !didApplyNormalPresentation,
              let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        didApplyNormalPresentation = true

        window.minSize = WorkspaceMetrics.minimumWindowSize
        let isGenericUITest = DebugTestComposition.current().boolValue(after: "-SiteForgeUITestMode") == true
            && !WorkspaceMetrics.usesDeterministicUITestPlacement()
        // Automation must neither consume nor mutate user restoration state.
        // It always starts from the usable screen frame; production retains
        // AppKit restoration when that frame is valid.
        let restored: CGRect?
        if isGenericUITest {
            window.setFrameAutosaveName("")
            restored = nil
        } else {
            window.setFrameAutosaveName(WorkspaceWindowPresentation.frameAutosaveName)
            restored = window.setFrameUsingName(WorkspaceWindowPresentation.frameAutosaveName)
                ? window.frame : nil
        }
        let minimumFrameSize = WorkspaceMetrics.requestedWindowFrameSize(
            contentSize: WorkspaceMetrics.minimumWindowSize,
            currentFrameSize: window.frame.size,
            currentContentLayoutSize: window.contentLayoutRect.size
        )
        let desired = WorkspaceWindowPresentation.initialFrame(
            visibleFrame: visibleFrame,
            restoredFrame: restored,
            minimumFrameSize: minimumFrameSize
        )
        if !window.frame.isApproximatelyEqual(to: desired) {
            window.setFrame(desired, display: true, animate: false)
        }
    }

}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
