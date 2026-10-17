import SwiftUI
import PyawwCore

/// Settings window (FR-10): hotkey, durations, clipboard restore, sound cue,
/// launch at login, plus permission status (FR-9).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Push-to-talk key", selection: Bindable(model.settings).pushToTalkKey) {
                    ForEach(PushToTalkKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .onChange(of: model.settings.pushToTalkKey) { _, _ in
                    model.applyHotkeySetting()
                }
                Picker("Minimum recording", selection: Bindable(model.settings).minimumDuration) {
                    ForEach(SettingsStore.minimumDurationChoices, id: \.self) { value in
                        Text(String(format: "%.1f s", value)).tag(value)
                    }
                }
                Picker("Maximum recording", selection: Bindable(model.settings).maximumDuration) {
                    ForEach(SettingsStore.maximumDurationChoices, id: \.self) { value in
                        Text("\(Int(value)) s").tag(value)
                    }
                }
            }

            Section("Pasting") {
                Toggle("Segment Myanmar words", isOn: Bindable(model.settings).wordSegmentation)
                    .help("Joins the model's syllable-by-syllable spacing into words (recommended). Turn off to paste the raw model output.")
                Toggle("Restore the previous clipboard contents", isOn: Bindable(model.settings).restoreClipboard)
            }

            Section("Feedback") {
                Toggle("Play a sound cue while recording", isOn: Bindable(model.settings).soundCue)
                Toggle("Launch at login", isOn: Bindable(model.settings).launchAtLogin)
            }

            Section("Permissions") {
                LabeledContent("Microphone", value: microphoneDescription)
                LabeledContent(
                    "Accessibility",
                    value: model.permissions.accessibilityTrusted ? "Granted" : "Not granted")
                HStack {
                    Button("Open Microphone Settings…") {
                        model.permissions.openMicrophoneSettings()
                    }
                    Button("Open Accessibility Settings…") {
                        model.permissions.openAccessibilitySettings()
                    }
                    Button("Refresh") {
                        model.refreshPermissions()
                    }
                }
            }

            Section("Model") {
                LabeledContent("Status", value: model.state.isModelReady ? "Ready" : "Loading…")
                LabeledContent(
                    "Word segmentation",
                    value: model.state.isWordSegmentationAvailable ? "Ready" : "Unavailable")
                LabeledContent("Hotkey", value: "Hold \(model.settings.pushToTalkKey.displayName) and speak")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .onAppear {
            model.permissions.refresh()
        }
    }

    private var microphoneDescription: String {
        switch model.permissions.microphoneStatus {
        case .authorized: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }
}
