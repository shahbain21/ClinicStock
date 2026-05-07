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
    @Published var isSearching: Bool = false
    @Published var isLoaded: Bool = false
    @Published var errorMessage: String? = nil

    // Full catalog loaded once into memory
    private var catalog: [HCPCSCatalogItem] = []

    private let dbService = DatabaseService.shared
    private let nlmBaseURL = "https://clinicaltables.nlm.nih.gov/api/hcpcs/v3/search"

    // Deduplicate concurrent loads so init + first search don't double-fetch
    private var loadTask: Task<Void, Never>?

    // Track in-flight search so we can cancel on rapid typing
    private var searchTask: Task<Void, Never>?

    init() {
        Task {
            await loadCatalog()
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Public read-only accessors
    // ══════════════════════════════════════════════════════

    /// Total number of items currently loaded. Views should use this
    /// instead of hardcoding counts.
    var catalogSize: Int {
        catalog.count
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load full catalog once
    // ══════════════════════════════════════════════════════

    /// Loads the catalog from Firestore. Safe to call concurrently —
    /// overlapping callers share the same underlying fetch.
    func loadCatalog() async {
        // If a load is already running, wait for it instead of firing another.
        if let existing = loadTask {
            await existing.value
            return
        }

        let task = Task {
            await performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        print("Starting catalog load...")
        do {
            let loaded = try await dbService.getAllCatalogItems()
            catalog = loaded
            isLoaded = true
            errorMessage = nil
            print("Catalog loaded: \(loaded.count) items")
        } catch {
            isLoaded = false
            errorMessage = "Failed to load catalog"
            print("Failed to load catalog: \(error.localizedDescription)")
        }
    }

    /// Forces a fresh fetch from Firestore, replacing the in-memory catalog.
    /// Useful after bulk imports or admin-triggered refreshes.
    func refreshCatalog() async {
        loadTask = nil  // invalidate any cached completion
        isLoaded = false
        await loadCatalog()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Text search — client side, instant
    // ══════════════════════════════════════════════════════

    /// Starts a new search, cancelling any previous in-flight search.
    /// Results flow to the @Published `results` property.
    func search(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            await performSearch(query: query)
        }
    }

    /// Clears search results and cancels any in-flight search. Use this
    /// when the user clears the search field.
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

        // Wait for catalog to finish loading if it hasn't yet
        if !isLoaded {
            await loadCatalog()
        }

        // Check for cancellation after the load (catalog load may take a sec)
        if Task.isCancelled { return }

        // Search locally first — instant
        let localResults = searchLocally(query: trimmed)

        if !localResults.isEmpty {
            results = localResults
            return
        }

        // Nothing local — try NLM (respects cancellation internally)
        let nlmResults = await searchNLM(query: trimmed)

        if Task.isCancelled { return }
        results = deduplicated(nlmResults)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Barcode lookup
    // ══════════════════════════════════════════════════════

    func lookupBarcode(_ rawValue: String) async -> BarcodeSearchResult {
        let parsed = BarcodeService.parse(rawValue)

        // Direct HCPCS code scan — may also carry a GTIN on GS1 packaging
        if let hcpcsCode = parsed.hcpcsCode {
            let normalized = hcpcsCode.uppercased()
            if let item = catalog.first(where: {
                $0.hcpcsCode.uppercased() == normalized
            }) {
                // Opportunistically associate the GTIN if the scan had one
                // and we don't already know about it.
                if let gtin = parsed.gtin, !(item.gtins?.contains(gtin) ?? false) {
                    Task { await confirmAndSaveGTIN(gtin: gtin, forItem: item) }
                }
                return .found(item, gtin: parsed.gtin, parsed: parsed)
            }
        }

        // GTIN lookup — check local catalog first
        if let gtin = parsed.gtin {
            if let item = catalog.first(where: { $0.gtins?.contains(gtin) == true }) {
                return .found(item, gtin: gtin, parsed: parsed)
            }

            // Not in local catalog — check Firestore
            do {
                if let item = try await dbService.getCatalogItemByGTIN(gtin: gtin) {
                    cacheItem(item)
                    return .found(item, gtin: gtin, parsed: parsed)
                }
            } catch {
                print("GTIN Firestore lookup error: \(error)")
            }

            return .gtinNotFound(gtin: gtin, parsed: parsed)
        }

        return .unrecognized
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Save GTIN after staff confirms item
    // ══════════════════════════════════════════════════════

    func confirmAndSaveGTIN(gtin: String, forItem item: HCPCSCatalogItem) async {
        let code = item.hcpcsCode.uppercased()

        do {
            try await dbService.addGTINToCatalog(code: code, gtin: gtin)

            // Update local cache
            if let index = catalog.firstIndex(where: {
                $0.hcpcsCode.uppercased() == code
            }) {
                var updated = catalog[index]
                if updated.gtins == nil {
                    updated.gtins = [gtin]
                } else if updated.gtins?.contains(gtin) == false {
                    updated.gtins?.append(gtin)
                }
                catalog[index] = updated
            }

            print("GTIN \(gtin) saved to \(code)")
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

        let normalizedCode = code.uppercased()

        do {
            try await dbService.addCommonNameToCatalog(
                code: normalizedCode,
                name: normalized
            )

            if let index = catalog.firstIndex(where: {
                $0.hcpcsCode.uppercased() == normalizedCode
            }) {
                if !catalog[index].commonNames.contains(normalized) {
                    catalog[index].commonNames.append(normalized)
                }
            }

            print("Common name '\(normalized)' saved to \(normalizedCode)")
        } catch {
            print("Failed to save common name: \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Direct code lookup
    // ══════════════════════════════════════════════════════

    func lookupByCode(_ code: String) -> HCPCSCatalogItem? {
        let normalized = code.uppercased()
        return catalog.first(where: {
            $0.hcpcsCode.uppercased() == normalized
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
    // MARK: - Private: cache mutations
    // ══════════════════════════════════════════════════════

    private func cacheItem(_ item: HCPCSCatalogItem) {
        let code = item.hcpcsCode.uppercased()
        if let index = catalog.firstIndex(where: {
            $0.hcpcsCode.uppercased() == code
        }) {
            catalog[index] = item
        } else {
            catalog.append(item)
        }
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
                // Normalize commonNames defensively even though they SHOULD
                // already be lowercased — don't trust the data invariant.
                if item.commonNames.contains(where: {
                    $0.lowercased().contains(token)
                }) { return true }
                if item.clinicalName.lowercased().contains(token) { return true }
                if item.category.lowercased().contains(token) { return true }
                return false
            }
        }

        return matched.sorted { a, b in
            let aExact = a.commonNames.contains(where: { $0.lowercased() == query })
            let bExact = b.commonNames.contains(where: { $0.lowercased() == query })
            if aExact != bExact { return aExact }
            return a.hcpcsCode < b.hcpcsCode
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: NLM fallback
    //
    // Returns new HCPCSCatalogItem values immediately for the UI.
    // Firestore persistence and local cache updates run in the background
    // so the user doesn't wait on N sequential writes.
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

            var resultItems: [HCPCSCatalogItem] = []
            var newlyDiscovered: [HCPCSCatalogItem] = []

            let currentYear = Calendar.current.component(.year, from: Date())

            for pair in pairs {
                guard pair.count >= 2 else { continue }
                let code = pair[0].uppercased()
                let clinical = pair[1]
                guard isDMECode(code) else { continue }

                // If we already have it, just include the cached version
                if let existing = catalog.first(where: {
                    $0.hcpcsCode.uppercased() == code
                }) {
                    resultItems.append(existing)
                    continue
                }

                // New item — default category assignment is intentionally
                // conservative. Staff can recategorize when they add stock.
                let item = HCPCSCatalogItem(
                    hcpcsCode: code,
                    clinicalName: clinical,
                    commonNames: [query.lowercased()],
                    category: defaultCategory,
                    gtins: [],
                    isActive: true,
                    sourceYear: currentYear,
                    lastUpdated: Date()
                )

                resultItems.append(item)
                newlyDiscovered.append(item)
            }

            // Optimistic: add to local cache immediately so subsequent
            // searches don't hit NLM again during this session.
            for item in newlyDiscovered {
                cacheItem(item)
            }

            // Persist newly discovered items in the background.
            // User sees results without waiting on Firestore writes.
            if !newlyDiscovered.isEmpty {
                Task.detached { [weak self] in
                    guard let self = self else { return }
                    await self.persistNLMItems(newlyDiscovered, year: currentYear)
                }
            }

            return resultItems

        } catch {
            print("NLM error: \(error)")
            return []
        }
    }

    private func persistNLMItems(
        _ items: [HCPCSCatalogItem],
        year: Int
    ) async {
        for item in items {
            do {
                try await dbService.saveCatalogItem([
                    "hcpcsCode": item.hcpcsCode,
                    "clinicalName": item.clinicalName,
                    "commonNames": item.commonNames,
                    "category": item.category,
                    "gtins": [] as [String],
                    "isActive": true,
                    "sourceYear": year,
                    "lastUpdated": Timestamp(date: Date())
                ])
                print("Saved NLM result to catalog: \(item.hcpcsCode)")
            } catch {
                print("Failed to save NLM result \(item.hcpcsCode): \(error)")
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: helpers
    // ══════════════════════════════════════════════════════

    private func deduplicated(_ items: [HCPCSCatalogItem]) -> [HCPCSCatalogItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.hcpcsCode.uppercased()).inserted }
    }

    private func isDMECode(_ code: String) -> Bool {
        guard let first = code.first else { return false }
        return ["A", "E", "K", "L"].contains(String(first).uppercased())
    }

    // Default category for NLM-imported items. Chosen to match an entry
    // in the settings/categories list seeded by DatabaseSeeder so the
    // filter UI stays consistent.
    private let defaultCategory = "General Medical"
}

// ══════════════════════════════════════════════════════
// MARK: - Barcode search result
// ══════════════════════════════════════════════════════

enum BarcodeSearchResult {
    /// Catalog match. `gtin` is the GTIN that matched (if the scan
    /// included one). `parsed` is the full GS1 parse result, which
    /// callers can use to extract lot number, expiry, etc. from the
    /// same scan instead of asking the user to re-scan.
    case found(HCPCSCatalogItem, gtin: String?, parsed: ParsedBarcode?)
    case gtinNotFound(gtin: String, parsed: ParsedBarcode)
    case unrecognized
}
