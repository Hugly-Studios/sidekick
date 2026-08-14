import Darwin
import Foundation
import Security

/// Two independent checks: same uid, then the peer's code signature Team ID.
public enum PeerAuthenticator {
    public static func accept(_ fileDescriptor: Int32) throws {
        try checkUID(fileDescriptor)
        try checkSignature(fileDescriptor)
    }

    public static func checkUID(_ fileDescriptor: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fileDescriptor, &uid, &gid) == 0 else {
            throw ControlTransportError.peerRejected("getpeereid failed")
        }

        guard uid == getuid() else {
            throw ControlTransportError.peerRejected("peer uid \(uid) != \(getuid())")
        }
    }

    public static func checkSignature(_ fileDescriptor: Int32) throws {
        guard let teamID = localTeamID() else {
            // Ad-hoc builds have no team. UID match is the only public check.
            return
        }

        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        let tokenOption: Int32 = 0x006  // LOCAL_PEERTOKEN
        let status = withUnsafeMutablePointer(to: &token) { pointer in
            getsockopt(fileDescriptor, SOL_LOCAL, tokenOption, pointer, &length)
        }

        guard status == 0 else {
            throw ControlTransportError.peerRejected("LOCAL_PEERTOKEN unavailable")
        }

        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary

        var guest: SecCode?
        guard
            SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
            let guest
        else {
            throw ControlTransportError.peerRejected("cannot read peer code")
        }

        let requirement = try makeRequirement(teamID: teamID)
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, [], &staticCode) == errSecSuccess, let staticCode else {
            throw ControlTransportError.peerRejected("cannot copy peer static code")
        }

        guard SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess else {
            throw ControlTransportError.peerRejected("peer signature does not match team \(teamID)")
        }
    }

    /// Apple Development **or** Developer ID, same Team ID. A single OU check
    /// is not enough: the two certificate policies do not substitute for each other.
    static func requirementText(teamID: String) -> String {
        let development = """
            anchor apple generic \
            and certificate leaf[subject.OU] = "\(teamID)" \
            and certificate 1[field.1.2.840.113635.100.6.2.1]
            """
        let developerID = """
            anchor apple generic \
            and certificate 1[field.1.2.840.113635.100.6.2.6] \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] \
            and certificate leaf[subject.OU] = "\(teamID)"
            """
        return "(\(development)) or (\(developerID))"
    }

    public static func localTeamID() -> String? {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
                == errSecSuccess,
            let staticCode
        else { return nil }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &information
            ) == errSecSuccess,
            let details = information as? [String: Any]
        else { return nil }

        return details[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func makeRequirement(teamID: String) throws -> SecRequirement {
        let text = requirementText(teamID: teamID)

        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else {
            throw ControlTransportError.peerRejected("invalid code requirement")
        }

        return requirement
    }
}
