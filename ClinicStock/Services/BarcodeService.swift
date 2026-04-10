//
//  BarcodeService.swift
//  ClinicStock
//
//  Created by Mohamed Kaid

import Foundation

struct BarcodeService {

    // ══════════════════════════════════════════════════════
    // MARK: - Parse a raw barcode string
    // Returns a ParsedBarcode with whatever fields were found
    // ══════════════════════════════════════════════════════

    static func parse(_ rawValue: String) -> ParsedBarcode {
        var result = ParsedBarcode(raw: rawValue)

        // GS1-128 format: (01)GTIN(10)LotNumber(241)ProductCode
        // Example: (01)00810041986108(10)19139(241)SUP2071
        if rawValue.contains("(01)") {
            result.gtin = extractGS1Field(rawValue, ai: "01")
            result.lotNumber = extractGS1Field(rawValue, ai: "10")
            result.productCode = extractGS1Field(rawValue, ai: "241")
            result.format = .gs1_128
        }
        // Plain HCPCS code — e.g. "L1820" typed or scanned directly
        else if isHCPCSCode(rawValue) {
            result.hcpcsCode = rawValue.uppercased()
            result.format = .hcpcs
        }
        // UPC-A or EAN-13 — plain numeric
        else if rawValue.allSatisfy({ $0.isNumber }) {
            result.gtin = normalizeGTIN(rawValue)
            result.format = rawValue.count == 12 ? .upc : .ean13
        }
        // Unknown
        else {
            result.format = .unknown
        }

        return result
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════

    // Extract a GS1 Application Identifier value
    // e.g. extractGS1Field("(01)00810041986108(10)19139", ai: "01") → "00810041986108"
    private static func extractGS1Field(_ input: String, ai: String) -> String? {
        let pattern = "\\(\(ai)\\)([^(]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: input,
                range: NSRange(input.startIndex..., in: input)
              ),
              let range = Range(match.range(at: 1), in: input)
        else { return nil }

        return String(input[range]).trimmingCharacters(in: .whitespaces)
    }

    // Check if a string looks like an HCPCS code
    // HCPCS = one letter followed by 4 digits e.g. L1820, E0720, A6530
    private static func isHCPCSCode(_ value: String) -> Bool {
        let pattern = "^[A-Za-z]\\d{4}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    // Normalize a GTIN to 14 digits (GS1 standard)
    // UPC-A is 12 digits, EAN-13 is 13 — pad to 14
    private static func normalizeGTIN(_ value: String) -> String {
        if value.count < 14 {
            return String(repeating: "0", count: 14 - value.count) + value
        }
        return value
    }
}

// ══════════════════════════════════════════════════════
// MARK: - ParsedBarcode
// ══════════════════════════════════════════════════════

struct ParsedBarcode {
    var raw: String
    var format: BarcodeFormat = .unknown
    var gtin: String? = nil
    var lotNumber: String? = nil
    var productCode: String? = nil
    var hcpcsCode: String? = nil

    enum BarcodeFormat {
        case gs1_128    // GS1-128 with application identifiers — most DME
        case upc        // UPC-A 12 digit
        case ean13      // EAN-13
        case hcpcs      // Direct HCPCS code scan
        case unknown
    }

    // Was this a useful scan?
    var isRecognized: Bool {
        return format != .unknown
    }

    // Best identifier to use for catalog lookup
    var lookupValue: String? {
        return hcpcsCode ?? gtin
    }
}
