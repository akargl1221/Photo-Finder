import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Vision

struct ContentView: View {
    @State private var referenceImage: NSImage?
    @State private var referenceImageURL: URL?
    @State private var searchFolderURL: URL?
    @State private var searchResults: [URL] = []
    @State private var statusMessage = "Choose a reference image and a folder to search."
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Person Finder")
                .font(.title2)
                .bold()

            Text(statusMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                referenceImagePreview
                    .frame(width: 220, height: 220)

                VStack(alignment: .leading, spacing: 12) {
                    Button("Choose reference photo") {
                        chooseReferenceImage()
                    }
                    .controlSize(.large)

                    Button("Choose search folder") {
                        chooseSearchFolder()
                    }
                    .controlSize(.large)

                    Button(action: runSearch) {
                        HStack {
                            if isSearching {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isSearching ? "Searching..." : "Search for matches")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSearching || referenceImageURL == nil || searchFolderURL == nil)
                }
            }

            if !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Matches found: \(searchResults.count)")
                        .font(.headline)

                    List(searchResults, id: \.self) { url in
                        Text(url.path)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .padding(24)
    }

    private var referenceImagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(.gray.opacity(0.5))

            if let image = referenceImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Drop image here")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFiles(providers: providers)
        }
    }

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    if url.isImageFile {
                        DispatchQueue.main.async {
                            self.referenceImage = NSImage(contentsOf: url)
                            self.referenceImageURL = url
                            self.statusMessage = "Reference image selected: \(url.lastPathComponent)"
                        }
                    }
                }
            }
        }
        return true
    }

    @MainActor
    private func chooseReferenceImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self.referenceImage = NSImage(contentsOf: url)
                self.referenceImageURL = url
                self.statusMessage = "Reference image selected: \(url.lastPathComponent)"
            }
        }
    }

    @MainActor
    private func chooseSearchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self.searchFolderURL = url
                self.statusMessage = "Search folder selected: \(url.path)"
            }
        }
    }

    @MainActor
    private func runSearch() {
        guard let referenceURL = referenceImageURL,
              let searchFolderURL else {
            statusMessage = "Please choose both a reference image and a search folder."
            return
        }

        isSearching = true
        statusMessage = "Scanning \(searchFolderURL.path) for matching images..."
        searchResults = []

        Task {
            let matches = await findMatches(referenceImageURL: referenceURL, searchFolderURL: searchFolderURL)

            await MainActor.run {
                self.searchResults = matches
                self.isSearching = false

                if matches.isEmpty {
                    self.statusMessage = "No matching images were found."
                } else {
                    self.statusMessage = "Found \(matches.count) matching image(s)."
                }
            }
        }
    }

    private func findMatches(referenceImageURL: URL, searchFolderURL: URL) async -> [URL] {
        let candidateFiles = collectImageFiles(in: searchFolderURL)

        guard let referenceSignature = faceSignature(for: NSImage(contentsOf: referenceImageURL)) else {
            return []
        }

        let scoredMatches = candidateFiles.compactMap { file -> (URL, Double)? in
            guard let image = NSImage(contentsOf: file),
                  let signature = faceSignature(for: image) else {
                return nil
            }

            let similarity = cosineSimilarity(referenceSignature, signature)
            return similarity > 0.9 ? (file, similarity) : nil
        }

        return scoredMatches
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func collectImageFiles(in folder: URL) -> [URL] {
        let fileManager = FileManager.default
        let permittedExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "bmp", "gif", "webp"]

        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.isImageFile else {
                return nil
            }

            let ext = url.pathExtension.lowercased()
            guard permittedExtensions.contains(ext) else {
                return nil
            }
            return url
        }
    }

    private func faceSignature(for image: NSImage?) -> [Float]? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let requests = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

        do {
            try handler.perform([requests])
        } catch {
            return nil
        }

        guard let face = requests.results?.first as? VNFaceObservation else {
            return nil
        }

        let normalizedRect = VNImageRectForNormalizedRect(face.boundingBox, cgImage.width, cgImage.height)
        guard let cropped = cgImage.cropping(to: normalizedRect) else {
            return nil
        }

        let targetWidth = 32
        let targetHeight = 32
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let destinationRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        context.draw(cropped, in: destinationRect)

        guard let data = context.data else {
            return nil
        }

        let ptr = data.bindMemory(to: UInt8.self, capacity: targetWidth * targetHeight * 4)
        var signature: [Float] = []
        signature.reserveCapacity(targetWidth * targetHeight * 3)

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let index = (y * targetWidth + x) * 4
                let r = Float(ptr[index]) / 255.0
                let g = Float(ptr[index + 1]) / 255.0
                let b = Float(ptr[index + 2]) / 255.0
                signature.append(r)
                signature.append(g)
                signature.append(b)
            }
        }

        return signature
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }

        var dot: Double = 0
        var lhsMagnitude: Double = 0
        var rhsMagnitude: Double = 0

        for index in 0..<count {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            lhsMagnitude += left * left
            rhsMagnitude += right * right
        }

        guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
        return dot / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
    }
}

extension URL {
    var isImageFile: Bool {
        let ext = pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "tif", "tiff", "bmp", "gif", "webp"].contains(ext)
    }
}

// Xcode build note:
// This project should be built in Xcode (not raw swift build) because the SwiftUI macro
// runtime and AppKit/SwiftUI toolchain integration are provided by the Xcode SDK and plugin system.
