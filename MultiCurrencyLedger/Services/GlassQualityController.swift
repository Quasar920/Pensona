import Foundation

enum GlassQuality: Equatable {
    case full
    case simplified
}

struct GlassQualityController {
    static func quality(
        reduceTransparency: Bool,
        isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        forceSimplified: Bool = false
    ) -> GlassQuality {
        if forceSimplified || reduceTransparency || isLowPowerMode {
            return .simplified
        }
        switch thermalState {
        case .serious, .critical:
            return .simplified
        case .nominal, .fair:
            return .full
        @unknown default:
            return .simplified
        }
    }
}
