import os

/// Unified logging. The subsystem keeps the legacy bundle identifier so logs, TCC grants
/// and stored settings stay continuous across the VoiceText → Voxara rename.
public enum VoxaraLog {
    public static let subsystem = "com.daniel.voicetext"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
