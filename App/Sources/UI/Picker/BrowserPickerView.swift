import SwiftUI
import TrafficWandCore

/// The floating picker UI: shows the link being routed and the list of browsers
/// (with their profiles), lets the user pick a destination by click or keyboard,
/// copy the URL, or cancel (Esc).
///
/// All behavior flows through `PickerViewModel`:
///  - tapping a browser-default row → `select(browser:profile:nil)`;
///  - tapping a profile sub-row → `select(browser:profile:)`;
///  - the Copy URL button → `copyURL()`;
///  - the Cancel button / Esc → `cancel()`.
///
/// Rows are driven by `viewModel.selectableItems` (a flattened browser-default →
/// profiles sequence). Each row is a hoverable, pointer-cursor button with press
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

    /// The row id the mouse is currently hovering, if any (drives the hover highlight).
    @State private var hoveredItemID: PickerViewModel.SelectableItem.ID?

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
        .frame(width: 390)
        .focusable()
        .focused($listFocused)
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
    }

    private var browserList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(viewModel.selectableItems.enumerated()), id: \.element.id) { index, item in
                    row(for: item, at: index)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    @ViewBuilder
    private func row(for item: PickerViewModel.SelectableItem, at index: Int) -> some View {
        let isFirst = index == 0
        let isBrowserRow = item.profile == nil

        Button {
            viewModel.select(browser: item.browser, profile: item.profile)
        } label: {
            rowLabel(for: item)
        }
        .buttonStyle(PickerRowButtonStyle())
        .pointerStyle(.link)
        .background(highlightBackground(for: item, at: index))
        .onHover { hovering in
            if hovering {
                hoveredItemID = item.id
                // Keep keyboard and mouse in agreement: hovering a row makes it the
                // selection target, so a subsequent Return activates the hovered row
                // and, once the mouse leaves, the highlight stays on that row.
                viewModel.selectedIndex = index
            } else if hoveredItemID == item.id {
                hoveredItemID = nil
            }
        }
        // Extra top spacing before each browser group, except the very first row.
        .padding(.top, isBrowserRow && !isFirst ? 6 : 0)
    }

    @ViewBuilder
    private func rowLabel(for item: PickerViewModel.SelectableItem) -> some View {
        if let profile = item.profile {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text(profile.name)
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.leading, 28)
        } else {
            HStack(spacing: 8) {
                Image(nsImage: iconProvider.icon(for: item.browser))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(item.browser.name)
                Spacer(minLength: 0)
            }
        }
    }

    /// Background fill for a row: hover wins, otherwise the keyboard-selected row.
    /// The selected row is highlighted from the start (the panel takes focus on
    /// appear), so the visibly highlighted row always matches the Return target.
    @ViewBuilder
    private func highlightBackground(for item: PickerViewModel.SelectableItem, at index: Int) -> some View {
        let isHovered = hoveredItemID == item.id
        let isSelected = index == viewModel.selectedIndex
        let fill: Color? = {
            if isHovered { return Color.accentColor.opacity(0.18) }
            if isSelected { return Color.accentColor.opacity(0.12) }
            return nil
        }()

        if let fill {
            RoundedRectangle(cornerRadius: 8)
                .fill(fill)
        }
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

/// Row button style: no default chrome (plain), full-row hit target, and a subtle
/// press effect (slightly dimmed + scaled) so taps feel responsive.
private struct PickerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#if DEBUG
/// Stub icon provider so previews never depend on which browsers are installed.
private struct PreviewIconProvider: BrowserIconProviding {
    func icon(for browser: Browser) -> NSImage {
        NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
    }
}

@MainActor
private func previewViewModel(browsers: [Browser]) -> PickerViewModel {
    PickerViewModel(
        url: URL(string: "https://www.rockpapershotgun.com/some/very/long/article/path")!,
        browsers: browsers,
        onSelect: { _, _ in },
        onCancel: {},
        onCopy: { _ in }
    )
}

#Preview("Picker") {
    BrowserPickerView(
        viewModel: previewViewModel(browsers: [
            Browser(
                bundleID: "com.google.Chrome",
                name: "Google Chrome",
                appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                profiles: [
                    BrowserProfile(id: "Default", name: "Personal"),
                    BrowserProfile(id: "Profile 1", name: "Work")
                ]
            ),
            Browser(
                bundleID: "org.mozilla.firefox",
                name: "Firefox",
                appURL: URL(fileURLWithPath: "/Applications/Firefox.app"),
                profiles: []
            ),
            Browser(
                bundleID: "com.apple.Safari",
                name: "Safari",
                appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                profiles: []
            )
        ]),
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
