import Foundation

struct BatteryState: Equatable {
    var leftPct: Int? = nil
    var rightPct: Int? = nil
    var casePct: Int? = nil
    var leftCharging: Bool = false
    var rightCharging: Bool = false
    var caseCharging: Bool = false

    var lowestPct: Int? {
        [leftPct, rightPct].compactMap { $0 }.min()
    }
}
