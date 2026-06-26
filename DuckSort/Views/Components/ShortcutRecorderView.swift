//
//  ShortcutRecorderView.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

struct ShortcutRecorderView: View {
    @Binding var hotkey: String?
    var validationMessage: (String) -> String? = { _ in nil }
    @State private var isRecording = false
    @State private var localMonitor: Any? = nil
    @State private var rejectionMessage: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: Theme.Space.s4) {
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(buttonLabel)
                        .font(Theme.Font.monoBody)
                        .foregroundStyle(
                            isRecording
                                ? Theme.Color.textInverse
                                : (hotkey == nil ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                        )
                        .padding(.horizontal, Theme.Space.s8)
                        .padding(.vertical, Theme.Space.s4)
                        .frame(minWidth: 70, minHeight: 22)
                        .background(
                            isRecording ? Theme.Color.accent : Theme.Color.overlaySoft,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.m)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .stroke(
                                    isRecording ? Theme.Color.accent : Theme.Color.overlaySofter,
                                    lineWidth: Theme.Stroke.hairline
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
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(Theme.Space.s4)
                    }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
                }
            }

            if let rejectionMessage {
                Text(rejectionMessage)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.warning)
                    .lineLimit(1)
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
        rejectionMessage = nil
        
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

            let proposed = info.serializedString
            if let message = validationMessage(proposed) {
                NSSound.beep()
                rejectionMessage = message
                stopRecording()
                return nil
            }

            hotkey = proposed
            
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
