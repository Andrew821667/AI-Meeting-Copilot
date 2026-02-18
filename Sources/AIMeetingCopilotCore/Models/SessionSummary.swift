import Foundation

public struct SessionSummary: Codable {
    public let sessionID: String
    public let profile: String
    public let exportJSONPath: String
    public let reportMDPath: String
    public let reportPDFPath: String?
    public let metrics: [String: Double]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case profile
        case exportJSONPath = "export_json_path"
        case reportMDPath = "report_md_path"
        case reportPDFPath = "report_pdf_path"
        case metrics
    }
}
