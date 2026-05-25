// ConfigureSheet.swift
//
// The configure sheet shown when the user clicks "Screen Saver
// Options…" in System Settings. Programmatic AppKit — no XIBs, no
// SwiftUI — so it works reliably inside .saver bundles.
//
// Phase 6 controls (plan §2.4):
//   • Resource folder picker  (required to run)
//   • Sound on/off
//   • Animation speed         (0.5× / 1× / 1.5× / 2×)
//   • Story day               (Auto / 1–30)
//   • Force holiday           (Off / Halloween / St Patrick / Christmas / NY)
//   • Engine fidelity mode    (Fixed / Raw)
//   • Show debug overlay      (Off / On)
//
// Note: a security-scoped bookmark is created by save() ONLY when running
// inside legacyScreenSaver — see ResourceFolder.swift.  In this sheet
// (System Settings extension process), save() persists the plain path
// only; the first-run panel running inside legacyScreenSaver creates the
// bookmark on first activation.

import AppKit
import ScreenSaver
import JohnnyEngine

@MainActor
final class ConfigureSheetController: NSObject {

    static let shared = ConfigureSheetController()

    private(set) lazy var window: NSWindow = makeWindow()

    private var statusLabel:    NSTextField!
    private var pathLabel:      NSTextField!
    private var soundCheckbox:  NSButton!
    private var remasteredAudioCheckbox: NSButton!
    private var speedPopup:     NSPopUpButton!
    private var dayPopup:       NSPopUpButton!
    private var holidayPopup:   NSPopUpButton!
    private var fidelityPopup:  NSPopUpButton!
    private var scalingPopup:   NSPopUpButton!
    private var crtCheckbox:    NSButton!
    private var clockCheckbox:  NSButton!
    private var batteryCheckbox:NSButton!
    private var debugCheckbox:  NSButton!

    // Layout constants — single source of truth so we can adjust the
    // window height by tweaking just the row count.
    private let leftMargin:   CGFloat = 20
    private let labelWidth:   CGFloat = 130
    private let controlX:     CGFloat = 160
    private let controlWidth: CGFloat = 300
    private let rowHeight:    CGFloat = 32
    private let sectionGap:   CGFloat = 14

    // ---------------------------------------------------------------
    // MARK: Window construction
    // ---------------------------------------------------------------

    private func makeWindow() -> NSWindow {
        let H: CGFloat = 626
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: H),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        win.title = "Johnny Castaway"
        win.isReleasedWhenClosed = false

        let content = NSView(frame: win.contentLayoutRect)
        win.contentView = content

        // AppKit origin is bottom-left; we lay out top-down by tracking `y`
        // and decrementing as we go.
        var y = H

        // ---- Resources section ----------------------------------------

        y -= 28
        addBoldLabel("Sierra Resource Files", to: content, x: leftMargin, y: y, w: 440)
        y -= 44
        let desc = NSTextField(wrappingLabelWithString:
            "Johnny Castaway requires the original Sierra resource files. "
          + "Choose the folder that contains RESOURCE.MAP and RESOURCE.001."
        )
        desc.frame = NSRect(x: leftMargin, y: y, width: 440, height: 40)
        content.addSubview(desc)
        y -= 22
        pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.frame = NSRect(x: leftMargin, y: y, width: 440, height: 16)
        content.addSubview(pathLabel)
        y -= 22
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.frame = NSRect(x: leftMargin, y: y, width: 440, height: 16)
        content.addSubview(statusLabel)

        y -= sectionGap
        addSeparator(to: content, y: y)

        // ---- Audio section --------------------------------------------

        y -= 24
        addBoldLabel("Audio", to: content, x: leftMargin, y: y, w: 440)
        y -= 26
        soundCheckbox = NSButton(
            checkboxWithTitle: "Enable sounds",
            target: self,
            action: #selector(soundToggled)
        )
        soundCheckbox.frame = NSRect(x: leftMargin, y: y, width: 440, height: 22)
        soundCheckbox.state = ResourceFolder.soundEnabled ? .on : .off
        content.addSubview(soundCheckbox)

        y -= 26
        remasteredAudioCheckbox = NSButton(
            checkboxWithTitle: "Use remastered audio (if present in 'remastered' subfolder)",
            target: self,
            action: #selector(remasteredAudioToggled)
        )
        remasteredAudioCheckbox.frame = NSRect(x: leftMargin, y: y, width: 440, height: 22)
        remasteredAudioCheckbox.state = ResourceFolder.useRemasteredAudio ? .on : .off
        content.addSubview(remasteredAudioCheckbox)

        y -= sectionGap
        addSeparator(to: content, y: y)

        // ---- Playback section -----------------------------------------

        y -= 24
        addBoldLabel("Playback", to: content, x: leftMargin, y: y, w: 440)

        y -= rowHeight
        speedPopup = makePopup(
            target: #selector(speedChanged),
            items: ["0.5×", "1.0× (faithful)", "1.5×", "2.0×"],
            tags:  [50, 100, 150, 200]
        )
        speedPopup.selectItem(withTag: speedTag(for: ResourceFolder.animationSpeed))
        addRow(label: "Animation speed:", control: speedPopup, to: content, y: y)

        y -= rowHeight
        let dayItems = ["Auto"] + (1...30).map { String($0) }
        let dayTags  = [0]    + Array(1...30)
        dayPopup = makePopup(
            target: #selector(dayChanged),
            items: dayItems,
            tags:  dayTags
        )
        dayPopup.selectItem(withTag: ResourceFolder.forceStoryDay)
        addRow(label: "Story day:", control: dayPopup, to: content, y: y)

        y -= rowHeight
        holidayPopup = makePopup(
            target: #selector(holidayChanged),
            items: ["Off (use today)", "Halloween", "St Patrick's Day", "Christmas", "New Year"],
            tags:  [0, 1, 2, 3, 4]
        )
        holidayPopup.selectItem(withTag: ResourceFolder.forceHoliday)
        addRow(label: "Force holiday:", control: holidayPopup, to: content, y: y)

        y -= rowHeight
        fidelityPopup = makePopup(
            target: #selector(fidelityChanged),
            items: ["Fixed (Go corrections)", "Raw (jc_reborn)"],
            tags:  [0, 1]
        )
        fidelityPopup.selectItem(withTag: ResourceFolder.fidelityMode == .fixed ? 0 : 1)
        addRow(label: "Engine fidelity:", control: fidelityPopup, to: content, y: y)

        y -= rowHeight
        scalingPopup = makePopup(
            target: #selector(scalingChanged),
            items: ["Fit (keep background)", "Fill (fullscreen cropped)"],
            tags:  [0, 1]
        )
        scalingPopup.selectItem(withTag: ResourceFolder.scalingMode == .fit ? 0 : 1)
        addRow(label: "Scaling mode:", control: scalingPopup, to: content, y: y)

        y -= 26
        crtCheckbox = NSButton(
            checkboxWithTitle: "Enable retro CRT filter (scanlines, screen curvature)",
            target: self,
            action: #selector(crtToggled)
        )
        crtCheckbox.frame = NSRect(x: leftMargin, y: y, width: 440, height: 22)
        crtCheckbox.state = ResourceFolder.crtFilterEnabled ? .on : .off
        content.addSubview(crtCheckbox)

        y -= 26
        clockCheckbox = NSButton(
            checkboxWithTitle: "Show retro digital clock",
            target: self,
            action: #selector(clockToggled)
        )
        clockCheckbox.frame = NSRect(x: leftMargin, y: y, width: 440, height: 22)
        clockCheckbox.state = ResourceFolder.clockOverlayEnabled ? .on : .off
        content.addSubview(clockCheckbox)

        y -= 26
        batteryCheckbox = NSButton(
            checkboxWithTitle: "Optimize battery on low charge (reduce FPS under 20%)",
            target: self,
            action: #selector(batteryToggled)
        )
        batteryCheckbox.frame = NSRect(x: leftMargin, y: y, width: 440, height: 22)
        batteryCheckbox.state = ResourceFolder.batterySavingEnabled ? .on : .off
        content.addSubview(batteryCheckbox)

        y -= sectionGap
        addSeparator(to: content, y: y)

        // ---- Debug section --------------------------------------------

        y -= 26
        debugCheckbox = NSButton(
            checkboxWithTitle: "Show debug overlay",
            target: self,
            action: #selector(debugToggled)
        )
        debugCheckbox.frame = NSRect(x: leftMargin, y: y, width: 440, height: 22)
        debugCheckbox.state = ResourceFolder.debugOverlayEnabled ? .on : .off
        content.addSubview(debugCheckbox)

        // ---- Action buttons (anchored to bottom) ----------------------

        let choose = NSButton(
            title: "Choose Folder…",
            target: self,
            action: #selector(chooseClicked)
        )
        choose.bezelStyle = .rounded
        choose.frame = NSRect(x: leftMargin, y: 12, width: 140, height: 32)
        content.addSubview(choose)

        let done = NSButton(
            title: "Done",
            target: self,
            action: #selector(doneClicked)
        )
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 360, y: 12, width: 100, height: 32)
        content.addSubview(done)

        refreshLabels()
        
        // Temporary debug log to trace sandbox behavior
        let debugMsg = """
        [Debug] makeWindow called
        [Debug] Bundle ID: \(Bundle(for: JohnnyScreenSaverView.self).bundleIdentifier ?? "nil")
        [Debug] Process Name: \(ProcessInfo.processInfo.processName)
        [Debug] soundEnabled: \(ResourceFolder.soundEnabled)
        [Debug] displayPath: \(ResourceFolder.displayPath ?? "nil")
        \n
        """
        try? debugMsg.write(toFile: "/tmp/johnny_debug.log", atomically: true, encoding: .utf8)

        return win
    }

    // ---------------------------------------------------------------
    // MARK: Layout helpers
    // ---------------------------------------------------------------

    private func addBoldLabel(_ text: String, to view: NSView, x: CGFloat, y: CGFloat, w: CGFloat) {
        let lbl = NSTextField(labelWithString: text)
        lbl.font  = .boldSystemFont(ofSize: 14)
        lbl.frame = NSRect(x: x, y: y, width: w, height: 20)
        view.addSubview(lbl)
    }

    private func addSeparator(to view: NSView, y: CGFloat) {
        let s = NSBox()
        s.boxType = .separator
        s.frame = NSRect(x: leftMargin, y: y, width: 440, height: 1)
        view.addSubview(s)
    }

    private func addRow(label text: String, control: NSView, to view: NSView, y: CGFloat) {
        let lbl = NSTextField(labelWithString: text)
        lbl.font      = .systemFont(ofSize: 12)
        lbl.alignment = .right
        lbl.frame     = NSRect(x: leftMargin, y: y + 4, width: labelWidth, height: 18)
        view.addSubview(lbl)
        control.frame = NSRect(x: controlX, y: y, width: controlWidth, height: 26)
        view.addSubview(control)
    }

    private func makePopup(target action: Selector, items: [String], tags: [Int]) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.target = self
        p.action = action
        for (i, title) in items.enumerated() {
            p.addItem(withTitle: title)
            p.itemArray.last?.tag = tags[i]
        }
        return p
    }

    /// Map an animation-speed Double to its popup tag (×100 to fit Int).
    private func speedTag(for v: Double) -> Int {
        let candidates = [50, 100, 150, 200]
        let target = Int((v * 100).rounded())
        return candidates.min(by: { abs($0 - target) < abs($1 - target) }) ?? 100
    }

    func refreshLabels() {
        guard soundCheckbox != nil else { return }
        if let path = ResourceFolder.displayPath {
            pathLabel.stringValue = "Configured: \(path)"
            pathLabel.textColor   = .secondaryLabelColor
        } else {
            pathLabel.stringValue = "Not configured."
            pathLabel.textColor   = .systemOrange
        }
        statusLabel.stringValue = ""
        soundCheckbox.state = ResourceFolder.soundEnabled ? .on : .off
        remasteredAudioCheckbox.state = ResourceFolder.useRemasteredAudio ? .on : .off
        scalingPopup.selectItem(withTag: ResourceFolder.scalingMode == .fit ? 0 : 1)
        crtCheckbox.state = ResourceFolder.crtFilterEnabled ? .on : .off
        clockCheckbox.state = ResourceFolder.clockOverlayEnabled ? .on : .off
        batteryCheckbox.state = ResourceFolder.batterySavingEnabled ? .on : .off
        debugCheckbox.state = ResourceFolder.debugOverlayEnabled ? .on : .off
    }

    // ---------------------------------------------------------------
    // MARK: Actions
    // ---------------------------------------------------------------

    @objc private func chooseClicked() {
        let panel = NSOpenPanel()
        panel.message                 = "Select the folder containing RESOURCE.MAP and RESOURCE.001"
        panel.prompt                  = "Choose"
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        if let stored = ResourceFolder.displayPath {
            panel.directoryURL = URL(fileURLWithPath: stored).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try ResourceFolder.save(folder: url)
            refreshLabels()
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func soundToggled() {
        let oldVal = ResourceFolder.soundEnabled
        let newVal = (soundCheckbox.state == .on)
        ResourceFolder.soundEnabled = newVal
        
        let appendMsg = "[Debug] soundToggled: oldVal=\(oldVal) newVal=\(newVal) verify=\(ResourceFolder.soundEnabled)\n"
        if let fileHandle = FileHandle(forWritingAtPath: "/tmp/johnny_debug.log") {
            fileHandle.seekToEndOfFile()
            if let data = appendMsg.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        }
    }

    @objc private func remasteredAudioToggled() {
        ResourceFolder.useRemasteredAudio = (remasteredAudioCheckbox.state == .on)
    }

    @objc private func debugToggled() {
        ResourceFolder.debugOverlayEnabled = (debugCheckbox.state == .on)
    }

    @objc private func speedChanged() {
        let tag = speedPopup.selectedTag()
        ResourceFolder.animationSpeed = Double(tag) / 100.0
    }

    @objc private func dayChanged() {
        ResourceFolder.forceStoryDay = dayPopup.selectedTag()
    }

    @objc private func holidayChanged() {
        ResourceFolder.forceHoliday = holidayPopup.selectedTag()
    }

    @objc private func fidelityChanged() {
        ResourceFolder.fidelityMode = (fidelityPopup.selectedTag() == 0) ? .fixed : .raw
    }

    @objc private func scalingChanged() {
        ResourceFolder.scalingMode = (scalingPopup.selectedTag() == 0) ? .fit : .fill
    }

    @objc private func crtToggled() {
        ResourceFolder.crtFilterEnabled = (crtCheckbox.state == .on)
    }

    @objc private func clockToggled() {
        ResourceFolder.clockOverlayEnabled = (clockCheckbox.state == .on)
    }

    @objc private func batteryToggled() {
        ResourceFolder.batterySavingEnabled = (batteryCheckbox.state == .on)
    }

    @objc private func doneClicked() {
        if let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        } else {
            window.orderOut(nil)
        }
    }
}
