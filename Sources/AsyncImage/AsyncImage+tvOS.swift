import SwiftUI
import UIKit

#if os(tvOS)
// Custom AsyncImagePhase to match the package version
public enum TVAsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
    
    var image: Image? {
        guard case .success(let image) = self else { return nil }
        return image
    }
    
    var error: Error? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}

// Create a tvOS-compatible ImageProcessor protocol to match the package version
public protocol TVImageProcessor {
    func process(_ image: UIImage) -> UIImage
}

// A custom ImageLoader for tvOS compatibility
public class TVImageLoader: ObservableObject {
    @Published var asyncImagePhase: TVAsyncImagePhase = .empty
    
    private let url: URL?
    private let scale: CGFloat
    private let processor: TVImageProcessor?
    private var task: URLSessionDataTask?
    
    init(url: URL?, scale: CGFloat = 1, processor: TVImageProcessor? = nil) {
        self.url = url
        self.scale = scale
        self.processor = processor
    }
    
    func loadImage() {
        guard let url = url else {
            asyncImagePhase = .empty
            return
        }
        
        task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    self.asyncImagePhase = .failure(error)
                    return
                }
                
                guard let data = data, let uiImage = UIImage(data: data, scale: self.scale) else {
                    self.asyncImagePhase = .failure(NSError(domain: "AsyncImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image"]))
                    return
                }
                
                let finalImage = self.processor?.process(uiImage) ?? uiImage
                self.asyncImagePhase = .success(Image(uiImage: finalImage))
            }
        }
        
        task?.resume()
    }
    
    func cancelDownload() {
        task?.cancel()
        task = nil
    }
}

// tvOS compatible AsyncImage implementation
public struct TVAsyncImage<Content: View>: View {
    @ObservedObject var loader: TVImageLoader
    var content: ((TVAsyncImagePhase) -> Content)?
    
    @ViewBuilder
    var contentOrImage: some View {
        if let content = content {
            content(loader.asyncImagePhase)
        } else if let image = loader.asyncImagePhase.image {
            image
        } else {
            // Use a tvOS compatible color instead of secondarySystemBackground
            Color.gray.opacity(0.2)
        }
    }
    
    public var body: some View {
        contentOrImage
            .onAppear { loader.loadImage() }
            .onDisappear { loader.cancelDownload() }
    }
    
    public init(url: URL, scale: CGFloat = 1, processor: TVImageProcessor? = nil) where Content == Image {
        loader = TVImageLoader(url: url, scale: scale, processor: processor)
    }
    
    public init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1,
        processor: TVImageProcessor? = nil,
        content: @escaping (Image) -> I,
        placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale, processor: processor) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }

    public init(
        url: URL?,
        scale: CGFloat = 1,
        processor: TVImageProcessor? = nil,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (TVAsyncImagePhase) -> Content
    ) {
        self.content = content
        loader = TVImageLoader(url: url, scale: scale, processor: processor)
    }
}

// Extension for easier SwiftUI integration
extension TVAsyncImage where Content == Image {
    public init(url: URL?, scale: CGFloat = 1, processor: TVImageProcessor? = nil) {
        self.init(url: url, scale: scale, processor: processor) { phase in
            phase.image ?? Image(systemName: "photo")
        }
    }
}

// Typealias to make the replacement seamless
// This allows us to use AsyncImage in the tvOS code and have it automatically use our TVAsyncImage
#if !swift(>=5.5)
public typealias AsyncImage = TVAsyncImage
public typealias AsyncImagePhase = TVAsyncImagePhase
public typealias ImageProcessor = TVImageProcessor
#endif
#endif
