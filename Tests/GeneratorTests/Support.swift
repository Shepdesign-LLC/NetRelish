import Foundation

/// Repo root, derived from this file's location so tests work from `swift test` and Xcode alike.
let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // GeneratorTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // repo

/// Runs `swift <script> <args>` and returns (exitCode, stdout, stderr).
func runScript(_ script: String, _ args: [String]) throws -> (Int32, String, String) {
    let p = Process()
    // /usr/bin/swift is the xcode-select shim; tests run inside the app host, whose PATH is minimal.
    p.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    p.arguments = [repoRoot.appendingPathComponent(script).path] + args
    p.currentDirectoryURL = repoRoot   // script arguments are repo-relative
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let o = out.fileHandleForReading.readDataToEndOfFile()
    let e = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
}
