import SwiftUI
import AppKit
import Observation

// MARK: - Canvas state

/// Zoom / rotation / pan state for the image-only "large image" mode.
///
/// Kept as a reference type so both the view and the AppKit event monitors
/// read and mutate the same live state (a captured SwiftUI view struct would
/// go stale after navigating between pins).
@Observable
final class LargeImageCanvas {
    static let minZoom: CGFloat = 0.5
    static let maxZoom: CGFloat = 8

    /// Physical zoom stops used by the + / − controls and keyboard shortcuts.
    private static let zoomStops: [CGFloat] = [
        0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5, 6, 8
    ]

    var zoom: CGFloat = 1
    /// Degrees. Multiples of 90 accumulated across rotations.
    var rotation: Double = 0
    /// Screen-space offset from the centre of the viewport.
    var pan: CGSize = .zero
    var mirrored = false
    var viewport: CGSize = .zero
    private(set) var aspectRatio: CGFloat = 1

    var zoomPercent: Int { Int((zoom * 100).rounded()) }

    var isDefault: Bool {
        abs(zoom - 1) < 0.001 && normalizedRotation == 0 && pan == .zero && !mirrored
    }

    private var normalizedRotation: Double {
        let value = rotation.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private var isQuarterTurn: Bool {
        let value = normalizedRotation
        return (value > 45 && value < 135) || (value > 225 && value < 315)
    }

    private var nearestFullTurn: Double {
        (rotation / 360).rounded() * 360
    }

    // MARK: - Sizing

    /// Frame size of the image *before* the rotation transform is applied.
    /// For quarter turns the frame is transposed so the rotated result still
    /// fits inside the reserved area.
    func baseSize() -> CGSize {
        let available = availableSize()
        let ratio = max(aspectRatio, 0.05)
        if isQuarterTurn {
            let box = Self.fit(aspect: 1 / ratio, in: available)
            return CGSize(width: box.height, height: box.width)
        }
        return Self.fit(aspect: ratio, in: available)
    }

    /// Screen footprint after rotation and zoom.
    private func displayedSize() -> CGSize {
        let base = baseSize()
        if isQuarterTurn {
            return CGSize(width: base.height * zoom, height: base.width * zoom)
        }
        return CGSize(width: base.width * zoom, height: base.height * zoom)
    }

    /// Space reserved for the image: the window minus room for the top chrome
    /// and the floating toolbar / hint at the bottom.
    private func availableSize() -> CGSize {
        CGSize(
            width: max(viewport.width - 260, 160),
            height: max(viewport.height - 220, 160)
        )
    }

    private static func fit(aspect: CGFloat, in available: CGSize) -> CGSize {
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    // MARK: - Lifecycle

    /// Updates the viewport size and re-clamps any existing pan so a window
    /// resize cannot leave the image drifting off-centre.
    func setViewport(_ size: CGSize) {
        viewport = size
        pan = clampedPan(pan)
    }

    /// Resets all transforms, e.g. when the viewer opens or another pin is
    /// shown. Does not animate.
    func configure(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            zoom = 1
            rotation = 0
            pan = .zero
            mirrored = false
        }
    }

    // MARK: - Mutations

    func zoomIn() {
        let target = Self.zoomStops.first(where: { $0 > zoom + 0.001 }) ?? Self.maxZoom
        animate { applyZoom(target, anchor: nil) }
    }

    func zoomOut() {
        let target = Self.zoomStops.last(where: { $0 < zoom - 0.001 }) ?? Self.minZoom
        animate { applyZoom(target, anchor: nil) }
    }

    func rotateLeft() {
        animate {
            rotation -= 90
            pan = clampedPan(pan)
        }
    }

    func rotateRight() {
        animate {
            rotation += 90
            pan = clampedPan(pan)
        }
    }

    func toggleMirror() {
        animate { mirrored.toggle() }
    }

    func reset() {
        animate {
            zoom = 1
            pan = .zero
            mirrored = false
            // Snap to the equivalent full turn so the animation never spins
            // through several revolutions.
            rotation = nearestFullTurn
        }
    }

    /// Double-click behaviour: any zoom level returns to fit, then a second
    /// double-click zooms to 250% around the clicked point.
    func toggleZoom(at point: CGPoint) {
        animate {
            if abs(zoom - 1) > 0.001 {
                zoom = 1
                pan = .zero
            } else {
                applyZoom(2.5, anchor: point)
            }
        }
    }

    /// Handles the viewer's single-key shortcuts. Returns `true` when the key
    /// was consumed. Kept here (instead of in the AppKit monitor) so the
    /// mapping can be covered by the transform tests.
    func handleKey(keyCode: UInt16, shift: Bool, isRepeat: Bool) -> Bool {
        switch keyCode {
        case 24: // = / +
            zoomIn()
        case 27: // -
            zoomOut()
        case 29: // 0
            guard !isRepeat else { return true }
            reset()
        case 15: // r
            guard !isRepeat else { return true }
            if shift {
                rotateLeft()
            } else {
                rotateRight()
            }
        case 46: // m
            guard !isRepeat else { return true }
            toggleMirror()
        default:
            return false
        }
        return true
    }

    /// Continuous zoom from the scroll wheel or a pinch gesture, no animation.
    func setZoom(_ target: CGFloat, anchor: CGPoint?) {
        applyZoom(target, anchor: anchor)
    }

    /// Zoom multiplier for one scroll-wheel event. Positive deltas zoom in.
    static func scrollZoomFactor(deltaY: Double, precise: Bool) -> CGFloat {
        CGFloat(exp(deltaY * (precise ? 0.0025 : 0.08)))
    }

    /// Gesture-driven panning, clamped to the image bounds.
    func setPan(_ value: CGSize) {
        pan = clampedPan(value)
    }

    // MARK: - Internals

    private func animate(_ changes: () -> Void) {
        withAnimation(.snappy(duration: 0.26, extraBounce: 0.04)) {
            changes()
        }
    }

    private func applyZoom(_ target: CGFloat, anchor: CGPoint?) {
        let newZoom = min(max(target, Self.minZoom), Self.maxZoom)
        guard abs(newZoom - zoom) > 0.0001 else { return }

        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let point = anchor ?? center
        let relative = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let ratio = newZoom / zoom
        let anchored = CGSize(
            width: relative.x - (relative.x - pan.width) * ratio,
            height: relative.y - (relative.y - pan.height) * ratio
        )
        zoom = newZoom
        pan = clampedPan(anchored)
    }

    private func clampedPan(_ value: CGSize) -> CGSize {
        let displayed = displayedSize()
        let limitX = max(0, (displayed.width - viewport.width) / 2)
        let limitY = max(0, (displayed.height - viewport.height) / 2)
        return CGSize(
            width: min(max(value.width, -limitX), limitX),
            height: min(max(value.height, -limitY), limitY)
        )
    }
}

// MARK: - Viewer

/// Full-window, image-only viewer with zoom, pan, rotation, mirror and reset
/// tools. Sits on top of the dimmed detail overlay; leaving is handled by the
/// parent through `onExit`.
struct LargeImageViewer: View {
    let pin: Pin
    var onExit: () -> Void

    @Environment(LibraryStore.self) private var store
    @State private var canvas = LargeImageCanvas()
    @State private var dragStart: CGSize?
    @State private var pinchStartZoom: CGFloat?
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    @State private var hostWindow: NSWindow?
    @State private var viewerClosed = false

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            ZStack {
                imageLayer(viewport: viewport)
                chrome
            }
            .frame(width: viewport.width, height: viewport.height)
            .coordinateSpace(.named("largeImageStage"))
            // Pan lives on the untransformed stage, not on the image: the image
            // grows past the window when zoomed, and a stage-wide gesture keeps
            // every visible pixel draggable (and the drag distance in screen
            // points) after zooming, rotating or mirroring.
            .simultaneousGesture(stagePanGesture)
            .onChange(of: viewport, initial: true) { _, size in
                canvas.setViewport(size)
            }
            .background(
                WindowResolver { window in
                    guard !viewerClosed, hostWindow == nil, let window else { return }
                    hostWindow = window
                    // A background-movable window would drag the whole app
                    // window out from under the image instead of panning it.
                    window.isMovableByWindowBackground = false
                    installEventMonitors(for: window)
                }
                .frame(width: 0, height: 0)
            )
        }
        .ignoresSafeArea()
        .onAppear {
            viewerClosed = false
            canvas.configure(aspectRatio: pin.aspectRatio)
        }
        .onDisappear {
            viewerClosed = true
            removeEventMonitors()
            // Restore the gallery's drag-the-window-from-empty-space behavior.
            hostWindow?.isMovableByWindowBackground = true
            hostWindow = nil
            dragStart = nil
        }
        .onChange(of: pin.id) { _, _ in
            canvas.configure(aspectRatio: pin.aspectRatio)
        }
    }

    // MARK: Image

    private func imageLayer(viewport: CGSize) -> some View {
        let base = canvas.baseSize()
        let cornerRadius = 10 / max(canvas.zoom, 0.5)
        let borderWidth = 1 / max(canvas.zoom, 1)

        return LibraryImage(paths: store.largeImageCandidates(for: pin), maxPixel: 0, contentMode: .fit)
            .frame(width: base.width, height: base.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: borderWidth)
            )
            .scaleEffect(canvas.zoom)
            .scaleEffect(x: canvas.mirrored ? -1 : 1, y: 1)
            .rotationEffect(.degrees(canvas.rotation))
            .offset(canvas.pan)
            .shadow(color: .black.opacity(0.55), radius: 50, x: 0, y: 22)
            .contentShape(Rectangle())
            .contextMenu {
                // Copies the stored original, not the 1200 px thumbnail, so the
                // clipboard keeps the resolution the viewer is showing.
                Button(T("Copy image")) {
                    store.copyImage(pin, fullResolution: true)
                }
            }
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(doubleClickGesture)
            .pointerCursor()
            .help(T("Double-click to zoom · hold and drag to pan"))
            .position(x: viewport.width / 2, y: viewport.height / 2)
    }

    /// Press-and-drag panning for the whole viewer. It is attached to the
    /// untransformed stage so the translation is always in screen points and
    /// the entire visible image stays draggable at any zoom or rotation.
    private var stagePanGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("largeImageStage"))
            .onChanged { value in
                if dragStart == nil { dragStart = canvas.pan }
                guard let start = dragStart else { return }
                canvas.setPan(
                    CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    )
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchStartZoom == nil { pinchStartZoom = canvas.zoom }
                guard let start = pinchStartZoom else { return }
                canvas.setZoom(start * value.magnification, anchor: nil)
            }
            .onEnded { _ in pinchStartZoom = nil }
    }

    private var doubleClickGesture: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .named("largeImageStage"))
            .onEnded { value in
                canvas.toggleZoom(at: value.location)
            }
    }

    // MARK: Chrome

    private var chrome: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }

            if store.filteredPins.count > 1 {
                HStack {
                    navButton(icon: "chevron.left", offset: -1)
                        .padding(.leading, 22)
                    Spacer()
                    navButton(icon: "chevron.right", offset: 1)
                        .padding(.trailing, 22)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            indexPill
            Spacer()
            HStack(spacing: 10) {
                overlayCircleButton(icon: "arrow.down.right.and.arrow.up.left", help: T("Exit large image")) {
                    onExit()
                }
                overlayCircleButton(icon: "xmark", help: T("Close")) {
                    store.dismissDetail()
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 40)
    }

    private var bottomBar: some View {
        VStack(spacing: 9) {
            toolbar
            // Stay visible after zooming: drag-to-pan is exactly what a zoomed
            // image needs, so the hint should not disappear with the fit state.
            hint
        }
        .padding(.bottom, 24)
    }

    private var indexPill: some View {
        Group {
            if let index = store.filteredPins.firstIndex(where: { $0.id == pin.id }) {
                Text("\(index + 1) / \(store.filteredPins.count)")
                    .font(Theme.mono(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.black.opacity(0.32)))
                    .allowsHitTesting(false)
            }
        }
    }

    private var hint: some View {
        Text(T("← → browse · scroll to zoom · hold and drag to pan · R rotate · 0 reset"))
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, 11)
            .frame(height: 23)
            .background(Capsule().fill(Color.black.opacity(0.26)))
            .allowsHitTesting(false)
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            toolButton(
                icon: "minus.magnifyingglass",
                help: T("Zoom out · −"),
                enabled: canvas.zoom > LargeImageCanvas.minZoom + 0.001
            ) {
                canvas.zoomOut()
            }

            Text("\(canvas.zoomPercent)%")
                .font(Theme.mono(10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
                .frame(width: 46)
                .help(T("Zoom · 100% fits the window"))
                .accessibilityLabel(Text(T("Zoom")))
                .accessibilityValue(Text("\(canvas.zoomPercent)%"))

            toolButton(
                icon: "plus.magnifyingglass",
                help: T("Zoom in · +"),
                enabled: canvas.zoom < LargeImageCanvas.maxZoom - 0.001
            ) {
                canvas.zoomIn()
            }

            toolbarSeparator

            toolButton(icon: "rotate.left", help: T("Rotate left · ⇧R")) {
                canvas.rotateLeft()
            }
            toolButton(icon: "rotate.right", help: T("Rotate right · R")) {
                canvas.rotateRight()
            }

            toolbarSeparator

            toolButton(
                icon: "flip.horizontal",
                help: T("Mirror horizontally · M"),
                active: canvas.mirrored
            ) {
                canvas.toggleMirror()
            }

            toolbarSeparator

            toolButton(
                icon: "arrow.counterclockwise",
                help: T("Reset view · 0"),
                enabled: !canvas.isDefault
            ) {
                canvas.reset()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.32), radius: 20, x: 0, y: 10)
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 17)
            .padding(.horizontal, 5)
    }

    private func toolButton(
        icon: String,
        help: String,
        active: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        ViewerToolButton(icon: icon, help: help, active: active, enabled: enabled, action: action)
    }

    private func overlayCircleButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.38)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private func navButton(icon: String, offset: Int) -> some View {
        Button {
            store.showAdjacentPin(offset: offset)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.46)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(PressableStyle())
        .help(offset < 0 ? T("Previous pin") : T("Next pin"))
        .accessibilityLabel(Text(offset < 0 ? T("Previous pin") : T("Next pin")))
    }

    // MARK: Event monitors

    /// Local monitors are the most reliable way to receive wheel / pinch keys
    /// while the SwiftUI viewer covers the window. They are scoped to the
    /// window hosting the viewer so Settings or the capture sheet keep their
    /// own scrolling, and they are installed only while the viewer exists.
    private func installEventMonitors(for window: NSWindow) {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.window === window else { return event }
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                // Leave shortcuts owned by the app menu (⌘, ⌥, ⌃) alone.
                if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                    return event
                }
                let consumed = canvas.handleKey(
                    keyCode: event.keyCode,
                    shift: event.modifierFlags.contains(.shift),
                    isRepeat: event.isARepeat
                )
                return consumed ? nil : event
            }
        }

        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.window === window else { return event }
                // Swallow momentum so a flick does not keep zooming.
                guard event.momentumPhase.isEmpty else { return nil }
                let delta = Double(event.scrollingDeltaY)
                guard abs(delta) > 0.0001 else { return event }
                let factor = LargeImageCanvas.scrollZoomFactor(
                    deltaY: delta,
                    precise: event.hasPreciseScrollingDeltas
                )
                canvas.setZoom(canvas.zoom * factor, anchor: nil)
                return nil
            }
        }
    }

    private func removeEventMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}

// MARK: - Toolbar button

private struct ViewerToolButton: View {
    var icon: String
    var help: String
    var active: Bool = false
    var enabled: Bool = true
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(enabled ? 0.9 : 0.3))
                .frame(width: 31, height: 31)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private var background: Color {
        if active { return Color.white.opacity(0.18) }
        if hovering && enabled { return Color.white.opacity(0.10) }
        return .clear
    }
}

// MARK: - Host window resolution

/// Reports the `NSWindow` that hosts the viewer so the AppKit event monitors
/// can be scoped to it (rather than to whatever window happens to be key).
private struct WindowResolver: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolve(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func resolve(_ view: NSView) {
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            } else {
                // The view can be attached a run loop later during the
                // detail overlay's appearance transition.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onResolve(view.window)
                }
            }
        }
    }
}
