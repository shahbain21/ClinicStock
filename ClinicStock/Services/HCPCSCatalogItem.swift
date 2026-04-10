//
//  HCPCSCatalogItem.swift
//  ClinicStock
//
//  Created by Mohamed Kaid

import Foundation
import FirebaseFirestore

struct HCPCSCatalogItem: Codable, Identifiable, Hashable {

    @DocumentID var id: String?

    var hcpcsCode: String
    var clinicalName: String
    var commonNames: [String]
    var category: String
    var gtins: [String]?
    var isActive: Bool
    var sourceYear: Int
    var lastUpdated: Timestamp

    // ── Hashable ──
    func hash(into hasher: inout Hasher) {
        hasher.combine(hcpcsCode)
    }

    static func == (lhs: HCPCSCatalogItem, rhs: HCPCSCatalogItem) -> Bool {
        lhs.hcpcsCode == rhs.hcpcsCode
    }

    // ── Display name ──
    // Shows the first commonName in title case as the friendly name
    var displayName: String {
        guard let first = commonNames.first else { return clinicalName }
        return first.capitalized
    }

    // ── Short clinical description ──
    // Truncates the long CMS clinical name for display
    var shortClinicalName: String {
        let maxLength = 60
        if clinicalName.count <= maxLength { return clinicalName }
        return String(clinicalName.prefix(maxLength)) + "..."
    }
}
