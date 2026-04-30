//
//  AddItemView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Add or edit an inventory item. Pass editingItem: to switch into edit
//  mode — same form, pre-populated, saves via updateItemInfo instead of
//  addNewItem.
//
//  NEW: Optional prefill init for the scan flow. When the Scan tab
//  hands off to Add Item, it passes whatever values the scan gave us
//  (barcode, lot, and if it matched a catalog entry: name, HCPCS,
//  category). Users don't re-type what we already know.
//
//  HIFI STYLING:
//  - Big bottom Add/Cancel buttons instead of toolbar buttons.
//  - All current fields preserved (hifi is styling reference, not scope).
//

import SwiftUI

struct AddItemView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @Environment(\.dismiss) private var dismiss

    let editingItem: InventoryItem?

    /// Init for adding a new item. All prefill params are optional —
    /// typically filled from a scan result when the user taps
    /// "Add to Inventory" on a catalog-only scan, or "Add as New Item"
    /// on an unmatched-GTIN scan.
    init(
        prefillName: String? = nil,
        prefillHCPCS: String? = nil,
        prefillBarcode: String? = nil,
        prefillCategory: String? = nil,
        prefillLotNumber: String? = nil
    ) {
        self.editingItem = nil

        _name = State(initialValue: prefillName ?? "")
        _hcpcsCode = State(initialValue: prefillHCPCS ?? "")
        _lotNumber = State(initialValue: prefillLotNumber ?? "")
        _size = State(initialValue: "Universal")
        _barcode = State(initialValue: prefillBarcode ?? "")
        _quantity = State(initialValue: "1")
        _threshold = State(initialValue: "10")
        _category = State(initialValue: prefillCategory ?? "General Medical")
        _manufacturer = State(initialValue: "")
        _unitCost = State(initialValue: "")
        _notes = State(initialValue: "")
    }

    /// Init for editing an existing item.
    init(editingItem: InventoryItem) {
        self.editingItem = editingItem

        _name = State(initialValue: editingItem.name)
        _hcpcsCode = State(initialValue: editingItem.hcpcsCode)
        _lotNumber = State(initialValue: editingItem.lotNumber)
        _size = State(initialValue: editingItem.size)
        _barcode = State(initialValue: editingItem.barcode)
        _quantity = State(initialValue: "\(editingItem.quantity)")
        _threshold = State(initialValue: "\(editingItem.lowStockThreshold)")
        _category = State(initialValue: editingItem.category)
        _manufacturer = State(initialValue: editingItem.manufacturer)
        _unitCost = State(
            initialValue: editingItem.unitCost.map {
                String(format: "%.2f", $0)
            } ?? ""
        )
        _notes = State(initialValue: editingItem.notes)
    }

    // Form fields
    @State private var name: String
    @State private var hcpcsCode: String
    @State private var lotNumber: String
    @State private var size: String
    @State private var barcode: String
    @State private var quantity: String
    @State private var threshold: String
    @State private var category: String
    @State private var manufacturer: String
    @State private var unitCost: String
    @State private var notes: String

    @State private var isSaving = false
    @State private var errorMessage: String?

    // Available values from settings
    @State private var categories: [String] = []
    @State private var sizes: [String] = []

    private var isEditing: Bool { editingItem != nil }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !hcpcsCode.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(quantity) ?? -1) >= 0 &&
        (Int(threshold) ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Basic Info") {
                        TextField("Name *", text: $name)
                        TextField("HCPCS Code *", text: $hcpcsCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()

                        if categories.isEmpty {
                            TextField("Category", text: $category)
                        } else {
                            Picker("Category", selection: $category) {
                                ForEach(categories, id: \.self) { Text($0).tag($0) }
                            }
                        }

                        if sizes.isEmpty {
                            TextField("Size", text: $size)
                        } else {
                            Picker("Size", selection: $size) {
                                ForEach(sizes, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }

                    Section("Stock") {
                        HStack {
                            Text("Quantity *")
                            Spacer()
                            TextField("0", text: $quantity)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        HStack {
                            Text("Low stock threshold")
                            Spacer()
                            TextField("10", text: $threshold)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    Section("Identification") {
                        TextField("Lot number", text: $lotNumber)
                            .autocorrectionDisabled()
                        TextField("Barcode / GTIN", text: $barcode)
                            .autocorrectionDisabled()
                            .keyboardType(.numberPad)
                    }

                    Section("Additional") {
                        // Labeled "Supplier" per hifi but still maps to
                        // the `manufacturer` field on the model.
                        TextField("Supplier", text: $manufacturer)
                        HStack {
                            Text("Unit cost")
                            Spacer()
                            Text("$")
                                .foregroundColor(AppColors.textTertiary)
                            TextField("0.00", text: $unitCost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        // Labeled "Description" — shown on Item Detail as
                        // the "Item Description" card.
                        TextField(
                            "Description",
                            text: $notes,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }

                    if let error = errorMessage {
                        Section {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppColors.danger)
                                Text(error)
                                    .foregroundColor(AppColors.danger)
                                    .font(AppFonts.caption)
                            }
                        }
                    }
                }

                VStack(spacing: AppSpacing.sm) {
                    Button(action: submit) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(
                                        CircularProgressViewStyle(tint: .white)
                                    )
                            } else {
                                Text(isEditing ? "Save" : "Add")
                            }
                        }
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.medium)
                                .fill(isFormValid ? AppColors.primary : AppColors.border)
                        )
                    }
                    .disabled(!isFormValid || isSaving)

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(AppFonts.bodySemibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .fill(AppColors.danger)
                            )
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
                .background(AppColors.background)
            }
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadSettings()
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load categories & sizes
    // ══════════════════════════════════════════════════════

    private func loadSettings() async {
        do {
            categories = try await DatabaseService.shared.getCategories()
            sizes = try await DatabaseService.shared.getSizes()

            // Apply the saved global low-stock default — only for new
            // items, never for edits. We detect "new item with default
            // threshold still showing" by checking that we're not in
            // edit mode AND the user hasn't already changed it from
            // the hardcoded "10" we initialized to.
            if editingItem == nil && threshold == "10" {
                if let savedDefault = try? await DatabaseService.shared.getLowStockDefault() {
                    threshold = "\(savedDefault)"
                }
            }

            // If the pre-filled value isn't in the loaded lists (e.g.
            // category came from a catalog scan but admin removed it from
            // settings), keep it in the picker anyway.
            if !categories.isEmpty && !categories.contains(category) {
                categories.insert(category, at: 0)
            }
            if !sizes.isEmpty && !sizes.contains(size) {
                sizes.insert(size, at: 0)
            }
        } catch {
            print("Failed to load categories/sizes: \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Submit
    // ══════════════════════════════════════════════════════

    private func submit() {
        guard let user = authManager.currentUser else { return }

        isSaving = true
        errorMessage = nil

        let qty = Int(quantity) ?? 0
        let thresh = Int(threshold) ?? 10
        let cost = Double(unitCost) ?? 0

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHCPCS = hcpcsCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let trimmedLot = lotNumber.trimmingCharacters(in: .whitespaces)
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespaces)
        let trimmedManuf = manufacturer.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                if let existing = editingItem, let itemID = existing.id {
                    try await submitEdit(
                        existing: existing,
                        itemID: itemID,
                        user: user,
                        name: trimmedName,
                        hcpcsCode: trimmedHCPCS,
                        lotNumber: trimmedLot,
                        barcode: trimmedBarcode,
                        quantity: qty,
                        threshold: thresh,
                        manufacturer: trimmedManuf,
                        unitCost: cost
                    )
                } else {
                    try await inventoryManager.addNewItem(
                        name: trimmedName,
                        hcpcsCode: trimmedHCPCS,
                        lotNumber: trimmedLot,
                        size: size,
                        barcode: trimmedBarcode,
                        quantity: qty,
                        lowStockThreshold: thresh,
                        category: category,
                        manufacturer: trimmedManuf,
                        notes: notes,
                        unitCost: cost,
                        by: user,
                        clinicID: authManager.effectiveClinicID
                    )
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func submitEdit(
        existing: InventoryItem,
        itemID: String,
        user: AppUser,
        name: String,
        hcpcsCode: String,
        lotNumber: String,
        barcode: String,
        quantity: Int,
        threshold: Int,
        manufacturer: String,
        unitCost: Double
    ) async throws {
        var updates: [String: Any] = [:]
        var changes: [String] = []

        if name != existing.name {
            updates["name"] = name
            changes.append("name")
        }
        if hcpcsCode != existing.hcpcsCode {
            updates["hcpcsCode"] = hcpcsCode
            changes.append("HCPCS")
        }
        if lotNumber != existing.lotNumber {
            updates["lotNumber"] = lotNumber
            changes.append("lot")
        }
        if size != existing.size {
            updates["size"] = size
            changes.append("size")
        }
        if barcode != existing.barcode {
            updates["barcode"] = barcode
            changes.append("barcode")
        }
        if threshold != existing.lowStockThreshold {
            updates["lowStockThreshold"] = threshold
            changes.append("threshold")
        }
        if category != existing.category {
            updates["category"] = category
            changes.append("category")
        }
        if manufacturer != existing.manufacturer {
            updates["manufacturer"] = manufacturer
            changes.append("supplier")
        }
        if unitCost != (existing.unitCost ?? 0) {
            updates["unitCost"] = unitCost
            changes.append("cost")
        }
        if notes != existing.notes {
            updates["notes"] = notes
            changes.append("description")
        }
        if quantity != existing.quantity {
            updates["quantity"] = quantity
            changes.append("quantity \(existing.quantity)→\(quantity)")
        }

        guard !updates.isEmpty else {
            return
        }

        let description = "Edited \(existing.name): \(changes.joined(separator: ", "))"

        try await inventoryManager.updateItemInfo(
            itemID: itemID,
            updates: updates,
            changeDescription: description,
            by: user,
            clinicID: authManager.effectiveClinicID
        )
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Add Blank") {
    AddItemView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
}

#Preview("Add Prefilled (from scan)") {
    AddItemView(
        prefillName: "Knee Orthosis, elastic with joints",
        prefillHCPCS: "L1820",
        prefillBarcode: "00810041986108",
        prefillCategory: "Orthopedic",
        prefillLotNumber: "19139"
    )
    .environmentObject(AuthManager.preview())
    .environmentObject(InventoryManager())
}

#Preview("Edit") {
    AddItemView(editingItem: InventoryItem(
        id: "preview",
        name: "Tens Unit",
        hcpcsCode: "L9534",
        lotNumber: "19140",
        size: "Universal",
        barcode: "",
        quantity: 71,
        originalQuantity: 80,
        lowStockThreshold: 2,
        clinicID: "preview-clinic",
        category: "Electrical Stimulation",
        manufacturer: "Viva Health",
        unitCost: 129.99,
        lastUpdatedBy: "admin",
        lastUpdated: Date(),
        dateAdded: Date(),
        notes: "Portable TENS unit for pain relief."
    ))
    .environmentObject(AuthManager.preview())
    .environmentObject(InventoryManager())
}
