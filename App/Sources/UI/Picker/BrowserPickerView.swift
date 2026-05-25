import SwiftUI
import TrafficWandCore

/// The floating picker UI: shows the link being routed and the list of browsers
/// (with their profiles), lets the user pick a destination by click or keyboard,
/// copy the URL, or cancel (Esc).
///
/// All behavior flows through `PickerViewModel`:
///  - tapping a browser with no profiles → `select(browser:profile:nil)`;
///  - tapping a specific profile → `select(browser:profile:)`;
///  - the Copy URL button → `copyURL()`;
///  - the Cancel button / Esc → `cancel()`.
///
/// The view performs no launching or pasteboard work itself; those are the
/// closures the panel controller injects into the view model. Live rendering and
/// keyboard selection are validated by Post-Completion manual verification.
struct BrowserPickerView: View {
    let viewModel: PickerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            if viewModel.browsers.isEmpty {
                emptyState
            } else {
                browserList
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open Link In…")
                .font(.headline)
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
            VStack(spacing: 4) {
                ForEach(viewModel.browsers) { browser in
                    BrowserRow(browser: browser) { profile in
                        viewModel.select(browser: browser, profile: profile)
                    }
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

/// A single browser row: a button selecting the browser's default profile, plus a
/// sub-button per discovered profile when the browser has any.
private struct BrowserRow: View {
    let browser: Browser
    /// Called with the chosen profile (`nil` = default profile).
    let onSelect: (BrowserProfile?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                onSelect(nil)
            } label: {
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(browser.name)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !browser.profiles.isEmpty {
                ForEach(browser.profiles) { profile in
                    Button {
                        onSelect(profile)
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                            Text(profile.name)
                                .font(.callout)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 24)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
