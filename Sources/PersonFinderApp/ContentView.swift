import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

                    List(searchResults, id: \ .self) { url in
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

        guard let reference = NSImage(contentsOf: referenceImageURL) else {
            return []
        }

        // Placeholder matching logic. Replace this with actual face-detection and face similarity code.
        // For now, this intentionally returns files that have the same filename stem as the reference.
        let referenceStem = referenceImageURL.deletingPathExtension().lastPathComponent.lowercased()

        return candidateFiles.filter { file in
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains(referenceStem) || referenceStem.contains(name)
        }
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
                  url.isImageFile,
                  let ext = url.pathExtension.lowercased(),
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
