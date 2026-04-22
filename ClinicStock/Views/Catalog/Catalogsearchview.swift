//
//  CatalogSearchView.swift
//  ClinicStock
//
//  Search + scanner for the HCPCS catalog. Reference-lookup interface
//  for "what is this thing?" — the fast checkout flow lives in the
//  Scan tab (ScanTabView) instead.
//
//  Three workflows:
//
//    1. Type a name to find an item.
//    2. Scan a barcode that resolves to a catalog entry.
//    3. Scan a barcode NOT in the catalog yet, then search by name and
//       tap a result to link the scanned GTIN to that HCPCS code
//       (self-improving catalog).
//
//  NEW INIT PARAM:
//  - initialPendingGTIN: when presented as a sheet from ScanTabView,
//    this pre-loads the "linking" state so tapping any search result
//    auto-links the scanned GTIN.
//
//  NEW CALLBACK:
//  - onLinkComplete: fires after a successful link. The parent sheet
//    uses this to dismiss and show a confirmation on the Scan tab.
//
//  BarcodeScannerView / ScannerViewController live in BarcodeScanner.swift.
//

import SwiftUI

struct CatalogSearchView: View {

    @EnvironmentObject var searchService: HCPCSSearchService
    @Environment(\.dismiss) private var dismiss

    // If non-nil at init, pre-loads "linking mode" for the flow where
    // Scan tab couldn't find a GTIN in the catalog and sent the user
    // here to link it to an existing entry.
    let initialPendingGTIN: String?

    // Fires after a successful link. Lets the parent dismiss + show a
    // confirmation. Nil means standalone use (no callback).
    var onLinkComplete: ((String, HCPCSCatalogItem) -> Void)? = nil

    @State private var searchText = ""
    @State private var showScanner = false
    @State private var selectedItem: HCPCSCatalogItem? = nil
    @State private var searchTask: Task<Void, Never>? = nil

    // GTIN confirmation flow
    @State private var pendingGTIN: String? = nil
    @State private var showGTINConfirmation = false

    // Unrecognized-barcode feedback
    @State private var showUnrecognizedAlert = false

    init(
        initialPendingGTIN: String? = nil,
        onLinkComplete: ((String, HCPCSCatalogItem) -> Void)? = nil
    ) {
        self.initialPendingGTIN = initialPendingGTIN
        self.onLinkComplete = onLinkComplete
    }

    // True when this view was presented as a sheet (usually from Scan),
    // so we want a Done/Close button in the nav bar.
    private var isPresentedModally: Bool {
        initialPendingGTIN != nil || onLinkComplete != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let gtin = pendingGTIN {
                    pendingGTINBanner(gtin: gtin)
                }

                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search by name or HCPCS code...", text: $searchText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: searchText) { _, newValue in
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    guard !Task.isCancelled else { return }
                                    searchService.search(query: newValue)
                                }
                            }
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchService.clearResults()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                }
                .padding()

                if !searchService.isLoaded {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading catalog...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                resultsContent
            }
            .navigationTitle("DME Catalog")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isPresentedModally {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { scannedValue in
                    showScanner = false
                    Task {
                        await handleScan(value: scannedValue)
                    }
                }
            }
            .alert("Item Not Recognized", isPresented: $showGTINConfirmation) {
                Button("Search for it") {
                    searchText = ""
                    searchService.clearResults()
                }
                Button("Cancel", role: .cancel) {
                    pendingGTIN = nil
                }
            } message: {
                Text("This barcode isn't in the catalog yet. Search for the item by name and tap it to link this barcode automatically.")
            }
            .alert("Barcode Not Recognized", isPresented: $showUnrecognizedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The scanned code isn't a valid HCPCS or product barcode. Try again or search by name.")
            }
            .sheet(item: $selectedItem) { item in
                CatalogItemDetailView(item: item)
            }
            .onAppear {
                // Pre-load linking state if opened from Scan tab
                if let initial = initialPendingGTIN, pendingGTIN == nil {
                    pendingGTIN = initial
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Subviews
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var resultsContent: some View {
        if searchService.isSearching {
            Spacer()
            ProgressView("Searching...")
            Spacer()
        } else if searchText.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Search by name or scan a barcode")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Text(catalogSizeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else if searchService.results.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No results for \"\(searchText)\"")
                    .foregroundColor(.secondary)
                Text("Try a different name or scan the barcode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            List(searchService.results, id: \.hcpcsCode) { item in
                Button {
                    selectResult(item)
                } label: {
                    CatalogResultRow(item: item)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func pendingGTINBanner(gtin: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("Linking barcode \(gtin)")
                    .font(.footnote.weight(.semibold))
                Text("Tap an item below to link this barcode to it")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                pendingGTIN = nil
                // If we were opened solely for linking, also dismiss the sheet
                if initialPendingGTIN != nil {
                    dismiss()
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Computed
    // ══════════════════════════════════════════════════════

    private var catalogSizeLabel: String {
        if searchService.isLoaded {
            return "\(searchService.catalogSize) items in catalog"
        }
        return "..."
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func selectResult(_ item: HCPCSCatalogItem) {
        // If we have a pending GTIN, do the link and bubble up. Otherwise
        // just open the item detail as usual.
        if let gtin = pendingGTIN {
            Task {
                await searchService.confirmAndSaveGTIN(gtin: gtin, forItem: item)

                pendingGTIN = nil

                // Tell the parent we linked — they decide what to do next
                // (typically: dismiss + show a confirmation toast).
                if let callback = onLinkComplete {
                    callback(gtin, item)
                    dismiss()
                } else {
                    // No callback — still show the item detail so the
                    // user sees what they linked.
                    selectedItem = item
                }
            }
        } else {
            selectedItem = item
        }
    }

    private func handleScan(value: String) async {
        let result = await searchService.lookupBarcode(value)
        switch result {
        case .found(let item, _):
            selectedItem = item

        case .gtinNotFound(let gtin, _):
            pendingGTIN = gtin
            showGTINConfirmation = true

        case .unrecognized:
            showUnrecognizedAlert = true
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Result Row
// ══════════════════════════════════════════════════════

struct CatalogResultRow: View {
    let item: HCPCSCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.displayName)
                    .font(.headline)
                Spacer()
                Text(item.hcpcsCode)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
            }
            Text(item.shortClinicalName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Text(item.category)
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Item Detail
// ══════════════════════════════════════════════════════

struct CatalogItemDetailView: View {
    let item: HCPCSCatalogItem
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Code") {
                    HStack {
                        Text("HCPCS")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.hcpcsCode)
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("Category")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.category)
                    }
                }

                Section("Clinical name") {
                    Text(item.clinicalName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Section("Known as") {
                    ForEach(item.commonNames, id: \.self) { name in
                        Text(name.capitalized)
                            .font(.subheadline)
                    }
                }

                if let gtins = item.gtins, !gtins.isEmpty {
                    Section("Linked barcodes") {
                        ForEach(gtins, id: \.self) { gtin in
                            Text(gtin)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(item.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Browse") {
    CatalogSearchView()
        .environmentObject(HCPCSSearchService())
}

#Preview("Linking Mode") {
    CatalogSearchView(
        initialPendingGTIN: "00810041986108",
        onLinkComplete: { _, _ in }
    )
    .environmentObject(HCPCSSearchService())
}
