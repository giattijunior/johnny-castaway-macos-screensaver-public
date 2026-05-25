// ResourceFolder.swift
//
// Persists the user's chosen Sierra resource folder path and options in a JSON file
// inside the sandboxed Application Support directory.
//
// In macOS Sonoma and Sequoia, System Settings and legacyScreenSaver run in separate
// processes. Using ScreenSaverDefaults (which redirects to process-specific sandbox containers
// or fails to write due to sandboxing restrictions) leads to clobbering and non-persisting
// values when both processes synchronize.
//
// Solution:
//   • Both the Configure sheet process and the legacyScreenSaver process run under the
//     same com.apple.ScreenSaver.Engine.legacyScreenSaver sandbox container, sharing
//     the same Application Support directory.
//   • We write all preferences (Sound, Speed, Overlay, Story Day, Holiday, and the folder path/bookmark)
//     to a single `settings.json` inside Application Support. This acts as the single source
//     of truth and completely resolves any multi-process clobbering.
//   • A migration layer is included to read from the old ScreenSaverDefaults if the JSON file
//     does not exist yet.

import Foundation
import AppKit
import ScreenSaver
import JohnnyEngine
import JohnnyMetalRenderer

enum ResourceFolder {

    private static let pathKey            = "ResourceFolderPath"
    private static let bookmarkKey        = "ResourceFolderBookmark"
    private static let soundEnabledKey    = "SoundEnabled"
    private static let animationSpeedKey  = "AnimationSpeed"
    private static let storyDayKey        = "ForceStoryDay"
    private static let forceHolidayKey    = "ForceHoliday"
    private static let fidelityModeKey    = "FidelityMode"
    private static let debugOverlayKey    = "ShowDebugOverlay"
    private static let scalingModeKey     = "ScalingMode"
    private static let crtFilterKey       = "CrtFilterEnabled"
    private static let clockOverlayKey    = "ClockOverlayEnabled"
    private static let batterySavingKey   = "BatterySavingEnabled"
    private static let useRemasteredAudioKey = "UseRemasteredAudio"
    private static let progressDayKey     = "ProgressStoryDay"
    private static let progressCalDayKey  = "ProgressLastCalendarDay"

    // Legacy ScreenSaverDefaults fallback for migration
    private nonisolated(unsafe) static let sharedDefaults: UserDefaults = {
        let id = Bundle(for: JohnnyScreenSaverView.self).bundleIdentifier
                     ?? "nz.petesmith.JohnnyScreenSaver"
        if let sd = ScreenSaverDefaults(forModuleWithName: id) {
            return sd
        }
        return .standard
    }()

    /// The URL whose security scope is currently active.
    /// Non-nil only after a successful resolve() in legacyScreenSaver.
    /// Cleared by stopAccessing().
    private nonisolated(unsafe) static var activeSecurityScopedURL: URL? = nil

    // ---------------------------------------------------------------
    // MARK: JSON Storage Model
    // ---------------------------------------------------------------

    private struct SettingsData: Codable {
        var resourceFolderPath: String?
        var resourceFolderBookmark: Data?
        var soundEnabled: Bool = false
        var animationSpeed: Double = 1.0
        var forceStoryDay: Int = 0
        var forceHoliday: Int = 0
        var fidelityMode: String = "fixed"
        var scalingMode: String = "fit"
        var crtFilterEnabled: Bool = false
        var clockOverlayEnabled: Bool = false
        var batterySavingEnabled: Bool = true
        var useRemasteredAudio: Bool = false
        var showDebugOverlay: Bool = false
        var progressStoryDay: Int = 1
        var progressLastCalendarDay: Int = -1
    }

    private static var settingsURL: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("nz.petesmith.JohnnyScreenSaver", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("settings.json")
    }

    private static func loadSettings() -> SettingsData {
        let url = settingsURL
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            // Attempt to migrate from legacy defaults on first launch
            return migrateFromDefaults()
        }
        return settings
    }

    private static func saveSettings(_ settings: SettingsData) {
        let url = settingsURL
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[Johnny] ResourceFolder: Failed to write settings to JSON — %@", error.localizedDescription)
        }
    }

    private static func migrateFromDefaults() -> SettingsData {
        var settings = SettingsData()
        NSLog("[Johnny] ResourceFolder: migrating preferences from ScreenSaverDefaults")
        
        if let path = sharedDefaults.string(forKey: pathKey) {
            settings.resourceFolderPath = path
        }
        if let bookmark = sharedDefaults.data(forKey: bookmarkKey) {
            settings.resourceFolderBookmark = bookmark
        }
        settings.soundEnabled = sharedDefaults.object(forKey: soundEnabledKey) != nil ? sharedDefaults.bool(forKey: soundEnabledKey) : false
        settings.animationSpeed = sharedDefaults.object(forKey: animationSpeedKey) != nil ? sharedDefaults.double(forKey: animationSpeedKey) : 1.0
        settings.forceStoryDay = sharedDefaults.integer(forKey: storyDayKey)
        settings.forceHoliday = sharedDefaults.integer(forKey: forceHolidayKey)
        if let raw = sharedDefaults.string(forKey: fidelityModeKey) {
            settings.fidelityMode = raw
        }
        if let rawScaling = sharedDefaults.string(forKey: scalingModeKey) {
            settings.scalingMode = rawScaling
        }
        settings.crtFilterEnabled = sharedDefaults.object(forKey: crtFilterKey) != nil ? sharedDefaults.bool(forKey: crtFilterKey) : false
        settings.clockOverlayEnabled = sharedDefaults.object(forKey: clockOverlayKey) != nil ? sharedDefaults.bool(forKey: clockOverlayKey) : false
        settings.batterySavingEnabled = sharedDefaults.object(forKey: batterySavingKey) != nil ? sharedDefaults.bool(forKey: batterySavingKey) : true
        settings.useRemasteredAudio = sharedDefaults.object(forKey: useRemasteredAudioKey) != nil ? sharedDefaults.bool(forKey: useRemasteredAudioKey) : false
        settings.progressStoryDay = sharedDefaults.object(forKey: progressDayKey) != nil ? sharedDefaults.integer(forKey: progressDayKey) : 1
        settings.progressLastCalendarDay = sharedDefaults.object(forKey: progressCalDayKey) != nil ? sharedDefaults.integer(forKey: progressCalDayKey) : -1
        
        saveSettings(settings)
        return settings
    }

    // ---------------------------------------------------------------
    // MARK: Public API
    // ---------------------------------------------------------------

    /// Return the URL of the configured resource folder if it exists
    /// and contains RESOURCE.MAP. Returns nil if not configured or
    /// the folder has been moved / deleted.
    static func resolve() -> URL? {
        if let url = activeSecurityScopedURL {
            NSLog("[Johnny] ResourceFolder.resolve: returning active scoped URL %@", url.path)
            return url
        }

        // ---- 0. Check if resources are embedded in the bundle itself -------
        let bundle = Bundle(for: JohnnyScreenSaverView.self)
        if let embeddedURL = bundle.url(forResource: "RESOURCE", withExtension: "MAP")?.deletingLastPathComponent() {
            let containerURL = embeddedURL.appendingPathComponent("RESOURCE.001")
            if FileManager.default.fileExists(atPath: containerURL.path) {
                NSLog("[Johnny] ResourceFolder.resolve: Using embedded resources in bundle at %@", embeddedURL.path)
                return embeddedURL
            }
        }

        let settings = loadSettings()


        // ---- 1. Try security-scoped bookmark --------------------------------
        if let data = settings.resourceFolderBookmark {
            NSLog("[Johnny] ResourceFolder.resolve: found bookmark data (%d bytes) in JSON", data.count)
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: data,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
                NSLog("[Johnny] ResourceFolder.resolve: bookmark resolved stale=%d path=%@",
                      isStale ? 1 : 0, url.path)
                let started = url.startAccessingSecurityScopedResource()
                NSLog("[Johnny] ResourceFolder.resolve: startAccessingSecurityScopedResource=%d",
                      started ? 1 : 0)
                let mapURL = url.appendingPathComponent("RESOURCE.MAP")
                if FileManager.default.fileExists(atPath: mapURL.path) {
                    activeSecurityScopedURL = url
                    if isStale {
                        // Renew the bookmark while we still have access.
                        if let newData = try? url.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        ) {
                            var s = settings
                            s.resourceFolderBookmark = newData
                            saveSettings(s)
                            NSLog("[Johnny] ResourceFolder.resolve: refreshed stale bookmark")
                        }
                    }
                    NSLog("[Johnny] ResourceFolder.resolve: bookmark OK → %@", url.path)
                    return url
                } else {
                    url.stopAccessingSecurityScopedResource()
                    NSLog("[Johnny] ResourceFolder.resolve: RESOURCE.MAP missing at %@", url.path)
                }
            } catch {
                NSLog("[Johnny] ResourceFolder.resolve: bookmark resolution failed — %@",
                      error.localizedDescription)
            }
        } else {
            NSLog("[Johnny] ResourceFolder.resolve: no bookmark data in JSON")
        }

        // ---- 2. Fall back to plain path (unsandboxed contexts) --------------
        guard let path = settings.resourceFolderPath else {
            NSLog("[Johnny] ResourceFolder.resolve: no path in JSON")
            return nil
        }
        NSLog("[Johnny] ResourceFolder.resolve: trying plain path %@", path)
        let url    = URL(fileURLWithPath: path)
        let mapURL = url.appendingPathComponent("RESOURCE.MAP")
        guard FileManager.default.fileExists(atPath: mapURL.path) else {
            NSLog("[Johnny] ResourceFolder.resolve: RESOURCE.MAP not found at plain path")
            return nil
        }
        NSLog("[Johnny] ResourceFolder.resolve: plain path OK → %@", url.path)
        return url
    }

    /// Stop accessing the security-scoped resource started by resolve().
    static func stopAccessing() {
        guard let url = activeSecurityScopedURL else { return }
        url.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
        NSLog("[Johnny] ResourceFolder.stopAccessing: done")
    }

    /// The display path of the configured folder.
    static var displayPath: String? {
        loadSettings().resourceFolderPath
    }

    /// Persist the user-picked folder path.
    static func save(folder url: URL) throws {
        NSLog("[Johnny] ResourceFolder.save: validating %@", url.path)
        let fm = FileManager.default
        let mapURL  = url.appendingPathComponent("RESOURCE.MAP")
        let dataURL = url.appendingPathComponent("RESOURCE.001")
        guard fm.fileExists(atPath: mapURL.path)  else { throw FolderError.missingFile("RESOURCE.MAP")  }
        guard fm.fileExists(atPath: dataURL.path) else { throw FolderError.missingFile("RESOURCE.001") }

        var settings = loadSettings()
        settings.resourceFolderPath = url.path

        let procName = ProcessInfo.processInfo.processName
        NSLog("[Johnny] ResourceFolder.save: processName=%@", procName)

        let isLegacyHost = procName.lowercased().contains("legacyscreensaver") || procName.lowercased().contains("wallpaperlegacyextension")
        if isLegacyHost {
            do {
                let data = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                settings.resourceFolderBookmark = data
                NSLog("[Johnny] ResourceFolder.save: security-scoped bookmark created (%d bytes)", data.count)
                activeSecurityScopedURL = nil
            } catch {
                NSLog("[Johnny] ResourceFolder.save: bookmark creation failed — %@",
                      error.localizedDescription)
            }
        } else {
            NSLog("[Johnny] ResourceFolder.save: non-legacyScreenSaver context — bookmark unchanged")
        }

        saveSettings(settings)
    }

    /// Whether the user has sound enabled.
    static var soundEnabled: Bool {
        get { loadSettings().soundEnabled }
        set {
            var s = loadSettings()
            s.soundEnabled = newValue
            saveSettings(s)
            NSLog("[Johnny] ResourceFolder.soundEnabled = %d (JSON)", newValue ? 1 : 0)
        }
    }

    /// Forget the saved folder (and any active security scope).
    static func clear() {
        stopAccessing()
        var s = loadSettings()
        s.resourceFolderPath = nil
        s.resourceFolderBookmark = nil
        saveSettings(s)
        NSLog("[Johnny] ResourceFolder.clear: done")
    }

    // ---------------------------------------------------------------
    // MARK: Option Properties
    // ---------------------------------------------------------------

    /// Animation speed multiplier; 1.0 = faithful pacing.
    static var animationSpeed: Double {
        get { loadSettings().animationSpeed }
        set {
            var s = loadSettings()
            s.animationSpeed = newValue
            saveSettings(s)
        }
    }

    /// Story-day override. 0 means auto, 1–30 = pinned day.
    static var forceStoryDay: Int {
        get { loadSettings().forceStoryDay }
        set {
            var s = loadSettings()
            s.forceStoryDay = newValue
            saveSettings(s)
        }
    }

    /// Force-holiday override. 0=Off, 1=Halloween, 2=St Patrick, 3=Christmas, 4=New Year.
    static var forceHoliday: Int {
        get { loadSettings().forceHoliday }
        set {
            var s = loadSettings()
            s.forceHoliday = newValue
            saveSettings(s)
        }
    }

    /// Engine fidelity mode.
    static var fidelityMode: FidelityMode {
        get {
            let raw = loadSettings().fidelityMode
            return FidelityMode(rawValue: raw) ?? .fixed
        }
        set {
            var s = loadSettings()
            s.fidelityMode = newValue.rawValue
            saveSettings(s)
        }
    }

    /// Whether the debug overlay is shown.
    static var debugOverlayEnabled: Bool {
        get { loadSettings().showDebugOverlay }
        set {
            var s = loadSettings()
            s.showDebugOverlay = newValue
            saveSettings(s)
        }
    }

    /// The scaling mode (fit or fill).
    static var scalingMode: ScalingMode {
        get {
            let raw = loadSettings().scalingMode
            return ScalingMode(rawValue: raw) ?? .fit
        }
        set {
            var s = loadSettings()
            s.scalingMode = newValue.rawValue
            saveSettings(s)
            NSLog("[Johnny] ResourceFolder.scalingMode = %@ (JSON)", newValue.rawValue)
        }
    }

    /// Whether the CRT filter is enabled.
    static var crtFilterEnabled: Bool {
        get { loadSettings().crtFilterEnabled }
        set {
            var s = loadSettings()
            s.crtFilterEnabled = newValue
            saveSettings(s)
            NSLog("[Johnny] ResourceFolder.crtFilterEnabled = %d (JSON)", newValue ? 1 : 0)
        }
    }

    /// Whether the clock overlay is enabled.
    static var clockOverlayEnabled: Bool {
        get { loadSettings().clockOverlayEnabled }
        set {
            var s = loadSettings()
            s.clockOverlayEnabled = newValue
            saveSettings(s)
            NSLog("[Johnny] ResourceFolder.clockOverlayEnabled = %d (JSON)", newValue ? 1 : 0)
        }
    }

    /// Whether battery saving mode is enabled.
    static var batterySavingEnabled: Bool {
        get { loadSettings().batterySavingEnabled }
        set {
            var s = loadSettings()
            s.batterySavingEnabled = newValue
            saveSettings(s)
            NSLog("[Johnny] ResourceFolder.batterySavingEnabled = %d (JSON)", newValue ? 1 : 0)
        }
    }

    /// Whether to use remastered audio files from the 'remastered' subfolder.
    static var useRemasteredAudio: Bool {
        get { loadSettings().useRemasteredAudio }
        set {
            var s = loadSettings()
            s.useRemasteredAudio = newValue
            saveSettings(s)
            NSLog("[Johnny] ResourceFolder.useRemasteredAudio = %d (JSON)", newValue ? 1 : 0)
        }
    }

    // ---------------------------------------------------------------
    // MARK: Holiday-date synthesis (for forceHoliday)
    // ---------------------------------------------------------------

    static func dateForForcedHoliday(_ holiday: Int) -> Date? {
        guard holiday >= 1 && holiday <= 4 else { return nil }
        var comps = Calendar.current.dateComponents([.year, .hour], from: Date())
        comps.hour = 12
        switch holiday {
        case 1: comps.month = 10; comps.day = 31  // Halloween
        case 2: comps.month =  3; comps.day = 17  // St Patrick
        case 3: comps.month = 12; comps.day = 24  // Christmas
        case 4: comps.month = 12; comps.day = 31  // New Year
        default: return nil
        }
        return Calendar.current.date(from: comps)
    }

    // ---------------------------------------------------------------
    // MARK: Story-arc persistence
    // ---------------------------------------------------------------

    /// The persisted story day from a prior activation, or 1 if unset.
    static var persistedStoryDay: Int {
        let raw = loadSettings().progressStoryDay
        return max(1, min(11, raw))
    }

    /// The persisted day-of-year when the story day was last advanced, or -1.
    static var persistedLastCalendarDay: Int {
        loadSettings().progressLastCalendarDay
    }

    /// Save the engine's natural-progression state for the next activation.
    static func saveStoryProgress(day: Int, lastCalendarDay: Int) {
        var s = loadSettings()
        s.progressStoryDay = day
        s.progressLastCalendarDay = lastCalendarDay
        saveSettings(s)
    }

    /// Reset the persisted story arc.
    static func clearStoryProgress() {
        var s = loadSettings()
        s.progressStoryDay = 1
        s.progressLastCalendarDay = -1
        saveSettings(s)
        NSLog("[Johnny] ResourceFolder.clearStoryProgress: done")
    }

    // ---------------------------------------------------------------
    // MARK: Errors
    // ---------------------------------------------------------------

    enum FolderError: LocalizedError {
        case missingFile(String)
        var errorDescription: String? {
            switch self {
            case .missingFile(let name):
                return "Folder is missing \(name). Pick the folder that contains both RESOURCE.MAP and RESOURCE.001."
            }
        }
    }
}
