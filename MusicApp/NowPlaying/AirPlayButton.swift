import AVKit
import SwiftUI

/// The system's audio output picker (AirPlay speakers and TVs, Bluetooth,
/// this iPhone), drawn in the theme's accent like the buttons beside it.
struct AirPlayButton: UIViewRepresentable {
    @Environment(\.themeAccent) private var accent

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        // Audio only: list speakers before TVs.
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        let color = accent.map(UIColor.init) ?? .tintColor
        picker.tintColor = color
        picker.activeTintColor = color
    }
}
