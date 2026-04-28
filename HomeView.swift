//
//  HomeView.swift
//  DiplomProjectToBook
//
//  Created by Sanzhar  Zhabagin  on 03.03.2026.
//

import Foundation
import SwiftUI
import Combine

struct Property: Identifiable, Codable, Hashable {
    let id: UUID
    let serverId: Int
    let title: String
    let location: String
    let pricePerNight: Int
    let rating: Double
    let imagePaths: [String]
    let rooms: Int
    let amenities: [String]
    let address: String?

    var primaryImagePath: String {
        imagePaths.first ?? ""
    }
}

struct Booking: Identifiable {
    let id: UUID
    let property: Property
    let checkIn: Date
    let checkOut: Date
    let totalPrice: Int
}

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Поиск жилья...", text: $text)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($isFocused)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
        .onTapGesture { isFocused = true }
        .padding(.horizontal)
    }
}

struct PropertyCardView: View {
    let property: Property
    @Binding var isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Image
            ZStack(alignment: .topTrailing) {
                PropertyRemoteImageView(imagePath: property.primaryImagePath, height: 200)

                Button {
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : .primary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(10)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(property.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(property.location)
                    .font(.subheadline)
                    .foregroundColor(.gray)

                HStack {
                    Text("₸\(property.pricePerNight)/ночь")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Label(
                        String(format: "%.1f", property.rating),
                        systemImage: "star.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
    }
}

private struct PropertyImagesCarouselView: View {
    let imagePaths: [String]
    let height: CGFloat

    var body: some View {
        if imagePaths.count <= 1 {
            PropertyRemoteImageView(imagePath: imagePaths.first ?? "", height: height)
        } else {
            TabView {
                ForEach(Array(imagePaths.enumerated()), id: \.offset) { _, imagePath in
                    PropertyRemoteImageView(imagePath: imagePath, height: height)
                        .padding(.horizontal, 12)
                }
            }
            .frame(height: height)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
    }
}

private struct PropertyRemoteImageView: View {
    let imagePath: String
    let height: CGFloat

    private var url: URL? {
        let trimmed = imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }

        let normalizedPath = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return URL(string: "http://192.168.10.16:8000/\(normalizedPath)")
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure(_), .empty:
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.gray)
                }
            @unknown default:
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(height: height)
        .clipped()
        .cornerRadius(16)
    }
}

final class HomeViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var properties: [Property] = []
    @Published var favorites: Set<Int> = []
    @Published var bookings: [BookingDTO] = []
    @Published var selectedCity: String = "Все"
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @MainActor
    func loadProperties() async {
        isLoading = true
        errorMessage = nil
        do {
            let dtos = try await APIClient.shared.getProperties(location: selectedCity)
            self.properties = dtos.map(Property.init(from:))
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    var cities: [String] {
        let unique = Set(properties.map { $0.location })
        return ["Все"] + unique.sorted()
    }

    func isFavorite(_ property: Property) -> Bool {
        favorites.contains(property.serverId)
    }
    
    func toggleFavorite(_ property: Property) {
        Task {
            let token = AuthService.shared.token ?? ""

            do {
                if favorites.contains(property.serverId) {

                    try await APIClient.shared.removeFavorite(
                        propertyId: property.serverId,
                        token: token
                    )

                    await MainActor.run {
                        favorites.remove(property.serverId)
                    }

                } else {

                    try await APIClient.shared.addFavorite(
                        propertyId: property.serverId,
                        token: token
                    )

                    await MainActor.run {
                        favorites.insert(property.serverId)
                    }
                }

            } catch {
                print("FAVORITE ERROR:", error)
            }
        }
    }

    func loadFavorites() async {
        do {
            let token = AuthService.shared.token ?? ""
            let favoritesFromServer = try await APIClient.shared.getFavorites(token: token)

            await MainActor.run {
                let ids = favoritesFromServer.map { $0.propertyId }
                self.favorites = Set(favoritesFromServer.map { $0.propertyId })
            }
        } catch {
            print("LOAD FAVORITES ERROR:", error)
        }
    }

    func loadBookings() async {
        do {
            let token = AuthService.shared.token ?? ""
            let data = try await APIClient.shared.getBookings(token: token)

            await MainActor.run {
                self.bookings = data
            }
        } catch {
            print(error)
        }
    }

    var filteredProperties: [Property] {
        properties.filter { property in

            let matchesSearch = searchText.isEmpty ||
            property.title.localizedCaseInsensitiveContains(searchText) ||
            property.location.localizedCaseInsensitiveContains(searchText)

            let matchesCity = selectedCity == "Все" || property.location == selectedCity

            return matchesSearch && matchesCity
        }
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Error message
                    if let error = viewModel.errorMessage, !error.isEmpty {
                        Text("Ошибка: \(error)")
                            .foregroundColor(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    
                    // List
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.filteredProperties) { property in
                            NavigationLink(value: property) {
                                PropertyCardView(
                                    property: property,
                                    isFavorite: Binding(
                                        get: { viewModel.isFavorite(property) },
                                        set: { _ in viewModel.toggleFavorite(property) }
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .task {
                await viewModel.loadProperties()
                await viewModel.loadFavorites()
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    SearchBar(text: $viewModel.searchText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.cities, id: \.self) { city in
                                Button {
                                    viewModel.selectedCity = city
                                    Task {
                                        await viewModel.loadProperties()
                                    }
                                } label: {
                                    Text(city)
                                        .font(.subheadline)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.selectedCity == city
                                            ? Color.blue
                                            : Color(.systemGray5)
                                        )
                                        .foregroundColor(
                                            viewModel.selectedCity == city
                                            ? .white
                                            : .primary
                                        )
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 6)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: Property.self) { property in
                PropertyDetailView(property: property, viewModel: viewModel)
            }
        }
    }
}

struct MainTabView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        TabView {
            HomeView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Главная")
                }
            
            FavoritesView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Избранное")
                }
            
            BookingsView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Брони")
                }
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Профиль")
                }
        }
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 28)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }
}

struct FavoritesView: View {
    @ObservedObject var viewModel: HomeViewModel
    
    var favoriteProperties: [Property] {
        viewModel.properties.filter {
            viewModel.favorites.contains($0.serverId)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if favoriteProperties.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("Нет избранных")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(favoriteProperties) { property in
                            NavigationLink(value: property) {
                                PropertyCardView(
                                    property: property,
                                    isFavorite: Binding(
                                        get: { viewModel.isFavorite(property) },
                                        set: { _ in viewModel.toggleFavorite(property) }
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: Property.self) { property in
                PropertyDetailView(property: property, viewModel: viewModel)
            }
            .navigationTitle("Избранное")
            .onAppear {
                Task {
                    await viewModel.loadFavorites()
                }
            }
        }
    }
}

struct BookingsView: View {
    @ObservedObject var viewModel: HomeViewModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.bookings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("Нет бронирований")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.bookings, id: \.id) { booking in
                            NavigationLink {
                                BookingDetailView(booking: booking) {
                                    Task {
                                        await viewModel.loadBookings()
                                    }
                                }
                            } label: {
                                BookingCardView(booking: booking)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Бронирования")
        }
        .onAppear {
            Task {
                await viewModel.loadBookings()
            }
        }
    }
}

struct BookingCardView: View {
    let booking: BookingDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.property?.title ?? "Квартира #\(booking.propertyId)")
                        .font(.headline)

                    Text(booking.property?.location ?? "Неизвестное место")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    if let address = booking.property?.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Text("ID брони: \(booking.id)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Text("₸\(booking.totalPrice)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            Divider()

            HStack {
                VStack(alignment: .leading) {
                    Text("Заезд")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(formatDateString(booking.checkIn))
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .leading) {
                    Text("Выезд")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(formatDateString(booking.checkOut))
                        .fontWeight(.medium)
                }
            }

            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)

                Text("\(booking.guests) гостей")
                    .font(.subheadline)

                Spacer()
            }

        }
        .padding()
        .background(Color.white)
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

private func formatDateString(_ dateString: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    if let date = formatter.date(from: dateString) {
        let output = DateFormatter()
        output.dateStyle = .medium
        return output.string(from: date)
    }

    return dateString
}


struct PropertyDetailView: View {
    let property: Property
    @ObservedObject var viewModel: HomeViewModel

    @State private var checkInDate = Date()
    @State private var checkOutDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    @State private var guests: Int = 1
    @State private var showSuccess = false

    var nights: Int {
        Calendar.current.dateComponents([.day], from: checkInDate, to: checkOutDate).day ?? 1
    }

    var totalPrice: Int {
        max(nights, 1) * property.pricePerNight
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Image
                PropertyImagesCarouselView(imagePaths: property.imagePaths, height: 300)

                VStack(alignment: .leading, spacing: 16) {

                    // Title
                    Text(property.title)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack {
                        Label(property.location, systemImage: "mappin.and.ellipse")
                            .foregroundColor(.secondary)

                        Spacer()

                        Label(
                            String(format: "%.1f", property.rating),
                            systemImage: "star.fill"
                        )
                        .foregroundColor(.orange)
                    }

                    // Rooms
                    HStack {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(.blue)

                        Text("\(property.rooms) комнат")
                            .font(.subheadline)

                        Spacer()
                    }

                    // Amenities section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Удобства")
                            .font(.headline)

                        ForEach(property.amenities, id: \.self) { amenity in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)

                                Text(amenity)
                                    .font(.subheadline)

                                Spacer()
                            }
                        }
                    }

                    Divider()

                    // Booking card (like Airbnb)
                    VStack(spacing: 16) {

                        // Dates
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Заезд")
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    DatePicker(
                                        "",
                                        selection: $checkInDate,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                }

                                Divider()

                                VStack(alignment: .leading) {
                                    Text("Выезд")
                                        .font(.caption)
                                        .foregroundColor(.gray)

                                    DatePicker(
                                        "",
                                        selection: $checkOutDate,
                                        in: checkInDate...,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                }
                            }
                        }

                        Divider()

                        // Guests
                        Stepper(value: $guests, in: 1...10) {
                            HStack {
                                Text("Гости")
                                Spacer()
                                Text("\(guests)")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 5)

                    Divider()

                    // Price calculation
                    VStack(spacing: 10) {
                        HStack {
                            Text("₸\(property.pricePerNight) × \(max(nights,1)) ночей")
                            Spacer()
                            Text("₸\(totalPrice)")
                        }

                        HStack {
                            Text("Итого")
                                .font(.headline)
                            Spacer()
                            Text("₸\(totalPrice)")
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                    }
                    
                    // Booking button inside the card (if any) was not present, so no change here
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            // Bottom booking bar (Airbnb style)
            HStack {
                VStack(alignment: .leading) {
                    Text("₸\(property.pricePerNight)")
                        .font(.headline)

                    Text("за ночь")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        do {
                            let payload = CreateBookingRequest(
                                propertyId: property.serverId,
                                checkIn: formatter.string(from: checkInDate),
                                checkOut: formatter.string(from: checkOutDate),
                                guests: guests,
                                totalPrice: totalPrice
                            )
                            let token = AuthService.shared.token ?? ""
                            _ = try await APIClient.shared.createBooking(payload, token: token)

                            // обновляем бронирования
                            await viewModel.loadBookings()

                            showSuccess = true
                        } catch {
                            // You may want to show an error alert here
                            showSuccess = false
                        }
                    }
                } label: {
                    Text("Забронировать")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Бронирование создано", isPresented: $showSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Жильё успешно забронировано")
        }
    }
}

#Preview{
    MainTabView()
        .environmentObject(AuthViewModel())
}


struct BookingDetailView: View {
    let booking: BookingDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                VStack(alignment: .leading, spacing: 8) {
                    Text(booking.property?.title ?? "Квартира #\(booking.propertyId)")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(booking.property?.location ?? "Неизвестное место")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    if let address = booking.property?.address {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading) {
                        Text("Заезд")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(formatDateString(booking.checkIn))
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .leading) {
                        Text("Выезд")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(formatDateString(booking.checkOut))
                            .fontWeight(.medium)
                    }
                }

                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.blue)
                    Text("\(booking.guests) гостей")
                }

                Divider()

                HStack {
                    Text("Итого оплачено")
                        .font(.headline)
                    Spacer()
                    Text("₸\(booking.totalPrice)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }

                Divider()

                Text(statusText)
                    .font(.headline)
                    .foregroundColor(statusColor)

                if booking.status != "cancelled" {
                    Button {
                        cancelBooking()
                    } label: {
                        if isCancelling {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        } else {
                            Text("Отменить бронирование")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isCancelling)
                }

            }
            .padding()
        }
        .navigationTitle("Детали брони")
        .alert("Ошибка", isPresented: $showCancelError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cancelErrorMessage)
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var isCancelling = false
    @State private var showCancelError = false
    @State private var cancelErrorMessage = ""

    var onCancelled: () -> Void = {}

    private var statusText: String {
        switch booking.status {
        case "cancelled":
            return "Бронирование отменено"
        case "confirmed":
            return "Бронирование подтверждено"
        default:
            return "Бронирование активно"
        }
    }

    private var statusColor: Color {
        switch booking.status {
        case "cancelled":
            return .red
        case "confirmed":
            return .green
        default:
            return .green
        }
    }

    private func cancelBooking() {
        Task {
            isCancelling = true
            defer { isCancelling = false }

            do {
                let token = AuthService.shared.token ?? ""
                _ = try await APIClient.shared.cancelBooking(bookingId: booking.id, token: token)
                onCancelled()
                dismiss()
            } catch {
                cancelErrorMessage = error.localizedDescription
                showCancelError = true
            }
        }
    }
}
