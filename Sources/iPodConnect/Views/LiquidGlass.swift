import SwiftUI
import AppKit

/// Real Liquid Glass, via AppKit's `NSGlassEffectView` (macOS 26).
///
/// SwiftUI's `glassEffect` modifier isn't in the Command Line Tools SDK, but
/// the underlying AppKit view is — so this wraps the genuine system material
/// rather than approximating it with gradients. The system handles the
/// refraction, specular edges and adaptive tinting, and it matches the
/// glass used elsewhere in macOS 26.
@available(macOS 26.0, *)
struct GlassEffectView: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: NSColor?
    var isClear: Bool

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        view.style = isClear ? .clear : .regular
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        view.style = isClear ? .clear : .regular
    }
}

/// Groups nearby glass elements so the system can blend them as one piece of
/// material — the effect that makes adjacent controls merge as they approach.
@available(macOS 26.0, *)
struct GlassContainer<Content: View>: NSViewRepresentable {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSGlassEffectContainerView {
        let container = NSGlassEffectContainerView()
        container.spacing = spacing
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.contentView = hosting
        return container
    }

    func updateNSView(_ container: NSGlassEffectContainerView, context: Context) {
        container.spacing = spacing
        (container.contentView as? NSHostingView<Content>)?.rootView = content
    }
}

extension View {
    /// Lays real Liquid Glass behind this view, falling back to a material on
    /// older systems.
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat, tint: NSColor? = nil, clear: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            background {
                GlassEffectView(cornerRadius: cornerRadius, tint: tint, isClear: clear)
            }
        } else {
            background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    }
            }
        }
    }
}
