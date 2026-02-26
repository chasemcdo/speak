import AppKit

/// Vocabulary extracted from the user's screen via the Accessibility tree.
/// Contains proper nouns, filenames, identifiers, and other terms the LLM should
/// use for spelling correction.
struct ScreenVocabulary: Sendable {
    /// The app name (e.g. "Slack", "Cursor").
    var appName: String?
    /// The window title (e.g. "#deploy — Daniyal", "generate_changelog.sh — MyProject").
    var windowTitle: String?
    /// The document/file path if the app exposes one.
    var documentPath: String?
    /// Additional text snippets found in the AX tree (tab titles, headers, labels).
    var visibleTerms: [String]

    /// True if we found anything useful.
    var isEmpty: Bool {
        appName == nil && windowTitle == nil && documentPath == nil && visibleTerms.isEmpty
    }
}

/// Reads surrounding text and screen vocabulary from the focused app via the Accessibility API.
@MainActor
final class ContextReader {
    /// Maximum characters of surrounding text context to return.
    private static let maxContextLength = 500
    /// Maximum number of AX children to inspect when gathering vocabulary.
    private static let maxChildrenToInspect = 40

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

    /// Read screen vocabulary from the frontmost window of the given app.
    /// Extracts window title, document path, and visible text terms from the AX tree.
    func readScreenVocabulary(from app: NSRunningApplication?) -> ScreenVocabulary? {
        guard let app else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var vocab = ScreenVocabulary(
            appName: app.localizedName,
            visibleTerms: []
        )

        // Get the focused window
        guard let window = axFocusedWindow(of: appElement) else {
            return vocab.isEmpty ? nil : vocab
        }

        // Window title (e.g. "Daniyal | Slack", "generate_changelog.sh — MyProject")
        vocab.windowTitle = axStringAttribute(kAXTitleAttribute, of: window)

        // Document path (editors often expose this)
        vocab.documentPath = axStringAttribute(kAXDocumentAttribute, of: window)

        // Walk shallow children of the window to pick up tab titles, labels, headers
        vocab.visibleTerms = collectVisibleTerms(from: window)

        return vocab.isEmpty ? nil : vocab
    }

    /// Check whether the given app has a focused text field (one that exposes a writable value attribute).
    func hasFocusedTextField(in app: NSRunningApplication?) -> Bool {
        guard let app else { return false }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success else {
            return false
        }

        let focused = focusedRef as! AXUIElement

        // Check if the focused element has a value attribute (indicates an editable field)
        var valueRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success
    }

    // MARK: - AX helpers

    private func axFocusedWindow(of app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXFocusedWindowAttribute as CFString,
            &ref
        ) == .success else {
            return nil
        }
        return (ref as! AXUIElement)
    }

    private func axStringAttribute(_ attr: String, of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attr as CFString,
            &ref
        ) == .success, let str = ref as? String, !str.isEmpty else {
            return nil
        }
        return str
    }

    private func axChildren(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &ref
        ) == .success, let children = ref as? [AXUIElement] else {
            return []
        }
        return children
    }

    private func axRole(of element: AXUIElement) -> String? {
        axStringAttribute(kAXRoleAttribute, of: element)
    }

    /// Walk the AX tree (2 levels deep) looking for short text values on
    /// static text, tab, and group elements — these are likely labels, tab titles, or headers.
    private func collectVisibleTerms(from root: AXUIElement) -> [String] {
        var terms: [String] = []
        var inspected = 0

        func visit(_ element: AXUIElement, depth: Int) {
            guard inspected < Self.maxChildrenToInspect, depth <= 2 else { return }
            inspected += 1

            let role = axRole(of: element)

            // Collect titles/values from relevant element types
            let interestingRoles: Set<String?> = [
                kAXStaticTextRole as String,
                kAXTabGroupRole as String,
                kAXButtonRole as String,
                kAXGroupRole as String,
                nil, // also check elements with unknown roles
            ]

            if interestingRoles.contains(role) {
                if let title = axStringAttribute(kAXTitleAttribute, of: element),
                   title.count >= 2, title.count <= 120 {
                    terms.append(title)
                }
                if role == kAXStaticTextRole as String,
                   let value = axStringAttribute(kAXValueAttribute, of: element),
                   value.count >= 2, value.count <= 120 {
                    terms.append(value)
                }
            }

            // Recurse into children
            if depth < 2 {
                for child in axChildren(of: element) {
                    visit(child, depth: depth + 1)
                }
            }
        }

        for child in axChildren(of: root) {
            visit(child, depth: 0)
        }

        // Deduplicate while preserving order
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }
    }
}
