import UIKit

struct ProfileImageManager {
    static var profileImageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile_image.jpg")
    }
    
    static func save(_ image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            let maxDimension: CGFloat = 300.0
            var targetSize = image.size
            let maxSide = max(image.size.width, image.size.height)
            
            if maxSide > maxDimension {
                let scale = maxDimension / maxSide
                targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            }
            
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0 // Ensure physical pixels match our computed targetSize
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            
            let resizedImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            
            if let data = resizedImage.jpegData(compressionQuality: 0.8) {
                try? data.write(to: profileImageURL, options: .atomic)
            }
        }
    }
    
    static func load() -> UIImage? {
        if FileManager.default.fileExists(atPath: profileImageURL.path) {
            return UIImage(contentsOfFile: profileImageURL.path)
        }
        return nil
    }
    
    static func remove() {
        if FileManager.default.fileExists(atPath: profileImageURL.path) {
            try? FileManager.default.removeItem(at: profileImageURL)
        }
    }
}
