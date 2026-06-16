import SwiftUI
import TrafficWandCore

/// A reusable "Browser vs Alias" destination editor for a `RoutingDestination`.
///
/// Renders a segmented control to pick between a concrete browser (`BrowserProfilePicker`)
/// and a reusable alias (a picker over `aliases`), then writes the chosen
/// `RoutingDestination` back through the `Binding`. Used by both the rule editor
/// and the fallback editor; the alias segment is disabled when no aliases exist.
///
/// It holds the browser target and the alias selection as **independent** working
/// state, seeded once from the incoming destination, so toggling Browser → Alias →
/// Browser preserves each side's prior selection instead of discarding it. Each
/// change recomputes the bound `RoutingDestination` from the active mode via the
/// pure `DestinationDraft.destination` mapping (unit-tested independently of the
/// view).
struct DestinationEditor: View {
    /// The browsers available as concrete targets (with discovered profiles).
    let browsers: [Browser]

    /// The aliases available as reusable targets.
    let aliases: [ProfileAlias]

    /// The destination being edited, written back on every change.
    @Binding var destination: RoutingDestination

    /// Independent working state for both modes (see the type doc comment).
    @State private var draft: DestinationDraft

    init(
        browsers: [Browser],
        aliases: [ProfileAlias],
        destination: Binding<RoutingDestination>
    ) {
        self.browsers = browsers
        self.aliases = aliases
        self._destination = destination
        self._draft = State(
            initialValue: DestinationDraft(
                destination: destination.wrappedValue,
                browsers: browsers,
                aliases: aliases
            )
        )
    }

    /// The bound `BrowserTarget`, kept in sync with the draft and pushed to the
    /// destination binding (in `.browser` mode) on every edit.
    private var targetBinding: Binding<BrowserTarget> {
        Binding(
            get: { draft.target },
            set: { newTarget in
                draft.target = newTarget
                pushDestination()
            }
        )
    }

    private var modeBinding: Binding<DestinationDraft.Mode> {
        Binding(
            get: { draft.mode },
            set: { newMode in
                draft.mode = newMode
                pushDestination()
            }
        )
    }

    private var aliasBinding: Binding<UUID?> {
        Binding(
            get: { draft.aliasID },
            set: { newID in
                draft.aliasID = newID
                pushDestination()
            }
        )
    }

    /// Recompute the bound destination from the draft, but only when the active mode
    /// resolves to a usable destination — never clobber the binding with an empty
    /// alias selection or a `.browser` whose bundle isn't a real installed browser
    /// (which would persist an unusable empty-bundleID target).
    private func pushDestination() {
        switch draft.destination {
        case .browser(let target):
            guard browsers.contains(where: { $0.bundleID == target.bundleID }) else { return }
            destination = .browser(target)
        case .alias(let id):
            destination = .alias(id)
        case nil:
            return
        }
    }

    var body: some View {
        Picker("Destination", selection: modeBinding) {
            ForEach(DestinationDraft.Mode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
                    // Disable a mode with nothing to offer, so the user can't switch
                    // into an empty browser/alias list (which would persist an
                    // unusable target). `.disabled`-on-tag only dims in AppKit-backed
                    // pickers, so `pushDestination` is the load-bearing guard.
                    .disabled(
                        (mode == .browser && browsers.isEmpty)
                            || (mode == .alias && aliases.isEmpty)
                    )
            }
        }
        .pickerStyle(.segmented)

        switch draft.mode {
        case .browser:
            BrowserProfilePicker(browsers: browsers, target: targetBinding)
        case .alias:
            Picker("Alias", selection: aliasBinding) {
                ForEach(aliases) { alias in
                    Text(alias.name).tag(UUID?.some(alias.id))
                }
            }
        }
    }
}

/// Pure, view-independent working state for `DestinationEditor`: the active mode
/// plus an independent browser target and alias selection. Mapping the draft to a
/// `RoutingDestination` lives here so it can be unit-tested without SwiftUI.
struct DestinationDraft: Equatable {
    /// The destination kind, surfaced as a segmented control.
    enum Mode: String, CaseIterable, Identifiable {
        case browser
        case alias
        var id: String { rawValue }

        var title: String {
            switch self {
            case .browser: return "Browser"
            case .alias: return "Alias"
            }
        }
    }

    var mode: Mode
    var target: BrowserTarget
    var aliasID: UUID?

    /// Seeds the draft from an existing destination, keeping each side's selection
    /// independent: the inactive side falls back to the first available browser /
    /// alias so switching modes always has a sensible default.
    init(destination: RoutingDestination, browsers: [Browser], aliases: [ProfileAlias]) {
        let firstBrowserTarget = browsers.first.map {
            BrowserTarget(bundleID: $0.bundleID, profileID: nil)
        } ?? BrowserTarget(bundleID: "", profileID: nil)

        switch destination {
        case .browser(let target):
            self.mode = .browser
            self.target = target
            self.aliasID = aliases.first?.id
        case .alias(let id):
            self.mode = .alias
            self.target = firstBrowserTarget
            self.aliasID = id
        }
    }

    /// The `RoutingDestination` the draft currently represents, or `nil` when the
    /// active mode has no resolvable selection (e.g. `.alias` with no id chosen).
    var destination: RoutingDestination? {
        switch mode {
        case .browser:
            return .browser(target)
        case .alias:
            return aliasID.map { .alias($0) }
        }
    }
}
