import Foundation
import Testing

@testable import ControlSurface

struct ControlCodecTests {
    @Test func requestRoundTrips() throws {
        let request = ControlRequest(operation: .run(id: "workspaces.capture", argument: "дом"))
        let frame = try ControlCodec.encode(request)
        let decoded = try ControlCodec.decode(frame, as: ControlRequest.self)

        #expect(decoded.id == request.id)
        #expect(decoded.operation == request.operation)
    }

    @Test func responseRoundTrips() throws {
        let response = ControlResponse.success(
            id: UUID(),
            payload: .run(message: "ok")
        )
        let frame = try ControlCodec.encode(response)
        let decoded = try ControlCodec.decode(frame, as: ControlResponse.self)

        #expect(decoded.ok)
        #expect(decoded.error == nil)
    }

    @Test func rejectsTruncatedFrame() {
        #expect(throws: ControlCodecError.self) {
            try ControlCodec.decode(Data([0, 0]), as: ControlRequest.self)
        }
    }
}
