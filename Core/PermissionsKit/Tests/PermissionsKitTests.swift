import AppCore
import Foundation
import Testing

@testable import PermissionsKit

@MainActor
struct PermissionsKitTests {
    @Test func everyKindHasASettingsURL() {
        for kind in PermissionKind.allCases {
            #expect(URL(string: kind.settingsURL) != nil)
        }
    }

    @Test func liveCheckerAnswersKnownKinds() {
        let checker = LivePermissionChecker()

        for kind in PermissionKind.allCases {
            _ = checker.status(of: kind)
        }
    }
}
