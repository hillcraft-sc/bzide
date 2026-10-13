import Contacts
import ContactsUI
import UIKit

/// Shows Apple's contact picker so the user can pick their own card for a
/// profile picture. Only the picked contact's photo reaches the app, so no
/// Contacts permission is needed. Contacts without a photo can't be picked.
///
/// Presented with UIKit: the contact picker misbehaves inside a SwiftUI sheet.
@MainActor
final class ContactPhotoPicker: NSObject, CNContactPickerDelegate {
    private let completion: (Data?) -> Void
    /// Kept alive while the picker is up; the picker holds its delegate weakly.
    private static var current: ContactPhotoPicker?

    private init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    /// Calls `completion` with the photo (`nil` if cancelled or it has none).
    static func present(completion: @escaping (Data?) -> Void) {
        let picker = CNContactPickerViewController()
        picker.predicateForEnablingContact = NSPredicate(format: "imageDataAvailable == true")
        let handler = ContactPhotoPicker(completion: completion)
        current = handler
        picker.delegate = handler
        guard let presenter = topViewController() else {
            current = nil
            completion(nil)
            return
        }
        presenter.present(picker, animated: true)
    }

    // The picker may call its delegate off the main actor; the photo is read
    // there and handed over.
    nonisolated func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let full = contact.isKeyAvailable(CNContactImageDataKey) ? contact.imageData : nil
        let thumbnail = contact.isKeyAvailable(CNContactThumbnailImageDataKey) ? contact.thumbnailImageData : nil
        let photo = full ?? thumbnail
        Task { @MainActor in Self.finish(with: photo) }
    }

    nonisolated func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        Task { @MainActor in Self.finish(with: nil) }
    }

    private static func finish(with photo: Data?) {
        current?.completion(photo)
        current = nil
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Picked pictures are cropped to a centered square and shrunk before they're
/// saved: a profile picture never needs more.
enum ProfilePictureSizer {
    static let side: CGFloat = 480

    /// JPEG data, or `nil` if the image can't be read.
    static func profileJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = side / min(image.size.width, image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}
