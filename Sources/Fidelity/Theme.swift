import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that resolves itself against the current appearance, so the
    /// whole interface flips between light and dark with no state threading.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// iTunes 10 (2010) colors in light, Apple's Human Interface Guidelines dark
/// palette in dark — same retro shapes and gloss, darker chrome.
enum Theme {
    // Brushed-metal toolbar
    static let toolbarTop = Color.dynamic(0xEAEAEA, 0x3C3C3E)
    static let toolbarBottom = Color.dynamic(0xC8C8C8, 0x2E2E30)
    static let toolbarBorder = Color.dynamic(0x8B8B8B, 0x1A1A1C)

    // The recessed LCD display — pale green-grey by day, backlit by night
    static let lcdTop = Color.dynamic(0xF4F5E8, 0x2B2F27)
    static let lcdBottom = Color.dynamic(0xDCDFC8, 0x1C1F19)
    static let lcdBorder = Color.dynamic(0x969884, 0x4B5044)
    static let lcdText = Color.dynamic(0x3E4038, 0xDCE7D2)
    static let lcdSubText = Color.dynamic(0x6D6F62, 0x98A28C)
    static let lcdProgressTrack = Color.dynamic(0xB9BCA4, 0x454A3E)
    static let lcdProgressFill = Color.dynamic(0x6E7160, 0x9FB08D)
    static let lcdKnob = Color.dynamic(0x4A4C40, 0xC3D1B6)

    // Source list (sidebar)
    static let sidebarBG = Color.dynamic(0xE1E6ED, 0x252527)
    static let sidebarHeaderText = Color.dynamic(0x6E7A8A, 0x8E8E93)
    static let sidebarText = Color.dynamic(0x333B45, 0xE8E8EA)
    static let sidebarIcon = Color.dynamic(0x6B7686, 0x8E8E93)
    static let sidebarSelTop = Color.dynamic(0x83A9D6, 0x0A84FF)
    static let sidebarSelBottom = Color.dynamic(0x5C82B4, 0x0060D8)
    static let sidebarBorder = Color.dynamic(0xB2B8C1, 0x38383A)

    // Content surfaces
    static let contentBG = Color.dynamic(0xFFFFFF, 0x1E1E1E)
    static let rowAlt = Color.dynamic(0xF0F5FA, 0x252528)
    static let listText = Color.dynamic(0x1E1E1E, 0xFFFFFF)
    static let secondaryText = Color.dynamic(0x808080, 0x98989D)
    static let tertiaryText = Color.dynamic(0x999999, 0x6E6E73)
    static let rowSelTop = Color.dynamic(0x4B84D0, 0x0A84FF)
    static let rowSelBottom = Color.dynamic(0x2F64AE, 0x0057C8)
    static let separator = Color.dynamic(0xD0D0D0, 0x3A3A3C)

    // Column headers
    static let headerTop = Color.dynamic(0xFBFBFB, 0x333335)
    static let headerBottom = Color.dynamic(0xE3E3E3, 0x2A2A2C)
    static let headerActiveTop = Color.dynamic(0xC9DCF0, 0x3E4A5C)
    static let headerActiveBottom = Color.dynamic(0xA8C5E4, 0x33404F)
    static let headerBorder = Color.dynamic(0xC5C5C5, 0x3A3A3C)
    static let headerText = Color.dynamic(0x3A3A3A, 0xE5E5E7)
    static let headerSortArrow = Color.dynamic(0x555555, 0xC7C7CC)

    // Bottom status bar
    static let statusTop = Color.dynamic(0xEFEFEF, 0x2E2E30)
    static let statusBottom = Color.dynamic(0xD2D2D2, 0x252527)
    static let statusBorder = Color.dynamic(0x9E9E9E, 0x1A1A1C)
    static let statusText = Color.dynamic(0x6A6A6A, 0x98989D)

    // Controls
    static let accent = Color.dynamic(0x2E64B0, 0x0A84FF)
    static let iconTint = Color.dynamic(0x7A7A7A, 0x98989D)
    static let fieldBG = Color.dynamic(0xFFFFFF, 0x1C1C1E)
    static let fieldBorder = Color.dynamic(0xA0A0A0, 0x48484A)
    static let sliderTint = Color.dynamic(0x8A8A8A, 0x8E8E93)
    static let nowPlayingIcon = Color.dynamic(0x3572C6, 0x0A84FF)

    // Artwork wells
    static let artPlaceholder = Color.dynamic(0xE8EAED, 0x2C2C2E)
    static let artGlyph = Color.dynamic(0xADB4BC, 0x5A5A5E)
    static let artBorder = Color.dynamic(0xC8C8C8, 0x3A3A3C)

    // Empty states
    static let emptyGlyph = Color.dynamic(0xAAB2BC, 0x4A4A4E)
    static let emptyTitle = Color.dynamic(0x4A4A4A, 0xE5E5E7)

    // Gradients — computed so they resolve per render, in either appearance.
    static var toolbarGradient: LinearGradient {
        LinearGradient(colors: [toolbarTop, toolbarBottom], startPoint: .top, endPoint: .bottom)
    }
    static var lcdGradient: LinearGradient {
        LinearGradient(colors: [lcdTop, lcdBottom], startPoint: .top, endPoint: .bottom)
    }
    static var sidebarSelGradient: LinearGradient {
        LinearGradient(colors: [sidebarSelTop, sidebarSelBottom], startPoint: .top, endPoint: .bottom)
    }
    static var rowSelGradient: LinearGradient {
        LinearGradient(colors: [rowSelTop, rowSelBottom], startPoint: .top, endPoint: .bottom)
    }
    static var headerGradient: LinearGradient {
        LinearGradient(colors: [headerTop, headerBottom], startPoint: .top, endPoint: .bottom)
    }
    static var headerActiveGradient: LinearGradient {
        LinearGradient(colors: [headerActiveTop, headerActiveBottom], startPoint: .top, endPoint: .bottom)
    }
    static var statusGradient: LinearGradient {
        LinearGradient(colors: [statusTop, statusBottom], startPoint: .top, endPoint: .bottom)
    }

    // iPod body — silver by day, the black anodized classic by night
    static let ipodBodyTop = Color.dynamic(0xEBECEE, 0x3A3A3C)
    static let ipodBodyBottom = Color.dynamic(0xD0D2D4, 0x232325)
    static let ipodWheelTop = Color.dynamic(0xFBFCFD, 0x303032)
    static let ipodWheelBottom = Color.dynamic(0xEDEEF0, 0x252527)
    static let ipodWheelBorder = Color.dynamic(0xD2D4D6, 0x171719)
    static let ipodWheelLabel = Color.dynamic(0xA6A9AC, 0x7A7A80)
    static let ipodCenterTop = Color.dynamic(0xD9DBDD, 0x3E3E42)
    static let ipodCenterBottom = Color.dynamic(0xC5C7C9, 0x2E2E32)
    static let ipodCenterBorder = Color.dynamic(0xB2B4B6, 0x171719)
    static let ipodScreenBezel = Color.dynamic(0x191A1B, 0x0E0E0F)
    static let ipodScreenEdge = Color.dynamic(0x9DA0A3, 0x4A4A4E)

    static var ipodBodyGradient: LinearGradient {
        LinearGradient(colors: [ipodBodyTop, ipodBodyBottom], startPoint: .top, endPoint: .bottom)
    }
    static var ipodWheelGradient: LinearGradient {
        LinearGradient(colors: [ipodWheelTop, ipodWheelBottom], startPoint: .top, endPoint: .bottom)
    }
    static var ipodCenterGradient: LinearGradient {
        LinearGradient(colors: [ipodCenterTop, ipodCenterBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Round, glossy iTunes-style transport button.
struct TransportButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    private static let faceTop = Color.dynamic(0xFDFDFD, 0x5A5A5E)
    private static let faceBottom = Color.dynamic(0xC6C6C6, 0x39393D)
    private static let edge = Color.dynamic(0x909090, 0x1F1F22)
    private static let glyph = Color.dynamic(0x4A4A4A, 0xDCDCE0)

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Self.faceTop, Self.faceBottom],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Self.edge, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                Image(systemName: systemName)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(Self.glyph)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}
