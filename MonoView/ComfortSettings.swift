import SwiftUI
import AudioToolbox

/// Shared by the first-run guide and Settings. All changes are local preferences.
struct ComfortSettings: View {
    var appearanceOnly = false
    @AppStorage("largeControls") private var large = false
    @AppStorage("showControlLabels") private var labels = false
    @AppStorage("panelOpacity") private var opacity = 0.62
    @AppStorage("opaqueControls") private var opaque = false
    @AppStorage("lockControls") private var locked = false
    @AppStorage("zoomSpeed") private var speed = 1.0
    @AppStorage("doubleTapZoom") private var tapZoom = 20.0
    @AppStorage("hapticFeedback") private var haptics = true
    @AppStorage("soundFeedback") private var sound = false
    @AppStorage("keepScreenAwake") private var awake = false
    @AppStorage("moveHoldDuration") private var hold = 0.45
    @AppStorage("moveTolerance") private var tolerance = 20.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Larger controls", isOn: $large).tint(.green).accessibilityIdentifier("largerControls")
            Toggle("Show button labels", isOn: $labels).tint(.green).accessibilityIdentifier("showControlLabels")
            Toggle("Opaque controls", isOn: $opaque).tint(.green)
            Text("Panel visibility").font(.headline)
            Slider(value: $opacity, in: 0.35...0.95, step: 0.05) { Text("Panel visibility") }
                .disabled(opaque).accessibilityValue("\(Int(opacity * 100)) percent")
            Text("Preview — try the buttons").font(.caption)
            ComfortPreview()
            if !appearanceOnly {
                Toggle("Lock controls position", isOn: $locked).tint(.green).accessibilityIdentifier("lockControls")
                Text("Unlock to move the panel or floating dot.").font(.caption)
                DisclosureGroup("Zoom and touch") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Zoom speed").font(.headline)
                        Picker("Zoom speed", selection: $speed) {
                            Text("Slow").tag(0.6); Text("Normal").tag(1.0); Text("Fast").tag(1.5)
                        }.pickerStyle(.segmented)
                        Text("Double-tap zoom").font(.headline)
                        Picker("Double-tap zoom", selection: $tapZoom) {
                            Text("4×").tag(4.0); Text("8×").tag(8.0); Text("20×").tag(20.0)
                        }.pickerStyle(.segmented)
                        Text("Applies in Tilt mode. Double tap again to fit the photo.").font(.caption)
                        Text("Hold before moving controls").font(.headline)
                        Picker("Hold before moving controls", selection: $hold) {
                            Text("Short").tag(0.45); Text("Medium").tag(0.8); Text("Long").tag(1.2)
                        }.pickerStyle(.segmented)
                        Text("Finger movement while holding").font(.headline)
                        Picker("Finger movement while holding", selection: $tolerance) {
                            Text("Standard").tag(20.0); Text("More forgiving").tag(40.0)
                        }.pickerStyle(.segmented)
                        Text("These options affect MonoView only. iPhone Touch Accommodations still apply.").font(.caption)
                    }.padding(.vertical, 12)
                }
                DisclosureGroup("Feedback and screen") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Haptic feedback", isOn: $haptics).tint(.green)
                        Toggle("Sound feedback", isOn: $sound).tint(.green)
                        Toggle("Keep screen awake", isOn: $awake).tint(.green)
                        Text("Keeps the screen on only while a photo is open in MonoView. Uses more battery.").font(.caption)
                    }.padding(.vertical, 12)
                }
            }
            Button(appearanceOnly ? "Reset appearance" : "Reset comfort settings") {
                large = false; labels = false; opacity = 0.62; opaque = false
                if !appearanceOnly {
                    locked = false; speed = 1; tapZoom = 20; haptics = true; sound = false
                    awake = false; hold = 0.45; tolerance = 20
                }
            }.frame(minHeight: 44).accessibilityIdentifier("resetComfort")
        }
    }
}

private struct ComfortPreview: View {
    @State private var zoom = 1.0
    @AppStorage("zoomSpeed") private var speed = 1.0
    var body: some View {
        VStack(spacing: 8) {
            Text("Zoom \(zoom.formatted(.number.precision(.fractionLength(1))))×").monospacedDigit()
            HStack {
                Button { zoom = max(1, zoom / pow(1.5, speed)); ComfortFeedback.play() } label: {
                    ManualMenuLabel(title: "Zoom out", icon: "minus.magnifyingglass")
                }
                Button { zoom = min(20, zoom * pow(1.5, speed)); ComfortFeedback.play() } label: {
                    ManualMenuLabel(title: "Zoom in", icon: "plus.magnifyingglass")
                }
            }.buttonStyle(ControlStyle())
        }.padding(12).background(ManualMenuSurface())
            .environment(\.manualMenuAppearance, true)
            .accessibilityIdentifier("comfortPreview")
    }
}

@MainActor enum ComfortFeedback {
    static func play(boundary: Bool = false) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "hapticFeedback") == nil || defaults.bool(forKey: "hapticFeedback") {
            UIImpactFeedbackGenerator(style: boundary ? .medium : .light).impactOccurred()
        }
        if defaults.bool(forKey: "soundFeedback") { AudioServicesPlaySystemSound(1104) }
    }
}
