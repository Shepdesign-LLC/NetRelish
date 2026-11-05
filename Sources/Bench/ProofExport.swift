// ProofExport.swift — Export Proof (Pro, ADR 0022): what a sealed page said, and when, in a
// form anyone can check without NetRelish.
//
// It saves one folder holding:
//   Proof.pdf               one page: the page, its address, when it was sealed, the
//                           fingerprint and the timestamp, in plain words
//   Saved copy.webarchive   the saved copy itself, byte for byte
//   Timestamp.tst           the authority's signed token (RFC 3161), when there is one
//   How to check.txt        the two standard commands that check the other files
//
// The PDF is drawn from a SwiftUI view, in the light scheme whatever the Mac uses, because
// it's meant for paper. Neutral tokens only; no relish (manifest §4).

import AppKit
import Pantry
import SwiftUI

enum ProofExport {
    /// Writes the proof into a new folder at `folder`. A folder already there (the save panel
    /// asked before replacing it) goes to the Trash first.
    @MainActor
    static func write(item: Item, provenance: Provenance, archive: Data, jarName: String?, to folder: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: folder.path) {
            try files.trashItem(at: folder, resultingItemURL: nil)
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: false)
        try archive.write(to: folder.appendingPathComponent(ProofText.archiveFile), options: .atomic)
        if let stamp = provenance.timestamp {
            try stamp.token.write(to: folder.appendingPathComponent(ProofText.tokenFile), options: .atomic)
        }
        try Data(ProofText.howToCheck(provenance).utf8)
            .write(to: folder.appendingPathComponent(ProofText.howToCheckFile), options: .atomic)
        let page = ProofPage(item: item, provenance: provenance, jarName: jarName)
        try pdf(page).write(to: folder.appendingPathComponent(ProofText.pdfFile), options: .atomic)
    }

    /// One US Letter page, drawn from `page`.
    @MainActor
    static func pdf(_ page: ProofPage) -> Data {
        let renderer = ImageRenderer(content: page
            .frame(width: ProofPage.size.width, height: ProofPage.size.height)
            .environment(\.colorScheme, .light))
        let data = NSMutableData()
        // The tokens are dynamic system colors; draw them as they look in Light mode.
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let consumer = CGDataConsumer(data: data as CFMutableData),
                      let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
                context.closePDF()
            }
        }
        return data as Data
    }
}

/// The proof's one page.
struct ProofPage: View {
    static let size = CGSize(width: 612, height: 792)   // US Letter, in points

    let item: Item
    let provenance: Provenance
    let jarName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NRSpace.sp6) {
            VStack(alignment: .leading, spacing: NRSpace.sp1) {
                Text(ProofText.heading)
                    .font(NRType.font(NRType.fsXl, weight: .semibold)).foregroundStyle(NRColor.fg)
                Text(ProofText.made(Date()))
                    .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg2)
            }
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            VStack(alignment: .leading, spacing: NRSpace.sp4) {
                ForEach(ProofText.rows(item: item, provenance: provenance, jarName: jarName), id: \.label) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label.uppercased())
                            .font(NRType.font(NRType.fsXs, weight: .medium)).foregroundStyle(NRColor.fg2)
                        Text(row.value)
                            .font(NRType.font(NRType.fsSm, design: row.isCode ? NRType.fontMono : NRType.fontUI))
                            .foregroundStyle(NRColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Rectangle().fill(NRColor.hairline).frame(height: NRSpace.hairline)
            Text(ProofText.whatItProves(provenance))
                .font(NRType.font(NRType.fsSm)).foregroundStyle(NRColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(ProofText.footer)
                .font(NRType.font(NRType.fsXs)).foregroundStyle(NRColor.fg3)
        }
        .padding(54)   // three-quarter-inch margins
        .frame(width: ProofPage.size.width, height: ProofPage.size.height, alignment: .topLeading)
        .background(Color.white)
    }
}

/// The proof's words, kept out of the views so tests can read them.
enum ProofText {
    static let pdfFile = "Proof.pdf"
    static let archiveFile = "Saved copy.webarchive"
    static let tokenFile = "Timestamp.tst"
    static let howToCheckFile = "How to check.txt"

    static let heading = "Proof of a sealed page"
    static let footer = "Exported from NetRelish. \(pdfFile), \(archiveFile), \(tokenFile) and \(howToCheckFile) belong together."

    struct Row: Equatable {
        let label: String
        let value: String
        var isCode = false
    }

    /// "Proof – Pricing", for the save panel. Slashes and colons would make it a path.
    static func exportName(_ item: Item) -> String {
        let title = item.title.isEmpty ? "Sealed page" : item.title
        let safe = title.map { "/:".contains($0) ? "-" : $0 }
        return "Proof – " + String(String(safe).prefix(80))
    }

    static func made(_ date: Date) -> String {
        "Made \(full(date))"
    }

    /// A date with its time zone, so the page means the same thing to whoever reads it.
    static func full(_ date: Date, in zone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .long, time: .standard)
        style.timeZone = zone
        return date.formatted(style) + " " + (zone.abbreviation(for: date) ?? zone.identifier)
    }

    static func rows(item: Item, provenance: Provenance, jarName: String?) -> [Row] {
        var rows = [Row(label: "Page", value: item.title.isEmpty ? "Untitled" : item.title)]
        if let url = item.url { rows.append(Row(label: "Address", value: url, isCode: true)) }
        if let sealed = item.sealedAt { rows.append(Row(label: "Sealed", value: full(sealed))) }
        if let jarName { rows.append(Row(label: "Jar", value: jarName)) }
        rows.append(Row(label: "Fingerprint (SHA-256 of the saved copy)", value: grouped(provenance.fingerprint), isCode: true))
        rows.append(Row(label: "Timestamp", value: timestampLine(provenance)))
        if let stamp = provenance.timestamp {
            rows.append(Row(label: "Timestamp serial number", value: stamp.serial, isCode: true))
        }
        return rows
    }

    /// The fingerprint in groups of eight, so it can be read aloud and compared by eye.
    static func grouped(_ hex: String) -> String {
        var groups: [String] = []
        var rest = Substring(hex)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(8)))
            rest = rest.dropFirst(8)
        }
        return groups.joined(separator: " ")
    }

    static func timestampLine(_ provenance: Provenance) -> String {
        if let stamp = provenance.timestamp {
            let utc = TimeZone(secondsFromGMT: 0)!
            let by = provenance.authority.map { ", signed by \($0)" } ?? ""
            return full(stamp.time, in: utc) + by
        }
        switch provenance.status {
        case .failed: return "None. The timestamp authority couldn’t give one."
        default: return "None yet. The fingerprint above was worked out on this Mac."
        }
    }

    static func whatItProves(_ provenance: Provenance) -> String {
        var text = "The fingerprint is worked out from \(archiveFile), byte for byte. If anything in that file changed, even one character, the fingerprint would be different."
        if provenance.timestamp != nil {
            text += " The timestamp is the authority’s signed statement that this exact fingerprint existed at the time shown, so the saved copy existed then too."
        }
        text += " Neither depends on NetRelish: \(howToCheckFile) shows how to check them with standard tools."
        return text
    }

    /// The plain-text instructions that travel with the proof.
    static func howToCheck(_ provenance: Provenance) -> String {
        var text = """
        How to check this proof

        Run these from the folder that holds this file. They use shasum and openssl, which come with macOS and most other systems.

        1. The fingerprint

           shasum -a 256 "\(archiveFile)"

           It should print:
           \(provenance.fingerprint)

        """
        if provenance.timestamp != nil {
            text += """

            2. The timestamp

               openssl ts -reply -token_in -in "\(tokenFile)" -text

               shows the time, and the fingerprint the authority signed ("Message data"). To check the authority's signature too:

               openssl ts -verify -token_in -in "\(tokenFile)" -data "\(archiveFile)" -CAfile root.pem

               where root.pem is the authority's root certificate\(provenance.authority.map { " (\($0) publishes it)" } ?? ""). It should print "Verification: OK".

            """
        }
        return text
    }
}
