import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model: ViewerModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: ViewerModel? = nil) {
        _model = StateObject(wrappedValue: model ?? ViewerModel())
    }
    @State private var selection: PhotosPickerItem?
    @State private var showSettings = false
    @State private var showPhotoTools = false
    @State private var showReader = false
    @State private var showOriginal = false
    @AppStorage("readingRulerEnabled") private var readingRulerEnabled = false
    @AppStorage("guideVersion") private var guideVersion = 0
    @AppStorage("reachCalibrationProfile") private var legacyProfile = Data()
    @AppStorage("panelPlacements") private var panelPlacements = Data()
    @AppStorage("tiltDotPlacements") private var tiltDotPlacements = Data()
    @AppStorage("tiltGuideSeen") private var tiltGuideSeen = false
    @State private var showGuide = false
    @State private var showTiltGuide = false
    @State private var startTiltAfterGuide = false
    @State private var guideAfterSettings = false
    @State private var openPhotoAfterGuide = false
    @State private var showPhotoPicker = false
    @State private var controlPage = 0
    @GestureState private var drag: CGSize = .zero
    @GestureState private var tiltSweepActive = false
    @AppStorage("preferredHand") private var preferredHand = "right"
    @AppStorage("lightCanvas") private var lightCanvas = false
    @AppStorage("controlWidth") private var controlWidth = 288.0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tiltSensitivity") private var tiltSensitivity = 1.0

    @AppStorage("largeControls") private var largeControls = false
    @AppStorage("showControlLabels") private var showControlLabels = false
    @AppStorage("zoomSpeed") private var zoomSpeed = 1.0
    @AppStorage("doubleTapZoom") private var doubleTapZoom = 20.0
    @AppStorage("keepScreenAwake") private var keepScreenAwake = false

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && model.image != nil && scenePhase == .active
    }

    var body: some View {
        GeometryReader { geometry in
            fullScreenContent(size: geometry.size)
        }
        .onAppear {
            model.setTiltSensitivity(tiltSensitivity)
            model.setZoomPreferences(speed: zoomSpeed, doubleTap: doubleTapZoom)
            updateIdleTimer()
            if guideVersion < 1 { showGuide = true }
        }
        .onChange(of: preferredHand) { _, _ in model.stopTilt() }
        .onChange(of: controlWidth) { _, _ in model.stopTilt() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stopTilt() }; updateIdleTimer() }
        .onChange(of: keepScreenAwake) { _, _ in updateIdleTimer() }
        .onChange(of: model.image) { _, _ in updateIdleTimer() }
        .onChange(of: zoomSpeed) { _, _ in model.setZoomPreferences(speed: zoomSpeed, doubleTap: doubleTapZoom) }
        .onChange(of: doubleTapZoom) { _, _ in model.setZoomPreferences(speed: zoomSpeed, doubleTap: doubleTapZoom) }
        .onChange(of: showSettings) { _, shown in if shown { model.stopTilt() } }
        .onChange(of: showPhotoTools) { _, shown in if shown { model.stopTilt() } }
        .onChange(of: showReader) { _, shown in if shown { model.stopTilt() } }
        .onChange(of: showGuide) { _, shown in if shown { model.stopTilt() } }
        .onChange(of: tiltSensitivity) { _, value in model.setTiltSensitivity(value) }
        .onChange(of: tiltSweepActive) { _, active in
            if !active { model.endTiltZoomSweep() }
        }
        .onDisappear { model.stopTilt(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: typeSize) { _, _ in controlPage = 0; model.stopTilt() }
        .background(MonoTheme.surface)
        .tint(MonoTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings, onDismiss: {
            if guideAfterSettings { guideAfterSettings = false; showGuide = true }
        }) { settings }
        .sheet(isPresented: $showPhotoTools, onDismiss: { showOriginal = false }) {
            PhotoToolsView(image: model.image, hand: preferredHand, showOriginal: $showOriginal)
        }
        .fullScreenCover(isPresented: $showReader) {
            if let image = model.image { PhotoReaderView(image: image, backLabel: "Back to photo") }
        }
        .fullScreenCover(isPresented: $showGuide, onDismiss: {
            if openPhotoAfterGuide { openPhotoAfterGuide = false; showPhotoPicker = true }
        }) {
            GeometryReader { geometry in
                MonoGuideView(hand: $preferredHand, practicePosition: panelPosition(for: geometry.size)) { openPhoto in
                    guideVersion = 1
                    legacyProfile = Data()
                    openPhotoAfterGuide = openPhoto
                    showGuide = false
                }
            }
        }
        .sheet(isPresented: $showTiltGuide, onDismiss: {
            if startTiltAfterGuide && canPan { startTiltAfterGuide = false; model.toggleTilt() }
            else { startTiltAfterGuide = false }
        }) {
            MonoTiltGuideView(onFinish: {
                tiltGuideSeen = true
                startTiltAfterGuide = true
                showTiltGuide = false
            }, onCancel: { startTiltAfterGuide = false; showTiltGuide = false })
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selection, matching: .images)
        .alert("Unable to open image", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Tilt panning", isPresented: Binding(get: { model.tiltNotice != nil }, set: { if !$0 { model.tiltNotice = nil } })) {
            Button("OK", role: .cancel) { model.tiltNotice = nil }
        } message: { Text(model.tiltNotice ?? "") }
        .task(id: selection) {
            guard let selection else { return }
            let id = model.beginImport()
            let data = try? await selection.loadTransferable(type: Data.self)
            await model.completeImport(data, id: id)
            self.selection = nil
        }
    }

    private func fullScreenContent(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if model.image != nil { imageArea.ignoresSafeArea() }
            else { imageArea }
            if !model.isTiltEnabled {
                let panel = panelSize(in: size)
                MovablePanel(container: size, panel: panel, hand: preferredHand, position: panelPosition(for: size)) {
                    controls(maxHeight: max(0, panel.height - 44))
                }
                .transition(.opacity)
            }
            if model.image != nil && readingRulerEnabled && !model.isOverview {
                GeometryReader { area in
                    ReadingRuler(size: area.size, hand: preferredHand, showShade: false)
                }.ignoresSafeArea()
            }
            if model.isTiltEnabled {
                tiltDot(size: size).transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isTiltEnabled)
    }

    private func panelSize(in size: CGSize) -> CGSize {
        let landscape = size.width > size.height
        return CGSize(width: max(0, min(CGFloat(largeControls ? max(336, controlWidth) : controlWidth), size.width - 24)),
                      height: max(0, min(typeSize.isAccessibilitySize || largeControls || showControlLabels ? 440 : 308, landscape ? size.height - 24 : size.height * 0.65)))
    }

    private func panelPosition(for size: CGSize) -> Binding<PanelPosition> {
        let key = "\(preferredHand)-\(size.width > size.height ? "landscape" : "portrait")"
        return Binding(get: {
            let saved = (try? JSONDecoder().decode([String: PanelPosition].self, from: panelPlacements)) ?? [:]
            return saved[key] ?? .initial(hand: preferredHand)
        }, set: { value in
            var saved = (try? JSONDecoder().decode([String: PanelPosition].self, from: panelPlacements)) ?? [:]
            saved[key] = value
            panelPlacements = (try? JSONEncoder().encode(saved)) ?? Data()
        })
    }

    private func tiltDot(size: CGSize) -> some View {
        let panel = panelSize(in: size)
        let range = PanelGeometry.range(container: size, panel: panel, hand: preferredHand)
        let origin = PanelGeometry.origin(position: panelPosition(for: size).wrappedValue, range: range)
        let defaultCenter = CGPoint(x: origin.x + (preferredHand == "left" ? 30 : max(30, panel.width - 30)),
                                    y: origin.y + max(30, panel.height - 30))
        return MovableTiltDot(container: size, hand: preferredHand, zoom: model.zoom,
                              defaultCenter: defaultCenter, position: dotPosition(for: size)) { model.stopTilt() }
    }

    private func dotPosition(for size: CGSize) -> Binding<PanelPosition?> {
        let key = "\(preferredHand)-\(size.width > size.height ? "landscape" : "portrait")"
        return Binding(get: {
            (try? JSONDecoder().decode([String: PanelPosition].self, from: tiltDotPlacements))?[key]
        }, set: { value in
            var saved = (try? JSONDecoder().decode([String: PanelPosition].self, from: tiltDotPlacements)) ?? [:]
            saved[key] = value
            tiltDotPlacements = (try? JSONEncoder().encode(saved)) ?? Data()
        })
    }

    private var overlayControls: Bool { model.image != nil && !showSettings }

    private func requestTilt() {
        guard canPan else { return }
        if tiltGuideSeen { model.toggleTilt() }
        else { showTiltGuide = true }
    }

    private var imageArea: some View {
        GeometryReader { geometry in
            ZStack {
                (lightCanvas ? Color.white : Color.black)
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .modifier(PhotoAppearance(original: showOriginal))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(model.displayedZoom)
                        .offset(model.isOverview ? .zero : model.bounded(CGSize(width: model.offset.width + drag.width, height: model.offset.height + drag.height)))
                        .accessibilityLabel("Selected image")
                        .accessibilityValue(model.isOverview ? "Full image overview" : "Zoom \(Int(model.zoom * 100)) percent")
                        .accessibilityIdentifier("viewerImage")
                        .accessibilityHint(model.isTiltEnabled
                                            ? "Tilt to explore. Use Actions to toggle double-tap zoom, or adjust up and down to change zoom with VoiceOver."
                                            : "Use the direction buttons to explore the image. Adjust up or down to change the zoom.")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: model.changeZoom(by: 1.5, keepingTilt: model.isTiltEnabled)
                            case .decrement: model.changeZoom(by: 1 / 1.5, keepingTilt: model.isTiltEnabled)
                            @unknown default: break
                            }
                        }
                        .accessibilityActions {
                            if model.isTiltEnabled {
                                Button("Toggle double-tap zoom") { model.toggleTiltZoomLimit() }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(imageGesture)
                    if readingRulerEnabled && !model.isOverview {
                        ReadingRuler(size: geometry.size, hand: preferredHand, interactive: false)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("MonoView").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Image(systemName: "photo").font(.system(size: 62, weight: .light)).accessibilityHidden(true)
                        Text("Open a photo to begin.").font(.title3)
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MonoTheme.text)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(MonoBackground())
                }
                if model.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading image…").font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }
            }
            .clipped()
            .coordinateSpace(name: "viewerSurface")
            .onAppear { model.resizeViewport(geometry.size) }
            .onChange(of: geometry.size) { _, size in model.resizeViewport(size) }
        }
    }

    private var imageGesture: AnyGesture<Void> {
        if model.isTiltEnabled {
            let doubleTap = TapGesture(count: 2).onEnded { model.toggleTiltZoomLimit() }
            let sweep = DragGesture(minimumDistance: 8, coordinateSpace: .named("viewerSurface"))
                .updating($tiltSweepActive) { _, active, _ in active = true }
                .onChanged { model.updateTiltZoomSweep(translation: $0.translation) }
                .onEnded { _ in model.endTiltZoomSweep() }
            return AnyGesture(doubleTap.exclusively(before: sweep).map { _ in () })
        }
        let pan = DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { model.finishDrag($0.translation) }
        return AnyGesture(pan.map { _ in () })
    }

    private func controls(maxHeight: CGFloat, compact: Bool = false) -> some View {
        let imageTitle = model.image == nil ? "Open photo" : "New photo"
        let columnCount = compact || typeSize.isAccessibilitySize ? 2 : 3
        let order = preferredHand == "left" ? [2, 1, 0, 3, 4, 5, 8, 7, 6] : Array(0...8)
        let visibleOrder = compact ? Array(order.dropFirst(controlPage * 2).prefix(2)) : order
        return VStack(spacing: 8) {
            ScrollView {
            VStack(spacing: 10) {
                Group {
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            readTextButton
                            HStack(spacing: 12) { photoToolButtons }
                        }
                    } else {
                        HStack(spacing: 8) {
                            readTextButton
                            photoToolButtons
                        }
                    }
                }
                .foregroundStyle(.white)
                // Nine controls do not need lazy creation; every action remains discoverable
                // to VoiceOver even when larger text requires scrolling.
                VStack(spacing: 8) {
                    ForEach(Array(stride(from: 0, to: visibleOrder.count, by: columnCount)), id: \.self) { start in
                        HStack(spacing: 8) {
                            ForEach(Array(visibleOrder.dropFirst(start).prefix(columnCount)), id: \.self) { item in
                                normalControl(item, photoTitle: imageTitle)
                            }
                            if visibleOrder.count - start < columnCount {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 56).accessibilityHidden(true)
                            }
                        }
                    }
                    if compact {
                        HStack(spacing: 8) {
                            command("Previous", icon: "chevron.left") { controlPage = (controlPage + 4) % 5 }
                            command("Next", icon: "chevron.right") { controlPage = (controlPage + 1) % 5 }
                        }
                    }
                }
            }
            .padding(10)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: max(0, min(maxHeight, compact ? 218 : typeSize.isAccessibilitySize || largeControls || showControlLabels ? 420 : 264)))
        .environment(\.manualMenuAppearance, true)
        .transition(.scale(scale: 0.2, anchor: preferredHand == "left" ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
    }

    private var readTextButton: some View {
        Button { showReader = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "text.viewfinder").font(.system(size: 24, weight: .semibold))
                Text("Read text").font(.callout.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(ControlStyle(primary: true))
        .disabled(!canUseImage)
        .accessibilityLabel("Read text")
        .accessibilityHint("Recognize text in this photo and open the reader.")
        .accessibilityIdentifier("readText")
    }

    @ViewBuilder private var photoToolButtons: some View {
                    Button { showPhotoTools = true } label: {
                        Image(systemName: "camera.filters").font(.title3)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(ControlStyle()).disabled(!canUseImage)
                        .accessibilityLabel("Photo tools").accessibilityIdentifier("photoTools")
                    if !model.isTiltEnabled {
                        Button { requestTilt() } label: {
                            Label("Tilt", systemImage: "move.3d")
                                .font(.callout.weight(.semibold))
                                .frame(minWidth: 60, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ControlStyle())
                        .disabled(!canPan)
                        .accessibilityLabel("Start tilt panning")
                        .accessibilityIdentifier("startTilt")
                    }
    }

    @ViewBuilder
    private func normalControl(_ item: Int, photoTitle: String) -> some View {
                        switch item {
                        case 0:
                            command("Zoom out", icon: "minus.magnifyingglass") { model.changeZoom(by: pow(1 / 1.5, zoomSpeed)) }
                                .disabled(!canUseImage || (model.zoom <= 1 && !model.isOverview))
                        case 1:
                            command("Up", icon: "arrow.up") { model.move(dx: 0, dy: 90) }.disabled(!canPan)
                        case 2:
                            command("Zoom in", icon: "plus.magnifyingglass") { model.changeZoom(by: pow(1.5, zoomSpeed)) }
                                .disabled(!canUseImage || (model.zoom >= 20 && !model.isOverview))
                        case 3:
                            command("Left", icon: "arrow.left") { model.move(dx: 90, dy: 0) }.disabled(!canPan)
                        case 4:
                            command(model.isOverview ? "Return" : "Overview", icon: "arrow.up.left.and.arrow.down.right") { model.toggleOverview() }.disabled(!canUseImage)
                        case 5:
                            command("Right", icon: "arrow.right") { model.move(dx: -90, dy: 0) }.disabled(!canPan)
                        case 6:
                            PhotosPicker(selection: $selection, matching: .images) {
                                controlLabel(photoTitle, icon: "photo")
                            }
                            .buttonStyle(ControlStyle(primary: true, transparent: overlayControls))
                            .disabled(model.isLoading)
                            .accessibilityIdentifier("chooseImage")
                .simultaneousGesture(TapGesture().onEnded { model.stopTilt() })
                        case 7:
                            command("Down", icon: "arrow.down") { model.move(dx: 0, dy: -90) }.disabled(!canPan)
                        default:
                            command("Settings", icon: "slider.horizontal.3") { showSettings = true }
                                .accessibilityIdentifier("settings")
                        }
    }

    private var canUseImage: Bool { model.image != nil && !model.isLoading }
    private var canPan: Bool { canUseImage && model.zoom > 1 && !model.isOverview }

    private func controlLabel(_ title: String, icon: String) -> some View {
        ManualMenuLabel(title: title, icon: icon)
    }

    private func command(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button { action(); ComfortFeedback.play() } label: { controlLabel(title, icon: icon) }
            .buttonStyle(ControlStyle(transparent: overlayControls))
    }

    private var settings: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Make it yours").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Button { guideAfterSettings = true; showSettings = false } label: {
                        Label("Open visual guide", systemImage: "book.fill").frame(maxWidth: .infinity, minHeight: 56)
                    }.buttonStyle(ControlStyle(primary: true)).accessibilityIdentifier("reopenGuide")
                    Text("Your hand").font(.title2.bold())
                    Picker("Hand used to hold your phone", selection: $preferredHand) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                    }.pickerStyle(.segmented)
                    Text("Control panel").font(.title2.bold())
                    Text("Hold the grip to move the panel within the outline. During Tilt, hold and drag the floating dot to reposition it.")
                    Picker("Panel width", selection: $controlWidth) {
                        Text("Compact").tag(288.0)
                        Text("Wide").tag(336.0)
                    }.pickerStyle(.segmented)
                    Button {
                        panelPlacements = Data()
                        tiltDotPlacements = Data()
                    } label: {
                        Label("Reset panel positions", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(ControlStyle()).accessibilityIdentifier("resetPanelPosition")
                    DisclosureGroup {
                        ComfortSettings().padding(.top, 12)
                    } label: { Text("Comfort settings").accessibilityIdentifier("comfortSettings") }
                    DisclosureGroup("Photo appearance") {
                        Toggle("Light image background", isOn: $lightCanvas).padding(.vertical, 12)
                    }
                    DisclosureGroup("Tilt and zoom help") {
                        VStack(alignment: .leading, spacing: 16) {
                            GuideIllustration(picture: .tilt)
                            Text("Zoom in and choose Tilt. A short visual guide explains the gestures the first time.")
                            Text("Tilt gently to explore. Tap the floating dot to stop.")
                            Text("Double tap the photo for your chosen zoom; double tap again to fit. Sweep up to zoom in and down to zoom out.")
                            Picker("Tilt sensitivity", selection: $tiltSensitivity) {
                                Text("Gentle").tag(0.6)
                                Text("Normal").tag(1.0)
                                Text("Fast").tag(1.5)
                            }.pickerStyle(.segmented)
                            Button { tiltGuideSeen = false } label: {
                                Text("Show Tilt guide next time").frame(maxWidth: .infinity, minHeight: 52)
                            }.buttonStyle(ControlStyle())
                            Text("Tilt stops when you tap the dot, open Settings, rotate the phone, show Overview, or leave the app.")
                            Text("Zoom enlarges existing detail; it cannot add missing detail.")
                        }.padding(.top, 12)
                    }
                    Button { model.reset() } label: {
                        Label("Reset photo view", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 52)
                    }.buttonStyle(ControlStyle()).disabled(model.image == nil)
                }.padding(24)
            }
            Button { showSettings = false } label: {
                Text("Done").frame(maxWidth: .infinity, minHeight: 56)
            }.buttonStyle(ControlStyle(primary: true)).padding(16)
        }
        .foregroundStyle(MonoTheme.text).background(MonoBackground())
        .tint(MonoTheme.accent).preferredColorScheme(.dark).presentationDragIndicator(.visible)
    }
}

/// Royal blue surfaces with white text; the photo canvas keeps its own background.
enum MonoTheme {
    static let royal = Color(red: 65 / 255, green: 105 / 255, blue: 225 / 255)
    static let deepBlue = Color(red: 30 / 255, green: 59 / 255, blue: 143 / 255)
    static let surface = Color(red: 42 / 255, green: 77 / 255, blue: 180 / 255)
    static let white = Color.white
    static let text = Color.white
    static let accent = Color.white
}

struct MonoBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        LinearGradient(colors: reduceTransparency || contrast == .increased
                       ? [MonoTheme.surface, MonoTheme.surface]
                       : [MonoTheme.royal, MonoTheme.surface, MonoTheme.deepBlue],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

struct MonoBrandMark: View {
    var size: CGFloat = 80
    var body: some View {
        Image("MonoBrand")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.23).stroke(MonoTheme.white.opacity(0.35), lineWidth: 1))
            .shadow(color: MonoTheme.deepBlue.opacity(0.3), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

private struct ManualMenuAppearanceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var manualMenuAppearance: Bool {
        get { self[ManualMenuAppearanceKey.self] }
        set { self[ManualMenuAppearanceKey.self] = newValue }
    }
}

/// A single shared surface lets icons read as a menu rather than separate cards.
struct ManualMenuSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("panelOpacity") private var panelOpacity = 0.62
    @AppStorage("opaqueControls") private var opaque = false

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(white: 0.07).opacity(reduceTransparency || opaque ? 1 : contrast == .increased ? max(0.85, panelOpacity) : panelOpacity))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(contrast == .increased ? 1 : 0.3), lineWidth: contrast == .increased ? 2 : 1))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

/// Shared visual face; touch and accessibility actions live on MovableTiltDot.
struct TiltDotFace: View {
    @AppStorage("largeControls") private var large = false
    @AppStorage("panelOpacity") private var opacity = 0.62
    @AppStorage("opaqueControls") private var opaque = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(reduceTransparency || opaque ? 1 : max(0.2, opacity * 0.6)))
            Circle().stroke(Color.black.opacity(0.75), lineWidth: 3)
            Circle().stroke(Color.white.opacity(contrast == .increased ? 1 : 0.75), lineWidth: 1.5)
            Circle().fill(Color.white.opacity(reduceTransparency || opaque ? 1 : max(0.5, opacity)))
                .frame(width: 28, height: 28)
        }.frame(width: large ? 76 : 60, height: large ? 76 : 60)
    }
}

struct ManualMenuLabel: View {
    let title: String
    let icon: String
    @Environment(\.manualMenuAppearance) private var manual
    @AppStorage("showControlLabels") private var labels = false
    @AppStorage("largeControls") private var large = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(manual ? .system(size: large ? 34 : 27, weight: .medium) : .title2)
                .frame(minHeight: 32)
                .accessibilityHidden(true)
            if !manual || labels {
                Text(title).font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: manual && !labels ? (large ? 72 : 56) : 86)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .shadow(color: manual ? .black.opacity(0.8) : .clear, radius: 1, y: 1)
    }
}

struct ControlStyle: ButtonStyle {
    var primary = false
    var transparent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @Environment(\.manualMenuAppearance) private var manual

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if manual {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(Color.white.opacity(configuration.isPressed ? 0.24 : primary ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(enabled ? 1 : 0.45)
        } else {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 6)
            .foregroundStyle(primary && !transparent ? MonoTheme.deepBlue : MonoTheme.white)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(transparent
                          ? AnyShapeStyle(MonoTheme.deepBlue.opacity(reduceTransparency ? 1 : 0.88))
                          : primary
                            ? AnyShapeStyle(MonoTheme.white)
                            : AnyShapeStyle(MonoTheme.surface))
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MonoTheme.white.opacity(primary || contrast == .increased ? 1 : 0.75),
                        lineWidth: primary || contrast == .increased ? 2.5 : 1.5))
            .shadow(color: MonoTheme.deepBlue.opacity(transparent ? 0 : 0.3), radius: 4, y: 2)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
        }
    }
}

#Preview { ContentView() }
