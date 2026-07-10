import Foundation
import Combine

/// Persistence + resolution front-end for the editable dictation modes.
/// Seeds the built-in catalog on first run; custom modes are stored ahead of
/// built-ins so they win resolution. The master switch reuses the original
/// `contentAwareModesEnabled` key (default on), so existing installs keep
/// their setting.
final class DictationModeStore: ObservableObject {
    static let shared = DictationModeStore()
    private static let storageKey = "dictationModeConfigsV1"
    private static let masterKey = "contentAwareModesEnabled"

    @Published var modes: [DictationModeConfig] {
        didSet { persist() }
    }

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.masterKey) }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([DictationModeConfig].self, from: data),
           !saved.isEmpty {
            modes = saved
        } else {
            modes = DictationModeCatalog.builtInModes()
        }
        isEnabled = UserDefaults.standard.object(forKey: Self.masterKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.masterKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Resolve the active mode for a dictation. Returns nil when modes are off
    /// entirely (callers then apply no snippet and show no chip).
    /// Reads the master key live because SettingsView's legacy toggle writes the
    /// same key via @AppStorage, bypassing this object's published property.
    func resolve(bundleIdentifier: String?, windowTitle: String? = nil) -> DictationModeConfig? {
        let live = UserDefaults.standard.object(forKey: Self.masterKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.masterKey)
        guard live else { return nil }
        return DictationModeResolver.resolve(
            modes: modes,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle
        )
    }

    // MARK: - Editing

    func addMode() -> DictationModeConfig {
        let mode = DictationModeConfig(name: "New Mode", icon: "sparkles")
        // Customs go ahead of built-ins so they take routing priority.
        modes.insert(mode, at: 0)
        return mode
    }

    func update(_ mode: DictationModeConfig) {
        guard let index = modes.firstIndex(where: { $0.id == mode.id }) else { return }
        modes[index] = mode
    }

    func delete(_ mode: DictationModeConfig) {
        guard !mode.isBuiltIn else { return }
        modes.removeAll { $0.id == mode.id }
    }

    /// Restores the built-in modes to catalog state, keeping custom modes.
    func restoreBuiltIns() {
        let customs = modes.filter { !$0.isBuiltIn }
        modes = customs + DictationModeCatalog.builtInModes()
    }
}
