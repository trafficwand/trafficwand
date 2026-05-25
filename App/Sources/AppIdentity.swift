import Foundation

/// App-wide identity constants.
///
/// Centralizes the reverse-DNS identifier so the `os.Logger` subsystem used across
/// the app is defined in exactly one place.
enum AppIdentity {
    /// The logging subsystem shared by every `os.Logger` in the app.
    static let subsystem = "com.tomakado.TrafficWand"
}
