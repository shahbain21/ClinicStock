//
//  AppTheme.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Central design system — colors, fonts, spacing, and reusable components.
//  Every view in the app should reference this file for consistency.
//  Supports both Light and Dark mode.
//

import SwiftUI

// ══════════════════════════════════════════════════════
// MARK: - Colors (Adaptive Light/Dark)
// ══════════════════════════════════════════════════════

struct AppColors {

    // ── Primary ──
    static let primary = Color.adaptive(light: "1B2A4A", dark: "E2E8F0")
    static let primaryLight = Color.adaptive(light: "2A4070", dark: "94A3B8")
    static let primaryDark = Color.adaptive(light: "111D35", dark: "F1F5F9")

    // ── Accent (stays blue in both modes) ──
    static let accent = Color.adaptive(light: "3B82F6", dark: "60A5FA")
    static let accentLight = Color.adaptive(light: "DBEAFE", dark: "1E3A5F")

    // ── Backgrounds ──
    static let background = Color.adaptive(light: "F5F6FA", dark: "0F1117")
    static let cardBackground = Color.adaptive(light: "FFFFFF", dark: "1A1D27")
    static let inputBackground = Color.adaptive(light: "F9FAFB", dark: "1E2130")

    // ── Text ──
    static let textPrimary = Color.adaptive(light: "1F2937", dark: "F1F5F9")
    static let textSecondary = Color.adaptive(light: "6B7280", dark: "94A3B8")
    static let textTertiary = Color.adaptive(light: "9CA3AF", dark: "64748B")
    static let textOnPrimary = Color.white

    // ── Status ──
    static let success = Color.adaptive(light: "22C55E", dark: "4ADE80")
    static let successLight = Color.adaptive(light: "DCFCE7", dark: "14532D")
    static let warning = Color.adaptive(light: "F59E0B", dark: "FBBF24")
    static let warningLight = Color.adaptive(light: "FEF3C7", dark: "713F12")
    static let danger = Color.adaptive(light: "EF4444", dark: "F87171")
    static let dangerLight = Color.adaptive(light: "FEE2E2", dark: "7F1D1D")

    // ── Borders ──
    static let border = Color.adaptive(light: "E5E7EB", dark: "2D3748")
    static let borderFocused = Color.adaptive(light: "3B82F6", dark: "60A5FA")

    // ── Role Colors (same in both modes) ──
    static let roleAdmin = Color(hex: "EF4444")
    static let roleManager = Color(hex: "8B5CF6")
    static let roleEditor = Color(hex: "3B82F6")
    static let roleStaff = Color(hex: "6B7280")

    // ── Tab Bar ──
    static let tabBarBackground = Color.adaptive(light: "1B2A4A", dark: "111827")
    static let tabBarActive = Color.white
    static let tabBarInactive = Color.adaptive(light: "7B8DB0", dark: "4B5563")
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

    // ── Numbers ──
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
    static let full: CGFloat = 100
}

// ══════════════════════════════════════════════════════
// MARK: - Shadows
// ══════════════════════════════════════════════════════

struct AppShadow {

    @Environment(\.colorScheme) static var colorScheme

    static var small: Shadow {
        Shadow(
            color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05),
            radius: 4,
            y: 2
        )
    }

    static var medium: Shadow {
        Shadow(
            color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08),
            radius: 8,
            y: 4
        )
    }

    static var large: Shadow {
        Shadow(
            color: .black.opacity(colorScheme == .dark ? 0.5 : 0.12),
            radius: 16,
            y: 8
        )
    }

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
// MARK: - Adaptive Color Extension
// Creates a Color that adapts to light/dark mode
// ══════════════════════════════════════════════════════

extension Color {
    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

// ══════════════════════════════════════════════════════
// MARK: - REUSABLE BUTTON STYLES
// ══════════════════════════════════════════════════════

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

// ── Underline Text Field (login screens) ──
struct UnderlineTextField: View {
    let title: String
    var placeholder: String = ""
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    @State private var isPasswordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)

            HStack {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .font(AppFonts.body)
                } else {
                    TextField(placeholder, text: $text)
                        .font(AppFonts.body)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                if isSecure {
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.system(size: 16))
                    }
                }
            }

            Divider()
                .background(AppColors.border)
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
        )
        .cardShadow()
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
        )
        .cardShadow()
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
        )
        .cardShadow()
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

struct AppBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppColors.background.ignoresSafeArea())
    }
}

struct CardShadowModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .shadow(
                color: colorScheme == .dark
                    ? .black.opacity(0.3)
                    : .black.opacity(0.05),
                radius: 4,
                y: 2
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
// MARK: - PREVIEWS
// ══════════════════════════════════════════════════════

#Preview("Light Mode") {
    ScrollView {
        VStack(spacing: 20) {
            AppSearchBar(text: .constant(""))
            StatCard(title: "Total Items", value: "1,346")
            LowStockBanner(count: 5)
            StatusBadge(text: "Item Found", color: AppColors.success, icon: "checkmark.circle.fill")
            HStack {
                RoleBadge(role: .admin)
                RoleBadge(role: .manager)
                RoleBadge(role: .editor)
                RoleBadge(role: .staff)
            }
        }
        .padding()
    }
    .appBackground()
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ScrollView {
        VStack(spacing: 20) {
            AppSearchBar(text: .constant(""))
            StatCard(title: "Total Items", value: "1,346")
            LowStockBanner(count: 5)
            StatusBadge(text: "Item Found", color: AppColors.success, icon: "checkmark.circle.fill")
            HStack {
                RoleBadge(role: .admin)
                RoleBadge(role: .manager)
                RoleBadge(role: .editor)
                RoleBadge(role: .staff)
            }
        }
        .padding()
    }
    .appBackground()
    .preferredColorScheme(.dark)
}
