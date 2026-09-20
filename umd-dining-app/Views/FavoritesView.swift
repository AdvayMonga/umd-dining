import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesManager.self) private var favorites
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var availability: [String: AvailabilityInfo] = [:]
    @State private var lastFetchedRecNums: Set<String> = []

    private var filteredFoods: [(recNum: String, name: String)] {
        let sorted = favorites.sortedFoods
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredStations: [String] {
        let sorted = favorites.sortedStations
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if favorites.favoriteFoods.isEmpty && favorites.favoriteStations.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "heart",
                    description: Text("Foods and stations you favorite will appear here.")
                )
            } else if filteredFoods.isEmpty && filteredStations.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No favorites matching \"\(searchText)\"")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !filteredFoods.isEmpty {
                            SectionHeader(title: "Foods")
                            ForEach(filteredFoods, id: \.recNum) { recNum, name in
                                NavigationLink(destination: NutritionDetailView(recNum: recNum, foodName: name, source: "favorites")) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(name)
                                                .font(.inter(size: 16, weight: .bold))
                                                .foregroundStyle(.primary)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if let info = availability[recNum] {
                                                AvailabilityLabel(availability: info)
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        unfavoriteButton { favorites.toggleFood(recNum: recNum, name: name) }
                                    }
                                    .padding(16)
                                    .homeCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !filteredStations.isEmpty {
                            SectionHeader(title: "Stations")
                                .padding(.top, filteredFoods.isEmpty ? 0 : 8)
                            ForEach(filteredStations, id: \.self) { station in
                                HStack(spacing: 12) {
                                    Text(station)
                                        .font(.inter(size: 16, weight: .bold))
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    unfavoriteButton { favorites.toggleStation(name: station) }
                                }
                                .padding(16)
                                .homeCard()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color.umdBackground)
        .navigationTitle("Favorites")
        .searchable(text: $searchText, prompt: "Search favorites")
        // Favorites save on tap; this matches the other preference pages
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.umdBackground)
        }
        .task(id: favorites.sortedFoods.map { $0.recNum }) {
            await loadAvailability()
        }
    }

    private func loadAvailability() async {
        let recNums = Set(favorites.sortedFoods.map { $0.recNum })
        guard !recNums.isEmpty else {
            availability = [:]
            lastFetchedRecNums = []
            return
        }
        if recNums == lastFetchedRecNums { return }
        do {
            let result = try await DiningAPIService.shared.fetchAvailability(recNums: Array(recNums))
            availability = result
            lastFetchedRecNums = recNums
        } catch {
            // silent fail — leaves rows without label
        }
    }

    // Filled heart matching FoodItemRow; tap to remove from favorites
    private func unfavoriteButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.umdRed, lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.umdRed)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
            .environment(FavoritesManager.shared)
    }
}
