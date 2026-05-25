// TrafficWandCore
//
// Pure, AppKit-free core of TrafficWand. Hosts the routing decision logic,
// domain models, glob matching, configuration persistence, and browser/profile
// parsing. The macOS App target adapts this core to the system via thin
// protocol-conforming adapters.
//
// This file intentionally declares no symbols: the module's public surface is the
// concrete types in Models/, Matching/, Routing/, Config/, and Browsers/.
