// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - Realistic material parts, stage 1: one knob and one pad (Tyrone, Oct 27)
//
// Built by tools/faceplate_art/materials/build_materials.py from base-colour, normal and roughness
// maps. Every face shares the knob's and the pad's shape, size and touch area; a face only changes
// their materials. Each part is separate pictures stacked:
//
//   knob: shadow on the plate (slides away from the light) · body lit from the fixed light, cross-
//         faded toward the same body lit from left / right / up / down as the light swings · the
//         spun cap's sheen, turned with the light (never with the knob) · the pointer, drawn live
//         from the parameter by KnobControl, with KnobControl's own drag, double tap and VoiceOver
//   pad:  shadow in the well · rubber lit the same way · PadView on top, so the hit goes to the
//         engine on touch-down exactly like Face 1's pads, and its press moves the rubber down
//
// Nothing here renders on the device: the GPU only blends a few cached pictures, and only redraws
// when the light really moves or a pad is pressed. With the light fixed, a part is exactly its
// fixed-light picture. The printing (labels, dial dots) stays in the plate, sharp, under it all.

enum MatGeometry {
    // in the v2 renders' pixels (tools/faceplate_art/face1/v2), the same for every face
    static let knobCenter = CGPoint(x: 768, y: 142)
    static let knobR: CGFloat = 40
    static let knobBox: CGFloat = 2.7
    static let capOffset: CGFloat = -0.30
    static let capR: CGFloat = 0.78
    static let pad: [Double] = [101, 636, 296, 790]
    static let padMargin: CGFloat = 14
    static let padCorner: CGFloat = 13
    static let knobCrop: [Double] = [700, 78, 836, 216]
    static let padCrop: [Double] = [84, 622, 312, 806]
    // the light (build_materials.L0 and SWING)
    static let light = SIMD3<Double>(-0.30, -0.55, 0.78)
    static let swing = 0.6

    static func lightVector(_ t: CGVector) -> SIMD3<Double> {
        let l = light + SIMD3(swing * Double(t.dx), swing * Double(t.dy), 0)
        return l / (l * l).sum().squareRoot()
    }

    /// The sheen's turn (radians), its strength, and how far a shadow slides (in units of `k`).
    static func sheen(_ t: CGVector) -> (turn: Double, strength: Double) {
        let l = lightVector(t), l0 = lightVector(.zero)
        let turn = atan2(l.y, l.x) - atan2(l0.y, l0.x)
        let strength = min(1, max(0.35, (l.x * l.x + l.y * l.y).squareRoot() / (l0.x * l0.x + l0.y * l0.y).squareRoot()))
        return (turn, strength)
    }

    static func shadowShift(_ t: CGVector, _ k: CGFloat) -> CGSize {
        let l = lightVector(t), l0 = lightVector(.zero)
        return CGSize(width: -CGFloat(l.x / l.z - l0.x / l0.z) * k, height: -CGFloat(l.y / l.z - l0.y / l0.z) * k)
    }
}

/// One material lit five ways, cross-faded by where the light has swung.
struct MatLit: View {
    let name: String
    let tilt: CGVector

    var body: some View {
        ZStack {
            layer("c", 1)
            layer("l", -tilt.dx)
            layer("r", tilt.dx)
            layer("u", -tilt.dy)
            layer("d", tilt.dy)
        }
    }

    private func layer(_ key: String, _ amount: CGFloat) -> some View {
        Image("\(name)_\(key)").resizable().interpolation(.high).opacity(Double(max(0, min(1, amount))))
    }
}

/// The PITCH knob (or any knob param) as a material part. `scale` = points per render pixel.
struct MaterialKnob: View {
    @ObservedObject var controller: KnockController
    @ObservedObject private var light = MaterialLight.shared
    let param: KParam
    let face: String
    let scale: CGFloat

    var body: some View {
        let g = MatGeometry.self
        let side = g.knobBox * g.knobR * scale
        let tilt = light.tilt
        let sheen = g.sheen(tilt)
        let shift = g.shadowShift(tilt, 3 * scale)
        // the pointer turns about the cap's centre, measured in render pixels inside this box
        let knob = FaceplateLayout.Knob(x: Double(g.knobBox * g.knobR / 2), y: Double(g.knobBox * g.knobR / 2 + g.capOffset * g.knobR),
                                        r: Double(g.capR * g.knobR), pointerInner: 0.15, pointerOuter: 0.92,
                                        bakedAngle: 0, pointerWidth: 0.115)
        ZStack(alignment: .topLeading) {
            Image("MatKnobShadow").resizable().interpolation(.high)
                .frame(width: side, height: side).offset(shift)
            MatLit(name: "MatKnob_\(face)", tilt: tilt).frame(width: side, height: side)
            Image("MatKnobSheen_\(face)").resizable().interpolation(.high)
                .frame(width: side, height: side)
                .opacity(sheen.strength)
                .rotationEffect(.radians(sheen.turn), anchor: UnitPoint(x: 0.5, y: 0.5 + g.capOffset / g.knobBox))
            KnobControl(controller: controller, param: param, knob: knob, scale: scale)
        }
        .frame(width: side, height: side)
    }
}

/// Pad `pad` as a material part: rubber that goes down under your finger, playing through PadView.
struct MaterialPad: View {
    @ObservedObject var controller: KnockController
    @ObservedObject private var light = MaterialLight.shared
    let pad: Int
    let face: String
    let scale: CGFloat
    @State private var pressed = false

    var body: some View {
        let g = MatGeometry.self
        let w = CGFloat(g.pad[2] - g.pad[0]), h = CGFloat(g.pad[3] - g.pad[1]), m = g.padMargin
        let size = CGSize(width: (w + 2 * m) * scale, height: (h + 2 * m) * scale)
        let tilt = light.tilt
        let shift = g.shadowShift(tilt, 4 * scale)
        ZStack(alignment: .topLeading) {
            Image("MatPadShadow").resizable().interpolation(.high)
                .frame(width: size.width, height: size.height)
                .scaleEffect(pressed ? 0.97 : 1)
                .opacity(pressed ? 0.35 : 1)
                .offset(shift)
            MatLit(name: "MatPad_\(face)", tilt: tilt)
                .frame(width: size.width, height: size.height)
                .scaleEffect(pressed ? 0.975 : 1)
                .offset(y: pressed ? 1.2 * scale : 0)
            PadView(controller: controller, pad: pad, rect: [Double(m), Double(m), Double(m + w), Double(m + h)], scale: scale,
                    cornerRadius: g.padCorner * scale,
                    pressedChanged: { down in
                        // down fast like rubber giving way, back up with a little spring
                        withAnimation(down ? .easeOut(duration: 0.035) : .spring(response: 0.16, dampingFraction: 0.62)) { pressed = down }
                    },
                    openEditor: { _ in })
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - MENU > HELP > TESTING > MATERIAL TEST

/// The knob and pad on each face's own plate (cut from the new renders, their own knob and pad
/// painted out), the MOTION LIGHT switch, and a live readout to judge smoothness on the iPad.
struct MaterialTestView: View {
    @ObservedObject var controller: KnockController
    @ObservedObject private var light = MaterialLight.shared
    @StateObject private var meter = FrameMeter()
    @State private var face: String?
    let palette: BKMenuPalette

    private static let faces = ["platinum", "modern", "vintage", "texture"]
    private let scale: CGFloat = 1.5

    var body: some View {
        let face = self.face ?? controller.faceKey
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Self.faces, id: \.self) { f in
                    Button { self.face = f } label: {
                        Text(f.uppercased()).font(.system(.caption, design: .monospaced).weight(.bold))
                            .padding(.horizontal, 10).frame(minHeight: 40)
                    }
                    .buttonStyle(BKHardwareButtonStyle(accent: palette.accent, selected: f == face))
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { knobDemo(face); padDemo(face) }
                VStack(alignment: .leading, spacing: 16) { knobDemo(face); padDemo(face) }
            }
            Button { light.enabled.toggle() } label: {
                HStack(spacing: 9) {
                    BKMenuLED(isOn: light.enabled, accent: palette.accent)
                    Text("MOTION LIGHT").font(.system(.caption, design: .monospaced).weight(.bold))
                    Spacer(minLength: 8)
                    Text(stateText).font(.system(.caption, design: .monospaced))
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
            }
            .buttonStyle(BKHardwareButtonStyle(accent: palette.accent, selected: light.enabled))
            Text(meter.text)
                .font(.system(size: 12, design: .monospaced)).foregroundColor(BKMenuPalette.wellText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(BKMenuWell())
            Text("Turn the PITCH knob and drum on the pad (it plays pad 1). Tilt the iPad to move the light. Watch the readout while you play: SCREEN should stay at the iPad's rate (60 or 120) with 0 late, here and inside Logic. Your Face 1 is unchanged until you say go.")
                .font(.callout).foregroundColor(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(MaterialOrientationProbe().frame(width: 1, height: 1))
        .onAppear { light.attach(); meter.start() }
        .onDisappear { light.detach(); meter.stop() }
    }

    private var stateText: String {
        switch light.state {
        case .moving: return "MOVES WITH THE iPAD"
        case .off: return "FIXED LIGHT"
        case .reduceMotion: return "FIXED (REDUCE MOTION)"
        case .noSensor: return "FIXED (NO SENSOR)"
        }
    }

    private func knobDemo(_ face: String) -> some View {
        let g = MatGeometry.self
        let crop = FaceplateLayout.rect(g.knobCrop)
        let side = g.knobBox * g.knobR
        return ZStack(alignment: .topLeading) {
            Image("MatDemoKnob_\(face)").resizable().interpolation(.high)
                .frame(width: crop.width * scale, height: crop.height * scale)
            MaterialKnob(controller: controller, param: .pitch, face: face, scale: scale)
                .offset(x: (g.knobCenter.x - side / 2 - crop.minX) * scale, y: (g.knobCenter.y - side / 2 - crop.minY) * scale)
        }
        .frame(width: crop.width * scale, height: crop.height * scale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func padDemo(_ face: String) -> some View {
        let g = MatGeometry.self
        let crop = FaceplateLayout.rect(g.padCrop)
        return ZStack(alignment: .topLeading) {
            Image("MatDemoPad_\(face)").resizable().interpolation(.high)
                .frame(width: crop.width * scale, height: crop.height * scale)
            MaterialPad(controller: controller, pad: 0, face: face, scale: scale)
                .offset(x: (CGFloat(g.pad[0]) - g.padMargin - crop.minX) * scale, y: (CGFloat(g.pad[1]) - g.padMargin - crop.minY) * scale)
        }
        .frame(width: crop.width * scale, height: crop.height * scale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
