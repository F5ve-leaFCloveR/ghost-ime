import Cocoa
import InputMethodKit

final class InputController: IMKInputController {
    private var buffer = ""
    private var suggestion: String?
    private let predictor = Predictor()

    override func recognizedEvents(_ sender: Any!) -> Int {
        return Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }
        guard event.type == .keyDown else { return false }

        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false {
            if !buffer.isEmpty { commitBuffer(client) }
            return false
        }

        switch event.keyCode {
        case 48, 124: // Tab or Right Arrow
            if commitSuggestion(client) { return true }
            return false
        case 53: // Escape
            if !buffer.isEmpty {
                buffer = ""
                suggestion = nil
                clearMarkedText(client)
                return true
            }
            return false
        case 51: // Delete (backspace)
            if !buffer.isEmpty {
                buffer.removeLast()
                updateMarkedText(client)
                return true
            }
            return false
        case 36, 76: // Return / Enter
            if !buffer.isEmpty {
                commitBuffer(client)
                client.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        case 49: // Space
            if !buffer.isEmpty {
                commitBuffer(client)
                client.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        default:
            break
        }

        guard let chars = event.characters, chars.count == 1, let scalar = chars.unicodeScalars.first else {
            if !buffer.isEmpty { commitBuffer(client) }
            return false
        }

        if isWordScalar(scalar) {
            buffer.append(String(scalar))
            updateMarkedText(client)
            return true
        }

        if isBoundaryScalar(scalar) {
            if !buffer.isEmpty {
                commitBuffer(client)
                client.insertText(String(scalar), replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                return true
            }
            return false
        }

        if !buffer.isEmpty { commitBuffer(client) }
        return false
    }

    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        if !buffer.isEmpty { commitBuffer(client) }
    }

    override func deactivateServer(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        if !buffer.isEmpty { commitBuffer(client) }
    }

    private func updateMarkedText(_ client: IMKTextInput) {
        guard !buffer.isEmpty else {
            clearMarkedText(client)
            return
        }

        let rawSuggestion = predictor.suggest(for: buffer.lowercased())
        if let rawSuggestion {
            let adjusted = adjustCase(rawSuggestion, for: buffer)
            if adjusted.lowercased().hasPrefix(buffer.lowercased()) {
                suggestion = adjusted
            } else {
                suggestion = nil
            }
        } else {
            suggestion = nil
        }

        if let suggestion = suggestion {
            let suffix = suffixAfterPrefix(full: suggestion, prefix: buffer)
            let display = buffer + suffix
            let attributed = NSMutableAttributedString(string: display)
            if !suffix.isEmpty {
                let range = NSRange(location: buffer.count, length: suffix.count)
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
            client.setMarkedText(attributed,
                                 selectionRange: NSRange(location: buffer.count, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        } else {
            let attributed = NSAttributedString(string: buffer)
            client.setMarkedText(attributed,
                                 selectionRange: NSRange(location: buffer.count, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        }
    }

    private func clearMarkedText(_ client: IMKTextInput) {
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    private func commitBuffer(_ client: IMKTextInput) {
        let text = buffer
        buffer = ""
        suggestion = nil
        clearMarkedText(client)
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        predictor.learn(word: text)
    }

    @discardableResult
    private func commitSuggestion(_ client: IMKTextInput) -> Bool {
        guard let suggestion = suggestion else { return false }
        buffer = ""
        self.suggestion = nil
        clearMarkedText(client)
        client.insertText(suggestion, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        predictor.learn(word: suggestion)
        return true
    }

    private func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
        if scalar.value == 0x27 { return true }
        return CharacterSet.letters.contains(scalar)
    }

    private func isBoundaryScalar(_ scalar: UnicodeScalar) -> Bool {
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
            || CharacterSet.punctuationCharacters.contains(scalar)
    }

    private func suffixAfterPrefix(full: String, prefix: String) -> String {
        guard full.count >= prefix.count else { return "" }
        let idx = full.index(full.startIndex, offsetBy: prefix.count)
        return String(full[idx...])
    }

    private func adjustCase(_ suggestion: String, for prefix: String) -> String {
        guard !prefix.isEmpty else { return suggestion }
        if prefix.uppercased() == prefix {
            return suggestion.uppercased()
        }

        let first = prefix.prefix(1)
        let rest = prefix.dropFirst()
        if first == first.uppercased(), rest == rest.lowercased() {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
        }

        return suggestion
    }
}
