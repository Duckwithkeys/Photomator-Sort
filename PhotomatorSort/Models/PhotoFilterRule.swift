//
//  PhotoFilterRule.swift
//  PhotomatorSort
//
//  Enumeration of display filter modes available in the grid toolbar.
//  New rules (e.g. "Has Tags", "Camera Model = X") can be added as
//  additional cases without touching existing logic.

import Foundation

enum PhotoFilterRule: String, CaseIterable, Identifiable, Sendable {
    case allPhotos         = "All Photos"
    case editedOnly        = "Edited Only"
    case uneditedOnly      = "Unedited Only"

    var id: String { rawValue }

    /// Whether the given ``PhotoSet`` passes this filter rule.
    func matches(_ photoSet: PhotoSet) -> Bool {
        switch self {
        case .allPhotos:
            return true
        case .editedOnly:
            return photoSet.hasEdit
        case .uneditedOnly:
            return !photoSet.hasEdit
        }
    }

    /// SF Symbols icon for each filter option.
    var systemImage: String {
        switch self {
        case .allPhotos:     return "photo.stack"
        case .editedOnly:    return "wand.and.stars"
        case .uneditedOnly:  return "minus.circle"
        }
    }
}
