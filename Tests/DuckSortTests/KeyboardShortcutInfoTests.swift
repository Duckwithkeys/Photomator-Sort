//
//  KeyboardShortcutInfoTests.swift
//  DuckSortTests
//
//  Covers the shortcut parsing + SwiftUI mapping that drives the unified
//  menu/keyboard-shortcut handling.
//

import XCTest
import SwiftUI
@testable import DuckSort

final class KeyboardShortcutInfoTests: XCTestCase {

    func testParseSingleModifier() {
        let info = KeyboardShortcutInfo.parse("cmd+t")
        XCTAssertEqual(info.key, "t")
        XCTAssertTrue(info.command)
        XCTAssertFalse(info.shift)
        XCTAssertFalse(info.option)
        XCTAssertFalse(info.control)
    }

    func testParseMultipleModifiersAndAliases() {
        let info = KeyboardShortcutInfo.parse("control+opt+shift+x")
        XCTAssertEqual(info.key, "x")
        XCTAssertTrue(info.control)
        XCTAssertTrue(info.option)
        XCTAssertTrue(info.shift)
        XCTAssertFalse(info.command)
    }

    func testRoundTripSerialization() {
        let info = KeyboardShortcutInfo.parse("shift+cmd+a")
        XCTAssertEqual(KeyboardShortcutInfo.parse(info.serializedString), info)
    }

    func testKeyboardShortcutMapsKeyAndModifiers() throws {
        let shortcut = try XCTUnwrap(KeyboardShortcutInfo.parse("cmd+shift+t").keyboardShortcut)
        XCTAssertEqual(shortcut.key.character, "t")
        XCTAssertTrue(shortcut.modifiers.contains(.command))
        XCTAssertTrue(shortcut.modifiers.contains(.shift))
        XCTAssertFalse(shortcut.modifiers.contains(.option))
        XCTAssertFalse(shortcut.modifiers.contains(.control))
    }

    func testKeyboardShortcutNilWithoutKey() {
        // No printable key means there's nothing for a menu command to bind.
        XCTAssertNil(KeyboardShortcutInfo.parse("cmd").keyboardShortcut)
        XCTAssertNil(KeyboardShortcutInfo.parse("").keyboardShortcut)
    }
}
