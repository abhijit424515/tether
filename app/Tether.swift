// Tether — menu bar app that keeps macOS audio on the highest-priority connected device.
// Same config file as the CLI: ~/.config/tether.json
// ponytail: one file, no Xcode project. Split it up when it stops fitting on a screen.

import SwiftUI
import CoreAudio
import ServiceManagement

// MARK: - CoreAudio

enum Direction: String, CaseIterable, Codable {
    case input, output

    var scope: AudioObjectPropertyScope {
        self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }
    var defaultSelector: AudioObjectPropertySelector {
        self == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
    }
    var label: String { self == .input ? "Microphone" : "Speakers" }
}

struct Device: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum Audio {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Every device that has at least one channel in this direction.
    static func devices(_ dir: Direction) -> [Device] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { channels($0, dir) > 0 && !isPrivateAggregate($0) }.compactMap { id in
            name(id).map { Device(id: id, name: $0) }
        }
    }

    /// CoreAudio spins up a private aggregate device — CADefaultDeviceAggregate-<pid>-0 —
    /// whenever a process opens the default input, which Tether's own level meter does. They
    /// are real devices with real channels, so they have to be filtered by intent rather than
    /// by shape. A user's own aggregate from Audio MIDI Setup is not private and stays listed.
    private static func isPrivateAggregate(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioAggregateDevicePropertyComposition)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var composition: CFDictionary?
        var size = UInt32(MemoryLayout<CFDictionary?>.size)
        let status = withUnsafeMutablePointer(to: &composition) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let entries = composition as? [String: Any] else { return false }
        return (entries[kAudioAggregateDeviceIsPrivateKey] as? Int) == 1
    }

    private static func channels(_ id: AudioDeviceID, _ dir: Direction) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, dir.scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                  alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func name(_ id: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }

    static func current(_ dir: Direction) -> AudioDeviceID? {
        var addr = address(dir.defaultSelector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &id) == noErr else { return nil }
        return id
    }

    /// Volume lives on the main element for some devices and on the individual channels for
    /// others, so every volume call walks main first, then channels 1 and 2.
    private static let volumeElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    /// nil when the device exposes no volume control at all — common for digital outputs
    /// and for many USB microphones, which want their own hardware knob used instead.
    static func volume(_ id: AudioDeviceID, _ dir: Direction) -> Float? {
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, dir.scope)
            addr.mElement = element
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr { return value }
        }
        return nil
    }

    static func setVolume(_ value: Float, _ id: AudioDeviceID, _ dir: Direction) {
        var value = Float32(min(max(value, 0), 1))
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, dir.scope)
            addr.mElement = element
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(id, &addr),
                  AudioObjectIsPropertySettable(id, &addr, &settable) == noErr,
                  settable.boolValue,
                  AudioObjectSetPropertyData(id, &addr, 0, nil,
                                             UInt32(MemoryLayout<Float32>.size), &value) == noErr
            else { continue }
            // The main element covers every channel; only fall through to 1 and 2 without it.
            if element == kAudioObjectPropertyElementMain { return }
        }
    }

    @discardableResult
    static func setDefault(_ id: AudioDeviceID, _ dir: Direction) -> Bool {
        var addr = address(dir.defaultSelector)
        var id = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                          &addr, 0, nil, size, &id) == noErr
    }
}

// MARK: - Config

/// ~/.config/tether.json — {"input": [...], "output": [...]}, first connected entry wins.
enum Config {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/tether.json")

    /// The config was called audio-priority.json before the app was named Tether.
    private static let legacyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/audio-priority.json")

    /// Versions before the private-aggregate filter recorded CoreAudio's throwaway
    /// CADefaultDeviceAggregate-<pid>-0 devices, one per launch. Drop them once; the
    /// enumeration filter keeps them from coming back.
    static func pruneScratchDevices() {
        var lists = load()
        let cleaned = lists.mapValues { $0.filter { !$0.hasPrefix("CADefaultDeviceAggregate") } }
        guard cleaned != lists else { return }
        lists = cleaned
        save(lists)
    }

    static func migrateLegacy() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacyURL.path) else { return }
        try? fm.moveItem(at: legacyURL, to: url)
    }

    static func load() -> [Direction: [String]] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return raw.reduce(into: [:]) { out, pair in
            if let dir = Direction(rawValue: pair.key) { out[dir] = pair.value }
        }
    }

    static func save(_ lists: [Direction: [String]]) {
        let raw = Dictionary(uniqueKeysWithValues: lists.map { ($0.key.rawValue, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]  // stays hand-editable for the CLI
        guard let data = try? encoder.encode(raw) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published private(set) var connected: [Direction: [Device]] = [:]
    @Published private(set) var currentID: [Direction: AudioDeviceID] = [:]
    /// nil for a device with no volume control; the slider is hidden in that case.
    @Published private(set) var volume: [Direction: Float] = [:]
    @Published var openAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet { setOpenAtLogin(openAtLogin) }
    }

    private var lists = Config.load()
    private var timer: Timer?
    /// While a slider is held, the 2s poll must not write the hardware's value back into it.
    private var adjusting: Direction?

    init() {
        Config.migrateLegacy()
        Config.pruneScratchDevices()
        refresh()
        // ponytail: 2s poll instead of a CoreAudio property listener. Both work; this one is 1 line.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// One row per remembered device, in priority order. Disconnected ones stay listed so
    /// you can position a device before plugging it back in.
    func rows(_ dir: Direction) -> [Row] {
        let devices = connected[dir] ?? []
        return (lists[dir] ?? []).map { name in
            let device = devices.first { $0.name == name }
            return Row(name: name,
                       isConnected: device != nil,
                       isActive: device != nil && device?.id == currentID[dir])
        }
    }

    /// Drag to reorder = set priority. Position in the list is the whole preference model.
    func setOrder(_ dir: Direction, _ names: [String]) {
        guard lists[dir] != names else { return }
        lists[dir] = names
        Config.save(lists)
        refresh()
    }

    func setVolume(_ dir: Direction, _ value: Float) {
        volume[dir] = value
        guard let id = currentID[dir] else { return }
        Audio.setVolume(value, id, dir)
    }

    func setAdjusting(_ dir: Direction, _ active: Bool) {
        adjusting = active ? dir : nil
    }

    func forget(_ dir: Direction, _ name: String) {
        lists[dir]?.removeAll { $0 == name }
        Config.save(lists)
        refresh()
    }

    func refresh() {
        lists = Config.load()  // pick up edits made by the CLI or by hand
        var discovered = false
        for dir in Direction.allCases {
            let devices = Audio.devices(dir)
            connected[dir] = devices
            // A device seen for the first time goes to the bottom — never silently outranks a choice.
            let known = lists[dir] ?? []
            let new = devices.map(\.name).filter { !known.contains($0) }
            if !new.isEmpty {
                lists[dir] = known + new
                discovered = true
            }
            apply(dir)
            let id = Audio.current(dir)
            currentID[dir] = id
            if adjusting != dir {
                volume[dir] = id.flatMap { Audio.volume($0, dir) }
            }
        }
        if discovered { Config.save(lists) }  // this runs every 2s — only write when it changed
    }

    /// Switch to the highest-priority device that is actually connected.
    private func apply(_ dir: Direction) {
        let devices = connected[dir] ?? []
        guard let want = (lists[dir] ?? []).lazy
            .compactMap({ name in devices.first { $0.name == name } }).first
        else { return }
        if Audio.current(dir) != want.id { Audio.setDefault(want.id, dir) }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
        } catch {
            NSLog("open at login failed: \(error.localizedDescription)")
            openAtLogin = SMAppService.mainApp.status == .enabled  // reflect what actually happened
        }
    }
}

// MARK: - UI

struct Row: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isConnected: Bool
    let isActive: Bool
}

struct RowView: View {
    let row: Row
    let rank: Int
    let isDragging: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.caption)
            Text(row.name)
                .lineLimit(1)
                .foregroundStyle(row.isConnected ? .primary : .secondary)
            Spacer(minLength: 8)
            if row.isActive {
                Text("in use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !row.isConnected {
                Text("not connected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isDragging ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 5))
        .shadow(radius: isDragging ? 4 : 0)
        .contentShape(.rect)  // whole row is the drag handle, not just the text
    }
}

struct PanelView: View {
    @ObservedObject var model: Model
    static let rowHeight: Double = 30

    @StateObject private var meter = InputMeter()
    @State private var tab: Direction = .input
    @State private var dragName: String?
    @State private var dragOffset: Double = 0

    /// Saved order, with the dragged row already shown in the slot it would land in.
    private var displayRows: [Row] {
        let rows = model.rows(tab)
        guard let from = draggedIndex(in: rows) else { return rows }
        let order = Reorder.moved(rows.map(\.name), from: from, to: target(in: rows))
        return order.compactMap { name in rows.first { $0.name == name } }
    }

    private func draggedIndex(in rows: [Row]) -> Int? {
        dragName.flatMap { name in rows.firstIndex { $0.name == name } }
    }

    private func target(in rows: [Row]) -> Int {
        guard let from = draggedIndex(in: rows) else { return 0 }
        return Reorder.target(from: from, offset: dragOffset,
                              rowHeight: Self.rowHeight, count: rows.count)
    }

    /// The dragged row follows the cursor; the slots it has already passed are taken out,
    /// so subtract the distance it has been shifted by the reordering itself.
    private var liftOffset: Double {
        let rows = model.rows(tab)
        guard let from = draggedIndex(in: rows) else { return 0 }
        return dragOffset - Double(target(in: rows) - from) * Self.rowHeight
    }

    /// Volume of whichever device is active in this tab. Absent for devices that expose no
    /// volume control, where a dead slider would just look broken.
    @ViewBuilder
    private var volumeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: tab == .input ? "mic.fill" : "speaker.wave.2.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(width: 14)
            // A device with no volume control gets a disabled slider rather than a hidden one,
            // so the panel does not change height when devices switch.
            Slider(value: Binding(get: { model.volume[tab] ?? 0 },
                                  set: { model.setVolume(tab, $0) }),
                   in: 0...1,
                   onEditingChanged: { model.setAdjusting(tab, $0) })
                .disabled(model.volume[tab] == nil)
                .help(model.volume[tab] == nil ? "This device has no volume control" : "")
        }
        .frame(height: 20)
    }

    private func dragGesture(for row: Row) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragName == nil { dragName = row.name }
                dragOffset = value.translation.height
            }
            .onEnded { _ in
                model.setOrder(tab, displayRows.map(\.name))
                dragName = nil
                dragOffset = 0
            }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(Direction.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            volumeSlider

            Text("Drag to set priority. The top device that is connected wins.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // ponytail: reorder by DragGesture, not drag-and-drop. A MenuBarExtra popover is a
            // non-activating panel, so NSDraggingSession never starts there — .onMove and
            // .draggable both silently do nothing. Plain gesture math has no such dependency.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(displayRows.enumerated()), id: \.element.id) { index, row in
                        RowView(row: row, rank: index + 1, isDragging: row.name == dragName)
                            .frame(height: PanelView.rowHeight)
                            .offset(y: row.name == dragName ? liftOffset : 0)
                            .zIndex(row.name == dragName ? 1 : 0)
                            .gesture(dragGesture(for: row))
                            .contextMenu {
                                if !row.isConnected {
                                    Button("Forget") { model.forget(tab, row.name) }
                                }
                            }
                    }
                }
                .animation(.snappy(duration: 0.18), value: displayRows)
                .padding(4)
            }
            .frame(height: 200)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))

            if tab == .input {
                HStack(spacing: 8) {
                    Text("Input level")
                        .font(.caption)
                        .foregroundStyle(meter.denied ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                    Spacer(minLength: 4)
                    if meter.denied {
                        Text("microphone access denied")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        MeterView(level: meter.level)
                    }
                }
                .frame(height: 14)
            }

            Divider()

            HStack {
                Toggle("Open at Login", isOn: $model.openAtLogin)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 320)
        // The mic is open only while its tab is visible — not while the panel is merely open,
        // and never while the panel is closed.
        .onAppear { if tab == .input { meter.start() } }
        .onDisappear { meter.stop() }
        .onChange(of: tab) { _, new in new == .input ? meter.start() : meter.stop() }
        .onChange(of: model.currentID[.input]) { _, _ in meter.restart() }
    }
}

// MARK: - App

enum Icon {
    /// Template image: macOS recolors it for light, dark, and highlighted menu bars, so the
    /// artwork ships as flat black with alpha rather than the gradient in icon.svg.
    static let menuBar: NSImage = {
        guard let image = NSImage(named: "MenuBarIcon") else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Tether")!
        }
        image.isTemplate = true
        return image
    }()
}

@main
struct TetherApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(nsImage: Icon.menuBar)
        }
        .menuBarExtraStyle(.window)
    }
}
