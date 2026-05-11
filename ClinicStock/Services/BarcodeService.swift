//
//  BarcodeService.swift
//  ClinicStock
//

import Foundation

struct BarcodeService {

    // MARK: - Regex Cache

    private static let hcpcsPattern =
        try! NSRegularExpression(pattern: "^[A-Za-z]\\d{4}$")

    private static var gs1FieldRegexCache: [String: NSRegularExpression] = [:]
    private static let gs1CacheQueue = DispatchQueue(label: "BarcodeService.gs1Cache")

    private static func gs1FieldRegex(ai: String) -> NSRegularExpression? {
        gs1CacheQueue.sync {
            if let cached = gs1FieldRegexCache[ai] { return cached }
            guard let regex = try? NSRegularExpression(
                pattern: "\\(\(ai)\\)([^(\\x1D]+)"
            ) else { return nil }
            gs1FieldRegexCache[ai] = regex
            return regex
        }
    }

    private static let fnc1 = "\u{1D}"

    // MARK: - Parse

    static func parse(_ rawValue: String) -> ParsedBarcode {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ParsedBarcode(raw: rawValue)

        guard !trimmed.isEmpty else {
            result.format = .unknown
            return result
        }

        if trimmed.contains("(01)") {
            parseGS1Parenthesized(trimmed, into: &result)
        } else if trimmed.contains(fnc1) && trimmed.hasPrefix("01") {
            parseGS1FNC1(trimmed, into: &result)
        } else if isHCPCSCode(trimmed) {
            result.hcpcsCode = trimmed.uppercased()
            result.format = .hcpcs
        } else if isASCIIDigits(trimmed) {
            parseNumeric(trimmed, into: &result)
        } else {
            result.format = .unknown
        }

        return result
    }

    // MARK: - Format-Specific Parsers

    private static func parseGS1Parenthesized(_ input: String, into result: inout ParsedBarcode) {
        result.gtin       = extractGS1Field(input, ai: "01").map { normalizeGTIN($0) }
        result.lotNumber  = extractGS1Field(input, ai: "10")
        result.productCode = extractGS1Field(input, ai: "241")
        result.format     = .gs1Display
    }

    private static func parseGS1FNC1(_ input: String, into result: inout ParsedBarcode) {
        let afterAI = input.dropFirst(2)
        let gtinPrefix = String(afterAI.prefix(14))

        if gtinPrefix.count == 14, isASCIIDigits(gtinPrefix) {
            result.gtin = gtinPrefix
        }

        let segments = String(afterAI.dropFirst(14)).components(separatedBy: fnc1)
        for segment in segments where !segment.isEmpty {
            if segment.hasPrefix("10")  { result.lotNumber   = String(segment.dropFirst(2)) }
            if segment.hasPrefix("241") { result.productCode = String(segment.dropFirst(3)) }
        }

        result.format = .gs1Raw
    }

    private static func parseNumeric(_ input: String, into result: inout ParsedBarcode) {
        guard (12...14).contains(input.count), isValidGTINCheckDigit(input) else {
            result.format = .unknown
            return
        }
        result.gtin = normalizeGTIN(input)
        switch input.count {
        case 12: result.format = .upcA
        case 13: result.format = .ean13
        case 14: result.format = .gtin14
        default: result.format = .unknown
        }
    }

    // MARK: - Helpers

    private static func extractGS1Field(_ input: String, ai: String) -> String? {
        guard let regex = gs1FieldRegex(ai: ai),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range(at: 1), in: input)
        else { return nil }
        return String(input[range]).trimmingCharacters(in: .whitespaces)
    }

    private static func isHCPCSCode(_ value: String) -> Bool {
        hcpcsPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static func isASCIIDigits(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// GS1 Mod-10 check digit validation.
    private static func isValidGTINCheckDigit(_ value: String) -> Bool {
        guard isASCIIDigits(value), value.count >= 8 else { return false }
        let digits = value.compactMap { $0.wholeNumberValue }
        guard digits.count == value.count else { return false }

        let checkDigit = digits.last!
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { acc, pair in
            acc + pair.element * (pair.offset % 2 == 0 ? 3 : 1)
        }
        return (10 - (sum % 10)) % 10 == checkDigit
    }

    /// Pads a GTIN to the GS1-standard 14 digits.
    private static func normalizeGTIN(_ value: String) -> String {
        value.count < 14 ? String(repeating: "0", count: 14 - value.count) + value : value
    }
}

// MARK: - ParsedBarcode

struct ParsedBarcode {
    var raw: String
    var format: BarcodeFormat = .unknown
    var gtin: String?        = nil
    var lotNumber: String?   = nil
    var productCode: String? = nil
    var hcpcsCode: String?   = nil

    enum BarcodeFormat {
        case gs1Display  // (AI) parentheses — most DME packaging
        case gs1Raw      // FNC1 separators — direct scanner output
        case upcA        // 12 digits
        case ean13       // 13 digits
        case gtin14      // 14 digits
        case hcpcs       // Direct HCPCS code
        case unknown
    }

    var isRecognized: Bool { format != .unknown }

    /// Best identifier to use for catalog lookup.
    var lookupValue: String? { hcpcsCode ?? gtin }
}
