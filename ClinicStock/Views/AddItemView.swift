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
//  Categories and sizes are loaded from global settings docs (populated
//  by DatabaseSeeder). If those aren't available, falls back to free
//  text so the form still works.
//

import SwiftUI

struct AddItemView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @Environment(\.dismiss) private var dismiss

    // Edit mode: if non-nil, submit updates this item instead of
    // creating a new one.
    let editingItem: InventoryItem?

    init(editingItem: InventoryItem? = nil) {
        self.editingItem = editingItem

        _name = State(initialValue: editingItem?.name ?? "")
        _hcpcsCode = State(initialValue: editingItem?.hcpcsCode ?? "")
        _lotNumber = State(initialValue: editingItem?.lotNumber ?? "")
        _size = State(initialValue: editingItem?.size ?? "Universal")
        _barcode = State(initialValue: editingItem?.barcode ?? "")
        _quantity = State(initialValue: "\(editingItem?.quantity ?? 0)")
        _threshold = State(initialValue: "\(editingItem?.lowStockThreshold ?? 10)")
        _category = State(initialValue: editingItem?.category ?? "General Medical")
        _manufacturer = State(initialValue: editingItem?.manufacturer ?? "")
        _unitCost = State(
            initialValue: editingItem.flatMap {
                $0.unitCost.map { String(format: "%.2f", $0) }
            } ?? ""
        )
        _notes = State(initialValue: editingItem?.notes ?? "")
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
                    TextField("Manufacturer", text: $manufacturer)
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
                    TextField("Notes", text: $notes, axis: .vertical)
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
            .navigationTitle(isEditing ? "Edit Item" : "Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isEditing ? "Save" : "Add") {
                            submit()
                        }
                        .disabled(!isFormValid)
                    }
                }
            }
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

            // If the current value isn't in the loaded list (e.g. editing
            // an item whose category was later removed), keep it in the
            // picker so the value doesn't appear blank.
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
                        by: user
                    )
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    // Edit path. Builds the updates dict and a human-readable description
    // of what changed (for the audit log).
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
            changes.append("manufacturer")
        }
        if unitCost != (existing.unitCost ?? 0) {
            updates["unitCost"] = unitCost
            changes.append("cost")
        }
        if notes != existing.notes {
            updates["notes"] = notes
            changes.append("notes")
        }

        // Quantity changes via the edit form are treated as info updates
        // for audit purposes. Larger quantity changes should use
        // addStock / checkOut flows instead.
        if quantity != existing.quantity {
            updates["quantity"] = quantity
            changes.append("quantity \(existing.quantity)→\(quantity)")
        }

        guard !updates.isEmpty else {
            // Nothing changed — just dismiss
            return
        }

        let description = "Edited \(existing.name): \(changes.joined(separator: ", "))"

        try await inventoryManager.updateItemInfo(
            itemID: itemID,
            updates: updates,
            changeDescription: description,
            by: user
        )
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Add") {
    AddItemView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
}

#Preview("Edit") {
    AddItemView(editingItem: InventoryItem(
        id: "preview",
        name: "Knee Brace",
        hcpcsCode: "L1820",
        lotNumber: "A12345",
        size: "L",
        barcode: "",
        quantity: 8,
        originalQuantity: 20,
        lowStockThreshold: 10,
        clinicID: "preview-clinic",
        category: "Orthopedic",
        manufacturer: "Breg",
        unitCost: 45.00,
        lastUpdatedBy: "admin",
        lastUpdated: Date(),
        dateAdded: Date(),
        notes: ""
    ))
    .environmentObject(AuthManager.preview())
    .environmentObject(InventoryManager())
}
