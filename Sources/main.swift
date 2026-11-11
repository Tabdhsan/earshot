// Earshot — catches only the volume keys (up / down / mute), changes the
// system output volume, and shows a classic centered macOS-style HUD on the
// screen under the mouse pointer. Brightness and every other key pass through.

import Cocoa
import CoreAudio
import AudioToolbox
import ServiceManagement

// MARK: - Audio

enum Audio {
    static let steps: Float = 16

    static func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func settable(_ dev: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> Bool {
        var a = addr(sel)
        guard AudioObjectHasProperty(dev, &a) else { return false }
        var s: DarwinBoolean = false
        return AudioObjectIsPropertySettable(dev, &a, &s) == noErr && s.boolValue
    }

    static func canSetVolume(_ dev: AudioDeviceID) -> Bool {
        settable(dev, kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
    }

    static func volume(_ dev: AudioDeviceID) -> Float {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v)
        return v
    }

    static func setVolume(_ dev: AudioDeviceID, _ v: Float) {
        var a = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var val = Float32(min(max(v, 0), 1))
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &val)
    }

    static func hasMute(_ dev: AudioDeviceID) -> Bool { settable(dev, kAudioDevicePropertyMute) }

    static func isMuted(_ dev: AudioDeviceID) -> Bool {
        guard hasMute(dev) else { return false }
        var a = addr(kAudioDevicePropertyMute)
        var m = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &m)
        return m != 0
    }

    static func setMuted(_ dev: AudioDeviceID, _ muted: Bool) {
        guard hasMute(dev) else { return }
        var a = addr(kAudioDevicePropertyMute)
        var m = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }
}

// MARK: - HUD

final class ChicletBar: NSView {
    var level: Float = 0 { didSet { needsDisplay = true } }
    var dimmed = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let n = Int(Audio.steps), gap: CGFloat = 1
        let w = (bounds.width - gap * CGFloat(n - 1)) / CGFloat(n)
        let empty = NSColor.labelColor.withAlphaComponent(0.12)
        let full = NSColor.labelColor.withAlphaComponent(dimmed ? 0.25 : 0.55)
        let filled = CGFloat(level) * CGFloat(n)
        for i in 0..<n {
            let r = NSRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: bounds.height)
            empty.setFill(); r.fill()
            let f = min(max(filled - CGFloat(i), 0), 1)   // partial chiclet for fine steps
            if f > 0 {
                full.setFill()
                NSRect(x: r.minX, y: r.minY, width: r.width * f, height: r.height).fill()
            }
        }
    }
}

final class HUD {
    private let size: CGFloat = 200
    private let bottomOffset: CGFloat = 140
    private let panel: NSPanel
    private let icon = NSImageView()
    private let bar = ChicletBar()
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.alphaValue = 0

        let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = NSImage(size: fx.bounds.size, flipped: false) { r in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).fill()
            return true
        }
        panel.contentView = fx

        icon.frame = NSRect(x: 40, y: 58, width: 120, height: 110)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = NSColor.labelColor.withAlphaComponent(0.55)
        fx.addSubview(icon)

        bar.frame = NSRect(x: 20, y: 22, width: 160, height: 8)
        fx.addSubview(bar)
    }

    private func symbol(level: Float, muted: Bool, available: Bool) -> NSImage? {
        // Always the full three-wave speaker so the icon never changes size or shifts;
        // waves light up with the level (SF Symbols variable value), like the classic HUD.
        let cfg = NSImage.SymbolConfiguration(pointSize: 80, weight: .regular)
        let value = (muted || !available) ? 0 : Double(level)
        return NSImage(systemSymbolName: "speaker.wave.3.fill", variableValue: value,
                       accessibilityDescription: "Volume")?.withSymbolConfiguration(cfg)
    }

    func show(level: Float, muted: Bool, available: Bool) {
        icon.image = symbol(level: level, muted: muted, available: available)
        bar.level = (muted || !available) ? 0 : level
        bar.dimmed = muted

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.frame {
            panel.setFrameOrigin(NSPoint(x: f.midX - size / 2, y: f.minY + bottomOffset))
        }

        hideWork?.cancel()
        NSAnimationContext.runAnimationGroup { $0.duration = 0; panel.animator().alphaValue = 1 }
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; self.panel.animator().alphaValue = 0 },
                                                 completionHandler: nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

// MARK: - Key handling

enum MediaKey: Int { case up = 0, down = 1, mute = 7 }

final class Controller {
    let hud = HUD()
    private var savedVolume: [AudioDeviceID: Float] = [:]   // for devices without a mute property
    private let feedback = NSSound(contentsOfFile:
        "/System/Library/LoginPlugins/EarshotServices.loginPlugin/Contents/Resources/volume.aiff", byReference: true)

    func handle(_ key: MediaKey, flags: NSEvent.ModifierFlags) {
        let fine = flags.contains(.shift) && flags.contains(.option)
        if flags.contains(.option) && !flags.contains(.shift) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            return
        }

        let dev = Audio.defaultOutput()
        guard Audio.canSetVolume(dev) else {
            hud.show(level: 0, muted: false, available: false)
            return
        }

        var vol = Audio.volume(dev)
        var muted = Audio.isMuted(dev)
        let step: Float = 1 / Audio.steps / (fine ? 4 : 1)

        switch key {
        case .mute:
            if Audio.hasMute(dev) {
                muted.toggle(); Audio.setMuted(dev, muted)
            } else if vol > 0 {
                savedVolume[dev] = vol; vol = 0; Audio.setVolume(dev, 0)
            } else {
                vol = savedVolume[dev] ?? 0.5; Audio.setVolume(dev, vol)
            }
        case .up, .down:
            vol = key == .up ? vol + step : vol - step
            vol = (vol / step).rounded() * step          // snap to the grid
            vol = min(max(vol, 0), 1)
            Audio.setVolume(dev, vol)
            if muted { muted = false; Audio.setMuted(dev, false) }
            if UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.sound.beep.feedback"] as? Int == 1
                || flags.contains(.shift) && !fine {
                feedback?.stop(); feedback?.play()
            }
        }
        hud.show(level: vol, muted: muted, available: true)
    }
}

let controller = Controller()
var eventTap: CFMachPort?

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14 /* NX_SYSDEFINED */, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8,
          let key = MediaKey(rawValue: (ns.data1 & 0xFFFF0000) >> 16)
    else { return Unmanaged.passUnretained(event) }

    let isDown = ((ns.data1 & 0xFF00) >> 8) == 0x0A
    if isDown { controller.handle(key, flags: ns.modifierFlags) }
    return nil   // swallow both key-down and key-up so the system HUD never shows
}

func installTap() -> Bool {
    guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(1 << 14), callback: callback, userInfo: nil)
    else { return false }
    eventTap = tap
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        if Bundle.main.bundlePath.hasPrefix("/Applications") {
            try? SMAppService.mainApp.register()   // launch at login
        }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !installTap() {
            // Wait for the Accessibility grant, then install.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { t in
                if installTap() { t.invalidate() }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
