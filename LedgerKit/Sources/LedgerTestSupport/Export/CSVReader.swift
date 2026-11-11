import Foundation

/// An RFC 4180 reader, for the tests of `CSVExport` (F14 S2): it reads a file back into its fields, so a test checks
/// what a spreadsheet would read and not the text the writer wrote. Rows end with CRLF; a field may be quoted, and
/// a quote inside a quoted field is written twice; a quoted field may hold commas, CRs and LFs. It reads Unicode
/// scalars, never `Character`s, as a spreadsheet reads bytes: "\r\n" is one `Character` in Swift.
public enum CSVReader {
    /// The rows of `text`, each a list of its fields with their quotes taken off. A byte-order mark is not read here:
    /// strip it first.
    public static func rows(_ text: String) -> [[String]] {
        let scalars = Array(text.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var isQuoted = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if isQuoted {
                if scalar == "\"", next == "\"" {
                    field.append("\"")
                    index += 1
                } else if scalar == "\"" {
                    isQuoted = false
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\"", field.isEmpty {
                isQuoted = true
            } else if scalar == "," {
                row.append(String(field))
                field = String.UnicodeScalarView()
            } else if scalar == "\r", next == "\n" {
                row.append(String(field))
                rows.append(row)
                row = []
                field = String.UnicodeScalarView()
                index += 1
            } else {
                field.append(scalar)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(String(field))
            rows.append(row)
        }
        return rows
    }
}
