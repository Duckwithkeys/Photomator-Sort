# Photomator Sort

A native macOS application designed to automate the workflow of scanning, organizing, tagging, and routing photo sets. It groups RAW files, JPEGs, and sidecar files (such as Photomator edits) into unified sets, allowing you to manage and export them efficiently using customizable routing rules.

---

## Features

- **Smart Photo Grouping**: Automatically pairs RAW files with their corresponding JPEG representations and sidecar files (e.g. `.photo` files, edit metadata) as unified photo sets.
- **Multi-Source Scan**: Scan multiple folders at the same time to collect and view all photo sets.
- **Custom Tagging**: A fully-featured Tag Manager to create, edit, and assign custom tags to your photo groups.
- **Export Routing Rules**: Define rule-based conditions (e.g. based on tags, file extensions, etc.) to automatically route your files to specific target directories.
- **Batch Transfer Engine**: Execute batch operations to copy or move files safely to their destination folders.
- **High-Resolution Preview**: Double-click or press space to view full-canvas previews of your images.
- **Photo Metadata Inspector**: A side-panel overlay in the image viewer to see Aperture, Shutter Speed, ISO, Camera, and Lens.
- **Visual Transfer Progress Bar**: High precision byte-level tracking displaying real-time data transfer rate and ETA during batch operations.
- **Keyboard-Driven Workflow**: High-efficiency keyboard shortcuts for rapid selection, navigation, and tagging.
- **JPEG-Only Mode**: A toggle to scan JPEG files exclusively and ignore sidecar warnings when editing.

---

## Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer.
- **Developer Tools**: Xcode 15+ / Swift 5.9+ (Swift Package Manager).

---

## Project Structure

- `Package.swift`: Swift Package Manager configuration file.
- `PhotomatorSort/`: Main source code directory containing:
  - `Models/`: Data models for PhotoSet, Tags, Routing Rules, and User Preferences.
  - `ViewModels/`: View-models implementing business logic and UI state.
  - `Views/`: SwiftUI components and layouts.
  - `Utilities/`: Helper extensions, window managers, and shortcut handlers.
  - `Resources/`: Application assets (icons, etc.).
- `package_app.sh`: Bash script to build the app in release mode and package it into `PhotomatorSort.app`.
- `create_dmg.sh`: Bash script to package the app bundle into a user-friendly disk image (`PhotomatorSort.dmg`).

---

## Getting Started

### Open and Run in Xcode

1. Open Xcode.
2. Select **Open Existing Project** (or **File > Open...**).
3. Select the folder containing `Package.swift`.
4. Click **Run** or press `Cmd + R` to build and launch the application.

### Command Line / Swift Package Manager

You can also run or test the project directly from the terminal:

```bash
# Run the application
swift run

# Build the project
swift build
```

---

## Packaging & Distribution

This repository includes helper scripts to compile and bundle the app for distribution:

1. **Build the App Bundle**:
   Run `package_app.sh` to compile in release configuration and generate a standalone `.app` bundle:
   ```bash
   ./package_app.sh
   ```
2. **Create the DMG Disk Image**:
   After creating the `.app` bundle, run `create_dmg.sh` to package it into a compressed `.dmg` file:
   ```bash
   ./create_dmg.sh
   ```

---

## Repository & Publishing Guide

To publish this project to GitHub, make sure you configure your repository correctly. Below is a guide on what to include and what to ignore.

### What to Upload (Tracked in Git)

- **Source Code**: All directories containing Swift source code files (`PhotomatorSort/`).
- **Configuration**: Swift Package Manager manifest (`Package.swift`).
- **Scripts**: Packaging scripts (`package_app.sh` and `create_dmg.sh`).
- **Documentation**: This `README.md` and standard repository files (such as `.gitignore` or `LICENSE`).

### What is Ignored (Excluded via `.gitignore`)

We have configured a `.gitignore` file to ensure the following files are **not** uploaded to GitHub:
- **Build Artifacts**: The Swift PM `.build/` folder and Xcode `build/` or `DerivedData` directories.
- **User Settings**: Local Xcode user data and workspaces (`.swiftpm/`, `xcuserdata/`, `*.xcuserstate`).
- **Compiled Binaries**: The final compiled app bundle (`PhotomatorSort.app/`) and packaging workspaces (`dmg_workspace/`, `tmp_iconset/`).
- **Distribution Packages**: The final disk image (`PhotomatorSort.dmg`).
- **OS Metadata**: Finder metadata (`.DS_Store`).
