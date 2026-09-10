import SwiftUI
import UniformTypeIdentifiers

/// A plain-text CSV wrapper for `fileExporter`. The export is a user-initiated
/// document write to a location the user picks — it never leaves the device on its
/// own, and the contents are exactly what `SightingsStore.exportCSV` renders.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
