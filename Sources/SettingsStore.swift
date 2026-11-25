import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var floatingIconEnabled: Bool {
        didSet { UserDefaults.standard.set(floatingIconEnabled, forKey: Keys.floatingIconEnabled) }
    }

    @Published var autoSkipChinese: Bool {
        didSet { UserDefaults.standard.set(autoSkipChinese, forKey: Keys.autoSkipChinese) }
    }

    @Published var smartWebCapture: Bool {
        didSet { UserDefaults.standard.set(smartWebCapture, forKey: Keys.smartWebCapture) }
    }

    @Published var isPaused: Bool = false

    private enum Keys {
        static let floatingIconEnabled = "qt.floatingIconEnabled"
        static let autoSkipChinese = "qt.autoSkipChinese"
        static let smartWebCapture = "qt.smartWebCapture"
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.floatingIconEnabled) == nil {
            defaults.set(true, forKey: Keys.floatingIconEnabled)
        }
        if defaults.object(forKey: Keys.autoSkipChinese) == nil {
            defaults.set(true, forKey: Keys.autoSkipChinese)
        }
        if defaults.object(forKey: Keys.smartWebCapture) == nil {
            defaults.set(true, forKey: Keys.smartWebCapture)
        }

        self.floatingIconEnabled = defaults.bool(forKey: Keys.floatingIconEnabled)
        self.autoSkipChinese = defaults.bool(forKey: Keys.autoSkipChinese)
        self.smartWebCapture = defaults.bool(forKey: Keys.smartWebCapture)
    }
}
