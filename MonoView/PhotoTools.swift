import SwiftUI

/// Non-destructive display adjustments. The imported bitmap is never rewritten.
struct PhotoAppearance: ViewModifier {
    var original = false
    @AppStorage("photoBrightness") private var brightness = 0.0
    @AppStorage("photoContrast") private var contrast = 1.0
    @AppStorage("photoGrayscale") private var grayscale = false
    @AppStorage("photoInverted") private var inverted = false

    func body(content: Content) -> some View {
        let adjusted = content
            .saturation(!original && grayscale ? 0 : 1)
            .contrast(original ? 1 : min(2.5, max(0.5, contrast)))
            .brightness(original ? 0 : min(0.4, max(-0.4, brightness)))
        if inverted && !original { adjusted.colorInvert() } else { adjusted }
    }
}

nonisolated enum ReadingRulerGeometry {
    static func band(height: CGFloat, requestedHeight: Double, position: Double) -> CGRect {
        guard height.isFinite, height > 0 else { return .zero }
        let requested = requestedHeight.isFinite ? CGFloat(requestedHeight) : 80
        let bandHeight = min(height, max(24, requested))
        let fraction = position.isFinite ? min(1, max(0, position)) : 0.45
        return CGRect(x: 0, y: (height - bandHeight) * fraction, width: 0, height: bandHeight)
    }
    static func position(center: CGFloat, height: CGFloat, bandHeight: CGFloat) -> Double {
        guard center.isFinite, height.isFinite, bandHeight.isFinite, height > bandHeight else { return 0.5 }
        return Double(min(1, max(0, (center - bandHeight / 2) / (height - bandHeight))))
    }
}

/// Only the grip receives touch; the shaded areas preserve photo gestures underneath.
struct ReadingRuler: View {
    let size: CGSize
    let hand: String
    var interactive = true
    var showShade = true
    @AppStorage("readingRulerPosition") private var position = 0.45
    @AppStorage("readingRulerHeight") private var height = 80.0
    @AppStorage("readingRulerDim") private var dim = 0.6
    @State private var startY: CGFloat?

    var body: some View {
        let band = ReadingRulerGeometry.band(height: size.height, requestedHeight: height, position: position)
        ZStack(alignment: .topLeading) {
            if showShade {
                Group {
                    Rectangle().fill(.black.opacity(min(0.85, max(0.2, dim))))
                        .frame(width: size.width, height: band.minY)
                    Rectangle().fill(.black.opacity(min(0.85, max(0.2, dim))))
                        .frame(width: size.width, height: max(0, size.height - band.maxY)).offset(y: band.maxY)
                    Rectangle().fill(.yellow).frame(width: size.width, height: 2).offset(y: band.minY)
                    Rectangle().fill(.yellow).frame(width: size.width, height: 2).offset(y: max(0, band.maxY - 2))
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            if interactive {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 44, height: 44).background(.yellow, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if startY == nil { startY = band.midY }
                            position = ReadingRulerGeometry.position(center: (startY ?? band.midY) + value.translation.height,
                                                                    height: size.height, bandHeight: band.height)
                        }.onEnded { _ in startY = nil })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Move reading ruler")
                    .accessibilityValue("\(Int(position * 100)) percent down")
                    .accessibilityHint("Drag up or down, or adjust with VoiceOver. Position can also be changed in Photo tools.")
                    .accessibilityIdentifier("readingRulerHandle")
                    .accessibilityAdjustableAction { direction in
                        position = min(1, max(0, position + (direction == .increment ? -0.1 : 0.1)))
                    }
                    .offset(x: hand == "left" ? 12 : max(0, size.width - 56), y: min(max(0, size.height - 44), max(0, band.midY - 22)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onChange(of: size) { _, _ in startY = nil }
    }
}

struct PhotoToolsView: View {
    let image: UIImage?
    let hand: String
    @Binding var showOriginal: Bool
    @State private var showReader = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("photoBrightness") private var brightness = 0.0
    @AppStorage("photoContrast") private var contrast = 1.0
    @AppStorage("photoGrayscale") private var grayscale = false
    @AppStorage("photoInverted") private var inverted = false
    @AppStorage("readingRulerEnabled") private var ruler = false
    @AppStorage("readingRulerPosition") private var rulerPosition = 0.45
    @AppStorage("readingRulerHeight") private var rulerHeight = 80.0
    @AppStorage("readingRulerDim") private var dim = 0.6

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Photo tools").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                preview
            }.padding(.horizontal, 24).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Make details easier to see. Your original photo stays unchanged.")
                    Button { showReader = true } label: {
                        Label("Read text", systemImage: "text.viewfinder").frame(maxWidth: .infinity, minHeight: 56)
                    }.buttonStyle(ControlStyle(primary: true)).disabled(image == nil)
                        .accessibilityIdentifier("readPhotoText")
                    Text("Large text and reading aloud, processed on this device.").font(.caption)
                    Toggle("Show original", isOn: $showOriginal).tint(.green).accessibilityIdentifier("showOriginal")
                    Text("Temporarily bypasses the filters for comparison.").font(.caption)
                    Text("Image filters").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Toggle("Black and white", isOn: $grayscale).tint(.green).accessibilityIdentifier("photoGrayscale")
                        .disabled(showOriginal)
                    Toggle("Invert colors", isOn: $inverted).tint(.green).accessibilityIdentifier("photoInverted")
                        .disabled(showOriginal)
                    Text("Brightness").font(.headline)
                    Slider(value: $brightness, in: -0.4...0.4, step: 0.05) { Text("Brightness") }
                        .accessibilityIdentifier("photoBrightness").disabled(showOriginal)
                        .accessibilityValue("\(Int(brightness * 100))")
                    Text("Contrast").font(.headline)
                    Slider(value: $contrast, in: 0.5...2.5, step: 0.1) { Text("Contrast") }
                        .accessibilityIdentifier("photoContrast").disabled(showOriginal)
                        .accessibilityValue("\(Int(contrast * 100)) percent")
                    Button("Reset filters") { resetFilters() }.frame(minHeight: 44)
                        .accessibilityIdentifier("resetPhotoFilters")
                    Toggle("Reading ruler", isOn: $ruler).tint(.green).accessibilityIdentifier("readingRulerToggle")
                    Text("Keep one strip clear and dim the rest. Drag the yellow grip on the photo, or use these controls.").font(.caption)
                    if ruler {
                        Text("Ruler position").font(.headline)
                        Slider(value: $rulerPosition, in: 0...1, step: 0.01) { Text("Ruler position") }
                            .accessibilityIdentifier("readingRulerPosition")
                            .accessibilityValue("\(Int(rulerPosition * 100)) percent down")
                        Text("Reading strip height").font(.headline)
                        Picker("Reading strip height", selection: $rulerHeight) {
                            Text("Narrow").tag(44.0); Text("Medium").tag(80.0); Text("Wide").tag(120.0)
                        }.pickerStyle(.segmented)
                        Text("Surrounding shade").font(.headline)
                        Slider(value: $dim, in: 0.2...0.85, step: 0.05) { Text("Surrounding shade") }
                            .accessibilityValue("\(Int(dim * 100)) percent")
                    }
                    Text("Your choices apply to the next photos too. Overview temporarily hides the ruler so you can see the whole photo.").font(.caption)
                    Button("Reset photo tools") {
                        resetFilters(); ruler = false; rulerPosition = 0.45; rulerHeight = 80; dim = 0.6
                    }.frame(maxWidth: .infinity, minHeight: 48).buttonStyle(ControlStyle())
                        .accessibilityIdentifier("resetPhotoTools")
                }.padding(24)
            }
            Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity, minHeight: 56) }
                .buttonStyle(ControlStyle(primary: true)).padding(16).accessibilityIdentifier("photoToolsDone")
        }
        .foregroundStyle(.white).background(MonoBackground()).tint(.white)
        .preferredColorScheme(.dark).presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showReader) {
            if let image { PhotoReaderView(image: image) }
        }
    }
    @ViewBuilder private var preview: some View {
                    if let image {
                        GeometryReader { area in
                            Image(uiImage: image).resizable().scaledToFit()
                                .modifier(PhotoAppearance(original: showOriginal))
                                .frame(width: area.size.width, height: area.size.height)
                                .background(.black)
                                .overlay {
                                    if ruler { ReadingRuler(size: area.size, hand: hand, interactive: false) }
                                }
                        }.frame(height: typeSize.isAccessibilitySize ? 80 : 140).clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Photo tools preview")
                            .accessibilityIdentifier("photoToolsPreview")
                    }
    }
    private func resetFilters() {
        showOriginal = false; brightness = 0; contrast = 1; grayscale = false; inverted = false
    }
}
