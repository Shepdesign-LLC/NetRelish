// ShortcutError.swift — what a NetRelish Shortcut says when it can't do what it was asked,
// in plain words (docs/voice). Shortcuts shows the message as it is.

import Foundation

public enum ShortcutError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notAWebPage
    case noJar
    case jarGone
    case nothingOpen
    case pageDidNotLoad(String)
    case couldNotSeal

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notAWebPage: "NetRelish keeps web pages only. Use a link that starts with http or https."
        case .noJar: "There's no jar to seal into. Make one on the Shelf first."
        case .jarGone: "That jar isn't on the Shelf anymore."
        case .nothingOpen: "Nothing is open in NetRelish to seal. Open a page, or give the Shortcut a link."
        case .pageDidNotLoad(let why): "The page didn't load, so nothing was sealed. \(why)"
        case .couldNotSeal: "NetRelish couldn't seal this page."
        }
    }
}
