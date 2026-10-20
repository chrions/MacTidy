import Foundation

/// A user-facing string from the app's translation tables. The English text is both the key and the fallback,
/// so the command-line tool (which has no tables) prints English.
func L(_ key: String.LocalizationValue) -> String { String(localized: key) }

enum AppLanguage {
    /// Languages with a translation table, besides English.
    static let translated = ["zh-Hans", "ja", "ko"]

    /// The language the interface is shown in right now.
    static var current: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// English name of the current language, e.g. "Japanese", for telling the AI what to answer in.
    static var englishName: String {
        Locale(identifier: "en").localizedString(forIdentifier: current) ?? "English"
    }
}
