import UIKit

/// A utility function to create SF Symbol images for CarPlay templates.
func symbolImage(named name: String) -> UIImage? {
    // The UIImage(systemName:) initializer is available on iOS 13+.
    // CarPlay requires iOS 14+, so this check is safe.
    return UIImage(systemName: name)
}
