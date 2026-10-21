import SwiftUI

/// The BreaKing logo: the crown over the name (with the plate's line under it on the sequencer), or
/// crown and name in one line on Face 1's bottom bar. Engraved into the metal: a dark name gets a lit
/// lower edge, a light one a shadow.
struct BrandLogo: View {
    var dark = true
    var tagline: String? = nil
    var inline = false
    var scale: CGFloat = 1

    static let name = "BreaKing"

    var body: some View {
        let ink = dark ? Color(white: 0.08) : Color(white: 0.92)
        let edge = dark ? Color.white.opacity(0.45) : Color.black.opacity(0.7)
        Group {
            if inline {
                HStack(spacing: 8 * scale) {
                    Image(systemName: "crown.fill").font(.system(size: 17 * scale))
                    Text(Self.name).font(.system(size: 26 * scale, weight: .semibold).width(.expanded))
                }
            } else {
                VStack(spacing: 2 * scale) {
                    Image(systemName: "crown.fill").font(.system(size: 21 * scale))
                    Text(Self.name).font(.system(size: 33 * scale, weight: .semibold).width(.expanded))
                    if let tagline {
                        Text(tagline).font(.system(size: 11 * scale, weight: .medium)).kerning(4.5 * scale).padding(.top, 2 * scale)
                    }
                }
            }
        }
        .foregroundColor(ink)
        .shadow(color: edge, radius: 0, x: 0, y: 1 * scale)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.name)
        .accessibilityIdentifier("brandLogo")
    }
}
