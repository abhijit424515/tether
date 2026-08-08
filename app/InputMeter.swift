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

    private let engine = AVAudioEngine()
    private var running = false

    /// Level below this counts as silence. Speech sits around -30 dBFS, so a 60 dB window
    /// puts normal talking in the middle of the meter rather than pinned at either end.
    private static let floorDB: Float = -60

    func start() {
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
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        level = 0
    }

    /// The engine binds to whatever the default input was when it started, so a device
    /// switch means tearing it down and building it again.
    func restart() {
        guard running else { return }
        stop()
        start()
    }

    private func startEngine() {
        denied = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }  // no usable input device

        // 256 frames is ~5ms at 48kHz, against ~21ms for the more usual 1024. The meter is
        // updated once per buffer, so the buffer length is the meter's floor on latency.
        input.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, _ in
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
    /// reads as noise. The 0.55 keeps the fall around 40ms, slow enough to be readable and
    /// fast enough that the meter does not visibly trail the voice.
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
