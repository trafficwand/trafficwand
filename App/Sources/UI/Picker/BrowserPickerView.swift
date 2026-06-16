import SwiftUI
import TrafficWandCore

/// The floating picker UI: shows the link being routed and the list of
/// destinations — an optional leading "Aliases" group followed by the installed
/// browsers (with their profiles) — and lets the user pick one by click or
/// keyboard, copy the URL, or cancel (Esc).
///
/// All behavior flows through `PickerViewModel`:
///  - tapping any row (alias, browser-default, or profile) → `select(item:)`;
///  - the Copy URL button → `copyURL()`;
///  - the Cancel button / Esc → `cancel()`.
///
/// Rows are driven by `viewModel.selectableItems`: when `aliases` are supplied it
/// leads with alias rows under an "Aliases" header, then a flattened
/// browser-default → profiles sequence per browser. Each row is a hoverable,
/// pointer-cursor button with press
/// feedback. The panel takes keyboard focus on appear, so the `selectedIndex` row
/// — the row Return will activate — is highlighted from the start (row 0 by
/// default); hover takes visual precedence while the mouse is over a row, and
/// leaving a row leaves the highlight on the last-hovered (== activatable) row.
/// The visible highlight and the Return target are therefore always the same row.
/// Arrow keys move the highlight, Return activates it, Esc cancels.
///
/// The view performs no launching or pasteboard work itself; those are the
/// closures the panel controller injects into the view model. Live rendering and
/// keyboard selection are validated by Post-Completion manual verification.
struct BrowserPickerView: View {
    @Bindable var viewModel: PickerViewModel

    /// Supplies each browser's real app icon. Defaulted so existing call sites keep
    /// compiling and `#Preview` can pass a stub that doesn't depend on installed apps.
    let iconProvider: BrowserIconProviding

    /// The row id the mouse is currently hovering, if any (drives the hover
    /// highlight). Internal (not `private`) so the row-rendering extension in
    /// `BrowserPickerRows.swift` can read/update it.
    @State var hoveredItemID: PickerViewModel.SelectableItem.ID?

    /// Owns keyboard focus so arrow keys / Return are delivered to the list.
    @FocusState private var listFocused: Bool

    init(viewModel: PickerViewModel, iconProvider: BrowserIconProviding = WorkspaceBrowserIconProvider()) {
        self.viewModel = viewModel
        self.iconProvider = iconProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if viewModel.selectableItems.isEmpty {
                emptyState
            } else {
                browserList
            }

            if let host = viewModel.rememberHost {
                Toggle("Remember choice for \(host)", isOn: $viewModel.rememberChoice)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            Divider()

            footer
        }
        .padding(16)
        // Zero-frame button hosting the ⌘, shortcut as a background so it joins
        // the responder chain without reserving layout space. Do NOT use
        // `.hidden()` — it removes the view from SwiftUI's event-delivery
        // hierarchy and the shortcut would silently fail.
        .background(
            Button("") {
                viewModel.openSettings(tab: .general)
            }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .frame(width: 390)
        // Paint the popup's own card: the hosting NSPanel is borderless and
        // transparent, so this background IS what the user sees as the "popup".
        // Solid system background + rounded corners approximates a sheet-style
        // card (the rule editor uses native SwiftUI .sheet chrome, not custom
        // styling — so this is the closest match achievable without a parent
        // window to sheet against).
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .focusable()
        .focused($listFocused)
        // Keep keyboard focus (so arrow keys / Return reach the list) but suppress
        // the system focus ring — this is a transient panel, not a form field, so the
        // blue outline around the whole content reads as a glitch.
        .focusEffectDisabled()
        .onAppear { listFocused = true }
        .onKeyPress(.upArrow) {
            viewModel.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.activateSelection()
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                    Text("Open Link In…")
                        .font(.headline)
                }
                Text(viewModel.urlString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Button {
                viewModel.openSettings(tab: .rules)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Edit Rules")
            .accessibilityLabel("Edit Rules")
        }
    }

    private var browserList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Aliases section header, shown only when the list leads with alias rows.
                if hasAliasRows {
                    Text("Aliases")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 2)
                }

                ForEach(Array(viewModel.selectableItems.enumerated()), id: \.element.id) { index, item in
                    // Separate the Aliases group from the browsers with a divider +
                    // "Browsers" header at the first browser row.
                    if hasAliasRows, isFirstBrowserRow(at: index) {
                        Divider()
                            .padding(.vertical, 4)
                        Text("Browsers")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)
                    }
                    row(for: item, at: index)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private var emptyState: some View {
        Text("No browsers found.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                viewModel.copyURL()
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            Spacer()

            Button("Cancel", role: .cancel) {
                viewModel.cancel()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

#if DEBUG
@MainActor
private func previewViewModel(
    browsers: [Browser],
    aliases: [ProfileAlias] = []
) -> PickerViewModel {
    PickerViewModel(
        url: URL(string: "https://www.rockpapershotgun.com/some/very/long/article/path")!,
        browsers: browsers,
        aliases: aliases,
        onSelect: { _, _, _ in },
        onCancel: {},
        onCopy: { _ in },
        onOpenSettings: { _ in }
    )
}

#Preview("Picker") {
    BrowserPickerView(
        viewModel: previewViewModel(browsers: PreviewFixtures.sampleBrowsers),
        iconProvider: PreviewIconProvider()
    )
}

#Preview("Picker — with aliases") {
    BrowserPickerView(
        viewModel: previewViewModel(
            browsers: PreviewFixtures.sampleBrowsers,
            aliases: PreviewFixtures.sampleAliases
        ),
        iconProvider: PreviewIconProvider()
    )
}

#Preview("Picker — empty") {
    BrowserPickerView(
        viewModel: previewViewModel(browsers: []),
        iconProvider: PreviewIconProvider()
    )
}
#endif
