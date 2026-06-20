//
//  ShortcutRecorderView.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @Binding var hotkey: String?
    @State private var isRecording = false
    @State private var localMonitor: Any? = nil

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(buttonLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isRecording ? .white : (hotkey == nil ? .secondary : .primary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: 70, minHeight: 22)
                    .background(
                        isRecording ? Color.blue : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isRecording ? Color.blue : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "Press any key combination to record, or Esc to cancel" : "Click to record shortcut")

            if hotkey != nil && !isRecording {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var buttonLabel: String {
        if isRecording {
            return "Record..."
        }
        if let hotkey = hotkey {
            let info = KeyboardShortcutInfo.parse(hotkey)
            return info.displayString
        }
        return "Record"
    }

    private func startRecording() {
        isRecording = true
        
        // Remove any old monitor
        if let existing = localMonitor {
            NSEvent.removeMonitor(existing)
        }
        
        // Hook local event monitor for key down
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc key (keycode 53) cancels recording
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let activeModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Check if key is printable or a valid navigation key
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  chars.count == 1,
                  let char = chars.first else {
                return event
            }
            
            // If they just press modifiers without a character, ignore and wait
            if activeModifiers.isEmpty && (event.keyCode == 54 || event.keyCode == 55 || event.keyCode == 56 || event.keyCode == 59 || event.keyCode == 60 || event.keyCode == 61 || event.keyCode == 62) {
                return event
            }

            var info = KeyboardShortcutInfo(key: String(char))
            info.shift = activeModifiers.contains(.shift)
            info.control = activeModifiers.contains(.control)
            info.option = activeModifiers.contains(.option)
            info.command = activeModifiers.contains(.command)

            // Save hotkey string
            self.hotkey = info.serializedString
            
            stopRecording()
            return nil // Consumes event so it doesn't trigger actions elsewhere
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
