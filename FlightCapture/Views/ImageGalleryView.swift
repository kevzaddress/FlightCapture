import SwiftUI

// MARK: - Siri-style Edge Lighting Effect
struct EdgeLightingView: View {
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Debug background to see if the view is being rendered
            Rectangle()
                .fill(Color.red.opacity(0.1))
                .onAppear {
                    print("[DEBUG] EdgeLightingView is being rendered")
                }
            
            // Top edge
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 8)
                .offset(y: -4 + sin(animationPhase) * 2)
            
            // Bottom edge
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.3), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: 8)
                .offset(y: 4 + sin(animationPhase + .pi) * 2)
            
            // Left edge
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.3), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 8)
                .offset(x: -4 + sin(animationPhase + .pi/2) * 2)
            
            // Right edge
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.3), Color.clear],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                )
                .frame(width: 8)
                .offset(x: 4 + sin(animationPhase + 3 * .pi/2) * 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: false)) {
                animationPhase = 2 * .pi
            }
        }
    }
}

struct ImageGalleryView: View {
    let images: [UIImage]
    let imageNames: [String] // New: descriptive names for each image
    @State private var currentIndex = 0
    @State private var showingFullScreen = false
    
    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(0..<images.count, id: \.self) { index in
                Image(uiImage: images[index])
                    .resizable()
                    .scaledToFit()
                    .tag(index)
                    .onTapGesture {
                        showingFullScreen = true
                    }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        .frame(height: 160)
        .sheet(isPresented: $showingFullScreen) {
            FullScreenImageView(images: images, imageNames: imageNames, initialIndex: currentIndex)
        }
        .onAppear {
            print("[DEBUG] ImageGalleryView appeared with imageNames: \(imageNames)")
        }
        .onChange(of: imageNames) { _, newNames in
            print("[DEBUG] ImageGalleryView imageNames changed to: \(newNames)")
        }
    }
}

struct FullScreenImageView: View {
    let images: [UIImage]
    let imageNames: [String]
    let initialIndex: Int
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss
    
    init(images: [UIImage], imageNames: [String], initialIndex: Int) {
        self.images = images
        self.imageNames = imageNames
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    func displayName(for index: Int) -> String {
        guard index < imageNames.count else { return "Image \(index + 1)" }
        switch imageNames[index] {
        case "dashboard": return "Dashboard"
        case "crewList": return "Crew List"
        default: return "Image \(index + 1)"
        }
    }
    
    var body: some View {
        NavigationView {
            TabView(selection: $currentIndex) {
                ForEach(0..<images.count, id: \.self) { index in
                    ZoomableImageView(image: images[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .navigationTitle(displayName(for: currentIndex))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                if images.count > 1 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 8) {
                            ForEach(0..<images.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentIndex ? Color.primary : Color.secondary)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1.0), 4.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        offset = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.0
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ImageGalleryView(images: [], imageNames: [])
} 