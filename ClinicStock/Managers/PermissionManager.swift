//
//  PermissionManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//

import Foundation

// ══════════════════════════════════════════════════════
// MARK: - Role hierarchy
//
// Higher level = more privileges. Add a new role by inserting it in
// the switch; the compiler's exhaustiveness check will flag every
// place that needs updating.
// ══════════════════════════════════════════════════════

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

    /// True if this role has at least the privileges of `minimum`.
    func hasPrivileges(atLeast minimum: AppUser.UserRole) -> Bool {
        return self.level >= minimum.level
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Permission gates
// ══════════════════════════════════════════════════════

struct PermissionManager {

    /// How long after a checkout any staff member can still void it.
    /// Exposed so views can reference it in UI messaging.
    static let voidWindow: TimeInterval = 5 * 60

    /// Human-readable rendering of the window, e.g. "5-minute".
    static var voidWindowDescription: String {
        let minutes = Int(voidWindow / 60)
        return "\(minutes)-minute"
    }

    // ── Check out items (subtract quantity) ──
    // Everyone can do this.
    static func canCheckOut(role: AppUser.UserRole) -> Bool {
        return true
    }

    // ── Void a recent checkout (within the void window) ──
    //
    // Within the window: anyone can void the checkout.
    // After the window: editor and above only.
    //
    // `now:` is injectable for testing — production calls get wall-clock time.
    // Note: this does NOT check that the voider was the original checkouter.
    // If we add that requirement, take a `checkedOutByUserID:` parameter
    // and a `currentUserID:` to compare.
    //
    static func canVoidRecentCheckout(
        role: AppUser.UserRole,
        checkoutTime: Date,
        now: Date = Date()
    ) -> Bool {
        let elapsed = now.timeIntervalSince(checkoutTime)

        if elapsed <= voidWindow {
            return true
        }

        return role.hasPrivileges(atLeast: .editor)
    }

    // ── Void any checkout (ignoring the window) ──
    // Editor and above.
    static func canVoidAnyCheckout(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .editor)
    }

    // ── Add stock (add new items or restock) ──
    // Editor and above.
    static func canAddStock(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .editor)
    }

    // ── Remove stock (delete items from inventory) ──
    // Editor and above.
    static func canRemoveStock(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .editor)
    }

    // ── See low-stock alerts ──
    // Everyone — low stock is operational info staff need on the floor.
    static func canSeeAlerts(role: AppUser.UserRole) -> Bool {
        return true
    }

    // ── Configure / dismiss alerts ──
    // Manager and admin.
    static func canConfigureAlerts(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .manager)
    }

    // ── See reports / dashboard analytics ──
    // Manager and admin.
    static func canSeeReports(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .manager)
    }

    // ── Manage users (invite, change role, deactivate) ──
    // Admin only.
    static func canManageUsers(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .admin)
    }

    // ── Export CSV ──
    // Manager and admin.
    static func canExportCSV(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .manager)
    }

    // ── Edit item info (name, HCPCS, threshold, etc.) ──
    // Editor and above.
    static func canEditItemInfo(role: AppUser.UserRole) -> Bool {
        return role.hasPrivileges(atLeast: .editor)
    }

    // ══════════════════════════════════════════════════════
    // Universal-access gates
    //
    // These currently return true for everyone. Kept as explicit functions
    // (rather than being removed) so that if a future role needs to be
    // restricted — a visitor/auditor role, for example — the change is
    // localized to this file instead of scattered through call sites.
    // ══════════════════════════════════════════════════════

    // ── View inventory list ──
    static func canViewInventory(role: AppUser.UserRole) -> Bool {
        return true
    }

    // ── Scan barcodes ──
    static func canScanBarcode(role: AppUser.UserRole) -> Bool {
        return true
    }

    // ── View history log ──
    static func canViewHistory(role: AppUser.UserRole) -> Bool {
        return true
    }
}
