// Live microphone level, like the Input level row in System Settings > Sound.
//
// This is the only part of Tether that actually opens the microphone, which is why it runs
// only while the Microphone tab is on screen: an always-on tap would keep the orange
// recording indicator lit for a menu bar app that otherwise never listens to anything.

import AVFoundation
import SwiftUI

@MainActor
final class InputMeter: ObservableObject {
    /// 0...1, ready to drive the segments. Smoothed — raw RMS flickers too fast to read.
    @Published private(set) var level: Float = 0
    @Published private(set) var denied = false

    /// Rebuilt on every start rather than kept for the process. An engine stops itself when
    /// the hardware changes underneath it, and one that has been through that carries the old
    /// device's state around; a new one binds to whatever is default now.
    private var engine = AVAudioEngine()
    private var running = false
    /// Whether the meter is wanted on screen. Distinct from `running`, because a device that
    /// is still settling leaves the meter wanted but not yet started.
    private var wanted = false

    init() {
        // The engine stops itself when the hardware changes underneath it, so without this the
        // meter stays dead until the next time the tab is switched away and back.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
    }

    /// Level below this counts as silence. Speech sits around -30 dBFS, so a 60 dB window
    /// puts normal talking in the middle of the meter rather than pinned at either end.
    private static let floorDB: Float = -60

    func start() {
        wanted = true
        guard !running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    granted ? self.startEngine() : (self.denied = true)
                }
            }
        default:
            denied = true
        }
    }

    func stop() {
        wanted = false
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
    }

    /// The engine binds to whatever the default input was when it started, so a device
    /// switch means tearing it down and building it again.
    func restart() {
        guard wanted else { return }
        stop()
        start()
    }

    private func startEngine() {
        // Two paths reach here — the tab appearing and the permission prompt returning — and
        // a tap installed twice on one bus is a raised ObjC exception, which is a crash and
        // not something Swift can catch.
        guard wanted, !running else { return }
        denied = false
        engine = AVAudioEngine()
        let input = engine.inputNode

        // A nil format, rather than the node's own: inputNode reports a flat 44100 whatever the
        // hardware is really running at, and handing that back as the client format is what
        // raised "Format mismatch: input hw 16000 Hz, client format 44100 Hz" and took the app
        // down. Passing nil leaves AVFAudio to resolve the bus format, so there is no second
        // copy of it to disagree with the device.
        //
        // bufferSize is a hint the input hardware is free to ignore — it hands over about
        // 100ms at a time here — so the meter updates at the rate the device feeds it.
        input.installTap(onBus: 0, bufferSize: 256, format: nil) { [weak self] buffer, _ in
            let value = Self.level(of: buffer)
            Task { @MainActor in self?.absorb(value) }
        }
        do {
            try engine.start()
            running = true
        } catch {
            NSLog("input meter failed to start: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
        }
    }

    /// Instant to rise, damped on the way down — a meter that decays as fast as it climbs
    /// reads as noise. The 0.55 puts the fall a few buffers behind the rise, so at the ~100ms
    /// buffers the input hardware actually delivers it trails the voice by about a third of a
    /// second: readable, and not obviously lagging.
    private func absorb(_ value: Float) {
        level = value > level ? value : level * 0.55 + value * 0.45
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = (sum / Float(count)).squareRoot()
        guard rms > 0 else { return 0 }

        let db = 20 * log10(rms)
        return min(max((db - floorDB) / -floorDB, 0), 1)
    }
}

/// The dotted row from System Settings: segments light up left to right with the level.
struct MeterView: View {
    let level: Float
    var segments = 20

    var body: some View {
        track(filled: false)
            .overlay {
                // The gradient spans the whole row and is masked to the lit segments, so a
                // given dot keeps its colour whatever the level is — the row fills into the
                // warm end rather than the whole meter changing hue as you get louder.
                LinearGradient(colors: [.accentColor, .accentColor, .orange, .red],
                               startPoint: .leading, endPoint: .trailing)
                    .mask(track(filled: true))
            }
        // No animation: the segments are discrete and arrive every few milliseconds, so
        // interpolating between them only adds delay to something already smoothed.
    }

    private func track(filled: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                Capsule()
                    .fill(filled
                          ? AnyShapeStyle(index < lit ? .white : .clear)  // mask: alpha only
                          : AnyShapeStyle(.quaternary))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var lit: Int { Int((level * Float(segments)).rounded()) }
}
