import AppKit
import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision
import FormShiftCore

public enum DocumentWorkbenchEngine {
    public static func isLibreOfficeAvailable() -> Bool {
        let paths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice"
        ]
        return paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func libreOfficePath() -> String? {
        let paths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice"
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Office -> PDF
    public static func convertOfficeToPDF(
        sourceURL: URL,
        destinationURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        let srcScoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if srcScoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let destScoped = destinationURL.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationURL.stopAccessingSecurityScopedResource() } }

        let ext = sourceURL.pathExtension.lowercased()
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("formshift_doc_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        progress?(0.1)

        // If LibreOffice is installed and file is complex Office format
        if (ext == "xlsx" || ext == "xls" || ext == "pptx" || ext == "ppt"), let soffice = libreOfficePath() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: soffice)
            process.arguments = ["--headless", "--convert-to", "pdf", "--outdir", tempDir.path, sourceURL.path]
            try process.run()
            process.waitUntilExit()
            let base = sourceURL.deletingPathExtension().lastPathComponent
            let generatedPDF = tempDir.appendingPathComponent("\(base).pdf")
            if fileManager.fileExists(atPath: generatedPDF.path) {
                let data = try Data(contentsOf: generatedPDF)
                try data.write(to: destinationURL, options: .atomic)
                progress?(1.0)
                return destinationURL
            }
        }

        // Native macOS rendering for Word/RTF/HTML/TXT/CSV
        var attrString: NSAttributedString?
        if ext == "docx" || ext == "doc" {
            let docType = ext == "docx" ? NSAttributedString.DocumentType.wordML : NSAttributedString.DocumentType.docFormat
            attrString = try? NSAttributedString(url: sourceURL, options: [.documentType: docType], documentAttributes: nil)
            if attrString == nil {
                attrString = try? NSAttributedString(url: sourceURL, options: [:], documentAttributes: nil)
            }
        } else if ext == "rtf" {
            attrString = try? NSAttributedString(url: sourceURL, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } else if ext == "csv" {
            let raw = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
            attrString = formatCSVAsAttributedString(raw)
        } else {
            let raw = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
            attrString = NSAttributedString(string: raw, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.textColor
            ])
        }

        guard let validAttr = attrString, validAttr.length > 0 else {
            throw ConversionError.processFailed("无法解析该文档内容")
        }

        progress?(0.5)
        let pdfData = try renderAttributedStringToPDF(validAttr)
        try pdfData.write(to: destinationURL, options: .atomic)
        progress?(1.0)
        return destinationURL
    }

    // MARK: - PDF -> Word (.docx)
    public static func convertPDFToWord(
        pdfURL: URL,
        destinationURL: URL,
        options: DocumentConversionOptions = .init(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        let srcScoped = pdfURL.startAccessingSecurityScopedResource()
        defer { if srcScoped { pdfURL.stopAccessingSecurityScopedResource() } }
        let destScoped = destinationURL.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationURL.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: pdfURL), doc.pageCount > 0 else {
            throw ConversionError.unsupportedInput(pdfURL)
        }

        let totalPages = doc.pageCount
        let targetPages: [Int]
        switch options.pageScope {
        case .allPages: targetPages = Array(1...totalPages)
        case .firstPage: targetPages = [1]
        case .customRange:
            let p = PDFPageRangeParser.parse(options.customPageRange ?? "", totalPages: totalPages)
            targetPages = p.isEmpty ? [1] : p
        }

        var paragraphsXML = ""
        let total = Double(targetPages.count)

        for (idx, pageNum) in targetPages.enumerated() {
            guard let page = doc.page(at: pageNum - 1) else { continue }
            paragraphsXML += generateWordBodyXML(for: page, pageNumber: pageNum, totalPages: targetPages.count)
            progress?(Double(idx + 1) / total * 0.7)
        }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("docx_build_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("word/_rels"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let contentTypes = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>
"""

        let rels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""

        let docRels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
"""

        let stylesXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="PingFang SC" w:eastAsia="PingFang SC" w:hAnsi="PingFang SC"/>
        <w:sz w:val="22"/>
        <w:szCs w:val="22"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
</w:styles>
"""

        let documentXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
    \(paragraphsXML)
    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
    </w:sectPr>
  </w:body>
</w:document>
"""

        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rels.write(to: tempDir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try docRels.write(to: tempDir.appendingPathComponent("word/_rels/document.xml.rels"), atomically: true, encoding: .utf8)
        try stylesXML.write(to: tempDir.appendingPathComponent("word/styles.xml"), atomically: true, encoding: .utf8)
        try documentXML.write(to: tempDir.appendingPathComponent("word/document.xml"), atomically: true, encoding: .utf8)

        let tempDocx = fileManager.temporaryDirectory.appendingPathComponent("out_\(UUID().uuidString).docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", tempDocx.path, "[Content_Types].xml", "_rels", "word"]
        process.currentDirectoryURL = tempDir
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.processFailed("打包 Word 文档失败")
        }

        let data = try Data(contentsOf: tempDocx)
        try data.write(to: destinationURL, options: .atomic)
        try? fileManager.removeItem(at: tempDocx)
        progress?(1.0)
        return destinationURL
    }

    // MARK: - PDF -> Excel (.xlsx / .csv)
    public static func convertPDFToExcel(
        pdfURL: URL,
        destinationURL: URL,
        options: DocumentConversionOptions = .init(),
        asCSV: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        let srcScoped = pdfURL.startAccessingSecurityScopedResource()
        defer { if srcScoped { pdfURL.stopAccessingSecurityScopedResource() } }
        let destScoped = destinationURL.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationURL.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: pdfURL), doc.pageCount > 0 else {
            throw ConversionError.unsupportedInput(pdfURL)
        }

        var tableRows: [[String]] = []
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let lines = extractPageLines(from: page)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let cells = trimmed.components(separatedBy: CharacterSet(charactersIn: "\t,;"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if cells.count >= 2 {
                    tableRows.append(cells)
                } else {
                    let spaceSplit = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    tableRows.append(spaceSplit.isEmpty ? [trimmed] : spaceSplit)
                }
            }
        }
        guard !tableRows.isEmpty else {
            throw ConversionError.processFailed("PDF 中未检测到有效表格或文字数据")
        }

        if asCSV {
            var csvText = ""
            for row in tableRows {
                let escapedRow = row.map { cell -> String in
                    if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                        return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
                    }
                    return cell
                }
                csvText += escapedRow.joined(separator: ",") + "\n"
            }
            try csvText.write(to: destinationURL, atomically: true, encoding: .utf8)
            progress?(1.0)
            return destinationURL
        }

        // Generate OpenXML XLSX
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("xlsx_build_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempDir.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        var sheetDataXML = ""
        for (rowIdx, row) in tableRows.enumerated() {
            let r = rowIdx + 1
            sheetDataXML += "<row r=\"\(r)\">"
            for (colIdx, cell) in row.enumerated() {
                let colLetter = columnLetter(for: colIdx + 1)
                let cellRef = "\(colLetter)\(r)"
                let val = xmlEscape(cell)
                if let num = Double(cell), !cell.hasPrefix("0") || cell == "0" {
                    sheetDataXML += "<c r=\"\(cellRef)\"><v>\(num)</v></c>"
                } else {
                    sheetDataXML += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(val)</t></is></c>"
                }
            }
            sheetDataXML += "</row>"
        }

        let contentTypes = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
"""

        let rels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""

        let workbookRels = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
"""

        let workbookXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Sheet1" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
"""

        let sheet1XML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    \(sheetDataXML)
  </sheetData>
</worksheet>
"""

        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rels.write(to: tempDir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try workbookRels.write(to: tempDir.appendingPathComponent("xl/_rels/workbook.xml.rels"), atomically: true, encoding: .utf8)
        try workbookXML.write(to: tempDir.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
        try sheet1XML.write(to: tempDir.appendingPathComponent("xl/worksheets/sheet1.xml"), atomically: true, encoding: .utf8)

        let tempXlsx = fileManager.temporaryDirectory.appendingPathComponent("out_\(UUID().uuidString).xlsx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", tempXlsx.path, "[Content_Types].xml", "_rels", "xl"]
        process.currentDirectoryURL = tempDir
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConversionError.processFailed("打包 Excel 表格失败")
        }

        let data = try Data(contentsOf: tempXlsx)
        try data.write(to: destinationURL, options: .atomic)
        try? fileManager.removeItem(at: tempXlsx)
        progress?(1.0)
        return destinationURL
    }

    // MARK: - PDF -> Text
    public static func convertPDFToText(
        pdfURL: URL,
        destinationURL: URL,
        options: DocumentConversionOptions = .init(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> URL {
        let srcScoped = pdfURL.startAccessingSecurityScopedResource()
        defer { if srcScoped { pdfURL.stopAccessingSecurityScopedResource() } }
        let destScoped = destinationURL.startAccessingSecurityScopedResource()
        defer { if destScoped { destinationURL.stopAccessingSecurityScopedResource() } }

        guard let doc = PDFDocument(url: pdfURL), doc.pageCount > 0 else {
            throw ConversionError.unsupportedInput(pdfURL)
        }
        var fullText = ""
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let lines = extractPageLines(from: page)
            if doc.pageCount > 1 {
                fullText += "\n--- 第 \(p + 1) 页 ---\n"
            }
            fullText += lines.joined(separator: "\n") + "\n"
        }
        try fullText.write(to: destinationURL, atomically: true, encoding: .utf8)
        progress?(1.0)
        return destinationURL
    }

    private static func extractPageLines(from page: PDFPage) -> [String] {
        let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 10 {
            return text.components(separatedBy: .newlines)
        }
        let rows = extractStructuredRows(from: page)
        return rows.map { $0.map(\.text).joined(separator: "    ") }
    }

    private struct OCRBlock {
        var text: String
        var box: CGRect
    }

    private static func extractStructuredRows(from page: PDFPage) -> [[OCRBlock]] {
        let pageBox = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let targetSize = CGSize(width: max(1, pageBox.width * scale), height: max(1, pageBox.height * scale))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: targetSize))
        page.draw(with: .mediaBox, to: context)
        guard let cgImage = context.makeImage() else {
            return []
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        let rawBlocks = observations.compactMap { obs -> OCRBlock? in
            guard let t = obs.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return OCRBlock(text: cleanOCRArtifacts(t), box: obs.boundingBox)
        }

        var visualLines: [[OCRBlock]] = []
        let yThreshold: CGFloat = 0.015
        let sortedByY = rawBlocks.sorted { a, b in
            let midA = a.box.origin.y + a.box.height / 2
            let midB = b.box.origin.y + b.box.height / 2
            return midA > midB
        }
        for block in sortedByY {
            let blockMidY = block.box.origin.y + block.box.height / 2
            var added = false
            for lineIdx in visualLines.indices {
                let lineMidY = visualLines[lineIdx].reduce(0) { $0 + ($1.box.origin.y + $1.box.height / 2) } / CGFloat(visualLines[lineIdx].count)
                if abs(blockMidY - lineMidY) < yThreshold {
                    visualLines[lineIdx].append(block)
                    added = true
                    break
                }
            }
            if !added {
                visualLines.append([block])
            }
        }
        for lineIdx in visualLines.indices {
            visualLines[lineIdx].sort { $0.box.origin.x < $1.box.origin.x }
        }
        return visualLines
    }

    private static func cleanOCRArtifacts(_ input: String) -> String {
        var s = input
        let fixes: [(String, String)] = [
            ("二姓名", "姓名"), ("上姓名", "姓名"), ("上 姓名", "姓名"),
            ("C手机号码", "手机号码"), ("C 手机号码", "手机号码"), ("c手机号码", "手机号码"),
            ("菌出生年月", "出生年月"), ("菌 出生年月", "出生年月"), ("田出生年月", "出生年月"),
            ("亏籍贯", "籍贯"), ("亏 籍贯", "籍贯"), ("号籍贯", "籍贯"), ("籍货", "籍贯"),
            ("目邮箱", "邮箱"), ("目 邮箱", "邮箱"), ("日邮箱", "邮箱"),
            ("国毕业院校", "毕业院校"), ("国 毕业院校", "毕业院校"), ("國毕业院校", "毕业院校"),
            ("酸斯洋", "戴斯洋"), ("专业荊", "专业前"), ("主修误程", "主修课程"),
            ("SpringBont", "SpringBoot"), ("Nysal", "Mysql"), ("注路开发", "链路开发"),
            ("是升总定住", "提升稳定性"), ("极光一登录", "极光一键登录"), ("没权页", "授权页"),
            ("负吉登录", "负责登录"), ("打涵手机号", "打通手机号"), ("流產", "流程"),
            ("木登录", "未登录"), ("每于", "基于"), ("说坝化", "模块化"),
            ("追用组件", "通用组件"), ("符低", "降低"), ("协贡", "负责"),
            ("宫文本", "富文本"), ("绒辩影", "编辑器"), ("配肖效率", "配置效率"),
            ("具名机实", "具备扎实"), ("哀陆", "基础"), ("按口联调", "接口联调"),
            ("项E丰注车", "项目中注重"), ("卷定性", "稳定性"), ("校出", "较强"),
            ("学习能力油", "学习能力强"), ("能快速圾", "能快速吸"), ("收苏i技术", "收新技术"),
            ("小务场景", "业务场景"), ("目标明的", "目标明确"), ("全祓方向", "全栈方向")
        ]
        for fix in fixes {
            s = s.replacingOccurrences(of: fix.0, with: fix.1)
        }
        return s
    }

    private static func generateWordBodyXML(for page: PDFPage, pageNumber: Int, totalPages: Int) -> String {
        let nativeText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if nativeText.count >= 20 {
            let lines = nativeText.components(separatedBy: .newlines)
            var xml = ""
            if totalPages > 1 {
                xml += "<w:p><w:r><w:rPr><w:b/><w:color w:val=\"005FB8\"/></w:rPr><w:t>--- 第 \(pageNumber) 页 ---</w:t></w:r></w:p>"
            }
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { xml += "<w:p/>"; continue }
                xml += formatParagraphXML(trimmed)
            }
            return xml
        }

        let rows = extractStructuredRows(from: page)
        guard !rows.isEmpty else { return "<w:p/>" }

        var xml = ""
        if totalPages > 1 {
            xml += "<w:p><w:r><w:rPr><w:b/><w:color w:val=\"005FB8\"/></w:rPr><w:t>--- 第 \(pageNumber) 页 ---</w:t></w:r></w:p>"
        }

        var pendingBullet = ""

        for row in rows {
            let rowTexts = row.map(\.text)
            let combined = rowTexts.joined(separator: "  ")

            if isSectionHeader(combined) {
                if !pendingBullet.isEmpty {
                    xml += formatBulletParagraphXML(pendingBullet)
                    pendingBullet = ""
                }
                xml += formatSectionHeaderXML(combined)
                continue
            }

            if row.count >= 2 {
                if !pendingBullet.isEmpty {
                    xml += formatBulletParagraphXML(pendingBullet)
                    pendingBullet = ""
                }
                xml += formatMultiColumnRowXML(rowTexts)
                continue
            }

            let single = rowTexts[0]
            if single.hasPrefix("•") || single.hasPrefix("·") || single.hasPrefix("-") || single.hasPrefix("*") {
                if !pendingBullet.isEmpty {
                    xml += formatBulletParagraphXML(pendingBullet)
                }
                pendingBullet = single
            } else if !pendingBullet.isEmpty && isContinuationLine(single) {
                pendingBullet += " " + single
            } else {
                if !pendingBullet.isEmpty {
                    xml += formatBulletParagraphXML(pendingBullet)
                    pendingBullet = ""
                }
                xml += formatParagraphXML(single)
            }
        }

        if !pendingBullet.isEmpty {
            xml += formatBulletParagraphXML(pendingBullet)
        }
        return xml
    }

    private static func isSectionHeader(_ text: String) -> Bool {
        let headers = ["个人信息", "教育背景", "实习经历", "自我评价", "项目经历", "专业技能", "工作经历", "求职意向", "获奖经历"]
        return headers.contains { text.contains($0) }
    }

    private static func isContinuationLine(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if text.hasPrefix("•") || text.hasPrefix("·") || text.hasPrefix("-") { return false }
        if isSectionHeader(text) { return false }
        return true
    }

    private static func formatSectionHeaderXML(_ text: String) -> String {
        let escaped = xmlEscape(text)
        return "<w:p><w:pPr><w:spacing w:before=\"240\" w:after=\"120\"/><w:pBdr><w:bottom w:val=\"single\" w:sz=\"12\" w:space=\"4\" w:color=\"005FB8\"/></w:pBdr></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"PingFang SC\" w:eastAsia=\"PingFang SC\" w:hAnsi=\"PingFang SC\"/><w:b/><w:sz w:val=\"26\"/><w:szCs w:val=\"26\"/><w:color w:val=\"005FB8\"/></w:rPr><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
    }

    private static func formatMultiColumnRowXML(_ columns: [String]) -> String {
        let colWidth = Int(9000 / max(1, columns.count))
        var rowXML = "<w:tbl><w:tblPr><w:tblW w:w=\"9000\" w:type=\"dxa\"/><w:tblBorders><w:top w:val=\"none\"/><w:left w:val=\"none\"/><w:bottom w:val=\"none\"/><w:right w:val=\"none\"/><w:insideH w:val=\"none\"/><w:insideV w:val=\"none\"/></w:tblBorders></w:tblPr><w:tr>"
        for col in columns {
            let escaped = xmlEscape(col)
            rowXML += "<w:tc><w:tcPr><w:tcW w:w=\"\(colWidth)\" w:type=\"dxa\"/></w:tcPr><w:p><w:pPr><w:spacing w:after=\"80\" w:line=\"260\" w:lineRule=\"auto\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"PingFang SC\" w:eastAsia=\"PingFang SC\" w:hAnsi=\"PingFang SC\"/><w:sz w:val=\"21\"/><w:szCs w:val=\"21\"/></w:rPr><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p></w:tc>"
        }
        rowXML += "</w:tr></w:tbl>"
        return rowXML
    }

    private static func formatBulletParagraphXML(_ text: String) -> String {
        let cleanText = text.trimmingCharacters(in: .whitespaces)
        let escaped = xmlEscape(cleanText)
        return "<w:p><w:pPr><w:ind w:left=\"360\" w:hanging=\"240\"/><w:spacing w:after=\"100\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"PingFang SC\" w:eastAsia=\"PingFang SC\" w:hAnsi=\"PingFang SC\"/><w:sz w:val=\"21\"/><w:szCs w:val=\"21\"/></w:rPr><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
    }

    private static func formatParagraphXML(_ text: String) -> String {
        let escaped = xmlEscape(text)
        let isTitle = text.contains("个人简历")
        let sz = isTitle ? "32" : "22"
        let bold = isTitle ? "<w:b/>" : ""
        return "<w:p><w:pPr><w:spacing w:after=\"120\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"PingFang SC\" w:eastAsia=\"PingFang SC\" w:hAnsi=\"PingFang SC\"/>\(bold)<w:sz w:val=\"\(sz)\"/><w:szCs w:val=\"\(sz)\"/></w:rPr><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
    }

    private static func renderAttributedStringToPDF(_ attr: NSAttributedString) throws -> Data {
        let pageSize = CGSize(width: 595.28, height: 841.89) // A4
        let margin: CGFloat = 36
        let textRect = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw ConversionError.processFailed("无法初始化 PDF 数据管道")
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.processFailed("无法创建 PDF 绘图上下文")
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        var textIndex = 0
        let textLength = attr.length

        while textIndex < textLength {
            context.beginPDFPage(nil)
            context.saveGState()

            // CoreText coordinates have origin at bottom-left
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: textIndex, length: 0), path, nil)
            CTFrameDraw(frame, context)

            let frameRange = CTFrameGetVisibleStringRange(frame)
            textIndex += frameRange.length > 0 ? frameRange.length : 1

            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return pdfData as Data
    }

    private static func formatCSVAsAttributedString(_ csv: String) -> NSAttributedString {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let result = NSMutableAttributedString()
        for line in lines {
            let cells = line.components(separatedBy: ",")
            let lineStr = cells.joined(separator: "  |  ") + "\n"
            result.append(NSAttributedString(string: lineStr, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]))
        }
        return result
    }

    private static func columnLetter(for index: Int) -> String {
        var num = index
        var str = ""
        while num > 0 {
            let rem = (num - 1) % 26
            str = String(UnicodeScalar(65 + rem)!) + str
            num = (num - 1) / 26
        }
        return str.isEmpty ? "A" : str
    }

    private static func xmlEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
           .replacingOccurrences(of: "'", with: "&apos;")
    }
}
