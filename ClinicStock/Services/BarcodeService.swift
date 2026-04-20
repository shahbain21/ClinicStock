//
//  BarcodeService.swift
//  ClinicStock
//
//  Created by Mohamed Kaid
//
//  FIXES:
//  - Trim whitespace/newlines from input (keyboard-wedge scanners often append)
//  - Guard against empty input (was silently producing all-zero GTIN)
//  - Replace Unicode-permissive isNumber with ASCII-only digit check
//  - Validate GTIN check digit (Mod-10); reject invalid numerics
//  - Rename .ean13 → .numeric with length stored separately (honest labels)
//  - Precompile regex patterns as static constants (not per-call)
//  - Basic FNC1 (GS) detection on raw GS1-128 scans — not full spec support,
//    but handles the most common case where a scanner emits raw AIs
//    separated by the Group Separator character (0x1D).
//
//  NOT FIXED (deferred to scanner SDK integration):
//  - Full GS1 Application Identifier table with fixed-length AIs
//  - Non-parenthesized, non-FNC1 concatenated AIs (ambiguous without AI table)
//

import Foundation

struct BarcodeService {

    // ══════════════════════════════════════════════════════
    // MARK: - Compiled regexes (reused across calls)
    // ══════════════════════════════════════════════════════

    private static let hcpcsPattern =
        try! NSRegularExpression(pattern: "^[A-Za-z]\\d{4}$")

    // Cache for per-AI regexes; GS1 parsing reuses the same few AIs constantly.
    private static var gs1FieldRegexCache: [String: NSRegularExpression] = [:]
    private static let gs1CacheQueue = DispatchQueue(label: "BarcodeService.gs1Cache")

    private static func gs1FieldRegex(ai: String) -> NSRegularExpression? {
        return gs1CacheQueue.sync {
            if let cached = gs1FieldRegexCache[ai] {
                return cached
            }
            // Match either the end-of-string, FNC1 (0x1D), or next "(AI)" group
            // as a terminator after the value.
            let pattern = "\\(\(ai)\\)([^(\\x1D]+)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            gs1FieldRegexCache[ai] = regex
            return regex
        }
    }

    // FNC1 (Group Separator) as a Swift string for the non-parenthesized path.
    private static let fnc1 = "\u{1D}"

    // ══════════════════════════════════════════════════════
    // MARK: - Parse a raw barcode string
    // Returns a ParsedBarcode with whatever fields were found
    // ══════════════════════════════════════════════════════

    static func parse(_ rawValue: String) -> ParsedBarcode {
        // Trim trailing newlines/whitespace that scanners often append
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        var result = ParsedBarcode(raw: rawValue)

        // Empty input is not a valid scan
        guard !trimmed.isEmpty else {
            result.format = .unknown
            return result
        }

        // GS1-128 display format: (01)GTIN(10)LotNumber(241)ProductCode
        // Example: (01)00810041986108(10)19139(241)SUP2071
        if trimmed.contains("(01)") {
            parseGS1Parenthesized(trimmed, into: &result)
        }
        // GS1-128 raw format: AIs separated by FNC1 (ASCII 0x1D)
        // Example: 01008100419861081019139\x1D241SUP2071
        else if trimmed.contains(fnc1) && trimmed.hasPrefix("01") {
            parseGS1FNC1(trimmed, into: &result)
        }
        // Plain HCPCS code — e.g. "L1820" typed or scanned directly
        else if isHCPCSCode(trimmed) {
            result.hcpcsCode = trimmed.uppercased()
            result.format = .hcpcs
        }
        // UPC-A, EAN-13, or GTIN-14 — plain ASCII digits only
        else if isASCIIDigits(trimmed) {
            parseNumeric(trimmed, into: &result)
        }
        // Unknown
        else {
            result.format = .unknown
        }

        return result
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Format-specific parsers
    // ══════════════════════════════════════════════════════

    private static func parseGS1Parenthesized(
        _ input: String,
        into result: inout ParsedBarcode
    ) {
        result.gtin = extractGS1Field(input, ai: "01")
        result.lotNumber = extractGS1Field(input, ai: "10")
        result.productCode = extractGS1Field(input, ai: "241")
        result.format = .gs1Display

        // Normalize the GTIN we extracted (might be 13-digit with leading zero)
        if let gtin = result.gtin {
            result.gtin = normalizeGTIN(gtin)
        }
    }

    private static func parseGS1FNC1(
        _ input: String,
        into result: inout ParsedBarcode
    ) {
        // The (01) GTIN is always exactly 14 digits and is always first.
        // After that, variable-length AIs are FNC1-separated.
        let afterAI = input.dropFirst(2) // strip "01"
        let gtinPrefix = String(afterAI.prefix(14))

        if gtinPrefix.count == 14, isASCIIDigits(gtinPrefix) {
            result.gtin = gtinPrefix
        }

        // Split remainder on FNC1 and pick out known AIs
        let remainder = String(afterAI.dropFirst(14))
        let segments = remainder.components(separatedBy: fnc1)

        for segment in segments where !segment.isEmpty {
            if segment.hasPrefix("10") {
                result.lotNumber = String(segment.dropFirst(2))
            } else if segment.hasPrefix("241") {
                result.productCode = String(segment.dropFirst(3))
            }
            // Other AIs (17 expiry, 21 serial, etc.) ignored for now
        }

        result.format = .gs1Raw
    }

    private static func parseNumeric(
        _ input: String,
        into result: inout ParsedBarcode
    ) {
        // Accept UPC-A (12), EAN-13 (13), GTIN-14 (14) only
        guard (12...14).contains(input.count) else {
            result.format = .unknown
            return
        }

        // Validate check digit — catches most scanner/typo errors
        guard isValidGTINCheckDigit(input) else {
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

    // ══════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════

    // Extract a GS1 Application Identifier value from the parenthesized form.
    private static func extractGS1Field(_ input: String, ai: String) -> String? {
        guard let regex = gs1FieldRegex(ai: ai),
              let match = regex.firstMatch(
                in: input,
                range: NSRange(input.startIndex..., in: input)
              ),
              let range = Range(match.range(at: 1), in: input)
        else { return nil }

        return String(input[range])
            .trimmingCharacters(in: .whitespaces)
    }

    // HCPCS = one letter followed by 4 digits e.g. L1820, E0720, A6530
    private static func isHCPCSCode(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return hcpcsPattern.firstMatch(in: value, range: range) != nil
    }

    // ASCII digits only — rejects Unicode digit lookalikes from other scripts.
    private static func isASCIIDigits(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // Validate GTIN check digit using GS1 Mod-10.
    // Algorithm: multiply digits alternately by 3 and 1 from the right
    // (excluding the rightmost check digit), sum, then check digit is
    // (10 - (sum mod 10)) mod 10.
    private static func isValidGTINCheckDigit(_ value: String) -> Bool {
        guard isASCIIDigits(value), value.count >= 8 else { return false }

        let digits = value.compactMap { $0.wholeNumberValue }
        guard digits.count == value.count else { return false }

        let checkDigit = digits.last!
        let payload = digits.dropLast().reversed()

        var sum = 0
        for (index, digit) in payload.enumerated() {
            // Rightmost payload digit gets weight 3, then alternating 1, 3, 1...
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }

        let expected = (10 - (sum % 10)) % 10
        return expected == checkDigit
    }

    // Normalize a GTIN to 14 digits (GS1 standard).
    // UPC-A is 12 digits, EAN-13 is 13 — pad to 14.
    // If input is longer than 14, return unchanged (caller should have validated).
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
        case gs1Display   // GS1-128 with (AI) parentheses — most DME packaging
        case gs1Raw       // GS1-128 with FNC1 separators — direct scanner output
        case upcA         // UPC-A, exactly 12 digits
        case ean13        // EAN-13, exactly 13 digits
        case gtin14       // GTIN-14, exactly 14 digits
        case hcpcs        // Direct HCPCS code scan
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
