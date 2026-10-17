import AppKit
import SwiftUI
import PyawwCore

/// The menu bar popover: status, permissions and every setting in one
/// surface (owner decision 2026-10-18 — the popover replaces both the plain
/// menu and the separate Settings window). Shown from the wave in the menu
/// bar by `MenuBarController` (a hosted `NSPopover`).
struct MenuPanelView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            permissionsCard
            dictationCard
            pastingCard
            feedbackCard
            modelCard
            footer
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            model.refreshPermissions()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            headerIcon
            VStack(alignment: .leading, spacing: 1) {
                Text("Pyaww")
                    .font(.system(size: 13, weight: .semibold))
                Text(headerMessage.text)
                    .font(.system(size: 11))
                    .foregroundStyle(headerMessage.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    /// The header's second line — always exactly one short line, so the
    /// panel keeps the same shape when messages appear (owner question
    /// 2026-10-18). An error beats a fresh notice (transient dictation
    /// feedback, orange), which beats the live status. Every message is
    /// kept short enough for one line, so nothing is ever truncated.
    private var headerMessage: (text: String, color: Color) {
        if case .error(let message) = model.state.phase {
            return (message, .secondary)
        }
        if let notice = model.state.notice {
            return (notice, .orange)
        }
        return (model.state.statusText, .secondary)
    }

    @ViewBuilder private var headerIcon: some View {
        Group {
            switch model.state.phase {
            case .recording:
                Image(nsImage: MenuBarIcon.recording)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)
            case .idle, .transcribing:
                Image(nsImage: MenuBarIcon.idle)
                    .renderingMode(.template)
                    .foregroundStyle(model.state.isModelReady ? Color.primary : Color.secondary)
            }
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        PanelCard(title: "Permissions", systemImage: "lock.shield") {
            permissionRow(
                name: "Microphone",
                granted: model.permissions.isMicrophoneGranted,
                canRequest: model.permissions.microphoneStatus == .notDetermined,
                request: { Task { await model.permissions.requestMicrophoneAccessIfNeeded() } },
                openSettings: { model.permissions.openMicrophoneSettings() })
            permissionRow(
                name: "Accessibility",
                granted: model.permissions.accessibilityTrusted,
                canRequest: true,
                request: { model.permissions.promptAccessibilityIfNeeded() },
                openSettings: { model.permissions.openAccessibilitySettings() })
        } accessory: {
            if !model.permissions.isMicrophoneGranted || !model.permissions.accessibilityTrusted {
                Button {
                    model.refreshPermissions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Refresh permission status")
            }
        }
    }

    @ViewBuilder
    private func permissionRow(name: String, granted: Bool, canRequest: Bool,
                              request: @escaping () -> Void,
                              openSettings: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            StatusDot(ok: granted)
            Text(name)
                .font(.system(size: 13))
            Spacer(minLength: 8)
            if granted {
                Text("Granted")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                if canRequest {
                    Button("Grant…", action: request)
                        .controlSize(.small)
                }
                Button("Open Settings…", action: openSettings)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Settings cards

    private var dictationCard: some View {
        PanelCard(title: "Dictation", systemImage: "mic") {
            PanelRow("Push-to-talk key") {
                Picker("", selection: Bindable(model.settings).pushToTalkKey) {
                    ForEach(PushToTalkKey.allCases) { key in
                        Text(key.keyCapLabel).tag(key)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .onChange(of: model.settings.pushToTalkKey) { _, _ in
                    model.applyHotkeySetting()
                }
            }
            PanelRow("Minimum recording") {
                durationPicker(
                    selection: Bindable(model.settings).minimumDuration,
                    choices: SettingsStore.minimumDurationChoices)
            }
            PanelRow("Maximum recording") {
                durationPicker(
                    selection: Bindable(model.settings).maximumDuration,
                    choices: SettingsStore.maximumDurationChoices)
            }
            Text("Hold \(model.settings.pushToTalkKey.keyCapLabel) and speak — release to paste.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func durationPicker(selection: Binding<Double>, choices: [Double]) -> some View {
        Picker("", selection: selection) {
            ForEach(choices, id: \.self) { value in
                Text(Self.durationLabel(value)).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 78)
    }

    /// "0.3 s" for fractions, "30 s" for whole seconds.
    private static func durationLabel(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f s", value)
            : String(format: "%.1f s", value)
    }

    private var pastingCard: some View {
        PanelCard(title: "Pasting", systemImage: "text.cursor") {
            toggleRow("Segment Myanmar words",
                      isOn: Bindable(model.settings).wordSegmentation,
                      help: "Joins the model's syllable-by-syllable spacing into words (recommended). Turn off to paste the raw model output.")
            toggleRow("Restore previous clipboard",
                      isOn: Bindable(model.settings).restoreClipboard)
        }
    }

    private var feedbackCard: some View {
        PanelCard(title: "Feedback", systemImage: "speaker.wave.2") {
            toggleRow("Sound cue while recording",
                      isOn: Bindable(model.settings).soundCue)
            toggleRow("Launch at login",
                      isOn: Bindable(model.settings).launchAtLogin)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, help: String? = nil) -> some View {
        PanelRow(title) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .help(help ?? title)
    }

    private var modelCard: some View {
        PanelCard(title: "Model", systemImage: "waveform") {
            speechModelRow
            // The segmentation row's only job is warning: the lexicon loads
            // once at launch, so when it loaded the row would repeat the
            // header's "Ready" forever (owner question 2026-10-18).
            if !model.state.isWordSegmentationAvailable {
                PanelValueRow(title: "Word segmentation",
                              value: "Unavailable", attention: true)
            }
        }
    }

    /// Speech-model row: the model's name once ready (SPEC §1 — the owner's
    /// Myanmar Conformer ASR; the header already carries live status, so a
    /// row that always echoed "Ready" was noise), a spinner during the cold
    /// start, and an orange warning after a failed load.
    @ViewBuilder private var speechModelRow: some View {
        if model.state.isModelReady {
            PanelValueRow(title: "Speech model", value: "Myanmar Conformer")
        } else if case .error = model.state.phase {
            PanelValueRow(title: "Speech model", value: "Unavailable", attention: true)
        } else {
            PanelValueRow(title: "Speech model", value: "Loading…", busy: true)
        }
    }

    // MARK: - Footer

    /// Version + GitHub link, and the teacher-style quiet Quit button
    /// (flat fill, hairline border, icon + label — owner decision
    /// 2026-10-18; the default bordered button looked like a foreign
    /// control next to the panel's own language).
    private var footer: some View {
        HStack(spacing: 7) {
            Text(Self.versionLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            if let url = Self.repositoryURL {
                Link(destination: url) {
                    HStack(spacing: 2) {
                        Text("GitHub")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 10.5))
                }
                .help("github.com/tklwin/pyaww")
            }
            Spacer(minLength: 8)
            quitButton
        }
        .padding(.horizontal, 2)
    }

    /// The teacher's footer button, roughly: soft flat fill, hairline
    /// border, icon + label centred — no system chrome.
    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "power")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("Quit")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Quit Pyaww")
    }

    private static let repositoryURL = URL(string: "https://github.com/tklwin/pyaww")

    /// "pyaww v0.1.0" from `CFBundleShortVersionString` in the assembled
    /// .app; "pyaww dev" for `swift run` (no Info.plist — "pyaww vdev"
    /// would read as a typo).
    private static var versionLabel: String {
        guard let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return "pyaww dev" }
        return "pyaww v\(short)"
    }
}
