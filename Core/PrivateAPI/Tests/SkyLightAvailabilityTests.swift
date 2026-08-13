import CoreGraphics
import Foundation
import Testing

@testable import PrivateAPI

/// Canary suite: it fails when a macOS update moves or renames the private
/// entry points Workspaces depends on, instead of letting the feature break
/// silently on users' machines.
struct SkyLightAvailabilityTests {
    private var hasWindowServerSession: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    @Test func skyLightImageLoads() {
        #expect(SkyLightBridge.shared != nil)
    }

    @Test func bridgedMoveEntryPointsExist() {
        #expect(
            MachOSymbols.localSymbol(
                imagePath: SkyLightBridge.imagePath,
                name: SkyLightBridge.performBridgedOperationSymbol
            ) != nil
        )
        #expect(NSClassFromString(SkyLightBridge.bridgedMoveOperationClass) != nil)
    }

    @Test func unknownSymbolIsNotFound() {
        #expect(
            MachOSymbols.localSymbol(
                imagePath: SkyLightBridge.imagePath,
                name: "__ZL0SidekickSymbolThatCannotExist"
            ) == nil
        )
    }

    @Test func unknownImageIsNotFound() {
        #expect(
            MachOSymbols.localSymbol(
                imagePath:
                    "/System/Library/PrivateFrameworks/NotAFramework.framework/NotAFramework",
                name: SkyLightBridge.performBridgedOperationSymbol
            ) == nil
        )
    }

    @Test func displaysExposeSpacesInOrder() throws {
        try #require(hasWindowServerSession, "requires a GUI session")
        let spaces = try #require(SkyLightSpaces())

        let displays = spaces.displays()
        try #require(!displays.isEmpty)

        for display in displays {
            #expect(!display.displayUUID.isEmpty)
            #expect(display.spaces.map(\.index) == Array(1...display.spaces.count))
        }
    }

    @Test func currentSpaceIsOneOfTheDisplaySpaces() throws {
        try #require(hasWindowServerSession, "requires a GUI session")
        let spaces = try #require(SkyLightSpaces())

        let mainDisplay = try #require(spaces.displays().first)

        #expect(mainDisplay.spaces.map(\.id).contains(mainDisplay.currentSpaceID))
    }
}

struct SpaceKindTests {
    @Test func mapsRawTypes() {
        #expect(SpaceKind(rawType: 0) == .user)
        #expect(SpaceKind(rawType: 4) == .fullscreen)
        #expect(SpaceKind(rawType: 2) == .other(2))
    }
}
