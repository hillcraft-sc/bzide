import SwiftUI

// Apple's minimum tap target is 44 by 44 points. An icon-only button's tap
// area is only as big as its icon, and a frame put around a button doesn't
// widen it: the room has to be inside the button's label. These give a
// control that room without changing how it looks.

/// An icon-only label with a 44-point tap area around the icon. Like
/// `.iconOnly`, VoiceOver still reads the label's title.
struct TapTargetIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.iconOnly)
            .tapTarget()
    }
}

extension LabelStyle where Self == TapTargetIconLabelStyle {
    /// `.iconOnly`, with a 44-point tap area.
    static var tapTarget: TapTargetIconLabelStyle { TapTargetIconLabelStyle() }
}

extension View {
    /// At least 44 by 44 points to tap, centered on the content; use inside a
    /// button's or menu's label (or on a link's content).
    func tapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
