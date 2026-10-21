import SwiftUI

extension ReachRegion {
    nonisolated func bounds(in size: CGSize) -> CGRect {
        let points = contours.flatMap { $0 }
        let left = points.map { $0.x * size.width }.min() ?? 0
        let right = points.map { $0.x * size.width }.max() ?? 0
        let top = points.map { $0.y * size.height }.min() ?? 0
        let bottom = points.map { $0.y * size.height }.max() ?? 0
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// The same boundary defines both the visible button and its hit-testing area.
struct ReachRegionShape: Shape {
    let region: ReachRegion
    let canvasSize: CGSize

    func path(in rect: CGRect) -> Path {
        let bounds = region.bounds(in: canvasSize)
        var path = Path()
        for loop in region.contours {
            guard let first = loop.first else { continue }
            path.move(to: CGPoint(x: first.x * canvasSize.width - bounds.minX, y: first.y * canvasSize.height - bounds.minY))
            for point in loop.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * canvasSize.width - bounds.minX, y: point.y * canvasSize.height - bounds.minY))
            }
            path.closeSubpath()
        }
        return path
    }
}

struct ReachTerritoryLabel: View {
    let region: ReachRegion
    let canvasSize: CGSize
    let title: String
    let icon: String
    var primary = false
    var checked = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let bounds = region.bounds(in: canvasSize)
        let shape = ReachRegionShape(region: region, canvasSize: canvasSize)
        ZStack(alignment: .topLeading) {
            // Clear fill retains the full custom hit area without hiding photo detail.
            shape.fill(Color.clear, style: FillStyle(eoFill: true))
            shape.stroke(Color.black.opacity(0.65), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
            shape.stroke(primary ? Color.yellow : Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            VStack(spacing: 2) {
                Image(systemName: checked ? "checkmark.circle.fill" : icon).font(.system(size: 21, weight: .bold))
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(primary ? Color.yellow : Color.white)
            .frame(width: 54, height: 50)
            .background(Color.black.opacity(reduceTransparency ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 8))
            .position(x: region.anchor.x * canvasSize.width - bounds.minX, y: region.anchor.y * canvasSize.height - bounds.minY)
            .accessibilityHidden(true)
        }
        .frame(width: bounds.width, height: bounds.height)
        .contentShape(shape, eoFill: true)
    }
}

struct ReachTerritoryPressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!enabled ? 0.45 : configuration.isPressed ? 0.65 : 1)
    }
}

struct ReachZonePreview: View {
    let profile: ReachProfile
    let canvasSize: CGSize
    let onTry: () -> Void
    let onChangeHand: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array((profile.regions ?? []).enumerated()), id: \.offset) { index, region in
                let bounds = region.bounds(in: canvasSize)
                let isHand = index == (profile.regions?.count ?? 0) - 1
                Button {
                    if index == 0 { onTry() }
                    else if isHand { onChangeHand() }
                } label: {
                    ReachTerritoryLabel(region: region, canvasSize: canvasSize,
                                        title: index == 0 ? "Try" : isHand ? (profile.hand == "left" ? "Left" : "Right") : "\(index + 1)",
                                        icon: index == 0 ? "checkmark" : isHand ? "hand.raised" : "hand.tap", primary: index == 0)
                }
                .buttonStyle(ReachTerritoryPressStyle())
                .contentShape(ReachRegionShape(region: region, canvasSize: canvasSize), eoFill: true)
                .accessibilityLabel(index == 0 ? "Try layout" : isHand ? "Change hand, currently \(profile.hand)" : "Preview touch region \(index + 1)")
                .disabled(index != 0 && !isHand)
                .position(x: bounds.midX, y: bounds.midY)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}
