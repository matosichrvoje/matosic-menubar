import SwiftUI

struct PopoverView: View {
    @ObservedObject var focus: FocusObserver
    @ObservedObject var store: ProfileStore
    @ObservedObject var clipboard: ClipboardWatcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            activeBlock
            Divider()
            profileList
            Divider()
            clipboardLogger
            Divider()
            configureLink
            Divider()
            footer
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }

    private var clipboardLogger: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save screenshots")
                        .font(.system(.body, design: .default).weight(.medium))
                    Text(clipboard.isEnabled
                         ? "Saving copied images to \(clipboard.displayPath)"
                         : "Save any image copied to the clipboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Save screenshots", isOn: $clipboard.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if clipboard.isEnabled {
                HStack(spacing: 6) {
                    if clipboard.savedCount > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.176, green: 0.290, blue: 0.208))
                        Text("\(clipboard.savedCount) saved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change folder…") {
                        clipboard.pickSaveDirectory()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    Button("Show in Finder") {
                        clipboard.revealInFinder()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                }
            }
            if let err = clipboard.lastError, clipboard.isEnabled {
                Text("Couldn't save last image: \(err)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var configureLink: some View {
        Link(destination: URL(string: "https://macropad.hrvojematosic.com/configure")!) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                Text("Configure macropad")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color(red: 0.176, green: 0.290, blue: 0.208))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            Text("matosic")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color(red: 0.176, green: 0.290, blue: 0.208)) // #2d4a35
            Spacer()
            Text("macropad")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var activeBlock: some View {
        let active = currentProfile()
        let isExplicitlyBound = !focus.bundleID.isEmpty
            && store.bindings[focus.bundleID] != nil
        return VStack(alignment: .leading, spacing: 6) {
            Text("Active app")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(focus.appName)
                .font(.system(.body, design: .default).weight(.medium))
                .lineLimit(1)

            // Entire profile row is the click target — much bigger hit area
            // than a small "Bind…" button, and matches macOS System Settings idioms.
            Menu {
                Section("Bind \(focus.appName) to") {
                    ForEach(store.profiles) { profile in
                        Button(profile.name) {
                            store.bind(
                                bundleID: focus.bundleID,
                                appName: focus.appName,
                                to: profile.name
                            )
                        }
                    }
                }
                if isExplicitlyBound {
                    Divider()
                    Button("Unbind \(focus.appName)") {
                        store.unbind(bundleID: focus.bundleID)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.176, green: 0.290, blue: 0.208))
                        .frame(width: 8, height: 8)
                    Text(active.name)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .disabled(focus.bundleID.isEmpty)

            if let hint = active.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Profiles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(store.profiles) { profile in
                HStack {
                    Text(profile.name)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    if profile.name == store.defaultProfileName {
                        Text("default")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Text(focus.bundleID.isEmpty ? "" : focus.bundleID)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func currentProfile() -> Profile {
        store.profile(forBundleID: focus.bundleID)
    }
}
