//
//  AppTheme.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/13/26.
//

//  Central design system — colors, fonts, spacing, and reusable components.
//  Every view in the app should reference this file for consistency.
//

import SwiftUI

// ══════════════════════════════════════════════════════
// MARK: - Colors
// ══════════════════════════════════════════════════════

struct AppColors {

    // ── Primary ──
    static let primary = Color(hex: "1B2A4A")         // Dark navy — buttons, tab bar, headers
    static let primaryLight = Color(hex: "2A4070")     // Lighter navy — hover states, accents
    static let primaryDark = Color(hex: "111D35")      // Deeper navy — pressed states

    // ── Accent ──
    static let accent = Color(hex: "3B82F6")           // Blue — links, secondary actions
    static let accentLight = Color(hex: "DBEAFE")      // Light blue — selected backgrounds

    // ── Backgrounds ──
    static let background = Color(hex: "F5F6FA")       // Light gray — main app background
    static let cardBackground = Color.white            // Cards, sheets
    static let inputBackground = Color(hex: "F9FAFB")  // Text field fill

    // ── Text ──
    static let textPrimary = Color(hex: "1F2937")      // Near black — headings, body
    static let textSecondary = Color(hex: "6B7280")    // Gray — subtitles, placeholders
    static let textTertiary = Color(hex: "9CA3AF")     // Light gray — hints, timestamps
    static let textOnPrimary = Color.white             // Text on dark backgrounds

    // ── Status ──
    static let success = Color(hex: "22C55E")          // Green — item found, in stock
    static let successLight = Color(hex: "DCFCE7")     // Light green background
    static let warning = Color(hex: "F59E0B")          // Amber — low stock warning
    static let warningLight = Color(hex: "FEF3C7")     // Light amber background
    static let danger = Color(hex: "EF4444")           // Red — out of stock, alerts, delete
    static let dangerLight = Color(hex: "FEE2E2")      // Light red background

    // ── Borders ──
    static let border = Color(hex: "E5E7EB")          // Input borders, dividers
    static let borderFocused = Color(hex: "3B82F6")    // Focused input border

    // ── Role Colors ──
    static let roleAdmin = Color(hex: "EF4444")        // Red
    static let roleManager = Color(hex: "8B5CF6")      // Purple
    static let roleEditor = Color(hex: "3B82F6")       // Blue
    static let roleStaff = Color(hex: "6B7280")        // Gray

    // ── Tab Bar ──
    static let tabBarBackground = Color(hex: "1B2A4A") // Dark navy
    static let tabBarActive = Color.white              // Active tab icon
    static let tabBarInactive = Color(hex: "7B8DB0")   // Inactive tab icon
}

// ══════════════════════════════════════════════════════
// MARK: - Typography
// ══════════════════════════════════════════════════════

struct AppFonts {

    // ── Large Titles ──
    static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let title3 = Font.system(size: 18, weight: .semibold, design: .rounded)

    // ── Body ──
    static let body = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 16, weight: .medium)
    static let bodySemibold = Font.system(size: 16, weight: .semibold)

    // ── Small ──
    static let caption = Font.system(size: 14, weight: .regular)
    static let captionMedium = Font.system(size: 14, weight: .medium)
    static let captionSemibold = Font.system(size: 14, weight: .semibold)

    // ── Extra Small ──
    static let footnote = Font.system(size: 12, weight: .regular)
    static let footnoteMedium = Font.system(size: 12, weight: .medium)

    // ── Numbers (for quantities) ──
    static let quantityLarge = Font.system(size: 32, weight: .bold, design: .rounded)
    static let quantityMedium = Font.system(size: 22, weight: .bold, design: .rounded)
    static let quantitySmall = Font.system(size: 18, weight: .bold, design: .rounded)
}

// ══════════════════════════════════════════════════════
// MARK: - Spacing
// ══════════════════════════════════════════════════════

struct AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
}

// ══════════════════════════════════════════════════════
// MARK: - Corner Radius
// ══════════════════════════════════════════════════════

struct AppRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
    static let full: CGFloat = 100     // Pill shape
}

// ══════════════════════════════════════════════════════
// MARK: - Shadows
// ══════════════════════════════════════════════════════

struct AppShadow {
    static let small = Shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    static let medium = Shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    static let large = Shadow(color: .black.opacity(0.12), radius: 16, y: 8)

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Hex Color Extension
// ══════════════════════════════════════════════════════

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// ══════════════════════════════════════════════════════
// MARK: - REUSABLE BUTTON STYLES
// ══════════════════════════════════════════════════════

// ── Primary Button — dark navy, full width ──
struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.bodySemibold)
            .foregroundColor(AppColors.textOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(isDisabled ? AppColors.primaryLight.opacity(0.5) : AppColors.primary)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// ── Secondary Button — outlined ──
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.bodySemibold)
            .foregroundColor(AppColors.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColors.primary, lineWidth: 1.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// ── Danger Button — red, for delete/cancel ──
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.bodySemibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.danger)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// ── Small Pill Button — for inline actions ──
struct PillButtonStyle: ButtonStyle {
    var color: Color = AppColors.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.captionSemibold)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                Capsule().fill(color)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - REUSABLE VIEW COMPONENTS
// ══════════════════════════════════════════════════════

// ── Styled Text Field ──
struct AppTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFonts.captionMedium)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: AppSpacing.md) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundColor(AppColors.textTertiary)
                        .frame(width: 20)
                }

                if isSecure {
                    SecureField(placeholder, text: $text)
                        .font(AppFonts.body)
                } else {
                    TextField(placeholder, text: $text)
                        .font(AppFonts.body)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColors.border, lineWidth: 1)
            )
        }
    }
}

// ── Card Container ──
struct AppCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.lg
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(AppColors.cardBackground)
                .shadow(
                    color: AppShadow.small.color,
                    radius: AppShadow.small.radius,
                    y: AppShadow.small.y
                )
        )
    }
}

// ── Section Header ──
struct AppSectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            if let action = action, let onAction = onAction {
                Button(action: onAction) {
                    Text(action)
                        .font(AppFonts.captionSemibold)
                        .foregroundColor(AppColors.accent)
                }
            }
        }
    }
}

// ── Status Badge / Pill ──
struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(AppFonts.footnoteMedium)
        }
        .foregroundColor(color)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(
            Capsule().fill(color.opacity(0.12))
        )
    }
}

// ── Role Badge ──
struct RoleBadge: View {
    let role: AppUser.UserRole

    var color: Color {
        switch role {
        case .admin: return AppColors.roleAdmin
        case .manager: return AppColors.roleManager
        case .editor: return AppColors.roleEditor
        case .staff: return AppColors.roleStaff
        }
    }

    var body: some View {
        StatusBadge(text: role.displayName, color: color)
    }
}

// ── Stock Quantity Badge ──
struct StockBadge: View {
    let quantity: Int
    let threshold: Int

    var color: Color {
        if quantity <= 0 { return AppColors.danger }
        if quantity <= threshold { return AppColors.warning }
        return AppColors.success
    }

    var body: some View {
        Text("\(quantity)")
            .font(AppFonts.quantitySmall)
            .foregroundColor(color)
            .frame(minWidth: 40)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .fill(color.opacity(0.12))
            )
    }
}

// ── Low Stock Alert Banner ──
struct LowStockBanner: View {
    let count: Int
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.danger)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Low Stock Alerts")
                        .font(AppFonts.captionSemibold)
                        .foregroundColor(AppColors.danger)
                    Text("\(count) item\(count == 1 ? "" : "s") below threshold")
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Text("\(count)")
                    .font(AppFonts.quantitySmall)
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(AppColors.danger))
            }
            .padding(AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.dangerLight)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .stroke(AppColors.danger.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// ── User Avatar ──
struct UserAvatar: View {
    let name: String
    let role: AppUser.UserRole
    var size: CGFloat = 40

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var color: Color {
        switch role {
        case .admin: return AppColors.roleAdmin
        case .manager: return AppColors.roleManager
        case .editor: return AppColors.roleEditor
        case .staff: return AppColors.roleStaff
        }
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
    }
}

// ── Search Bar ──
struct AppSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)

            TextField(placeholder, text: $text)
                .font(AppFonts.body)
                .autocapitalization(.none)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

// ── Inventory Row ──
struct InventoryRowView: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.name)
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)

                Text("\(item.hcpcsCode) • \(item.size)")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            StockBadge(
                quantity: item.quantity,
                threshold: item.lowStockThreshold
            )
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
                .shadow(
                    color: AppShadow.small.color,
                    radius: AppShadow.small.radius,
                    y: AppShadow.small.y
                )
        )
    }
}

// ── Dashboard Stat Card ──
struct StatCard: View {
    let title: String
    let value: String
    var color: Color = AppColors.primary

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Text(value)
                .font(AppFonts.quantityMedium)
                .foregroundColor(color)

            Text(title)
                .font(AppFonts.footnote)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
                .shadow(
                    color: AppShadow.small.color,
                    radius: AppShadow.small.radius,
                    y: AppShadow.small.y
                )
        )
    }
}

// ── Empty State ──
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text(title)
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            Text(message)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            if let buttonTitle = buttonTitle, let onAction = onAction {
                Button(action: onAction) {
                    Text(buttonTitle)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.huge)
            }
        }
        .padding(AppSpacing.xxxl)
    }
}

// ── Loading Overlay ──
struct LoadingOverlay: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primary))
                .scaleEffect(1.2)

            Text(message)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.opacity(0.8))
    }
}

// ══════════════════════════════════════════════════════
// MARK: - VIEW MODIFIERS
// ══════════════════════════════════════════════════════

// ── Standard screen background ──
struct AppBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.background.ignoresSafeArea())
    }
}

// ── Card shadow ──
struct CardShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(
                color: AppShadow.small.color,
                radius: AppShadow.small.radius,
                y: AppShadow.small.y
            )
    }
}

extension View {
    func appBackground() -> some View {
        modifier(AppBackgroundModifier())
    }

    func cardShadow() -> some View {
        modifier(CardShadowModifier())
    }
}

// ══════════════════════════════════════════════════════
// MARK: - PREVIEW HELPERS
// ══════════════════════════════════════════════════════

#Preview("Buttons") {
    VStack(spacing: 16) {
        Button("Sign In") {}
            .buttonStyle(PrimaryButtonStyle())

        Button("Register") {}
            .buttonStyle(SecondaryButtonStyle())

        Button("Delete Item") {}
            .buttonStyle(DangerButtonStyle())

        Button("Add Stock") {}
            .buttonStyle(PillButtonStyle())

        Button("Low Stock") {}
            .buttonStyle(PillButtonStyle(color: AppColors.danger))
    }
    .padding()
}

#Preview("Components") {
    ScrollView {
        VStack(spacing: 20) {
            AppSearchBar(text: .constant(""))

            StatCard(title: "Total Items", value: "1,346")

            LowStockBanner(count: 5)

            StatusBadge(text: "Item Found", color: AppColors.success, icon: "checkmark.circle.fill")

            RoleBadge(role: .admin)
            RoleBadge(role: .manager)
            RoleBadge(role: .editor)
            RoleBadge(role: .staff)

            HStack {
                UserAvatar(name: "John Doe", role: .admin)
                UserAvatar(name: "Sarah Smith", role: .manager)
                UserAvatar(name: "Mike Lee", role: .editor)
                UserAvatar(name: "Anna Bell", role: .staff)
            }

            EmptyStateView(
                icon: "shippingbox",
                title: "No Items",
                message: "Start by adding inventory items",
                buttonTitle: "Add Item",
                onAction: {}
            )
        }
        .padding()
    }
    .appBackground()
}
