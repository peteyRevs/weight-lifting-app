import Foundation

/// F14 S2, G2 round 1: an RFC 4180 reader written apart from LedgerTestSupport's `CSVReader`, for
/// `CSVExportAdversarialTests`. It reads Unicode scalars, as a spreadsheet reads bytes.
enum CSVAdversarialReader {
    // swiftlint:disable cyclomatic_complexity function_body_length
    /// The rows of `text`, each a list of fields as scalar views, so canonical equivalence never hides a difference.
    /// Returns nil when the text is not RFC 4180: a quote inside an unquoted field, text after a closing quote, a bare
    /// CR or LF outside quotes, an unterminated quote, or a last row without its CRLF.
    static func read(_ text: String) -> [[String.UnicodeScalarView]]? {
        let input = Array(text.unicodeScalars)
        var rows: [[String.UnicodeScalarView]] = []
        var row: [String.UnicodeScalarView] = []
        var field = String.UnicodeScalarView()
        var index = 0
        var atFieldStart = true
        while index < input.count {
            let scalar = input[index]
            if atFieldStart, scalar == "\"" {
                index += 1
                while true {
                    guard index < input.count else {
                        return nil
                    }
                    if input[index] == "\"" {
                        if index + 1 < input.count, input[index + 1] == "\"" {
                            field.append("\"")
                            index += 2
                            continue
                        }
                        index += 1
                        break
                    }
                    field.append(input[index])
                    index += 1
                }
                guard index < input.count, input[index] == "," || input[index] == "\r" else {
                    return nil
                }
                atFieldStart = false
                continue
            }
            switch scalar {
            case ",":
                row.append(field)
                field = String.UnicodeScalarView()
                atFieldStart = true
                index += 1
            case "\r":
                guard index + 1 < input.count, input[index + 1] == "\n" else {
                    return nil
                }
                row.append(field)
                rows.append(row)
                row = []
                field = String.UnicodeScalarView()
                atFieldStart = true
                index += 2
            case "\n", "\"":
                return nil
            default:
                field.append(scalar)
                atFieldStart = false
                index += 1
            }
        }
        guard row.isEmpty, field.isEmpty, atFieldStart else {
            return nil
        }
        return rows
    }

    static func strings(_ text: String) -> [[String]]? {
        read(text)?.map { $0.map(String.init) }
    }

    static func scalars(_ text: String) -> [Unicode.Scalar] {
        Array(text.unicodeScalars)
    }
    // swiftlint:enable cyclomatic_complexity function_body_length
}
