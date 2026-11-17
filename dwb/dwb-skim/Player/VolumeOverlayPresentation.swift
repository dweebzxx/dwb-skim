import AppKit

struct VideoVolumeMeterPresentation: Equatable {
    static let regularVolumeMaximum = 100
    static let maximumVolume = 200

    let volume: Int
    /// The independently rendered 0...100% regular-volume meter fill.
    let regularLevel: Double
    /// The independently rendered 101...200% overdrive meter fill.
    let overdriveLevel: Double
    let isMuted: Bool
    let percentageText: String
    let symbolName: String

    init(volume: Int, muted: Bool) {
        let clamped = min(Self.maximumVolume, max(0, volume))
        self.volume = clamped
        self.regularLevel = Double(min(clamped, Self.regularVolumeMaximum)) / Double(Self.regularVolumeMaximum)
        self.overdriveLevel = Double(max(0, clamped - Self.regularVolumeMaximum))
            / Double(Self.maximumVolume - Self.regularVolumeMaximum)
        self.isMuted = muted || clamped == 0
        self.percentageText = "\(clamped)%"
        self.symbolName = self.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }
}

/// Segment and heat math for the volume HUD (design system, "Volume HUD (all apps, 0–200%)").
/// The first group has 7 segments across 0–100%; the boost group has 4, one per 25% above 100%.
/// Muted lights nothing and never heats.
extension VideoVolumeMeterPresentation {
    static let regularSegmentCount = 7
    static let boostSegmentCount = 4
    static let boostStepPercent = 25
    /// Heat starts here and reaches full strength at `maximumVolume`.
    static let heatStartVolume = 150

    /// Lit segments in the 0–100% group. The lit count rounds up (suite rule SD-039): segment `i`
    /// (0-based) lights once the volume passes `i * 100 / 7` percent, so the segments light at
    /// 1, 15, 29, 43, 58, 72, and 86%. 100% lights all seven.
    var litRegularSegments: Int {
        guard !isMuted else { return 0 }
        let scaled = min(volume, Self.regularVolumeMaximum) * Self.regularSegmentCount
        return (scaled + Self.regularVolumeMaximum - 1) / Self.regularVolumeMaximum
    }

    /// Lit segments in the boost group. The lit count rounds up (suite rule SD-039): the boost segments
    /// light at 101, 126, 151, and 176%. 200% lights all four.
    var litBoostSegments: Int {
        guard !isMuted else { return 0 }
        let boost = max(0, volume - Self.regularVolumeMaximum)
        return min(Self.boostSegmentCount, (boost + Self.boostStepPercent - 1) / Self.boostStepPercent)
    }

    /// 0 up to 150%, then (volume − 150) / 50: 0.5 at 175%, 1 at 200%.
    var heatFraction: Double {
        guard !isMuted else { return 0 }
        let span = Double(Self.maximumVolume - Self.heatStartVolume)
        return min(1, max(0, Double(volume - Self.heatStartVolume) / span))
    }

    /// A segment color blended toward `heatColor` by `heatFraction`.
    static func heatedColor(_ base: NSColor, heatFraction: Double, heatColor: NSColor = DWBColor.errorFill) -> NSColor {
        guard heatFraction > 0 else { return base }
        return base.blended(withFraction: CGFloat(heatFraction), of: heatColor) ?? base
    }
}

enum VolumeOverlayTiming {
    static let dismissalDelay: TimeInterval = DWBMotion.volumeHold
    static let fadeDuration: TimeInterval = DWBMotion.fade
}
