// PlatformPasteboard.swift — Timed Core / Platform
// Cross-platform pasteboard wrapper.
// macOS: NSPasteboard.general
// iOS:   UIPasteboard.general

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public enum PlatformPasteboard {
    public static func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}
