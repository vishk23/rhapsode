import SwiftUI
import AppKit

// MARK: - Modes tab (editable power modes)

/// Editor for content-aware dictation modes. The four built-ins ship with the
/// tuned defaults, so this surface is entirely optional — hands-off behavior is
/// unchanged until the user customizes something.
struct DashboardModesTab: View {
    @ObservedObject private var store = DictationModeStore.shared
    @State private var expandedID: String?
    @State private var confirmingRestore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if store.isEnabled {
                    ForEach(store.modes) { mode in
                        ModeRow(
                            mode: mode,
                            isExpanded: expandedID == mode.id,
                            onToggleExpand: {
                                expandedID = expandedID == mode.id ? nil : mode.id
                            }
                        )
                    }

                    HStack {
                        Button {
                            let mode = store.addMode()
                            expandedID = mode.id
                        } label: {
                            Label("New Mode", systemImage: "plus")
                        }
                        Spacer()
                        Button("Restore built-in defaults") { confirmingRestore = true }
                            .foregroundStyle(.secondary)
                    }
                    .controlSize(.small)
                }
            }
            .padding(24)
        }
        .alert("Restore built-in modes?", isPresented: $confirmingRestore) {
            Button("Restore", role: .destructive) { store.restoreBuiltIns() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Formal, Code, Casual, and Standard return to their defaults. Custom modes are kept.")
        }
    }

    private var header: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $store.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Content-aware modes").font(.headline)
                        Text("Dictations are cleaned differently depending on where you're typing — casual in Messages, terse in a terminal, formal in Mail. First matching mode from the top wins; custom modes outrank built-ins.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Row + editor

private struct ModeRow: View {
    @ObservedObject private var store = DictationModeStore.shared
    let mode: DictationModeConfig
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    private var matchSummary: String {
        if mode.isFallback { return "Everything else" }
        let parts = mode.bundleIdentifierMatches + mode.windowTitleMatches.map { "“\($0)”" }
        return parts.isEmpty ? "No triggers yet" : parts.prefix(6).joined(separator: ", ")
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: mode.icon.isEmpty ? "questionmark" : mode.icon)
                        .frame(width: 22)
                        .foregroundStyle(modeTint(for: mode.name))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name).font(.callout.weight(.semibold))
                        Text(matchSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { mode.isEnabled },
                        set: { var m = mode; m.isEnabled = $0; store.update(m) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(mode.isFallback)
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleExpand)

                if isExpanded {
                    ModeEditor(mode: mode)
                        .padding(.top, 12)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct ModeEditor: View {
    @ObservedObject private var store = DictationModeStore.shared
    let mode: DictationModeConfig

    @State private var name: String = ""
    @State private var icon: String = ""
    @State private var snippet: String = ""
    @State private var cleanupModel: String = ""
    @State private var newBundleMatch: String = ""
    @State private var newTitleMatch: String = ""

    private static let iconPresets = [
        "text.alignleft", "envelope", "chevron.left.forwardslash.chevron.right",
        "bubble.left", "briefcase", "graduationcap", "doc.text", "sparkles"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            HStack(spacing: 12) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(save)
                HStack(spacing: 4) {
                    ForEach(Self.iconPresets, id: \.self) { preset in
                        Button {
                            icon = preset
                            save()
                        } label: {
                            Image(systemName: preset)
                                .frame(width: 20, height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(icon == preset ? Color.accentColor.opacity(0.25) : .clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !mode.isFallback {
                triggerSection
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Cleanup style").font(.caption.weight(.semibold))
                TextEditor(text: $snippet)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                Text("Appended to the cleanup prompt. Be explicit — soft hints lose to the base rules (say what this OVERRIDES).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup model override").font(.caption.weight(.semibold))
                    TextField("Default model", text: $cleanupModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit(save)
                }
                Spacer()
                Button("Save") { save() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                if !mode.isBuiltIn {
                    Button(role: .destructive) {
                        store.delete(mode)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: mode.id) { _ in load() }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apps (bundle-id contains)").font(.caption.weight(.semibold))
                matchChips(
                    values: mode.bundleIdentifierMatches,
                    remove: { value in
                        var m = currentMode()
                        m.bundleIdentifierMatches.removeAll { $0 == value }
                        store.update(m)
                    }
                )
                HStack(spacing: 6) {
                    TextField("e.g. com.apple.mail or just \u{201C}mail\u{201D}", text: $newBundleMatch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit(addBundleMatch)
                    Button("Add") { addBundleMatch() }
                        .controlSize(.small)
                        .disabled(newBundleMatch.trimmingCharacters(in: .whitespaces).isEmpty)
                    Menu("Running apps") {
                        ForEach(runningApps(), id: \.self) { bundleID in
                            Button(bundleID) {
                                var m = currentMode()
                                if !m.bundleIdentifierMatches.contains(bundleID) {
                                    m.bundleIdentifierMatches.append(bundleID)
                                    store.update(m)
                                }
                            }
                        }
                    }
                    .controlSize(.small)
                    .frame(width: 130)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Window title contains (for web apps)").font(.caption.weight(.semibold))
                matchChips(
                    values: mode.windowTitleMatches,
                    remove: { value in
                        var m = currentMode()
                        m.windowTitleMatches.removeAll { $0 == value }
                        store.update(m)
                    }
                )
                HStack(spacing: 6) {
                    TextField("e.g. gmail, jira, notion", text: $newTitleMatch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                        .onSubmit(addTitleMatch)
                    Button("Add") { addTitleMatch() }
                        .controlSize(.small)
                        .disabled(newTitleMatch.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func matchChips(values: [String], remove: @escaping (String) -> Void) -> some View {
        FlowLayoutLite(items: values) { value in
            HStack(spacing: 3) {
                Text(value).font(.caption)
                Button { remove(value) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }

    private func runningApps() -> [String] {
        Array(Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
        )).sorted()
    }

    private func currentMode() -> DictationModeConfig {
        store.modes.first { $0.id == mode.id } ?? mode
    }

    private func load() {
        let m = currentMode()
        name = m.name
        icon = m.icon
        snippet = m.promptSnippet
        cleanupModel = m.cleanupModel
    }

    private func save() {
        var m = currentMode()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { m.name = trimmedName }
        if !icon.isEmpty { m.icon = icon }
        m.promptSnippet = snippet
        m.cleanupModel = cleanupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        store.update(m)
    }

    private func addBundleMatch() {
        let value = newBundleMatch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        var m = currentMode()
        if !m.bundleIdentifierMatches.contains(value) {
            m.bundleIdentifierMatches.append(value)
            store.update(m)
        }
        newBundleMatch = ""
    }

    private func addTitleMatch() {
        let value = newTitleMatch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        var m = currentMode()
        if !m.windowTitleMatches.contains(value) {
            m.windowTitleMatches.append(value)
            store.update(m)
        }
        newTitleMatch = ""
    }
}

/// Mirrors the recording-pill chip colors so the editor and the pill agree.
private func modeTint(for modeName: String) -> Color {
    switch modeName {
    case "Formal":   return .blue
    case "Code":     return .purple
    case "Casual":   return .orange
    case "Standard": return .secondary
    default:         return .teal
    }
}

/// Minimal wrapping layout for match chips — avoids pulling in a Layout
/// dependency for a handful of capsules.
private struct FlowLayoutLite<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            // Chips are short; a few per row in an HStack-wrapped grid is enough.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 220), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { content($0) }
            }
        }
    }
}
