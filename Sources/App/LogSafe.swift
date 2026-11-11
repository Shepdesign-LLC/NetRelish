// LogSafe.swift — what may be written to the system log about something that went wrong.
//
// The system log isn't private: other apps on this Mac can read it, and it travels inside a
// sysdiagnose. An error's own words can carry the page's address or a line of its text
// (WebKit's script errors do), and that is browsing data. So a log line says which kind of
// error it was, in the clear, and keeps what the error said private: it shows on this Mac
// while a developer is watching, and as <private> everywhere else.

import Foundation

/// The kind of error, with nothing the page or the person wrote in it: "NSURLErrorDomain -1009".
func errorKind(_ error: any Error) -> String {
    let bridged = error as NSError
    return "\(bridged.domain) \(bridged.code)"
}
