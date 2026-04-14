//
//  HCPCSSearchService.swift
//  ClinicStock
//
//  FIXES:
//  - NLM results now saved to Firestore via DatabaseService
//  - Routed Firestore operations through DatabaseService where practical
//  - loadCatalog uses DatabaseService.getAllCatalogItems()
//  - confirmAndSaveGTIN uses DatabaseService
//  - saveCommonName uses DatabaseService
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class HCPCSSearchService: ObservableObject {

    @Published var results: [HCPCSCatalogItem] = []
    @Published var isSearching: Bool = false
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String? = nil

    // Full catalog loaded once into memory
    private var catalog: [HCPCSCatalogItem] = []

    private let dbService = DatabaseService.shared
    private let nlmBaseURL = "https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search"

    init() {
        Task {
            await loadCatalog()
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load full catalog once
    // ══════════════════════════════════════════════════════

    func loadCatalog() async {
        print("Starting catalog load...")
        do {
            catalog = try await dbService.getAllCatalogItems()
            print("Catalog loaded: \(catalog.count) items")
            isLoaded = true
        } catch {
            print("Failed to load catalog: \(error.localizedDescription)")
            errorMessage = "Failed to load catalog"
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Text search — client side, instant
    // ══════════════════════════════════════════════════════

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        guard trimmed.count >= 2 else {
            results = []
            return
        }

        // Wait for catalog to finish loading if it hasn't yet
        if !isLoaded {
            await loadCatalog()
        }

        // Search locally first — instant
        let localResults = searchLocally(query: trimmed)

        if !localResults.isEmpty {
            results = localResults
            return
        }

        // Nothing local — try NLM
        isSearching = true
        let nlmResults = await searchNLM(query: trimmed)
        results = deduplicated(nlmResults)
        isSearching = false
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Barcode lookup
    // ══════════════════════════════════════════════════════

    func lookupBarcode(_ rawValue: String) async -> BarcodeSearchResult {
        let parsed = BarcodeService.parse(rawValue)

        // Direct HCPCS code scan
        if let hcpcsCode = parsed.hcpcsCode {
            if let item = catalog.first(where: {
                $0.hcpcsCode.uppercased() == hcpcsCode.uppercased()
            }) {
                return .found(item, gtin: nil)
            }
        }

        // GTIN lookup — check local catalog first
        if let gtin = parsed.gtin {
            if let item = catalog.first(where: { $0.gtins?.contains(gtin) == true }) {
                return .found(item, gtin: gtin)
            }

            // Not in local catalog — check Firestore
            do {
                if let item = try await dbService.getCatalogItemByGTIN(gtin: gtin) {
                    // Update local cache
                    if let index = catalog.firstIndex(where: {
                        $0.hcpcsCode == item.hcpcsCode
                    }) {
                        catalog[index] = item
                    } else {
                        catalog.append(item)
                    }
                    return .found(item, gtin: gtin)
                }
            } catch {
                print("GTIN Firestore lookup error: \(error)")
            }

            // GTIN not found anywhere
            return .gtinNotFound(gtin: gtin, parsed: parsed)
        }

        return .unrecognized
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Save GTIN after staff confirms item
    // ══════════════════════════════════════════════════════

    func confirmAndSaveGTIN(gtin: String, forItem item: HCPCSCatalogItem) async {
        do {
            try await dbService.addGTINToCatalog(
                code: item.hcpcsCode,
                gtin: gtin
            )

            // Update local cache immediately
            if let index = catalog.firstIndex(where: {
                $0.hcpcsCode == item.hcpcsCode
            }) {
                var updated = catalog[index]
                if updated.gtins == nil {
                    updated.gtins = [gtin]
                } else if updated.gtins?.contains(gtin) == false {
                    updated.gtins?.append(gtin)
                }
                catalog[index] = updated
            }

            print("GTIN \(gtin) saved to \(item.hcpcsCode)")
        } catch {
            print("Failed to save GTIN: \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Save new common name
    // ══════════════════════════════════════════════════════

    func saveCommonName(_ name: String, toCode code: String) async {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return }

        do {
            try await dbService.addCommonNameToCatalog(
                code: code,
                name: normalized
            )

            if let index = catalog.firstIndex(where: {
                $0.hcpcsCode.uppercased() == code.uppercased()
            }) {
                if !catalog[index].commonNames.contains(normalized) {
                    catalog[index].commonNames.append(normalized)
                }
            }

            print("Common name '\(normalized)' saved to \(code)")
        } catch {
            print("Failed to save common name: \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Direct code lookup
    // ══════════════════════════════════════════════════════

    func lookupByCode(_ code: String) -> HCPCSCatalogItem? {
        return catalog.first(where: {
            $0.hcpcsCode.uppercased() == code.uppercased()
        })
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Get all items by category
    // ══════════════════════════════════════════════════════

    func itemsByCategory(_ category: String) -> [HCPCSCatalogItem] {
        return catalog
            .filter { $0.category == category }
            .sorted { $0.hcpcsCode < $1.hcpcsCode }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - All categories
    // ══════════════════════════════════════════════════════

    var allCategories: [String] {
        Array(Set(catalog.map { $0.category })).sorted()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: local search
    // ══════════════════════════════════════════════════════

    private func searchLocally(query: String) -> [HCPCSCatalogItem] {
        print("Searching locally — catalog size: \(catalog.count), query: \(query)")
        let tokens = query.split(separator: " ").map(String.init)

        let matched = catalog.filter { item in
            tokens.allSatisfy { token in
                if item.hcpcsCode.lowercased().contains(token) { return true }
                if item.commonNames.contains(where: { $0.contains(token) }) { return true }
                if item.clinicalName.lowercased().contains(token) { return true }
                if item.category.lowercased().contains(token) { return true }
                return false
            }
        }

        return matched.sorted { a, b in
            let aExact = a.commonNames.contains(where: { $0 == query })
            let bExact = b.commonNames.contains(where: { $0 == query })
            if aExact != bExact { return aExact }
            return a.hcpcsCode < b.hcpcsCode
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: NLM fallback
    // Now saves new items to Firestore for future searches
    // ══════════════════════════════════════════════════════

    private func searchNLM(query: String) async -> [HCPCSCatalogItem] {
        guard var components = URLComponents(string: nlmBaseURL) else { return [] }

        components.queryItems = [
            URLQueryItem(name: "terms", value: query),
            URLQueryItem(name: "maxList", value: "10"),
            URLQueryItem(name: "df", value: "code,display")
        ]

        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count >= 4,
                  let pairs = json[3] as? [[String]]
            else { return [] }

            var newItems: [HCPCSCatalogItem] = []

            for pair in pairs {
                guard pair.count >= 2 else { continue }
                let code = pair[0]
                let clinical = pair[1]
                guard isDMECode(code) else { continue }

                // Return from local cache if already exists
                if let existing = catalog.first(where: { $0.hcpcsCode == code }) {
                    newItems.append(existing)
                    continue
                }

                // Create new item
                let item = HCPCSCatalogItem(
                    hcpcsCode: code,
                    clinicalName: clinical,
                    commonNames: [query.lowercased()],
                    category: categoryForCode(code),
                    gtins: [],
                    isActive: true,
                    sourceYear: 2026,
                    lastUpdated: Date()
                )

                newItems.append(item)

                // Save to Firestore so future searches find it locally
                do {
                    try await dbService.saveCatalogItem([
                        "hcpcsCode": code,
                        "clinicalName": clinical,
                        "commonNames": [query.lowercased()],
                        "category": categoryForCode(code),
                        "gtins": [] as [String],
                        "isActive": true,
                        "sourceYear": 2026,
                        "lastUpdated": Timestamp(date: Date())
                    ])

                    // Add to local cache
                    catalog.append(item)
                    print("Saved NLM result to catalog: \(code)")
                } catch {
                    print("Failed to save NLM result \(code): \(error)")
                }
            }

            return newItems

        } catch {
            print("NLM error: \(error)")
            return []
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: helpers
    // ══════════════════════════════════════════════════════

    private func deduplicated(_ items: [HCPCSCatalogItem]) -> [HCPCSCatalogItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.hcpcsCode).inserted }
    }

    private func isDMECode(_ code: String) -> Bool {
        guard let first = code.first else { return false }
        return ["A", "E", "K", "L"].contains(String(first).uppercased())
    }

    private func categoryForCode(_ code: String) -> String {
        guard let first = code.first else { return "General Medical" }
        switch String(first).uppercased() {
        case "E": return "Durable Medical Equipment"
        case "L": return "Orthopedic"
        case "A": return "Medical Supplies"
        case "K": return "Wheelchairs"
        default: return "General Medical"
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Barcode search result
// ══════════════════════════════════════════════════════

enum BarcodeSearchResult {
    case found(HCPCSCatalogItem, gtin: String?)
    case gtinNotFound(gtin: String, parsed: ParsedBarcode)
    case unrecognized
}
