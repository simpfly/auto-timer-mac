import AppKit
import Carbon
import XCTest
@testable import itstime

final class ReminderShortcutTests: XCTestCase {
    private func keyEvent(flags: NSEvent.ModifierFlags, keyCode: UInt16 = 0, characters: String = "a") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: 0, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func testRejectsUnmodifiedAndShiftOnlyTyping() {
        XCTAssertNil(ReminderShortcut.from(keyEvent(flags: [])))
        XCTAssertNil(ReminderShortcut.from(keyEvent(flags: [.shift])))
    }

    func testConvertsModifiersAndIgnoresCapsLock() {
        let shortcut = ReminderShortcut.from(keyEvent(flags: [.control, .option, .shift, .capsLock]))
        XCTAssertEqual(shortcut?.modifiers, UInt32(controlKey | optionKey | shiftKey))
        XCTAssertEqual(shortcut?.displayName, "⌃⌥⇧A")
        XCTAssertEqual(shortcut?.keyCode, 0)
    }

    func testDefaultAndClearedBindingRoundTrip() throws {
        let configured: ReminderShortcut? = .standard
        let encoded = try JSONEncoder().encode(configured)
        XCTAssertEqual(try JSONDecoder().decode(ReminderShortcut?.self, from: encoded), configured)
        XCTAssertEqual(configured?.displayName, "⌃⌥N")
        let cleared: ReminderShortcut? = nil
        let clearedData = try JSONEncoder().encode(cleared)
        XCTAssertNil(try JSONDecoder().decode(ReminderShortcut?.self, from: clearedData))
    }

    func testSpecialKeyHasReadableLabel() {
        let shortcut = ReminderShortcut.from(keyEvent(flags: [.command, .shift], keyCode: 49, characters: " "))
        XCTAssertEqual(shortcut?.displayName, "⇧⌘Space")
    }
}
