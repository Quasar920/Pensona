import Foundation
import zlib

struct SpreadsheetTable: Equatable {
    let headers: [String]
    let rows: [[String]]
}

enum SpreadsheetImportError: LocalizedError, Equatable {
    case emptyFile
    case unsupportedFormat
    case malformedCSV
    case malformedXLSX
    case missingWorksheet

    var errorDescription: String? {
        switch self {
        case .emptyFile: AppLocalization.string( "文件中没有可导入的数据")
        case .unsupportedFormat: AppLocalization.string( "仅支持 CSV、TSV 和 XLSX 文件")
        case .malformedCSV: AppLocalization.string( "表格文本格式不完整，请检查引号和换行")
        case .malformedXLSX: AppLocalization.string( "XLSX 文件已损坏或使用了暂不支持的压缩格式")
        case .missingWorksheet: AppLocalization.string( "XLSX 中没有可读取的工作表")
        }
    }
}

enum SpreadsheetImportDecoder {
    static func decode(data: Data, fileExtension: String) throws -> SpreadsheetTable {
        guard !data.isEmpty else { throw SpreadsheetImportError.emptyFile }
        switch fileExtension.lowercased() {
        case "csv", "tsv", "txt":
            return try decodeDelimited(data)
        case "xlsx":
            return try XLSXDecoder(data: data).decode()
        default:
            throw SpreadsheetImportError.unsupportedFormat
        }
    }

    static func decodeDelimited(_ data: Data) throws -> SpreadsheetTable {
        let content: String
        if let utf8 = String(data: data, encoding: .utf8) {
            content = String(utf8.trimmingPrefix("\u{feff}"))
        } else if let gb18030 = String(data: data, encoding: .init(rawValue: 0x8000_0632)) {
            content = gb18030
        } else {
            throw SpreadsheetImportError.malformedCSV
        }
        let firstLine = content.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? ""
        let candidates: [Character] = [",", "\t", ";"]
        let delimiter = candidates.max { count($0, in: firstLine) < count($1, in: firstLine) } ?? ","
        let grid = try parseDelimited(content, delimiter: delimiter)
        return try makeTable(grid)
    }

    private static func count(_ character: Character, in value: String) -> Int {
        value.reduce(0) { $1 == character ? $0 + 1 : $0 }
    }

    private static func parseDelimited(_ content: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            if quoted {
                if character == "\"" {
                    let next = content.index(after: index)
                    if next < content.endIndex, content[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"", field.isEmpty {
                quoted = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character.isNewline {
                row.append(field)
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = content.index(after: index)
        }
        guard !quoted else { throw SpreadsheetImportError.malformedCSV }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
        return rows
    }

    fileprivate static func makeTable(_ grid: [[String]]) throws -> SpreadsheetTable {
        guard let first = grid.first else { throw SpreadsheetImportError.emptyFile }
        let headers = first.enumerated().map { index, value in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "第 \(index + 1) 列" : clean
        }
        guard !headers.isEmpty else { throw SpreadsheetImportError.emptyFile }
        let rows = grid.dropFirst().map { row in
            headers.indices.map { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
        }.filter { $0.contains(where: { !$0.isEmpty }) }
        guard !rows.isEmpty else { throw SpreadsheetImportError.emptyFile }
        return SpreadsheetTable(headers: headers, rows: rows)
    }
}

private struct ZIPEntry {
    let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localOffset: Int
}

private struct ZIPReader {
    let data: Data
    let entries: [ZIPEntry]

    init(data: Data) throws {
        self.data = data
        guard let endOffset = data.lastIndex(ofLittleEndian: 0x0605_4B50, maximumDistanceFromEnd: 65_557),
              let centralOffset = data.int32(at: endOffset + 16),
              let entryCount = data.int16(at: endOffset + 10) else {
            throw SpreadsheetImportError.malformedXLSX
        }
        var result: [ZIPEntry] = []
        var offset = centralOffset
        for _ in 0..<entryCount {
            guard data.int32(at: offset) == 0x0201_4B50,
                  let method = data.uint16(at: offset + 10),
                  let compressedSize = data.int32(at: offset + 20),
                  let uncompressedSize = data.int32(at: offset + 24),
                  let nameLength = data.int16(at: offset + 28),
                  let extraLength = data.int16(at: offset + 30),
                  let commentLength = data.int16(at: offset + 32),
                  let localOffset = data.int32(at: offset + 42),
                  let nameData = data.slice(at: offset + 46, count: nameLength),
                  let name = String(data: nameData, encoding: .utf8) else {
                throw SpreadsheetImportError.malformedXLSX
            }
            result.append(ZIPEntry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localOffset: localOffset
            ))
            offset += 46 + nameLength + extraLength + commentLength
        }
        entries = result
    }

    func contents(of name: String) throws -> Data? {
        guard let entry = entries.first(where: { $0.name == name }) else { return nil }
        let offset = entry.localOffset
        guard data.int32(at: offset) == 0x0403_4B50,
              let nameLength = data.int16(at: offset + 26),
              let extraLength = data.int16(at: offset + 28),
              let compressed = data.slice(
                at: offset + 30 + nameLength + extraLength,
                count: entry.compressedSize
              ) else { throw SpreadsheetImportError.malformedXLSX }
        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try inflateRaw(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw SpreadsheetImportError.malformedXLSX
        }
    }

    private func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        let initialized = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initialized == Z_OK else { throw SpreadsheetImportError.malformedXLSX }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(expectedSize, 1))
        let outputCapacity = output.count
        let status: Int32 = input.withUnsafeBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCapacity)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw SpreadsheetImportError.malformedXLSX }
        output.count = Int(stream.total_out)
        return output
    }
}

private struct XLSXDecoder {
    let archive: ZIPReader

    init(data: Data) throws { archive = try ZIPReader(data: data) }

    func decode() throws -> SpreadsheetTable {
        let sharedStrings: [String]
        if let data = try archive.contents(of: "xl/sharedStrings.xml") {
            sharedStrings = try SharedStringsParser.parse(data)
        } else {
            sharedStrings = []
        }
        let dateStyles: Set<Int>
        if let data = try archive.contents(of: "xl/styles.xml") {
            dateStyles = try StyleParser.parse(data)
        } else {
            dateStyles = []
        }
        guard let sheetName = archive.entries.map(\.name)
            .filter({ $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") })
            .sorted().first,
              let sheetData = try archive.contents(of: sheetName) else {
            throw SpreadsheetImportError.missingWorksheet
        }
        let rows = try WorksheetParser.parse(sheetData, sharedStrings: sharedStrings, dateStyles: dateStyles)
        return try SpreadsheetImportDecoder.makeTable(rows)
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var values: [String] = []
    private var current = ""
    private var insideText = false

    static func parse(_ data: Data) throws -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SpreadsheetImportError.malformedXLSX }
        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { insideText = false }
        if elementName == "si" { values.append(current) }
    }
}

private final class StyleParser: NSObject, XMLParserDelegate {
    private var customDates = Set<Int>()
    private var dateStyles = Set<Int>()
    private var insideCellFormats = false
    private var styleIndex = 0

    static func parse(_ data: Data) throws -> Set<Int> {
        let delegate = StyleParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SpreadsheetImportError.malformedXLSX }
        return delegate.dateStyles
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "numFmt", let id = attributeDict["numFmtId"].flatMap(Int.init),
           let code = attributeDict["formatCode"]?.lowercased(),
           code.range(of: #"[ymdhis]"#, options: .regularExpression) != nil {
            customDates.insert(id)
        } else if elementName == "cellXfs" {
            insideCellFormats = true
            styleIndex = 0
        } else if elementName == "xf", insideCellFormats {
            let formatID = attributeDict["numFmtId"].flatMap(Int.init) ?? 0
            if (14...22).contains(formatID) || (45...47).contains(formatID) || customDates.contains(formatID) {
                dateStyles.insert(styleIndex)
            }
            styleIndex += 1
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "cellXfs" { insideCellFormats = false }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let dateStyles: Set<Int>
    private var rows: [[String]] = []
    private var row: [String] = []
    private var column = 0
    private var type: String?
    private var style: Int?
    private var value = ""
    private var readingValue = false

    init(sharedStrings: [String], dateStyles: Set<Int>) {
        self.sharedStrings = sharedStrings
        self.dateStyles = dateStyles
    }

    static func parse(_ data: Data, sharedStrings: [String], dateStyles: Set<Int>) throws -> [[String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings, dateStyles: dateStyles)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw SpreadsheetImportError.malformedXLSX }
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" {
            row = []
        } else if elementName == "c" {
            column = Self.columnIndex(attributeDict["r"] ?? "A1")
            type = attributeDict["t"]
            style = attributeDict["s"].flatMap(Int.init)
            value = ""
        } else if elementName == "v" || elementName == "t" {
            readingValue = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingValue { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" {
            readingValue = false
        } else if elementName == "c" {
            while row.count <= column { row.append("") }
            row[column] = renderedValue()
        } else if elementName == "row" {
            rows.append(row)
        }
    }

    private func renderedValue() -> String {
        if type == "s", let index = Int(value), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        if type == "b" { return value == "1" ? "TRUE" : "FALSE" }
        if let style, dateStyles.contains(style), let serial = Double(value) {
            let origin = Calendar(identifier: .gregorian).date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0), year: 1899, month: 12, day: 30
            ))!
            let date = origin.addingTimeInterval(serial * 86_400)
            return date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
        }
        return value
    }

    private static func columnIndex(_ reference: String) -> Int {
        var result = 0
        for scalar in reference.unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(0, result - 1)
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
    }

    func int16(at offset: Int) -> Int? { uint16(at: offset).map(Int.init) }

    func int32(at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            let first = UInt32(bytes[offset])
            let second = UInt32(bytes[offset + 1]) << 8
            let third = UInt32(bytes[offset + 2]) << 16
            let fourth = UInt32(bytes[offset + 3]) << 24
            return Int(first | second | third | fourth)
        }
    }

    func slice(at offset: Int, count length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= count else { return nil }
        return subdata(in: offset..<(offset + length))
    }

    func lastIndex(ofLittleEndian signature: UInt32, maximumDistanceFromEnd: Int) -> Int? {
        guard count >= 4 else { return nil }
        let minimum = Swift.max(0, count - maximumDistanceFromEnd)
        var index = count - 4
        while index >= minimum {
            if int32(at: index) == Int(signature) { return index }
            index -= 1
        }
        return nil
    }
}
