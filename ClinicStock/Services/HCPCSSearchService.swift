//
//  HCPCSSearchService.swift
//  ClinicStock
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class HCPCSSearchService: ObservableObject {

    @Published var results: [HCPCSCatalogItem] = []
    @Published var isSearching = false
    @Published var isLoaded = false
    @Published var errorMessage: String?

    private var catalog: [HCPCSCatalogItem] = []
    private let dbService = DatabaseService.shared
    private let nlmBaseURL = "https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search"
    private let defaultCategory = "General Medical"

    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init() {
        Task { await loadCatalog() }
    }

    // MARK: - Public Accessors

    var catalogSize: Int { catalog.count }

    var allCategories: [String] {
        Array(Set(catalog.map { $0.category })).sorted()
    }

    func lookupByCode(_ code: String) -> HCPCSCatalogItem? {
        catalog.first { $0.hcpcsCode.uppercased() == code.uppercased() }
    }

    func itemsByCategory(_ category: String) -> [HCPCSCatalogItem] {
        catalog
            .filter { $0.category == category }
            .sorted { $0.hcpcsCode < $1.hcpcsCode }
    }

    // MARK: - Catalog Loading

    /// Loads the full catalog from Firestore. Concurrent callers share the same fetch.
    func loadCatalog() async {
        if let existing = loadTask {
            await existing.value
            return
        }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// Forces a fresh fetch, replacing the in-memory catalog.
    func refreshCatalog() async {
        loadTask = nil
        isLoaded = false
        await loadCatalog()
    }

    private func performLoad() async {
        do {
            catalog = try await dbService.getAllCatalogItems()
            isLoaded = true
            errorMessage = nil
        } catch {
            isLoaded = false
            errorMessage = "Failed to load catalog"
        }
    }

    // MARK: - Text Search

    /// Searches locally first, falls back to NLM if nothing is found.
    /// Cancels any in-flight search before starting.
    func search(query: String) {
        searchTask?.cancel()
        searchTask = Task { await performSearch(query: query) }
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        isSearching = false
    }

    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        defer { isSearching = false }

        if !isLoaded { await loadCatalog() }
        guard !Task.isCancelled else { return }

        let local = searchLocally(query: trimmed)
        if !local.isEmpty {
            results = local
            return
        }

        let nlm = await searchNLM(query: trimmed)
        guard !Task.isCancelled else { return }
        results = deduplicated(nlm)
    }

    
    //-------------------------
    // MARK: - Barcode Lookup

    func lookupBarcode(_ rawValue: String) async -> BarcodeSearchResult {
        let parsed = BarcodeService.parse(rawValue)

        // Direct HCPCS scan — opportunistically save any new GTIN.
        if let code = parsed.hcpcsCode,
           let item = catalog.first(where: { $0.hcpcsCode.uppercased() == code.uppercased() }) {
            //check if the barcode exist if not add it to the database
            if let gtin = parsed.gtin, !(item.gtins?.contains(gtin) ?? false) {
                Task { await confirmAndSaveGTIN(gtin: gtin, forItem: item) }
            }
            return .found(item, gtin: parsed.gtin, parsed: parsed)
        }

        // GTIN lookup — local cache first, then Firestore.
        guard let gtin = parsed.gtin else { return .unrecognized }

        if let item = catalog.first(where: { $0.gtins?.contains(gtin) == true }) {
            return .found(item, gtin: gtin, parsed: parsed)
        }

        do {
            if let item = try await dbService.getCatalogItemByGTIN(gtin: gtin) {
                cacheItem(item)
                return .found(item, gtin: gtin, parsed: parsed)
            }
        } catch {
            
        }

        return .gtinNotFound(gtin: gtin, parsed: parsed)
    }

    //--------------------------
    // MARK: - Self-Improving Catalog

    /// Links a scanned GTIN to a catalog entry and persists it to Firestore.
    func confirmAndSaveGTIN(gtin: String, forItem item: HCPCSCatalogItem) async {
        let code = item.hcpcsCode.uppercased()
        do {
            try await dbService.addGTINToCatalog(code: code, gtin: gtin)
            if let index = catalog.firstIndex(where: { $0.hcpcsCode.uppercased() == code }) {
                var updated = catalog[index]
                if updated.gtins == nil {
                    updated.gtins = [gtin]
                } else if updated.gtins?.contains(gtin) == false {
                    updated.gtins?.append(gtin)
                }
                catalog[index] = updated
            }
        } catch {
            // Non-critical — GTIN will be saved on the next successful scan.
        }
    }

    /// Adds a new common name to a catalog entry and persists it to Firestore.
    func saveCommonName(_ name: String, toCode code: String) async {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return }
        let upperCode = code.uppercased()
        do {
            try await dbService.addCommonNameToCatalog(code: upperCode, name: normalized)
            if let index = catalog.firstIndex(where: { $0.hcpcsCode.uppercased() == upperCode }),
               !catalog[index].commonNames.contains(normalized) {
                catalog[index].commonNames.append(normalized)
            }
        } catch {
            // Non-critical — name will be retried on next save attempt.
        }
    }

    // MARK: - Private: Local Search

    private func searchLocally(query: String) -> [HCPCSCatalogItem] {
        let tokens = query.split(separator: " ").map(String.init)

        return catalog
            .filter { item in
                tokens.allSatisfy { token in
                    item.hcpcsCode.lowercased().contains(token) ||
                    item.commonNames.contains(where: { $0.lowercased().contains(token) }) ||
                    item.clinicalName.lowercased().contains(token) ||
                    item.category.lowercased().contains(token)
                }
            }
            .sorted { a, b in
                let aExact = a.commonNames.contains(where: { $0.lowercased() == query })
                let bExact = b.commonNames.contains(where: { $0.lowercased() == query })
                if aExact != bExact { return aExact }
                return a.hcpcsCode < b.hcpcsCode
            }
    }

    // MARK: - Private: NLM Fallback

    /// Hits the NLM API for codes not found locally.
    /// Results return immediately; Firestore persistence runs in the background.
    private func searchNLM(query: String) async -> [HCPCSCatalogItem] {
        guard var components = URLComponents(string: nlmBaseURL) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "terms",   value: query),
            URLQueryItem(name: "maxList", value: "10"),
            URLQueryItem(name: "df",      value: "code,display")
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json  = try JSONSerialization.jsonObject(with: data) as? [Any],
                json.count >= 4,
                let pairs = json[3] as? [[String]]
            else { return [] }

            let year = Calendar.current.component(.year, from: Date())
            var results: [HCPCSCatalogItem] = []
            var newItems: [HCPCSCatalogItem] = []

            for pair in pairs {
                guard pair.count >= 2, isDMECode(pair[0]) else { continue }
                let code = pair[0].uppercased()

                if let existing = catalog.first(where: { $0.hcpcsCode.uppercased() == code }) {
                    results.append(existing)
                    continue
                }

                let item = HCPCSCatalogItem(
                    hcpcsCode: code,
                    clinicalName: pair[1],
                    commonNames: [query.lowercased()],
                    category: defaultCategory,
                    gtins: [],
                    isActive: true,
                    sourceYear: year,
                    lastUpdated: Date()
                )
                results.append(item)
                newItems.append(item)
            }

            newItems.forEach { cacheItem($0) }

            if !newItems.isEmpty {
                Task.detached { [weak self] in
                    guard let self else { return }
                    await self.persistNLMItems(newItems, year: year)
                }
            }

            return results
        } catch {
            return []
        }
    }

    private func persistNLMItems(_ items: [HCPCSCatalogItem], year: Int) async {
        for item in items {
            try? await dbService.saveCatalogItem([
                "hcpcsCode":    item.hcpcsCode,
                "clinicalName": item.clinicalName,
                "commonNames":  item.commonNames,
                "category":     item.category,
                "gtins":        [String](),
                "isActive":     true,
                "sourceYear":   year,
                "lastUpdated":  Timestamp(date: Date())
            ])
        }
    }

    // MARK: - Private: Helpers

    private func cacheItem(_ item: HCPCSCatalogItem) {
        let code = item.hcpcsCode.uppercased()
        if let index = catalog.firstIndex(where: { $0.hcpcsCode.uppercased() == code }) {
            catalog[index] = item
        } else {
            catalog.append(item)
        }
    }

    private func deduplicated(_ items: [HCPCSCatalogItem]) -> [HCPCSCatalogItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.hcpcsCode.uppercased()).inserted }
    }

    private func isDMECode(_ code: String) -> Bool {
        guard let first = code.first else { return false }
        return ["A", "E", "K", "L"].contains(String(first).uppercased())
    }
}

// MARK: - BarcodeSearchResult

enum BarcodeSearchResult {
    /// Found in catalog. `gtin` is the matched barcode; `parsed` carries full GS1 data.
    case found(HCPCSCatalogItem, gtin: String?, parsed: ParsedBarcode?)
    case gtinNotFound(gtin: String, parsed: ParsedBarcode)
    case unrecognized
}
