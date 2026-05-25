// TrafficWandCore
//
// Pure, AppKit-free core of TrafficWand. Hosts the routing decision logic,
// domain models, glob matching, configuration persistence, and browser/profile
// parsing. The macOS App target adapts this core to the system via thin
// protocol-conforming adapters.
//
// This placeholder marks the package as buildable; concrete types are added in
// subsequent tasks.

/// Marker enum describing this package. Carries no behavior; exists so the
/// module has a stable, documented entry symbol from the very first task.
public enum TrafficWandCore {
    /// Human-readable name of this package.
    public static let name = "TrafficWandCore"
}
