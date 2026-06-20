//
//  RoutedOperation.swift
//  PhotomatorSort
//
//  Defines the three routed operations (copy, move, export JPEG) and the
//  common plan / result types they share. All three use the same
//  ExportPathRule to build per-photo destination folders.
//

import Foundation

enum RoutedOperation: String, CaseIterable, Identifiable, Sendable {
    case copyOriginals
    case moveOriginals
    case exportJPEGs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .copyOriginals:  return "Copy Originals"
        case .moveOriginals:  return "Move Originals"
        case .exportJPEGs:    return "Export JPEGs"
        }
    }

    var systemImage: String {
        switch self {
        case .copyOriginals:  return "doc.on.doc"
        case .moveOriginals:  return "folder"
        case .exportJPEGs:    return "photo.on.rectangle"
        }
    }

    var progressTitle: String {
        switch self {
        case .copyOriginals:  return "Copying"
        case .moveOriginals:  return "Moving"
        case .exportJPEGs:    return "Exporting JPEGs"
        }
    }

    var menuShortcut: String {
        switch self {
        case .copyOriginals:  return "c"
        case .moveOriginals:  return "m"
        case .exportJPEGs:    return "e"
        }
    }
}

/// One photo set ready to be routed. Carries the photo set, its metadata,
/// and the user-assigned tags so the router doesn't have to look them up.
struct RoutedPhoto: Sendable {
    let photoSet: PhotoSet
    let metadata: MetadataSnapshot
    let tags: [CustomTag]
}

struct RoutedPlan: Sendable {
    let operation: RoutedOperation
    let baseDestination: URL
    let rule: [ExportPathComponent]
    let photos: [RoutedPhoto]
    let jpegQuality: Double
    let namingPreset: ExportNamingPreset

    init(
        operation: RoutedOperation,
        baseDestination: URL,
        rule: [ExportPathComponent],
        photos: [RoutedPhoto],
        jpegQuality: Double = 0.92,
        namingPreset: ExportNamingPreset = .dateOriginalSequence
    ) {
        self.operation = operation
        self.baseDestination = baseDestination
        self.rule = rule
        self.photos = photos
        self.jpegQuality = jpegQuality
        self.namingPreset = namingPreset
    }
}

struct RoutedSummary: Sendable {
    let operation: RoutedOperation
    let fileCount: Int
    let baseDestination: URL
    let foldersCreated: Int
}
