//
//  PermissionManager.swift
//  ClinicStock
//

import Foundation

// MARK: - Role Hierarchy

extension AppUser.UserRole {

    /// Numeric privilege level. Higher = more access.
    var level: Int {
        switch self {
        case .staff:   return 1
        case .editor:  return 2
        case .manager: return 3
        case .admin:   return 4
        }
    }

    func hasPrivileges(atLeast minimum: AppUser.UserRole) -> Bool {
        self.level >= minimum.level
    }
}

// MARK: - Permission Gates

struct PermissionManager {

    /// How long after a checkout any user can void it (5 minutes).
    static let voidWindow: TimeInterval = 5 * 60

    static var voidWindowDescription: String {
        "\(Int(voidWindow / 60))-minute"
    }

    // Checkout — everyone
    static func canCheckOut(role: AppUser.UserRole) -> Bool { true }

    // Void within the time window — anyone; after the window — editor+
    static func canVoidRecentCheckout(role: AppUser.UserRole, checkoutTime: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(checkoutTime) <= voidWindow || role.hasPrivileges(atLeast: .editor)
    }

    // Editor and above
    static func canVoidAnyCheckout(role: AppUser.UserRole) -> Bool  { role.hasPrivileges(atLeast: .editor) }
    static func canAddStock(role: AppUser.UserRole) -> Bool          { role.hasPrivileges(atLeast: .editor) }
    static func canRemoveStock(role: AppUser.UserRole) -> Bool       { role.hasPrivileges(atLeast: .editor) }
    static func canEditItemInfo(role: AppUser.UserRole) -> Bool      { role.hasPrivileges(atLeast: .editor) }

    // Manager and above
    static func canConfigureAlerts(role: AppUser.UserRole) -> Bool   { role.hasPrivileges(atLeast: .manager) }
    static func canSeeReports(role: AppUser.UserRole) -> Bool        { role.hasPrivileges(atLeast: .manager) }
    static func canExportCSV(role: AppUser.UserRole) -> Bool         { role.hasPrivileges(atLeast: .manager) }

    // Admin only
    static func canManageUsers(role: AppUser.UserRole) -> Bool       { role.hasPrivileges(atLeast: .admin) }

    // Everyone
    static func canSeeAlerts(role: AppUser.UserRole) -> Bool         { true }
    static func canViewInventory(role: AppUser.UserRole) -> Bool     { true }
    static func canScanBarcode(role: AppUser.UserRole) -> Bool       { true }
    static func canViewHistory(role: AppUser.UserRole) -> Bool       { true }
}
