import SwiftUI

/// Tile → Detail zoom (spec: Motion & focus → Choreography, **[spike]** S2 seam).
///
/// Source ids are `"<shelf>/<item>"` so the same title in two shelves zooms from the right tile.
/// With a nil namespace or Reduce Motion both modifiers do nothing and the system's default push is used.
public extension View {
    /// S2 seam.
    func detailZoomSource(id: String, in namespace: Namespace.ID?) -> some View {
        modifier(DetailZoomSource(id: id, namespace: namespace))
    }

    func detailZoomDestination(id: String, in namespace: Namespace.ID?) -> some View {
        modifier(DetailZoomDestination(id: id, namespace: namespace))
    }
}

private struct DetailZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct DetailZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
