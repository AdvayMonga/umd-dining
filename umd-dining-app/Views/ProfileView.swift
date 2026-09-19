import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @Binding var tabResetID: UUID
    @State private var preferences = UserPreferences.shared
    @Environment(FavoritesManager.self) private var favorites
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var isUpgrading = false
    @State private var upgradeError: String?
    @State private var showSignOutAlert = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // Account card
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.umdRed.opacity(0.12))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "person.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.umdRed)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(accountName)
                                    .font(.inter(size: 18, weight: .bold))
                                    .foregroundStyle(.primary)
                                Text(AuthManager.shared.isGuest ? "Not signed in" : "Signed in with Apple")
                                    .font(.inter(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        if AuthManager.shared.isGuest {
                            SignInWithAppleButton(.signIn) { request in
                                request.requestedScopes = [.fullName]
                            } onCompletion: { result in
                                switch result {
                                case .success(let authorization):
                                    if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                        isUpgrading = true
                                        Task {
                                            await AuthManager.shared.upgradeToApple(credential: credential)
                                            isUpgrading = false
                                        }
                                    }
                                case .failure(let error):
                                    upgradeError = "Sign in failed. Please try again."
                                    print("Upgrade failed: \(error.localizedDescription)")
                                }
                            }
                            .signInWithAppleButtonStyle(isDarkMode ? .white : .black)
                            .frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled(isUpgrading)
                        } else {
                            Button { showSignOutAlert = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Sign Out")
                                        .font(.inter(size: 15, weight: .semibold))
                                }
                                .foregroundStyle(Color.umdRed)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.umdRed.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .homeCard()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                    // PREFERENCES section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Preferences")

                        // Cuisine Preferences
                        NavigationLink {
                            PalateSurveyView(onComplete: {}, isOnboarding: false)
                        } label: {
                            navItemRow(icon: "fork.knife", title: "Cuisine Preferences")
                        }
                        .buttonStyle(.plain)

                        // Allergens & Dietary Needs
                        NavigationLink {
                            DietaryPrefsView(preferences: preferences)
                        } label: {
                            navItemRow(icon: "exclamationmark.triangle", title: "Allergens & Dietary Needs")
                        }
                        .buttonStyle(.plain)

                        // Manage Favorites
                        NavigationLink {
                            FavoritesView()
                        } label: {
                            navItemRow(icon: "heart", title: "Manage Favorites")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 24)

                    // APP SETTINGS section
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "App Settings")

                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("Dark Mode")
                                    .font(.inter(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(isDarkMode ? "On" : "Off")
                                    .font(.inter(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            isDarkMode.toggle()
                        }

                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("Privacy Policy")
                                    .font(.inter(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(.systemGray2))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            if let url = URL(string: "https://api.umddining.com/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }

                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: "message")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("App Feedback")
                                    .font(.inter(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            if let url = URL(string: "https://forms.gle/53RrYDkmZjmf72Py9") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 24)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(build))")
                            .font(.inter(size: 12))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer().frame(height: 24)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .background(Color.umdBackground)
            .overlay {
                if isUpgrading {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
            .overlay { if showSignOutAlert { signOutOverlay } }
            .overlay { if showDeleteAlert { deleteAccountOverlay } }
            .alert("Error", isPresented: Binding(
                get: { upgradeError != nil },
                set: { if !$0 { upgradeError = nil } }
            )) {
                Button("OK") { upgradeError = nil }
            } message: {
                Text(upgradeError ?? "")
            }
        }
        .id(tabResetID)
    }

    private var accountName: String {
        if AuthManager.shared.isGuest { return "Guest" }
        guard let name = AuthManager.shared.displayName, !name.isEmpty else { return "Your Account" }
        return name
    }

    // MARK: - Item Card

    private func itemCard<Content: View>(
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .homeCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nav Item Row

    private func navItemRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color.umdRed)
                .frame(width: 24)
            Text(title)
                .font(.inter(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.systemGray3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .homeCard()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Profile")
                .font(.inter(size: 22, weight: .bold))
                .foregroundStyle(Color.umdRed)
            Spacer()
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.umdBackground.ignoresSafeArea(edges: .top))
    }

    // MARK: - Sign Out Overlay

    private var signOutOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showSignOutAlert = false }
            VStack(spacing: 16) {
                Text("Sign Out?")
                    .font(.inter(size: 18, weight: .bold))
                Text(AuthManager.shared.isGuest
                     ? "Your favorites and preferences will be lost."
                     : "Your data will be saved to your account. Sign back in anytime to restore it.")
                    .font(.inter(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button { showSignOutAlert = false } label: {
                        Text("Cancel")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    Button {
                        showSignOutAlert = false
                        AuthManager.shared.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(.inter(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.umdRed)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
            .padding(.horizontal, 30)
        }
    }

    // MARK: - Delete Account Overlay

    private var deleteAccountOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showDeleteAlert = false }
            VStack(spacing: 16) {
                Text("Delete Account?")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("This will permanently delete your account and all your data. This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showDeleteAlert = false
                    isDeleting = true
                    Task {
                        do { try await DiningAPIService.shared.deleteAccount() }
                        catch { print("Delete account API error: \(error)") }
                        FavoritesManager.shared.clearAll()
                        UserPreferences.shared.clearAll()
                        AuthManager.shared.signOut()
                        UserDefaults.standard.set(false, forKey: "hasCompletedPalateSurvey")
                        isDeleting = false
                    }
                } label: {
                    Text("Delete Account")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button { showDeleteAlert = false } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Dietary Prefs View

struct DietaryPrefsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: UserPreferences

    private let allergenOptions: [(label: String, key: String)] = [
        ("Dairy",     "Contains dairy"),
        ("Egg",       "Contains egg"),
        ("Fish",      "Contains fish"),
        ("Gluten",    "Contains gluten"),
        ("Nuts",      "Contains nuts"),
        ("Shellfish", "Contains Shellfish"),
        ("Sesame",    "Contains sesame"),
        ("Soy",       "Contains soy"),
    ]

    var body: some View {
        ScrollView {
                VStack(spacing: 24) {
                    filterSection(title: "Dietary Preferences", icon: "leaf.fill", iconColor: Color.umdRed) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            dietaryPill("Vegetarian",     isOn: $preferences.vegetarian)
                            dietaryPill("Vegan",          isOn: $preferences.vegan)
                            dietaryPill("Halal Friendly", isOn: $preferences.halal)
                            dietaryPill("Gluten Free",    isOn: $preferences.glutenFree)
                            dietaryPill("Dairy Free",     isOn: $preferences.dairyFree)
                        }
                    }

                    Divider()

                    filterSection(
                        title: "Allergens to Avoid",
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(red: 180/255, green: 83/255, blue: 9/255),
                        subtitle: "Items containing these ingredients will be hidden from your menu."
                    ) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(allergenOptions, id: \.key) { option in
                                allergenPill(option.label, key: option.key)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color(.systemGray3))
                            .font(.system(size: 18))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dining Safety")
                                .font(.inter(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Maryland Dining does not guarantee allergen-free preparation. Cross-contamination may occur. Consult dining staff if you have a severe allergy.")
                                .font(.inter(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.umdBorder, lineWidth: 1))

                    Button { dismiss() } label: {
                        Text("Save & Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.umdRed)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.umdRed)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                Spacer()
                Text("Allergens & Dietary Needs")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
                    .padding(.trailing, 8)
            }
            .frame(height: 44)
            .background(Color(.systemBackground))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func filterSection<Content: View>(
        title: String, icon: String, iconColor: Color,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.inter(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.top, -6)
            }
            content()
        }
    }

    private func dietaryPill(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Color.umdRed : .primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.umdRed)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isOn.wrappedValue ? Color.umdRed.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isOn.wrappedValue ? Color.umdRed : Color.umdBorder,
                        lineWidth: isOn.wrappedValue ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
    }

    private func allergenPill(_ label: String, key: String) -> some View {
        let isOn = preferences.allergens.contains(key)
        let color = Color(red: 180/255, green: 83/255, blue: 9/255)
        return Button {
            if isOn { preferences.allergens.remove(key) }
            else { preferences.allergens.insert(key) }
        } label: {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(isOn ? color : .primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isOn ? color.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isOn ? color : Color.umdBorder, lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

#Preview {
    ProfileView(tabResetID: .constant(UUID()))
        .environment(FavoritesManager.shared)
}
