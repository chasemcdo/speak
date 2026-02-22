import AppKit

/// Reads surrounding text from the focused text field via the Accessibility API.
@MainActor
final class ContextReader {
    /// Maximum characters of context to return (keeps LLM token budget in check).
    private static let maxContextLength = 500

    /// Read the text content from the focused text field in the given app.
    /// Returns nil if the app doesn't expose text via Accessibility, or no text field is focused.
    func readContext(from app: NSRunningApplication?) -> String? {
        guard let app else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused UI element
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success else {
            return nil
        }

        let focused = focusedRef as! AXUIElement

        // Try to read the text value
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success, let text = valueRef as? String, !text.isEmpty else {
            return nil
        }

        // Trim to keep within token budget
        if text.count > Self.maxContextLength {
            return String(text.suffix(Self.maxContextLength))
        }

        return text
    }
}
