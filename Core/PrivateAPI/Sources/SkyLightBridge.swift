import CoreGraphics
import Foundation

/// Runtime access to the SkyLight private framework.
///
/// SkyLight ships only inside the dyld shared cache, so there is nothing to link
/// against: the framework is opened with `dlopen` and every entry point is
/// resolved by name. If a future macOS renames or removes one of them, the
/// bridge reports it as unavailable instead of failing to launch.
final class SkyLightBridge: @unchecked Sendable {
    // Function pointers into a dlopened image: resolved once, immutable for the
    // lifetime of the process.

    static let imagePath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// File-local symbol, only reachable through the image's symbol table.
    static let performBridgedOperationSymbol =
        "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"

    static let bridgedMoveOperationClass = "SLSBridgedMoveWindowsToManagedSpaceOperation"

    typealias MainConnectionID = @convention(c) () -> Int32
    typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> CFArray?
    typealias ManagedDisplayGetCurrentSpace = @convention(c) (Int32, CFString) -> UInt64
    typealias CopyWindowsWithOptionsAndTags =
        @convention(c) (
            Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>,
            UnsafeMutablePointer<UInt64>
        ) -> CFArray?
    typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> CFArray?
    typealias PerformBridgedOperation = @convention(c) (UnsafeRawPointer) -> Int64
    typealias MsgSendAlloc = @convention(c) (AnyClass, Selector) -> AnyObject?
    typealias MsgSendInitWithWindowsSpaceID =
        @convention(c) (
            AnyObject, Selector, NSArray, UInt64
        ) -> AnyObject?

    static let shared: SkyLightBridge? = SkyLightBridge()

    let connectionID: Int32

    private let copyManagedDisplaySpaces: CopyManagedDisplaySpaces
    private let managedDisplayGetCurrentSpace: ManagedDisplayGetCurrentSpace
    private let copyWindowsWithOptionsAndTags: CopyWindowsWithOptionsAndTags
    private let copySpacesForWindows: CopySpacesForWindows
    private let msgSend: UnsafeMutableRawPointer

    private init?() {
        guard let skyLight = dlopen(Self.imagePath, RTLD_LAZY),
            let mainConnectionID = dlsym(skyLight, "SLSMainConnectionID"),
            let copyManagedDisplaySpaces = dlsym(skyLight, "SLSCopyManagedDisplaySpaces"),
            let managedDisplayGetCurrentSpace = dlsym(skyLight, "SLSManagedDisplayGetCurrentSpace"),
            let copyWindowsWithOptionsAndTags = dlsym(skyLight, "SLSCopyWindowsWithOptionsAndTags"),
            let copySpacesForWindows = dlsym(skyLight, "SLSCopySpacesForWindows"),
            let msgSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")
        else { return nil }

        self.connectionID = unsafeBitCast(mainConnectionID, to: MainConnectionID.self)()
        self.copyManagedDisplaySpaces = unsafeBitCast(
            copyManagedDisplaySpaces,
            to: CopyManagedDisplaySpaces.self
        )
        self.managedDisplayGetCurrentSpace = unsafeBitCast(
            managedDisplayGetCurrentSpace,
            to: ManagedDisplayGetCurrentSpace.self
        )
        self.copyWindowsWithOptionsAndTags = unsafeBitCast(
            copyWindowsWithOptionsAndTags,
            to: CopyWindowsWithOptionsAndTags.self
        )
        self.copySpacesForWindows = unsafeBitCast(
            copySpacesForWindows,
            to: CopySpacesForWindows.self
        )
        self.msgSend = msgSend
    }

    /// Raw `Spaces` description keyed by display, in on-screen order.
    func managedDisplaySpaces() -> [[String: Any]] {
        copyManagedDisplaySpaces(connectionID) as? [[String: Any]] ?? []
    }

    func currentSpaceID(displayUUID: String) -> UInt64 {
        managedDisplayGetCurrentSpace(connectionID, displayUUID as CFString)
    }

    func windowIDs(onSpace spaceID: UInt64) -> [CGWindowID] {
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0

        return withUnsafeMutablePointer(to: &setTags) { setTagsPointer in
            withUnsafeMutablePointer(to: &clearTags) { clearTagsPointer in
                copyWindowsWithOptionsAndTags(
                    connectionID,
                    0,
                    [spaceID] as CFArray,
                    Self.includeMinimizedWindowsOption,
                    setTagsPointer,
                    clearTagsPointer
                ) as? [CGWindowID] ?? []
            }
        }
    }

    func spaceIDs(ofWindow windowID: CGWindowID) -> [UInt64] {
        copySpacesForWindows(
            connectionID,
            Self.allSpacesSelector,
            [windowID] as CFArray
        ) as? [UInt64] ?? []
    }

    /// Asks the WindowServer to move windows to a space.
    ///
    /// The plain `SLSMoveWindowsToManagedSpace` entry point is a no-op for
    /// processes that do not own the WindowServer connection (verified on 26.5.1),
    /// so the bridged operation is the only path that works without disabling SIP.
    /// The operation is asynchronous — callers must verify the result.
    func requestBridgedMove(windowIDs: [CGWindowID], toSpace spaceID: UInt64) throws {
        guard
            let performSymbol = MachOSymbols.localSymbol(
                imagePath: Self.imagePath,
                name: Self.performBridgedOperationSymbol
            )
        else {
            throw PrivateAPIError.symbolUnavailable(Self.performBridgedOperationSymbol)
        }

        guard let operationClass = NSClassFromString(Self.bridgedMoveOperationClass) else {
            throw PrivateAPIError.symbolUnavailable(Self.bridgedMoveOperationClass)
        }

        let alloc = unsafeBitCast(msgSend, to: MsgSendAlloc.self)
        let initWithWindowsSpaceID = unsafeBitCast(
            msgSend,
            to: MsgSendInitWithWindowsSpaceID.self
        )

        guard let allocated = alloc(operationClass, NSSelectorFromString("alloc")),
            let operation = initWithWindowsSpaceID(
                allocated,
                NSSelectorFromString("initWithWindows:spaceID:"),
                windowIDs.map(NSNumber.init(value:)) as NSArray,
                spaceID
            )
        else {
            throw PrivateAPIError.symbolUnavailable(
                "\(Self.bridgedMoveOperationClass) -initWithWindows:spaceID:"
            )
        }

        let perform = unsafeBitCast(performSymbol, to: PerformBridgedOperation.self)
        _ = perform(Unmanaged.passUnretained(operation).toOpaque())
    }

    /// `SLSCopyWindowsWithOptionsAndTags` option that includes minimized windows.
    private static let includeMinimizedWindowsOption: UInt32 = 0x2

    /// `SLSCopySpacesForWindows` selector covering all spaces a window lives on.
    private static let allSpacesSelector: Int32 = 0x7
}
