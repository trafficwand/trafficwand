import Foundation

/// One page of the first-launch onboarding flow.
///
/// Each case is a single concept, advanced with Back / Next. The pages are, in
/// order: point at the menu bar, set TrafficWand as the default browser, explain
/// rules, explain aliases. The aliases (last) page's primary action deep-links to
/// the Rules tab in Settings (issue #9's "button to open rules editor / settings").
///
/// Every page exposes a `title`, a `body`, and an `image` source. The image is
/// either a named asset (a real screenshot the user drops into the asset catalog)
/// or a code-drawn illustration rasterized to a flat image — every page renders a
/// non-interactive `Image`, so a visual can never be mistaken for a live control.
/// Live actions (Set as Default, Open Settings, Next / Back) live only in the
/// footer.
enum OnboardingPage: CaseIterable {
    case menuBar
    case defaultBrowser
    case rules
    case aliases

    /// The page's headline.
    var title: String {
        switch self {
        case .menuBar:
            return "TrafficWand lives in your menu bar"
        case .defaultBrowser:
            return "Make TrafficWand your default browser"
        case .rules:
            return "Route links automatically with rules"
        case .aliases:
            return "Reuse a browser + profile with aliases"
        }
    }

    /// The page's supporting body copy.
    var body: String {
        switch self {
        case .menuBar:
            return "Look for the TrafficWand icon in the menu bar at the top of "
                + "your screen. That's where you'll find settings and quick actions."
        case .defaultBrowser:
            return "Set TrafficWand as your default browser so every link opens "
                + "through it — then it can route each link to the right browser "
                + "for you."
        case .rules:
            return "Create rules that match a site and send it straight to a "
                + "specific browser or profile — no picker, no clicks."
        case .aliases:
            return "An alias is a reusable name for a browser + profile. Point a "
                + "rule at an alias, and re-pointing the alias later re-routes "
                + "every rule that uses it."
        }
    }

    /// The source of the page's framed visual.
    enum ImageSource: Equatable {
        /// A named image asset (a real screenshot the user drops into the catalog).
        case asset(String)
        /// A code-drawn illustration rasterized to an `NSImage` at render time.
        case rendered
    }

    /// Where the page's framed visual comes from: a named screenshot asset, or the
    /// rendered menu-bar illustration.
    var image: ImageSource {
        switch self {
        case .menuBar:
            return .rendered
        case .defaultBrowser:
            return .asset("onboarding-default-browser")
        case .rules:
            return .asset("onboarding-rules")
        case .aliases:
            return .asset("onboarding-aliases")
        }
    }
}
