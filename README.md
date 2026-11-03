# Person Finder

This project is a macOS SwiftUI starter app for a local-only person-matching tool.

## What it does

- lets you drag in a photo of a person
- lets you choose a folder to search for images
- scans image files under that folder
- displays matching file paths

## Important note

The app currently includes the UI and the folder scanning flow, but the actual face-recognition logic is intentionally left as a placeholder.

To make it truly identify a person from a reference photo, you should replace the stub in `ContentView.swift` with Apple Vision + Core ML face comparison logic.

## Build instructions

1. Open Xcode.
2. Create a new macOS App project.
3. Add the source files from `Sources/PersonFinderApp`.
4. Ensure the target is macOS and uses SwiftUI.
5. Build and run.

## Next upgrade

The next step is to replace the placeholder `findMatches` method with code that:

- walks every image file in the selected folder recursively
- uses Vision to detect faces in each image
- extracts a face embedding or feature vector
- compares it against the reference face embedding
- returns only likely matches

This keeps everything on the local machine and does not require Siri or cloud processing.
