import AppKit
import Foundation

/// 戏仿音效（SPEC §9.4 / settings.soundEnabled）。
/// NSSound(named:) 播系统自带音色；找不到或关闭时静默。
@MainActor
enum SoundService {
    enum Cue {
        case completed, rateLimited, quotaReplenished, teapot

        var systemName: String {
            switch self {
            case .completed: return "Glass"
            case .rateLimited: return "Basso"
            case .quotaReplenished: return "Pop"
            case .teapot: return "Frog"
            }
        }
    }

    static func play(_ cue: Cue, enabled: Bool) {
        guard enabled, let sound = NSSound(named: cue.systemName) else { return }
        sound.play()
    }
}
