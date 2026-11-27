import AppKit
import Carbon
import SwiftUI

struct ReminderShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let standard = ReminderShortcut(keyCode: UInt32(kVK_ANSI_N),
                                          modifiers: UInt32(controlKey | optionKey), keyLabel: "N")

    var displayName: String {
        var label = ""
        if modifiers & UInt32(controlKey) != 0 { label += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { label += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { label += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { label += "⌘" }
        return label + keyLabel
    }

    static func from(_ event: NSEvent) -> ReminderShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
                                       123: "←", 124: "→", 125: "↓", 126: "↑"]
        let label = special[event.keyCode] ?? characters.uppercased()
        return ReminderShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }
}

@MainActor
final class GlobalReminderShortcut: ObservableObject {
    static let shared = GlobalReminderShortcut()
    private static let storageKey = "ItsTime_GlobalReminderShortcut"
    private static let signature: OSType = 0x4954524D
    @Published private(set) var shortcut: ReminderShortcut?
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var monitor: Any?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            shortcut = (try? JSONDecoder().decode(ReminderShortcut?.self, from: data)) ?? nil
        } else {
            shortcut = .standard
        }
    }

    func start() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4954524D, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in
                guard !GlobalReminderShortcut.shared.isRecording else { return }
                WindowManager.shared.openNewReminder()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
        guard status == noErr else {
            errorMessage = "无法启用全局快捷键，请重新启动应用。"
            return
        }
        registerCurrentShortcut()
    }

    private func registerCurrentShortcut() {
        guard let shortcut else { return }
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        errorMessage = status == noErr ? nil : "此快捷键无法注册，可能已被其他应用占用，请换一个组合。"
    }

    func beginRecording() {
        guard !isRecording else { return }
        start()
        guard eventHandler != nil else { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        errorMessage = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.isARepeat { return nil }
            if event.keyCode == UInt16(kVK_Escape) {
                self.cancelRecording()
                return nil
            }
            guard let candidate = ReminderShortcut.from(event) else {
                self.errorMessage = "请搭配 ⌘、⌃ 或 ⌥ 使用；Esc 取消。"
                return nil
            }
            let previous = self.shortcut
            self.shortcut = candidate
            self.registerCurrentShortcut()
            if self.hotKey != nil {
                self.persist()
                self.endRecording()
            } else {
                self.shortcut = previous
            }
            return nil
        }
    }

    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    func cancelRecording() {
        guard isRecording else { return }
        endRecording()
        registerCurrentShortcut()
    }

    func clear() {
        endRecording()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        shortcut = nil
        errorMessage = nil
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

struct ReminderShortcutSetting: View {
    @ObservedObject private var shortcut = GlobalReminderShortcut.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("全局新建提醒", systemImage: "keyboard")
                Spacer()
                Button(shortcut.isRecording ? "按下快捷键…" : shortcut.shortcut?.displayName ?? "设置快捷键") {
                    if shortcut.isRecording { shortcut.cancelRecording() }
                    else { shortcut.beginRecording() }
                }
                .accessibilityLabel("录制全局新建提醒快捷键")
                if shortcut.shortcut != nil {
                    Button("清除") { shortcut.clear() }
                }
            }
            if let error = shortcut.errorMessage {
                Text(error).font(.caption).foregroundColor(.red)
            } else if shortcut.isRecording {
                Text("Esc 取消").font(.caption).foregroundColor(.secondary)
            }
        }
        .font(.system(size: 13))
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onDisappear { shortcut.cancelRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            shortcut.cancelRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            shortcut.cancelRecording()
        }
    }
}
