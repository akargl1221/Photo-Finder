import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Vision

struct MatchResult: Identifiable {
    let id = UUID()
    let url: URL
    let score: Double
}

struct SearchOutcome {
    let matches: [MatchResult]
    let referenceDetected: Bool
}

struct ContentView: View {
    @State private var referenceImage: NSImage?
    @State private var referenceImageURL: URL?
    @State private var searchFolderURL: URL?
    @State private var matchResults: [MatchResult] = []
    @State private var statusMessage = "Choose a reference image and a folder to search."
    @State private var isSearching = false
    @State private var similarityThreshold: Double = 0.72
    @State private var bestMatchPreview: NSImage?

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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Match confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(value: $similarityThreshold, in: 0.5...0.95, step: 0.01)
                            .frame(width: 220)

                        Text(String(format: "Threshold: %.2f", similarityThreshold))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

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

            if let bestMatch = matchResults.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Best match")
                        .font(.headline)

                    HStack(alignment: .center, spacing: 14) {
                        if let preview = bestMatchPreview {
                            Image(nsImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .cornerRadius(8)
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 120, height: 120)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(bestMatch.url.lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(2)
                            Text(String(format: "Similarity: %.2f", bestMatch.score))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if !matchResults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Matches found: \(matchResults.count)")
                        .font(.headline)

                    List(matchResults) { match in
                        HStack(alignment: .center, spacing: 10) {
                            if let preview = loadPreviewImage(from: match.url) {
                                Image(nsImage: preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .cornerRadius(6)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 48, height: 48)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.url.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(2)
                                Text(String(format: "Similarity: %.2f", match.score))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxHeight: 60)
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .padding(24)
    }

    private func loadPreviewImage(from url: URL) -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = NSSize(width: 48, height: 48)
        image.size = size
        return image
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
        matchResults = []
        bestMatchPreview = nil

        Task {
            let outcome = await findMatches(referenceImageURL: referenceURL, searchFolderURL: searchFolderURL, threshold: similarityThreshold)

            await MainActor.run {
                self.matchResults = outcome.matches
                self.isSearching = false

                if let bestMatch = outcome.matches.first,
                   let preview = NSImage(contentsOf: bestMatch.url) {
                    self.bestMatchPreview = preview
                }

                if !outcome.referenceDetected {
                    self.statusMessage = "No face was detected in the reference image."
                } else if outcome.matches.isEmpty {
                    self.statusMessage = "No matching images were found."
                } else {
                    self.statusMessage = "Found \(outcome.matches.count) matching image(s)."
                }
            }
        }
    }

    private func findMatches(referenceImageURL: URL, searchFolderURL: URL, threshold: Double) async -> SearchOutcome {
        let candidateFiles = collectImageFiles(in: searchFolderURL)

        guard let referenceDescriptor = faceDescriptor(for: NSImage(contentsOf: referenceImageURL)) else {
            return SearchOutcome(matches: [], referenceDetected: false)
        }

        let scoredMatches = candidateFiles.compactMap { file -> MatchResult? in
            guard let image = NSImage(contentsOf: file),
                  let descriptor = faceDescriptor(for: image) else {
                return nil
            }

            let similarity = cosineSimilarity(referenceDescriptor, descriptor)
            return similarity >= threshold ? MatchResult(url: file, score: similarity) : nil
        }

        let sortedMatches = scoredMatches.sorted { $0.score > $1.score }
        return SearchOutcome(matches: sortedMatches, referenceDetected: true)
    }

    private func faceDescriptor(for image: NSImage?) -> [Float]? {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceImage = CIImage(cgImage: cgImage)
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: sourceImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let faceObservation = request.results?.first as? VNFaceObservation else {
            return nil
        }

        let faceRect = VNImageRectForNormalizedRect(faceObservation.boundingBox, cgImage.width, cgImage.height)
        guard let croppedCGImage = cgImage.cropping(to: faceRect) else {
            return nil
        }

        let faceImage = CIImage(cgImage: croppedCGImage)
        return normalizeFaceDescriptor(from: faceImage)
    }

    private func normalizeFaceDescriptor(from image: CIImage) -> [Float] {
        let targetWidth = 32
        let targetHeight = 32
        let resized = image
            .transformed(by: CGAffineTransform(scaleX: CGFloat(targetWidth) / image.extent.width, y: CGFloat(targetHeight) / image.extent.height))
            .cropped(to: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(resized, from: resized.extent) else {
            return Array(repeating: 0, count: targetWidth * targetHeight)
        }

        let width = targetWidth
        let height = targetHeight
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalPixels = width * height

        guard let rawData = calloc(totalPixels * bytesPerPixel, MemoryLayout<UInt8>.size)?.assumingMemoryBound(to: UInt8.self) else {
            return Array(repeating: 0, count: totalPixels)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bitmapContext = CGContext(
            data: rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            free(rawData)
            return Array(repeating: 0, count: totalPixels)
        }

        bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        var descriptor: [Float] = []
        descriptor.reserveCapacity(totalPixels)

        for index in 0..<totalPixels {
            let offset = index * bytesPerPixel
            let r = Double(rawData[offset])
            let g = Double(rawData[offset + 1])
            let b = Double(rawData[offset + 2])
            let gray = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            descriptor.append(Float(gray))
        }

        free(rawData)

        let mean = descriptor.reduce(0.0) { partial, value in
            partial + Double(value)
        } / Double(descriptor.count)

        let variance = descriptor.reduce(0.0) { partial, value in
            let diff = Double(value) - mean
            return partial + (diff * diff)
        } / Double(descriptor.count)

        let std = sqrt(variance)

        return descriptor.map { value in
            let normalized = (Double(value) - mean) / (std == 0 ? 1.0 : std)
            return Float(normalized)
        }
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 0.0
        }

        let dotProduct = zip(lhs, rhs).reduce(0.0) { partial, pair in
            partial + Double(pair.0) * Double(pair.1)
        }

        let lhsMagnitude = sqrt(zip(lhs, lhs).reduce(0.0) { partial, pair in
            partial + Double(pair.0) * Double(pair.1)
        })
        let rhsMagnitude = sqrt(zip(rhs, rhs).reduce(0.0) { partial, pair in
            partial + Double(pair.0) * Double(pair.1)
        })

        guard lhsMagnitude > 0, rhsMagnitude > 0 else {
            return 0.0
        }

        return dotProduct / (lhsMagnitude * rhsMagnitude)
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
            guard let url = item as? URL else {
                return nil
            }

            let ext = url.pathExtension.lowercased()
            guard url.isImageFile,
                  permittedExtensions.contains(ext) else {
                return nil
            }

            return url
        }
    }
}

extension URL {
    var isImageFile: Bool {
        let ext = pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "tif", "tiff", "bmp", "gif", "webp"].contains(ext)
    }
}
