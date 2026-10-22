import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var model: ViewerModel
    @State private var tiltDotAnchor: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: ViewerModel? = nil) {
        _model = StateObject(wrappedValue: model ?? ViewerModel())
    }
    @State private var selection: PhotosPickerItem?
    @State private var showSettings = false
    @AppStorage("reachSetupCompleted") private var reachSetupCompleted = false
    @AppStorage("reachCalibrationVersion") private var reachCalibrationVersion = 0
    @AppStorage("reachCalibrationProfile") private var reachCalibrationData = Data()
    @State private var showCalibration = false
    @AppStorage("purposeIntroSeen") private var purposeIntroSeen = false
    @State private var showPurpose = false
    @State private var calibrateAfterSettings = false
    @State private var pendingProfile: ReachProfile?
    @State private var storedProfile: ReachProfile?
    @State private var controlPage = 0
    @State private var isSettingUp = false
    @State private var setupStep = 0
    @State private var testedControls: Set<Int> = []
    @State private var lastTestedControl = ""
    @GestureState private var drag: CGSize = .zero
    @GestureState private var tiltSweepActive = false
    @AppStorage("preferredHand") private var preferredHand = "right"
    @AppStorage("lightCanvas") private var lightCanvas = false
    @AppStorage("controlLift") private var controlLift = 0.0
    @AppStorage("controlWidth") private var controlWidth = 288.0
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tiltSensitivity") private var tiltSensitivity = 1.0

    var body: some View {
        VStack(spacing: 0) {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && !typeSize.isAccessibilitySize
            let panelWidth = min(CGFloat(controlWidth), max(0, geometry.size.width - 24))
            Group {
                if model.image != nil && !isSettingUp {
                    fullScreenContent(size: geometry.size)
                } else if let profile = activeProfile,
                   profile.matches(geometry.size),
                   !typeSize.isAccessibilitySize {
                    calibratedContent(profile, size: geometry.size)
                } else if wide {
                    HStack(alignment: .bottom, spacing: 0) {
                        if preferredHand == "left" {
                            controls(maxHeight: geometry.size.height - 12)
                                .frame(width: min(panelWidth, geometry.size.width * 0.46))
                        }
                        imageArea
                        if preferredHand != "left" {
                            controls(maxHeight: geometry.size.height - 12)
                                .frame(width: min(panelWidth, geometry.size.width * 0.46))
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        imageArea
                        controls(maxHeight: min(typeSize.isAccessibilitySize ? 420 : 340, geometry.size.height * 0.6))
                            .frame(width: panelWidth)
                            .padding(.bottom, min(CGFloat(controlLift), geometry.size.height * 0.12))
                            .frame(maxWidth: .infinity, alignment: preferredHand == "left" ? .leading : .trailing)
                            .padding(.horizontal, 6)
                    }
                }
            }
        }
        }
        .onAppear {
            storedProfile = try? JSONDecoder().decode(ReachProfile.self, from: reachCalibrationData)
            model.setTiltSensitivity(tiltSensitivity)
            if !purposeIntroSeen || reachCalibrationVersion < 2 {
                showPurpose = !purposeIntroSeen
                beginReachSetup()
            }
        }
        .onChange(of: preferredHand) { _, hand in
            if activeProfile?.hand != hand { useManualLayout() }
            clearReachTrials()
        }
        .onChange(of: controlWidth) { _, _ in useManualLayout(); clearReachTrials() }
        .onChange(of: controlLift) { _, _ in useManualLayout(); clearReachTrials() }
        .onChange(of: reachCalibrationData) { _, data in
            storedProfile = try? JSONDecoder().decode(ReachProfile.self, from: data)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.stopTilt() } }
        .onChange(of: showSettings) { _, shown in if shown { model.stopTilt() } }
        .onChange(of: showCalibration) { _, shown in if shown { model.stopTilt() } }
        .onChange(of: tiltSensitivity) { _, value in model.setTiltSensitivity(value) }
        .onChange(of: model.isTiltEnabled) { _, enabled in
            if !enabled { tiltDotAnchor = nil }
        }
        .onChange(of: tiltSweepActive) { _, active in
            if !active { model.endTiltZoomSweep() }
        }
        .onDisappear { model.stopTilt() }
        .onChange(of: typeSize) { _, _ in controlPage = 0; clearReachTrials() }
        .background(MonoTheme.surface)
        .tint(MonoTheme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings, onDismiss: {
            if calibrateAfterSettings {
                calibrateAfterSettings = false
                beginReachSetup()
            }
        }) { settings }
        .fullScreenCover(isPresented: $showCalibration) {
            if showPurpose {
                MonoPurposeView {
                    purposeIntroSeen = true
                    showPurpose = false
                    if reachCalibrationVersion >= 2 { showCalibration = false }
                }
            } else {
            ReachCalibrationView(initialHand: preferredHand, onManual: {
                showCalibration = false
                useManualLayout()
                startManualSetup()
            }, onApply: { profile in
                preferredHand = profile.hand
                pendingProfile = profile
                controlPage = 0
                setupStep = 2
                testedControls = []
                lastTestedControl = ""
                isSettingUp = true
                showCalibration = false
            })
            }
        }
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

    /// Image geometry expands to the display; the calibrated controls keep their safe-area coordinates.
    private func fullScreenContent(size: CGSize) -> some View {
        ZStack(alignment: preferredHand == "left" ? .bottomLeading : .bottomTrailing) {
            imageArea.ignoresSafeArea()
            if model.isTiltEnabled {
                tiltDot(size: size)
                    .transition(.opacity)
            } else if let profile = activeProfile, profile.matches(size), !typeSize.isAccessibilitySize {
                if let regions = profile.regions, regions.count >= 2 {
                    curvedControls(regions, size: size)
                    let pages = (10 + regions.count - 2) / (regions.count - 1)
                    Text("Zoom \(Double(model.zoom).formatted(.number.precision(.fractionLength(1))))× · Page \(controlPage % pages + 1) of \(pages)\(model.isTiltEnabled ? " · Tilt on" : "")")
                        .font(.headline.monospacedDigit())
                        .padding(8)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                } else {
                    let rect = profile.rect(in: size)
                    controls(maxHeight: rect.height, compact: profile.compact)
                        .frame(width: rect.width)
                        .position(x: rect.midX, y: rect.midY)
                }
            } else {
                controls(maxHeight: min(typeSize.isAccessibilitySize ? 420 : 340, size.height * 0.7))
                    .frame(width: min(CGFloat(controlWidth), max(0, size.width - 24)))
                    .padding(.bottom, min(CGFloat(controlLift), size.height * 0.12))
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isTiltEnabled)
    }

    private func tiltDot(size: CGSize) -> some View {
        let profile = typeSize.isAccessibilitySize ? nil : activeProfile.flatMap { $0.matches(size) ? $0 : nil }
        let fallback = CGPoint(x: preferredHand == "left" ? 36 : max(36, size.width - 36),
                               y: max(36, size.height - min(CGFloat(controlLift), size.height * 0.12) - 36))
        let anchor = profile != nil ? tiltDotAnchor ?? profile.map { CGPoint(x: $0.rect(in: size).midX, y: $0.rect(in: size).midY) } ?? fallback : fallback
        return TiltDotButton(zoom: model.zoom) { model.stopTilt() }
            .position(x: min(max(30, anchor.x), max(30, size.width - 30)),
                      y: min(max(30, anchor.y), max(30, size.height - 30)))
            .frame(width: size.width, height: size.height)
    }

    private var overlayControls: Bool { model.image != nil && !isSettingUp && !showSettings }

    @ViewBuilder
    private func calibratedContent(_ profile: ReachProfile, size: CGSize) -> some View {
        let rect = profile.rect(in: size)
        ZStack(alignment: .topLeading) {
            imageArea
                .padding(.bottom, profile.landscape ? 0 : max(0, size.height - rect.minY + 8))
                .padding(.leading, profile.landscape && profile.hand == "left" ? rect.maxX + 8 : 0)
                .padding(.trailing, profile.landscape && profile.hand == "right" ? size.width - rect.minX + 8 : 0)
            if let regions = profile.regions, regions.count >= 2 {
                curvedControls(regions, size: size)
                if !isSettingUp {
                    let pages = (10 + regions.count - 2) / (regions.count - 1)
                    Text("Zoom \(Double(model.zoom).formatted(.number.precision(.fractionLength(1))))× · Page \(controlPage % pages + 1) of \(pages)\(model.isTiltEnabled ? " · Tilt on" : "")")
                        .font(.headline.monospacedDigit())
                        .padding(10)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            } else {
                controls(maxHeight: rect.height, compact: profile.compact)
                    .frame(width: rect.width)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func curvedControls(_ regions: [ReachRegion], size: CGSize) -> some View {
        let order = isSettingUp ? [6, 2, 0, 4, 1, 7, 3, 5, 8, 9, 10] : [6, 2, 0, 13, 4, 1, 7, 3, 5, 8]
        let capacity = regions.count - 1
        let pageCount = (order.count + capacity - 1) / capacity
        let page = controlPage % pageCount
        return ZStack(alignment: .topLeading) {
            ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                let bounds = region.bounds(in: size)
                let itemIndex = page * capacity + index
                let item: Int = model.isTiltEnabled && !isSettingUp
                    ? (index == regions.count - 1 ? 15 : index == 0 ? 14 : itemIndex < order.count ? order[itemIndex] : 12)
                    : (index == regions.count - 1 ? 11 : itemIndex < order.count ? order[itemIndex] : 12)
                curvedControl(item, region: region, size: size, pageCount: pageCount)
                    .position(x: bounds.midX, y: bounds.midY)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func curvedControl(_ item: Int, region: ReachRegion, size: CGSize, pageCount: Int) -> some View {
        let names = ["Zoom out", "Up", "Zoom in", "Left", model.isOverview ? "Return to detail" : "Overview", "Right", "Open photo", "Down", "Settings", "Save setup", "Manual adjustments", "More controls", "Empty slot", "Start tilt panning", "Recenter tilt panning", "Stop tilt panning"]
        let titles = ["Out", "Up", "In", "Left", model.isOverview ? "Return" : "Whole", "Right", "Photo", "Down", "Options", "Save", "Adjust", "More", "", "Tilt", "Center", "Stop"]
        let icons = ["minus.magnifyingglass", "arrow.up", "plus.magnifyingglass", "arrow.left", "arrow.up.left.and.arrow.down.right", "arrow.right", "photo", "arrow.down", "slider.horizontal.3", "checkmark", "slider.horizontal.3", "ellipsis", "", "move.3d", "scope", "pause.fill"]
        let primary = item == 6 || item == 9 || item == 15
        let checked = isSettingUp && testedControls.contains(item)
        let label = ReachTerritoryLabel(region: region, canvasSize: size, title: titles[item], icon: icons[item], primary: primary, checked: checked)
        let shape = ReachRegionShape(region: region, canvasSize: size)
        if item == 12 {
            Color.clear.frame(width: region.bounds(in: size).width, height: region.bounds(in: size).height).allowsHitTesting(false)
        } else if item == 6 && !isSettingUp {
            PhotosPicker(selection: $selection, matching: .images) { label }
                .buttonStyle(ReachTerritoryPressStyle())
                .contentShape(shape, eoFill: true)
                .disabled(model.isLoading)
                .accessibilityLabel("Open photo")
                .accessibilityIdentifier("chooseImage")
                .simultaneousGesture(TapGesture().onEnded { model.stopTilt() })
        } else {
            Button {
                if item == 11 { controlPage = (controlPage + 1) % pageCount }
                else if item == 9 { finishReachSetup() }
                else if item == 10 { useManualLayout(); startManualSetup() }
                else if isSettingUp { testedControls.insert(item); lastTestedControl = names[item] }
                else {
                    if item == 13 {
                        tiltDotAnchor = CGPoint(x: region.anchor.x * size.width, y: region.anchor.y * size.height)
                    }
                    performCurvedAction(item)
                }
            } label: { label }
            .buttonStyle(ReachTerritoryPressStyle())
            .contentShape(shape, eoFill: true)
            .disabled(curvedControlDisabled(item))
            .accessibilityLabel(isSettingUp && item < 9 ? "Try \(names[item])" : names[item])
            .accessibilityValue(item == 11 ? "Page \(controlPage % pageCount + 1) of \(pageCount)" : checked ? "Tried" : "")
            .accessibilityIdentifier(item == 8 && !isSettingUp ? "settings" : "curvedControl\(item)")
        }
    }

    private func curvedControlDisabled(_ item: Int) -> Bool {
        if item == 13 { return !canPan }
        if isSettingUp || item >= 8 { return false }
        if item == 6 { return model.isLoading }
        if item == 0 { return !canUseImage || (model.zoom <= 1 && !model.isOverview) }
        if item == 2 { return !canUseImage || (model.zoom >= 20 && !model.isOverview) }
        if item == 4 { return !canUseImage }
        return !canPan
    }

    private func performCurvedAction(_ item: Int) {
        switch item {
        case 0: model.changeZoom(by: 1 / 1.5)
        case 1: model.move(dx: 0, dy: 90)
        case 2: model.changeZoom(by: 1.5)
        case 3: model.move(dx: 90, dy: 0)
        case 4: model.toggleOverview()
        case 5: model.move(dx: -90, dy: 0)
        case 7: model.move(dx: 0, dy: -90)
        case 8: showSettings = true
        case 13: model.toggleTilt()
        case 14: model.recenterTilt()
        case 15: model.stopTilt()
        default: break
        }
    }

    private func finishReachSetup() {
        if let pendingProfile {
            storedProfile = pendingProfile
            reachCalibrationData = (try? JSONEncoder().encode(pendingProfile)) ?? Data()
        }
        pendingProfile = nil
        reachSetupCompleted = true
        reachCalibrationVersion = 2
        controlPage = 0
        isSettingUp = false
    }

    private var imageArea: some View {
        GeometryReader { geometry in
            ZStack {
                (lightCanvas ? Color.white : Color.black)
                if isSettingUp {
                    VStack(spacing: 0) {
                        setupInstructions
                        if pendingProfile?.regions == nil { setupFooter }
                    }
                } else if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(model.displayedZoom)
                        .offset(model.isOverview ? .zero : model.bounded(CGSize(width: model.offset.width + drag.width, height: model.offset.height + drag.height)))
                        .accessibilityLabel("Selected image")
                        .accessibilityValue(model.isOverview ? "Full image overview" : "Zoom \(Int(model.zoom * 100)) percent")
                        .accessibilityIdentifier("viewerImage")
                        .accessibilityHint(model.isTiltEnabled
                                            ? "Tilt to explore. Use Actions to toggle maximum zoom, or adjust up and down to change zoom with VoiceOver."
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
                                Button("Toggle maximum zoom") { model.toggleTiltZoomLimit() }
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(imageGesture)
                } else {
                    VStack(spacing: 16) {
                        MonoBrandMark(size: 104)
                        Text("MonoView").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("See the detail.\nUse one hand.")
                            .font(.title3).multilineTextAlignment(.center)
                        Text("Open a photo to begin. Fit the controls to your hand in Settings.")
                            .font(.body).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(MonoTheme.text)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: compact || typeSize.isAccessibilitySize ? 2 : 3)
        let order = preferredHand == "left" ? [2, 1, 0, 3, 4, 5, 8, 7, 6] : Array(0...8)
        let visibleOrder = compact ? Array(order.dropFirst(controlPage * 2).prefix(2)) : order
        return VStack(spacing: 8) {
            ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text((compact ? "\(controlPage + 1)/5 · " : "") + (isSettingUp ? "Try the controls" : model.isOverview ? "Overview" : "Zoom \(Double(model.zoom).formatted(.number.precision(.fractionLength(1))))×"))
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity)
                    if !isSettingUp && !model.isTiltEnabled {
                        Button { tiltDotAnchor = nil; model.toggleTilt() } label: {
                            Label("Tilt", systemImage: "move.3d")
                                .font(.callout.weight(.semibold))
                                .frame(minWidth: 60, minHeight: 44)
                        }
                        .buttonStyle(ControlStyle())
                        .disabled(!canPan)
                        .accessibilityLabel("Start tilt panning")
                        .accessibilityIdentifier("startTilt")
                    }
                }
                .foregroundStyle(.white)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(visibleOrder, id: \.self) { item in
                        if isSettingUp {
                            trialControl(item, photoTitle: imageTitle)
                        } else {
                            normalControl(item, photoTitle: imageTitle)
                        }
                    }
                    if compact {
                        if visibleOrder.count == 1 { Color.clear.frame(height: 76).accessibilityHidden(true) }
                        command("Previous", icon: "chevron.left") { controlPage = (controlPage + 4) % 5 }
                        command("Next", icon: "chevron.right") { controlPage = (controlPage + 1) % 5 }
                    }
                }
            }
            .padding(10)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .frame(height: max(0, min(maxHeight, compact ? 218 : typeSize.isAccessibilitySize ? 420 : 332)))
        .background(ManualMenuSurface())
        .environment(\.manualMenuAppearance, true)
        .transition(.scale(scale: 0.2, anchor: preferredHand == "left" ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
    }

    @ViewBuilder
    private func normalControl(_ item: Int, photoTitle: String) -> some View {
                        switch item {
                        case 0:
                            command("Zoom out", icon: "minus.magnifyingglass") { model.changeZoom(by: 1 / 1.5) }
                                .disabled(!canUseImage || (model.zoom <= 1 && !model.isOverview))
                        case 1:
                            command("Up", icon: "arrow.up") { model.move(dx: 0, dy: 90) }.disabled(!canPan)
                        case 2:
                            command("Zoom in", icon: "plus.magnifyingglass") { model.changeZoom(by: 1.5) }
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

    private func clearReachTrials() {
        guard isSettingUp else { return }
        testedControls = []
        lastTestedControl = ""
    }

    private var activeProfile: ReachProfile? {
        pendingProfile ?? storedProfile
    }

    private func useManualLayout() {
        pendingProfile = nil
        storedProfile = nil
        reachCalibrationData = Data()
        controlPage = 0
    }

    private func beginReachSetup() {
        showCalibration = true
    }

    private func startManualSetup() {
        setupStep = 0
        testedControls = []
        lastTestedControl = ""
        isSettingUp = true
    }

    private var setupInstructions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Make MonoView fit your hand")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(pendingProfile == nil ? "Step \(min(setupStep + 1, 2)) of 2" : "Check your suggested layout")
                    .font(.headline).foregroundStyle(MonoTheme.accent)
                switch setupStep {
                case 0:
                    Text("Choose your hand. The controls move to that side.")
                case 1:
                    Text("Adjust the panel and try its buttons. Save when you can reach them without stretching or changing your grip.")
                default:
                    Text(pendingProfile?.regions != nil ? "Try the buttons with a relaxed grip. More shows the next controls, including Save and Adjust." : "Try the buttons without stretching. Save when comfortable, or go Back to adjust.")
                }
                Text(lastTestedControl.isEmpty ? "Practice buttons only — no photo needed." : "\(lastTestedControl) reached. \(testedControls.count) of 9 tried.")
                    .foregroundStyle(MonoTheme.text)
                    .accessibilityIdentifier("reachFeedback")
                if setupStep >= 1 {
                    Text(pendingProfile?.regions != nil ? "If a button feels uncomfortable, choose Adjust. Save when ready." : "You can change this later in Settings.")
                        .font(.footnote)
                }
            }
            .font(.body)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(MonoTheme.text)
        .background(MonoBackground())
    }

    private func trialControl(_ item: Int, photoTitle: String) -> some View {
        let titles = ["Zoom out", "Up", "Zoom in", "Left", "Overview", "Right", photoTitle, "Down", "Settings"]
        let icons = ["minus.magnifyingglass", "arrow.up", "plus.magnifyingglass", "arrow.left", "arrow.up.left.and.arrow.down.right", "arrow.right", "photo", "arrow.down", "slider.horizontal.3"]
        return Button {
            testedControls.insert(item)
            lastTestedControl = titles[item]
        } label: {
            controlLabel(titles[item], icon: icons[item])
                .overlay(alignment: .topTrailing) {
                    if testedControls.contains(item) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MonoTheme.royal, MonoTheme.white)
                            .padding(4)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(ControlStyle(primary: item == 6))
        .accessibilityLabel("Try \(titles[item])")
        .accessibilityValue(testedControls.contains(item) ? "Tried" : "Not tried yet")
        .accessibilityIdentifier("reachTrial\(item)")
    }

    private var setupFooter: some View {
        VStack(spacing: 12) {
            if setupStep == 0 {
                Picker("Hand used to hold your phone", selection: $preferredHand) {
                    Text("Left hand").tag("left")
                    Text("Right hand").tag("right")
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)
            } else if setupStep == 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Panel width").font(.headline)
                    Picker("Panel width", selection: $controlWidth) {
                        Text("Compact").tag(288.0)
                        Text("Wide").tag(336.0)
                    }.pickerStyle(.segmented)
                    Text("Panel height (portrait)").font(.headline)
                    Picker("Panel height", selection: $controlLift) {
                        Text("Low").tag(0.0)
                        Text("Middle").tag(40.0)
                        Text("High").tag(80.0)
                    }.pickerStyle(.segmented)
                }
            }
            HStack(spacing: 12) {
                if setupStep > 0 {
                    Button("Back") {
                        if pendingProfile != nil { useManualLayout(); startManualSetup() }
                        else { setupStep -= 1 }
                    }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .buttonStyle(ControlStyle(transparent: overlayControls))
                }
                Button(setupStep >= 1 ? "Save setup" : "Next") {
                    if setupStep == 0 {
                        setupStep += 1
                    } else {
                        finishReachSetup()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .buttonStyle(ControlStyle(primary: true, transparent: overlayControls))
                .accessibilityIdentifier("reachNext")
            }
        }
        .padding(12)
        .frame(maxWidth: 336)
        .frame(maxWidth: .infinity, alignment: preferredHand == "left" ? .leading : .trailing)
        .foregroundStyle(MonoTheme.text)
        .background(MonoTheme.surface)
        .environment(\.colorScheme, .dark)
    }

    private var canUseImage: Bool { model.image != nil && !model.isLoading }
    private var canPan: Bool { canUseImage && model.zoom > 1 && !model.isOverview }

    private func controlLabel(_ title: String, icon: String) -> some View {
        ManualMenuLabel(title: title, icon: icon)
    }

    private func command(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlLabel(title, icon: icon) }
            .buttonStyle(ControlStyle(transparent: overlayControls))
    }

    private var settings: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        MonoBrandMark(size: 64)
                        Text("Make it yours").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    Text("Which hand do you use?").font(.title2.bold())
                    Picker("Hand used to hold your phone", selection: $preferredHand) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                    }
                    .pickerStyle(.segmented)
                    Button("Set up thumb reach again") {
                        calibrateAfterSettings = true
                        showSettings = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .buttonStyle(ControlStyle())
                    .accessibilityIdentifier("reopenReachSetup")
                    if activeProfile != nil {
                        Text("Your fitted layout is saved. Rotating the phone or using accessibility text sizes uses the manual layout. Changing hand, width, or height replaces the fitted layout.")
                            .font(.body)
                        Button("Use manual layout") { useManualLayout(); startManualSetup(); showSettings = false }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .buttonStyle(ControlStyle())
                    }
                    Text("Thumb reach").font(.title2.bold())
                    Text("Choose a comfortable width and height. Keep the same relaxed grip.")
                    Picker("Panel width", selection: $controlWidth) {
                        Text("Compact").tag(288.0)
                        Text("Wide").tag(336.0)
                    }
                    .pickerStyle(.segmented)
                    Picker("Panel position", selection: $controlLift) {
                        Text("Low").tag(0.0)
                        Text("Middle").tag(40.0)
                        Text("High").tag(80.0)
                    }
                    .pickerStyle(.segmented)
                    Text("Height applies in portrait. In landscape, controls sit on your chosen side.")
                        .font(.footnote).foregroundStyle(MonoTheme.text)
                    Toggle("Light image background", isOn: $lightCanvas)
                        .font(.title3)
                    Text("Tilt panning").font(.title2.bold())
                    Text("Zoom in and choose Tilt. The controls become a translucent dot. Tilt gently to move; tap the dot to stop and show the controls. Start Tilt again to set a new resting position.")
                    Picker("Tilt sensitivity", selection: $tiltSensitivity) {
                        Text("Gentle").tag(0.6)
                        Text("Normal").tag(1.0)
                        Text("Fast").tag(1.5)
                    }
                    .pickerStyle(.segmented)
                    DisclosureGroup("Photo controls and tilt help") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Zoom in for detail. Drag with one finger or use the arrows to move through your photo.")
                            Text("Overview shows the whole photo. Return restores your previous view.")
                            Text("In a fitted layout, More shows the next set of controls.")
                            Text("While Tilt is on, double tap the photo for maximum zoom. Double tap again at maximum zoom to fit the whole photo.")
                            Text("Sweep your thumb upward to zoom in, or downward to zoom out. Curved sweeps work with either hand. Tilt stays on at the full-image size.")
                            Text("Tilt pauses while you sweep and resumes from your new grip when you lift your thumb. It stops when you tap the dot, open Settings, rotate the phone, show Overview, or leave the app.")
                            Text("Zoom enlarges existing detail; it cannot add missing detail.")
                        }
                        .font(.body)
                        .padding(.top, 8)
                    }
                    Button("Reset view") { model.reset() }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .buttonStyle(ControlStyle())
                        .disabled(model.image == nil)
                }
                .padding(24)
            }
            Button("Done") { showSettings = false }
                .frame(maxWidth: .infinity, minHeight: 56)
                .buttonStyle(ControlStyle(primary: true))
                .padding(16)
        }
        .foregroundStyle(MonoTheme.text)
        .background(MonoBackground())
        .tint(MonoTheme.accent)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }
}

/// Purpose comes before reach setup and is acknowledged once on this device.
struct MonoPurposeView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MonoBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        Text("MonoView")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("See more. Reach comfortably.")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Made for people with low vision and for anyone who uses a phone with one hand.")
                        Text("Seeing detail and reaching controls shouldn’t require an uncomfortable grip. MonoView brings photo magnification and controls that fit your thumb into one place.")
                        Button(action: onContinue) {
                            Text("Continue")
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .buttonStyle(ControlStyle(primary: true))
                        .frame(maxWidth: 260)
                            .accessibilityIdentifier("purposeContinue")
                    }
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                }
            }
        }
        .foregroundStyle(MonoTheme.text)
        .preferredColorScheme(.dark)
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

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(white: 0.07).opacity(reduceTransparency ? 1 : contrast == .increased ? 0.85 : 0.62))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(contrast == .increased ? 1 : 0.3), lineWidth: contrast == .increased ? 2 : 1))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

/// A single, generously sized stop target keeps the image visible during tilt panning.
struct TiltDotButton: View {
    let zoom: CGFloat
    let onStop: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: onStop) {
            ZStack {
                Circle().fill(Color.black.opacity(reduceTransparency ? 1 : 0.28))
                Circle().stroke(Color.black.opacity(0.75), lineWidth: 3)
                Circle().stroke(Color.white.opacity(contrast == .increased ? 1 : 0.75), lineWidth: 1.5)
                Circle().fill(Color.white.opacity(reduceTransparency ? 1 : 0.65))
                    .frame(width: 28, height: 28)
            }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop tilt and show controls")
        .accessibilityValue("Tilt panning is on. Zoom \(Int(zoom * 100)) percent")
        .accessibilityHint("Double tap to stop movement and restore the control panel.")
        .accessibilityIdentifier("stopTiltDot")
    }
}

struct ManualMenuLabel: View {
    let title: String
    let icon: String
    @Environment(\.manualMenuAppearance) private var manual

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(manual ? .system(size: 27, weight: .medium) : .title2)
                .frame(minHeight: 32)
                .accessibilityHidden(true)
            Text(title).font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .contentShape(Rectangle())
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
