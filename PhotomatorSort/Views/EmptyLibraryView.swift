//
//  EmptyLibraryView.swift
//  PhotomatorSort
//

import SwiftUI

struct EmptyLibraryView: View {
    let isScanning: Bool
    let selectFolderAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if isScanning {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }

            Text(isScanning ? "Scanning photoshoot..." : "Choose a source folder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Photomator Sort groups RAW, HEIF, JPEG, and .photo-edit files by base name.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !isScanning {
                Button("Select Folder...") {
                    selectFolderAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

