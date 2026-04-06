//
//  PermissionManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//


import Foundation

struct PermissionManager {
    
    // ── Check out items (subtract quantity) ──
    // Everyone can do this
    static func canCheckOut(role: AppUser.UserRole) -> Bool {
        return true
    }
    
    // ── Void a checkout (within 5 min window) ──
    // Everyone can void their OWN within 5 minutes
    static func canVoidOwnCheckout(role: AppUser.UserRole, checkoutTime: Date) -> Bool {
        let fiveMinutes: TimeInterval = 5 * 60
        let timeSinceCheckout = Date().timeIntervalSince(checkoutTime)
        
        // Anyone can void within 5 min window
        if timeSinceCheckout <= fiveMinutes {
            return true
        }
        
        // After 5 min, only editor and above
        return role == .admin || role == .manager || role == .editor
    }
    
    // ── Void any checkout (after window closes) ──
    // Only editor and above
    static func canVoidAnyCheckout(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager || role == .editor
    }
    
    // ── Add stock (add new items or restock) ──
    // Editor and above
    static func canAddStock(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager || role == .editor
    }
    
    // ── Remove stock (delete items from inventory) ──
    // Editor and above
    static func canRemoveStock(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager || role == .editor
    }
    
    // ── See low stock alerts ──
    // Manager and admin only
    static func canSeeAlerts(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager
    }
    
    // ── See reports / dashboard ──
    // Manager and admin only
    static func canSeeReports(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager
    }
    
    // ── Manage users (add/edit/remove users) ──
    // Admin only
    static func canManageUsers(role: AppUser.UserRole) -> Bool {
        return role == .admin
    }
    
    // ── Export CSV ──
    // Manager and admin
    static func canExportCSV(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager
    }
    
    // ── Edit item info (name, HCPCS, etc.) ──
    // Editor and above
    static func canEditItemInfo(role: AppUser.UserRole) -> Bool {
        return role == .admin || role == .manager || role == .editor
    }
    
    // ── View inventory list ──
    // Everyone
    static func canViewInventory(role: AppUser.UserRole) -> Bool {
        return true
    }
    
    // ── Scan barcodes ──
    // Everyone
    static func canScanBarcode(role: AppUser.UserRole) -> Bool {
        return true
    }
    
    // ── View history log ──
    // Everyone can see history
    static func canViewHistory(role: AppUser.UserRole) -> Bool {
        return true
    }
}
