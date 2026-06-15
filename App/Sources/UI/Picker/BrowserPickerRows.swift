import SwiftUI
import TrafficWandCore

/// Row rendering for `BrowserPickerView`, factored into an extension so the main
/// view file stays within size limits. Renders the flattened
/// `PickerViewModel.SelectableItem` list: an "Aliases" group (alias name + resolved
/// browser/profile secondary label) above the browser groups, each browser-default
/// row leading its profile sub-rows. Selection routes through
/// `viewModel.select(item:)`; hover/keyboard highlighting and group spacing match
/// the original inline implementation.
extension BrowserPickerView {

    /// Whether the flattened list leads with one or more alias rows (drives the
    /// "Aliases" section header).
    var hasAliasRows: Bool {
        if case .alias = viewModel.selectableItems.first?.kind { return true }
        return false
    }

    /// True when the item at `index` is the first browser row in the list (the
    /// boundary between the Aliases group and the browser groups).
    func isFirstBrowserRow(at index: Int) -> Bool {
        let items = viewModel.selectableItems
        guard index < items.count, case .browser = items[index].kind else { return false }
        if index == 0 { return true }
        if case .alias = items[index - 1].kind { return true }
        return false
    }

    @ViewBuilder
    func row(for item: PickerViewModel.SelectableItem, at index: Int) -> some View {
        let isFirst = index == 0

        Button {
            viewModel.select(item: item)
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
        // Extra top spacing before each new browser group, except the very first
        // row — and also before the first browser row when alias rows precede it,
        // so the Aliases group is visually separated from the browsers.
        .padding(.top, topSpacing(for: item, at: index, isFirst: isFirst))
    }

    /// Top padding inserted before a row: a gap before each browser-group leader
    /// (the browser's default row) except the very first row in the list.
    private func topSpacing(for item: PickerViewModel.SelectableItem, at index: Int, isFirst: Bool) -> CGFloat {
        guard !isFirst else { return 0 }
        switch item.kind {
        case .alias:
            return 0
        case .browser(_, let profile):
            // A profile sub-row hugs its parent; a browser-default row leads a group.
            return profile == nil ? 6 : 0
        }
    }

    @ViewBuilder
    private func rowLabel(for item: PickerViewModel.SelectableItem) -> some View {
        switch item.kind {
        case .alias(let alias):
            aliasRowLabel(for: alias)
        case .browser(let browser, let profile):
            if let profile {
                profileRowLabel(profile)
            } else {
                browserRowLabel(browser)
            }
        }
    }

    /// An alias row: the alias name (primary) with the resolved browser/profile as a
    /// secondary line, fronted by the resolved browser's icon.
    @ViewBuilder
    private func aliasRowLabel(for alias: ProfileAlias) -> some View {
        HStack(spacing: 8) {
            if let browser = viewModel.browsers.first(where: { $0.bundleID == alias.target.bundleID }) {
                Image(nsImage: iconProvider.icon(for: browser))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(alias.name)
                    .font(.callout)
                if let secondary = aliasSecondaryLabel(for: alias) {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The resolved "Browser — Profile" (or just "Browser") secondary label for an
    /// alias, or nil if the target browser isn't among the offered browsers.
    private func aliasSecondaryLabel(for alias: ProfileAlias) -> String? {
        guard let browser = viewModel.browsers.first(where: { $0.bundleID == alias.target.bundleID }) else {
            return nil
        }
        if let profileID = alias.target.profileID,
           let profile = browser.profiles.first(where: { $0.id == profileID }) {
            return "\(browser.name) — \(profile.name)"
        }
        return browser.name
    }

    @ViewBuilder
    private func profileRowLabel(_ profile: BrowserProfile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text(profile.name)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.leading, 28)
    }

    @ViewBuilder
    private func browserRowLabel(_ browser: Browser) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: iconProvider.icon(for: browser))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(browser.name)
            Spacer(minLength: 0)
        }
    }

    /// Background fill for a row: hover wins, otherwise the keyboard-selected row.
    /// The selected row is highlighted from the start (the panel takes focus on
    /// appear), so the visibly highlighted row always matches the Return target.
    @ViewBuilder
    func highlightBackground(for item: PickerViewModel.SelectableItem, at index: Int) -> some View {
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
}

/// Row button style: no default chrome (plain), full-row hit target, and a subtle
/// press effect (slightly dimmed + scaled) so taps feel responsive.
struct PickerRowButtonStyle: ButtonStyle {
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
