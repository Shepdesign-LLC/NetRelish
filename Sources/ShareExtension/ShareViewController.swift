// ShareViewController.swift — NetRelish in the Share menu (ADR 0012: "Capture from Safari
// or any app"). Shows the page and one button. Capture leaves it in the shared inbox; the
// app puts it in Brine, with "The Share menu" as its source. Nothing is sent anywhere.

import AppKit
import UniformTypeIdentifiers

final class ShareViewController: NSViewController {
    private var pageURL: URL?
    private var pageTitle = ""
    private let titleField = NSTextField(labelWithString: "")
    private let urlField = NSTextField(labelWithString: "")
    private let captureButton = NSButton(title: "Capture", target: nil, action: nil)

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let heading = NSTextField(labelWithString: "Capture to NetRelish")
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let note = NSTextField(labelWithString: "Into Brine. Sort it into a jar later.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        titleField.lineBreakMode = .byTruncatingTail
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.textColor = .secondaryLabelColor
        urlField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        captureButton.target = self
        captureButton.action = #selector(capture(_:))
        captureButton.keyEquivalent = "\r"
        captureButton.isEnabled = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, captureButton])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [heading, titleField, urlField, note, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 170))
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 380),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        // The title the sharing app gave, else its text; first line only, so a shared selection
        // doesn't become a paragraph-long title.
        let given = [items.first?.attributedTitle?.string, items.first?.attributedContentText?.string]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        pageTitle = String((given.split(whereSeparator: \.isNewline).first ?? "").prefix(300))
        titleField.stringValue = pageTitle.isEmpty ? "Untitled page" : pageTitle
        let provider = items.flatMap { $0.attachments ?? [] }.first { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
        guard let provider else {
            urlField.stringValue = "There's no page to capture here."
            return
        }
        // The controller is main-actor bound, so it's safe to hold here; the provider's
        // object isn't, so only the URL (a value) crosses back to the main actor.
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            let url = (object as? NSURL) as URL?
            Task { @MainActor in self.show(url) }
        }
    }

    private func show(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            urlField.stringValue = "NetRelish captures web pages only."
            return
        }
        pageURL = url
        urlField.stringValue = url.absoluteString
        captureButton.isEnabled = true
    }

    @objc private func capture(_ sender: Any?) {
        guard let pageURL else { return cancel(sender) }
        guard let inbox = ShareInbox() else {
            urlField.stringValue = "Couldn't hand this page to NetRelish. Try again."
            return
        }
        inbox.add(SharedPage(url: pageURL.absoluteString, title: pageTitle))
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    @objc private func cancel(_ sender: Any?) {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
