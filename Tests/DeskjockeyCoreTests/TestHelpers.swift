import Foundation
@testable import DeskjockeyCore

final class MockDisplayManager: DisplayManaging {
    var displays: [DisplaySnapshot]
    var applied: [DisplayConfiguration] = []

    init(displays: [DisplaySnapshot]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplaySnapshot] {
        displays
    }

    func apply(configuration: DisplayConfiguration, to display: DisplaySnapshot) throws {
        applied.append(configuration)
    }
}

final class InMemoryProfileStore: MonitorProfileStoring {
    private var profiles: [MonitorSetProfile] = []

    func loadProfiles() throws -> [MonitorSetProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [MonitorSetProfile]) throws {
        self.profiles = profiles
    }
}

struct ImmediateSleepManager: SleepManaging {
    func sleep(milliseconds: UInt64) async {}
}
