//
//  Clinic.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import Foundation
//import FirebaseFirestore

struct Clinic: Codable /*, Identifiable*/ {
//    @DocumentID var id: String?
    var name: String
    var address: String
    var city: String
    var state: String
    var zip: String
    var phone: String
    var email: String
    var managerID: String
    var isActive: Bool
    var dateCreated: Date
    
    var fullAddress: String {
        "\(address), \(city), \(state) \(zip)"
    }
}
