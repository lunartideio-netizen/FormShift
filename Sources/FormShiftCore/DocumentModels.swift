import Foundation

public enum DocumentConversionDirection: String, Codable, CaseIterable, Sendable {
    case officeToPDF
    case pdfToOffice
}

public enum PDFToOfficeFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case docx
    case xlsx
    case pptx
    case txt
    case csv

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .docx: "Word 文档 (.docx)"
        case .xlsx: "Excel 表格 (.xlsx)"
        case .pptx: "PowerPoint 幻灯片 (.pptx)"
        case .txt: "纯文本 (.txt)"
        case .csv: "表格逗号分隔 (.csv)"
        }
    }

    public var fileExtension: String { rawValue }
}

public struct DocumentConversionOptions: Codable, Hashable, Sendable {
    public var pageScope: PDFPageExportScope
    public var customPageRange: String?
    public var includePageBackdrops: Bool

    public init(
        pageScope: PDFPageExportScope = .allPages,
        customPageRange: String? = nil,
        includePageBackdrops: Bool = true
    ) {
        self.pageScope = pageScope
        self.customPageRange = customPageRange
        self.includePageBackdrops = includePageBackdrops
    }
}
