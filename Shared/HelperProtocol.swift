import Foundation

/// The XPC contract between DFU Pulse and its privileged helper. Each side
/// checks the other's code signature, so only this team's builds can talk.
@objc protocol DFUHelperProtocol {
    /// Runs `macvdmtool dfu` as root; replies with its exit status and output.
    func enterDFU(withReply reply: @escaping @Sendable (Int32, String) -> Void)
}

enum HelperIdentity {
    static let teamID = "6LKS98VG4F"
    static let machService = "fr.bartox.DFUPulse.helper"
    static let plistName = "fr.bartox.DFUPulse.helper.plist"

    static func requirement(identifier: String) -> String {
        #"identifier "\#(identifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(teamID)""#
    }
}
