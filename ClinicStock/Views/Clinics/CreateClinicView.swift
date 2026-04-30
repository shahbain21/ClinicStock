//
//  CreateClinicView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/27/26.
//


//
//  CreateClinicView.swift
//  ClinicStock
//
//  Form for platform admin to create a new clinic location. Reachable
//  from Settings → Admin Tools → "Create New Clinic" (admin only).
//
//  Flow:
//   1. Admin fills out clinic name, address, contact info
//   2. Tap Create → AuthManager.createClinic writes the doc
//   3. Confirmation dialog asks "Switch to it now?"
//      - Switch: selectClinic(newClinicID), sheet dismisses, app
//        re-routes to MainTabView in the new clinic context
//      - Stay Here: sheet dismisses, admin is back where they were
//
//  Only the clinic name is required. Address fields can be filled in
//  later (admin → Settings → Switch Clinic → ... → Edit clinic, when
//  that flow exists).
//

import SwiftUI

struct CreateClinicView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var phone = ""
    @State private var email = ""

    @State private var isCreating = false
    @State private var errorMessage: String?

    // Post-creation state. When non-nil, the confirmation dialog
    // appears with "Switch to it now?".
    @State private var newlyCreatedClinicID: String?
    @State private var newlyCreatedClinicName: String = ""

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("Clinic Info") {
                        TextField("Clinic name *", text: $name)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                    }

                    Section("Address") {
                        TextField("Street address", text: $address)
                            .textInputAutocapitalization(.words)
                        TextField("City", text: $city)
                            .textInputAutocapitalization(.words)
                        HStack {
                            TextField("State", text: $state)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .frame(maxWidth: 80)
                            TextField("ZIP", text: $zip)
                                .keyboardType(.numberPad)
                        }
                    }

                    Section("Contact") {
                        TextField("Phone", text: $phone)
                            .keyboardType(.phonePad)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    if let error = errorMessage {
                        Section {
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppColors.danger)
                                Text(error)
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.danger)
                            }
                        }
                    }

                    Section {
                        Text("After creating, you can switch into this clinic to set up users, inventory, and more.")
                            .font(AppFonts.footnote)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                VStack(spacing: AppSpacing.sm) {
                    Button(action: submit) {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(
                                        CircularProgressViewStyle(tint: .white)
                                    )
                            } else {
                                Text("Create Clinic")
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
                    .disabled(!isFormValid || isCreating)

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(AppFonts.bodySemibold)
                            .foregroundColor(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }
                    .disabled(isCreating)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.lg)
                .background(AppColors.background)
            }
            .navigationTitle("New Clinic")
            .navigationBarTitleDisplayMode(.large)
            .alert(
                "Clinic Created",
                isPresented: Binding(
                    get: { newlyCreatedClinicID != nil },
                    set: { if !$0 { newlyCreatedClinicID = nil } }
                )
            ) {
                Button("Switch to It") {
                    Task {
                        if let id = newlyCreatedClinicID {
                            await authManager.selectClinic(id)
                        }
                        dismiss()
                    }
                }
                Button("Stay Here", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("\(newlyCreatedClinicName) is ready. Would you like to switch into it now to set up users and inventory?")
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Submit
    // ══════════════════════════════════════════════════════

    private func submit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let newID = try await authManager.createClinic(
                    name: trimmedName,
                    address: address,
                    city: city,
                    state: state,
                    zip: zip,
                    phone: phone,
                    email: email
                )
                newlyCreatedClinicName = trimmedName
                newlyCreatedClinicID = newID  // triggers alert
                isCreating = false
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    CreateClinicView()
        .environmentObject(AuthManager.preview())
}