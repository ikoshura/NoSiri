import SwiftUI

// MARK: - Motion
//
// Every animation in the app goes through here. One rule: use `smooth`
// (a continuous, non-velocity-jumping curve) rather than `easeOut`, which
// begins at full speed and therefore reads as a snap. Durations are long
// enough that a mid-flight state change blends into the animation already
// running instead of restarting it visibly.

private enum Motion {
    /// Layout shifts: the transcript appearing resizes the stack.
    static let layout = Animation.smooth(duration: 0.38)
    /// Rows appearing inside the transcript.
    static let content = Animation.smooth(duration: 0.28)
    /// Hover/press feedback, and the window's background wash.
    static let subtle = Animation.smooth(duration: 0.22)
    /// Autoscroll to the tail.
    static let scroll = Animation.smooth(duration: 0.30)
}

// MARK: - Menu code allowlist

/// Apple codes for the system menu items we want to keep visible.
/// "abtm" (About This Mac) is intentionally excluded: it is unconditionally
/// visible in the current macOS build, so allowlisting it is unnecessary.
private let keptCodes = ["soft", "apwn", "exit", "loca", "lock", "logo",
                        "rlgo", "rcnt", "rrst", "rest", "rsdn", "shut",
                        "slep", "spro", "syss"]

private func hexOf(_ s: String) -> String {
    s.utf8.map { String(format: "%02X", $0) }.joined()
}

enum PatchState: Equatable {
    case defaultState   // key absent -> "Ask Siri" is available
    case patched        // key present and matches our exact allowlist
    case custom         // key present but not our allowlist

    var title: String {
        switch self {
        case .defaultState: return "Default"
        case .patched:      return "Patched"
        case .custom:       return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .defaultState:
            return "The  menu filter is not active, so \"Ask Siri\" is available in every context menu."
        case .patched:
            return "The  menu filter is active with all system items allowlisted. \"Ask Siri\" is hidden in context menus."
        case .custom:
            return "NSAppleMenuAllowedItems is set, but it does not match the allowlist this app writes. It may have been edited by hand."
        }
    }

    var showApply: Bool { self == .defaultState }
    var showRevert: Bool { self != .defaultState }
}

enum StateError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let m) = self { return m }
        return nil
    }
}

enum Prefs {
    static let key = "NSAppleMenuAllowedItems"

    /// The numeric value of each allowlisted menu code, as `defaults` stores it.
    static var expectedNumbers: [String] {
        ["0"] + keptCodes.map { String(UInt32(hexOf($0), radix: 16) ?? 0) }
    }

    /// The argv the user can paste back into a shell, wrapped for the narrow
    /// panel. Showing the real command (rather than an elided summary) means the
    /// transcript is a true record of what ran.
    static func displayCommand(_ arguments: [String]) -> [String] {
        let text = (["/usr/bin/defaults"] + arguments).joined(separator: " ")
        return wrap(text, width: 62)
    }

    /// Greedy wrap that never splits a token that is longer than the width.
    static func wrap(_ text: String, width: Int) -> [String] {
        var rows: [String] = []
        var row = ""
        for token in text.split(separator: " ", omittingEmptySubsequences: true) {
            if row.isEmpty {
                row = String(token)
            } else if row.count + 1 + token.count <= width {
                row += " " + token
            } else {
                rows.append(row); row = String(token)
            }
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    static func revertCommand() -> [String] {
        displayCommand(["delete", "-g", key])
    }

    /// The exact argv tail we write: `-int 0` then one `-int <code>` per item.
    static var expectedArgs: [String] {
        expectedNumbers.flatMap { ["-int", $0] }
    }

    /// `defaults read` prints the array as bare integers, one per line, e.g.
    /// "(\n    0,\n    1936680564,\n ...\n)". We compare those numbers to the
    /// exact list the original command would produce.
    static func currentState() throws -> PatchState {
        let r = try run("/usr/bin/defaults", ["read", "-g", key])
        let combined = r.stdout + "\n" + r.stderr
        if r.status != 0 || combined.contains("does not exist")
            || combined.contains("Could not find key") {
            return .defaultState
        }
        let numbers = combined
            .components(separatedBy: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: "(),")))
            .filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        return numbers == expectedNumbers ? .patched : .custom
    }

    /// Writes the allowlist and returns the raw result so the UI can echo the
    /// exact argv and its output into the terminal panel.
    static func apply() throws -> Result {
        let r = try run("/usr/bin/defaults", ["write", "-g", key, "-array"] + expectedArgs)
        guard r.status == 0 else {
            throw StateError.failed("Could not write the preference: \(r.stderr.isEmpty ? "exit code \(r.status)" : r.stderr)")
        }
        return r
    }

    static func revert() throws -> Result {
        let r = try run("/usr/bin/defaults", ["delete", "-g", key])
        // defaults exits non-zero when the key is already gone; that is the desired end state.
        if r.status != 0 && !r.stderr.contains("does not exist")
            && !r.stderr.contains("Could not find key") {
            throw StateError.failed("Could not delete the preference: \(r.stderr)")
        }
        return r
    }

    /// Only Finder needs cycling: it is the process that builds the context menus
    /// and caches the menu filter, so it picks up a new value on startup. No
    /// reboot, no admin rights and no Automation consent are required — Finder is
    /// an ordinary per-user process that relaunches itself, restoring the windows
    /// that were open.
    static func reloadFinder() throws -> Result {
        // `killall` exits non-zero when Finder is not running, which is harmless
        // here, so the result is reported but never treated as a failure.
        return (try? run("/usr/bin/killall", ["Finder"]))
            ?? Result(status: 0, stdout: "", stderr: "")
    }

    struct Result { let status: Int32; let stdout: String; let stderr: String }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = arguments
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        // Drain fully before waiting so a large value can never deadlock the pipe.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }
}

// MARK: - App

@main
struct NosiriApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        WindowGroup("NoSiri") {
            ContentView()
                .environmentObject(model)
        }
        // Free resizing, with a translucent body so the desktop shows through.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 460, height: 420)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class Model: ObservableObject {
    @Published var state: PatchState = .defaultState
    @Published var busy = false
    @Published var error: String?
    /// Terminal transcript, oldest first. Empty until a button is pressed, which
    /// is what keeps the panel collapsed on a freshly launched window.
    @Published fileprivate(set) var lines: [LogLine] = []

    init() { refresh() }

    /// Re-reads the preference. Also drops any previous transcript, so the panel
    /// only ever shows the action the user just asked for and never a stale
    /// run from earlier in the session.
    func refresh() {
        lines = []
        do {
            state = try Prefs.currentState()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Writes the preference and then relaunches Finder in one step, so a single
    /// button is all the user ever needs: Finder builds the context menus and
    /// caches the filter, so it picks up the new value on startup. Relaunching
    /// is quick and silently restores the windows that were open.
    private func perform(_ action: String, _ command: [String],
                         _ body: @escaping () throws -> Prefs.Result) {
        busy = true
        error = nil
        // Always start from a clean slate: the transcript documents one action.
        // Clearing and logging happen in one main-actor turn, so the panel can
        // never be shown holding a stale run.
        withAnimation(Motion.layout) {
            lines = [LogLine(text: action, kind: .heading)]
            for row in command { lines.append(LogLine(text: "$ " + row, kind: .plain)) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try body().report(self)
                try Prefs.reloadFinder().report(self)
                self.log("Reloading Finder…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.log("✓ Finder reloaded", kind: .success)
                    self.busy = false
                    // Re-read the state without wiping the transcript we just built.
                    self.state = (try? Prefs.currentState()) ?? self.state
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("✗ " + error.localizedDescription, kind: .failure)
                    self.error = error.localizedDescription
                    self.busy = false
                }
            }
        }
    }

    func apply()  { perform("Apply Patch", Prefs.displayCommand(["write", "-g", Prefs.key, "-array"] + Prefs.expectedArgs)) { try Prefs.apply() } }
    func revert() { perform("Restore Default", Prefs.revertCommand()) { try Prefs.revert() } }

    /// Appends one transcript line. Always hops to the main actor so the text
    /// can be fed straight from the background worker above.
    fileprivate func log(_ text: String, kind: LogLine.Kind = .plain) {
        let line = LogLine(text: text, kind: kind)
        if Thread.isMainThread {
            // Animated so the row's transition is actually driven; an unanimated
            // append would drop the new row in with no fade.
            withAnimation(Motion.content) { lines.append(line) }
        } else {
            DispatchQueue.main.async {
                withAnimation(Motion.content) { self.lines.append(line) }
            }
        }
    }
}

/// One terminal row. `Kind` only affects colour: green for success, red for
/// failure, plain secondary for echoed commands.
struct LogLine: Identifiable {
    enum Kind { case heading, plain, success, failure }
    let id = UUID()
    let text: String
    let kind: Kind
}

extension Prefs.Result {
    /// Echoes a finished command: its stderr as a failure line, otherwise its
    /// stdout if there is any, otherwise a plain success tick.
    @discardableResult
    func report(_ model: Model) -> Self {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty {
            model.log(err, kind: .failure)
        } else if !out.isEmpty {
            model.log(out, kind: .plain)
        } else {
            model.log("exit 0", kind: .success)
        }
        return self
    }
}

// MARK: - Window chrome

/// Makes the window background translucent so the desktop shows through.
/// The window must also be marked non-opaque, otherwise AppKit ignores the alpha.
struct TranslucentBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Button styles

/// Borderless at rest, with a faint fill that only appears under the cursor.
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(hovering && !configuration.isPressed ? 0.18 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering = $0 }
            .animation(Motion.subtle, value: hovering)
    }
}

// MARK: - Terminal panel

/// Compact terminal readout of whatever the last button did. Frosted like the
/// window, but its own rounded surface so it reads as a separate element.
/// Only the transcript scrolls; the panel itself is a fixed, modest height.
struct TerminalPanel: View {
    let lines: [LogLine]
    /// A transcript starts at its heading, where the action is named. It only
    /// follows the tail once the user has scrolled up themselves, so a long
    /// command never pushes the heading out of sight.
    @State private var followTail = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: 10, weight: line.kind == .heading ? .semibold : .regular,
                          design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            // New rows fade and rise slightly into place. Without
                            // this they pop in on a single frame, which is what
                            // makes a streaming transcript read as jumping.
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                // Scoped to the rows only, so an appended line animates its own
                // transition without the panel or the window reflowing around it.
                .animation(Motion.content, value: lines.count)
            }
            // 108pt is roughly eight 10pt rows: the heading, the full wrapped
            // command and its output all stay visible without scrolling in the
            // common case, while the panel still never dominates the window.
            .frame(height: 108)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .simultaneousGesture(
                // Scrolling by hand hands control back to the user: scrolling
                // toward the tail re-arms auto-follow, scrolling away drops it.
                DragGesture(minimumDistance: 2)
                    .onChanged { followTail = $0.translation.height < 0 }
            )
            .onChange(of: lines.count) { _, _ in
                guard followTail, let last = lines.last else { return }
                withAnimation(Motion.scroll) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: LogLine.Kind) -> Color {
        switch kind {
        case .heading: return .primary
        case .plain:   return .secondary
        case .success: return .green
        case .failure: return .red
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                statusIcon
                Text(model.state.title).font(.title2.bold())
                    // The title swaps wholesale between states; cross-fading the
                    // glyphs avoids a hard one-frame cut.
                    .contentTransition(.opacity)
                Text(model.state.detail)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
                    .contentTransition(.opacity)
                actions
                if !model.lines.isEmpty {
                    TerminalPanel(lines: model.lines)
                        .frame(maxWidth: 380)
                        // The panel is inserted above the bottom spacer, so it
                        // grows the stack upward. Fading it while that happens
                        // keeps the move from looking like the window "kicks".
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if let e = model.error {
                    Text(e).font(.caption).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 400, minHeight: 340)
        // Symmetric 44pt insets: they clear the floating traffic lights and keep
        // the content optically centered in the window at any size.
        .padding(44)
        // Animate only the transcript's own appearance, and only on the stack
        // that actually reflows. This used to be a bare `.animation` on the
        // whole body keyed on `lines.count`, which re-triggered on every single
        // appended line and animated the background and icon along with it —
        // the main source of the jumping.
        .animation(Motion.layout, value: model.lines.isEmpty)
        .background(TranslucentBackground())
        // Frosted glass: the material blurs the desktop, and the window is
        // non-opaque so the blur actually shows through.
        .background(.ultraThinMaterial)
        // Patched state washes the whole glass in the signature red. It sits
        // above the material but stays translucent, so the frosted desktop
        // still reads through instead of going flat.
        .background {
            if model.state == .patched {
                Color(red: 0.902, green: 0.200, blue: 0.157)
                    .opacity(0.32)
            }
        }
        // Scoped to the wash and the icon only. Applying this to the whole
        // subtree made the state change drag every layout change along too.
        .animation(Motion.subtle, value: model.state)
    }

    /// Apple Intelligence mark from Resources, tinted by state. Loaded once and
    /// cached, since NSImage decoding is not cheap to repeat on every redraw.
    private var statusIcon: some View {
        Group {
            if let image = Self.markImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    // Template rendering lets the monochrome SVG pick up the tint.
                    .foregroundStyle(statusColor)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(statusColor)
            }
        }
    }

    private static let markImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "icon",
                                       withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Fallback glyph used only if the bundled SVG is ever missing.
    private var iconName: String {
        switch model.state {
        case .defaultState: return "waveform"
        case .patched:      return "waveform.badge.minus"
        case .custom:       return "waveform.badge.exclamationmark"
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .defaultState: return .secondary
        // The window itself is red in this state, so the mark goes red to
        // stay legible against the wash.
        case .patched:      return Color(red: 0.902, green: 0.200, blue: 0.157)
        case .custom:       return .orange
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            // Swapping the primary button on a state change used to be an
            // instant cut. Fading it keeps the control row from appearing
            // to twitch when a patch is applied.
            if model.state.showApply {
                Button("Apply Patch") { model.apply() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.busy)
                    .transition(.opacity)
            }
            if model.state.showRevert {
                Button("Restore Default") { model.revert() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    // In the patched state the window is washed in red, so the
                    // accent is forced to the system secondary gray to stay readable on the wash.
                    .tint(model.state == .patched ? Color.secondary : .accentColor)
                    .disabled(model.busy)
                    .transition(.opacity)
            }
            Button("Refresh") { model.refresh() }
                .buttonStyle(HoverButtonStyle())
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(model.busy)
        }
        .padding(.top, 6)
    }
}
