// JohnnyScreensaverExtension.swift
//
// Tahoe-era (.appex / ExtensionKit) entry point for the Johnny Castaway
// screensaver. This file is the dual of JohnnyScreenSaverView.swift:
//
//   • .saver legacy host (legacyScreenSaver)  →  JohnnyScreenSaverView
//     is loaded directly by CFBundle as the principal class via
//     Info.plist's NSPrincipalClass.
//
//   • .appex Tahoe host (ExtensionKit)        →  THIS file's
//     JohnnyScreensaverExtension is the NSExtensionPrincipalClass
//     (per com.apple.screensaver extension point), and it returns a
//     JohnnyScreensaverViewController whose `.view` IS a
//     JohnnyScreenSaverView (the same Metal-rendering view the
//     legacy host uses).
//
// Why a thin wrapper and not a rewrite: the engine, renderer, and
// scene scheduler are all internal Swift. The view alone (~1000 LOC)
// owns the CAMetalLayer lifecycle, story runner, sound sink, and
// battery-saving frame throttle. Recreating that surface in a
// dedicated view controller would duplicate work and risk drift;
// instead we embed the existing ScreenSaverView as the `.view` of
// a Tahoe view controller. The Tahoe host draws the controller's
// view into the fullscreen / preview window, lifecycle wiring goes
// through startAnimation / stopAnimation on the embedded view, and
// the configure sheet is provided via the controller's
// `configureSheet` property (per the screen saver view controller
// contract — see Arabesque.appex in /System/Library).
//
// The two host paths therefore share the entire rendering / engine
// surface; only the lifecycle wrapper changes.

import Foundation
import AppKit
import ScreenSaver
import JohnnyResources
import JohnnyEngine
import JohnnyMetalRenderer

// All host-driven lifecycle methods (loadView, viewDidAppear,
// viewWillDisappear) run on the main actor; mark the whole file so
// the compiler doesn't have to flag each call site.
@MainActor
private enum MainActorIsolation {}

// -----------------------------------------------------------------------
// MARK: - Screensaver Extension (NSExtensionPrincipalClass)
// -----------------------------------------------------------------------

/// Tahoe-era screensaver extension. Loaded by the screen-saver host
/// via `NSExtensionPrincipalClass` in the bundle's Info.plist
/// (`JohnnyScreensaverExtension`).
///
/// The legacy `legacyScreenSaver` engine uses `NSPrincipalClass`
/// instead and instantiates `JohnnyScreenSaverView` directly; this
/// class is invisible to it because the legacy host does not consult
/// `NSExtensionPrincipalClass` at all. The two paths are independent
/// and can coexist in the same binary.
@objc(JohnnyScreensaverExtension)
@MainActor
public final class JohnnyScreensaverExtension: NSObject {

    /// The view controller that the host will embed. We allocate it
    /// once and reuse; the host treats this object as the singleton
    /// for the lifetime of the host process.
    @objc public static let shared = JohnnyScreensaverExtension()

    private override init() {
        super.init()
        NSLog("[Johnny] JohnnyScreensaverExtension init (Tahoe/.appex path)")
    }

    /// Returns the view controller the host should display.
    ///
    /// Tahoes screensaver host calls this once after loading the
    /// extension; the returned object is expected to be a
    /// ScreenSaverViewController subclass whose `.view` is a
    /// ScreenSaverView (or a view controller whose `loadView`
    /// installs one).
    @objc public func makeViewController() -> JohnnyScreensaverViewController {
        NSLog("[Johnny] JohnnyScreensaverExtension.makeViewController")
        return JohnnyScreensaverViewController()
    }
}

// -----------------------------------------------------------------------
// MARK: - Screensaver View Controller (Tahoe path)
// -----------------------------------------------------------------------

/// Tahoe-era view controller. Embedded by the screensaver host into
/// the preview / fullscreen window. Its `.view` is a
/// `JohnnyScreenSaverView`, so all the rendering and engine wiring
/// from the legacy path is reused without duplication.
///
/// The view controller also surfaces the configure sheet. The legacy
/// `JohnnyScreenSaverView` has its own `configureSheet`; we forward
/// to it so System Settings shows the same panel regardless of host.
@objc(JohnnyScreensaverViewController)
@MainActor
public final class JohnnyScreensaverViewController: NSViewController {

    /// The view the host displays. Lazy because `loadView` is the
    /// contract point for view construction in a view controller —
    /// the host calls it before adding the view to its window.
    private var saverView: JohnnyScreenSaverView?

    /// The frame the view is installed with. The Tahoe host hands us
    /// the window's bounds via `view.frame` after `loadView`; we
    /// resize the embedded ScreenSaverView to match.
    public override func loadView() {
        NSLog("[Johnny] JohnnyScreensaverViewController.loadView")
        // Initial size: a reasonable default. The host will resize
        // the view after installation; the embedded ScreenSaverView
        // responds to layout via NSView's autoresize mask.
        //
        // JohnnyScreenSaverView's `init(frame:isPreview:)` is
        // failable; the only thing that can fail is the parent
        // ScreenSaverView's init, which never fails for non-zero
        // frames. Force-unwrap is safe here.
        let initial = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        guard let view = JohnnyScreenSaverView(frame: initial, isPreview: false) else {
            // The host installed us with an invalid frame; fall back
            // to a 1×1 placeholder so we don't crash the host. The
            // .error is non-fatal because the host will re-invoke
            // loadView with a valid frame.
            let placeholder = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            NSLog("[Johnny] JohnnyScreenSaverView init returned nil; using placeholder")
            self.view = placeholder
            return
        }
        view.autoresizingMask = [.width, .height]
        self.view = view
        self.saverView = view
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        NSLog("[Johnny] JohnnyScreensaverViewController.viewDidAppear")
        saverView?.startAnimation()
    }

    public override func viewWillDisappear() {
        NSLog("[Johnny] JohnnyScreensaverViewController.viewWillDisappear")
        saverView?.stopAnimation()
        super.viewWillDisappear()
    }

    /// Whether the host should show a "Screen Saver Options…"
    /// affordance. Mirrors the legacy view's `hasConfigureSheet`.
    @objc public var hasConfigureSheet: Bool {
        // JohnnyScreenSaverView overrides `hasConfigureSheet` to
        // return true unconditionally. Forward via a transient
        // instance — cheap, since the configure sheet is built
        // lazily.
        guard let probe = JohnnyScreenSaverView(frame: .zero, isPreview: true) else {
            return false
        }
        return probe.hasConfigureSheet
    }

    /// The configure sheet window. Mirrors the legacy view's
    /// `configureSheet` by constructing the same panel on demand.
    @objc public var configureSheet: NSWindow? {
        guard let probe = JohnnyScreenSaverView(frame: .zero, isPreview: true) else {
            return nil
        }
        return probe.configureSheet
    }
}
