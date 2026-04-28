import SwiftUI
import PhotosUI
import UIKit

struct AdminView: View {
    var body: some View {
        TabView {
            AdminPropertiesView()
                .tabItem {
                    Image(systemName: "building.2.fill")
                    Text("Квартиры")
                }

            OwnerStatsView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Статистика")
                }

            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Профиль")
                }
        }
    }
}

struct AdminPropertiesView: View {
    @EnvironmentObject var auth: AuthViewModel

    @State private var properties: [PropertyDTO] = []
    @State private var isLoading = false
    @State private var showCreate = false
    @State private var showVerificationAlert = false
    @State private var showVerificationFlow = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .padding()
                } else if properties.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(properties) { property in
                            NavigationLink {
                                EditPropertyView(property: property) {
                                    loadProperties()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(property.title)
                                        .font(.headline)

                                    Text(property.location)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)

                                    Text("₸\(property.pricePerNight)")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .onDelete(perform: deleteProperty)
                    }
                }
            }
            .navigationTitle("Мои квартиры")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if auth.user.isVerified {
                            showCreate = true
                        } else {
                            showVerificationAlert = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Добавление квартир доступно только после верификации", isPresented: $showVerificationAlert) {
                Button("Понятно", role: .cancel) {}
                Button("Пройти верификацию") {
                    showVerificationFlow = true
                }
            } message: {
                Text("Сначала пройдите верификацию пользователя, затем сможете публиковать квартиры.")
            }
            .sheet(isPresented: $showCreate) {
                CreatePropertyView {
                    loadProperties()
                }
            }
            .sheet(isPresented: $showVerificationFlow) {
                UserVerificationView()
                    .environmentObject(auth)
            }
            .onAppear {
                loadProperties()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 40))
                .foregroundColor(.gray)

            Text("Нет квартир")
                .foregroundColor(.secondary)

            if !auth.user.isVerified {
                Text("Публикация доступна только после верификации")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 50)
    }

    func loadProperties() {
        Task {
            isLoading = true
            do {
                let data = try await APIClient.shared.getMyProperties()
                await MainActor.run {
                    properties = data
                }
            } catch {
                print("LOAD ADMIN PROPERTIES ERROR:", error)
            }
            isLoading = false
        }
    }

    func deleteProperty(at offsets: IndexSet) {
        for index in offsets {
            let property = properties[index]

            Task {
                do {
                    try await APIClient.shared.deleteProperty(id: property.id)
                    await MainActor.run {
                        properties.remove(at: index)
                    }
                } catch {
                    print("DELETE ERROR:", error)
                }
            }
        }
    }
}

struct OwnerStatsView: View {
    @State private var properties: [PropertyDTO] = []
    @State private var bookings: [BookingDTO] = []
    @State private var isLoading = false

    private var propertyIds: Set<Int> {
        Set(properties.map { $0.id })
    }

    private var ownerBookings: [BookingDTO] {
        bookings.filter { propertyIds.contains($0.propertyId) }
    }

    private var totalIncome: Int {
        ownerBookings.reduce(0) { $0 + $1.totalPrice }
    }

    private var uniqueTenantsCount: Int {
        Set(ownerBookings.map { $0.userId }).count
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                Section("Сводка") {
                    StatRow(title: "Мои квартиры", value: "\(properties.count)")
                    StatRow(title: "Бронирований", value: "\(ownerBookings.count)")
                    StatRow(title: "Доход", value: "₸\(totalIncome)")
                    StatRow(title: "Арендаторов", value: "\(uniqueTenantsCount)")
                }

                Section("Детализация") {
                    NavigationLink("Мои бронирования (как владелец)") {
                        OwnerBookingsListView(bookings: ownerBookings)
                    }

                    NavigationLink("Доход") {
                        OwnerIncomeView(bookings: ownerBookings)
                    }

                    NavigationLink("Кто снял мою квартиру") {
                        OwnerTenantsView(bookings: ownerBookings)
                    }
                }
            }
            .navigationTitle("Статистика владельца")
            .onAppear {
                loadStats()
            }
            .refreshable {
                loadStats()
            }
        }
    }

    private func loadStats() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                async let props = APIClient.shared.getMyProperties()
                async let allBookings = APIClient.shared.getAllBookingsForOwner()

                let loadedProps = try await props
                let loadedBookings = try await allBookings

                await MainActor.run {
                    properties = loadedProps
                    bookings = loadedBookings
                }
            } catch {
                print("OWNER STATS LOAD ERROR:", error)
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

struct OwnerBookingsListView: View {
    let bookings: [BookingDTO]

    var body: some View {
        List {
            if bookings.isEmpty {
                Text("Пока нет бронирований")
                    .foregroundColor(.secondary)
            } else {
                ForEach(bookings) { booking in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(booking.property?.title ?? "Квартира #\(booking.propertyId)")
                            .font(.headline)
                        Text("Гость: \(booking.tenantDisplayName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Даты: \(booking.checkIn) - \(booking.checkOut)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("Доход: ₸\(booking.totalPrice)")
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Мои бронирования")
    }
}

struct OwnerIncomeView: View {
    let bookings: [BookingDTO]

    private var totalIncome: Int {
        bookings.reduce(0) { $0 + $1.totalPrice }
    }

    private var incomeByProperty: [(title: String, income: Int)] {
        let grouped = Dictionary(grouping: bookings) { $0.propertyId }
        return grouped.map { key, value in
            let title = value.first?.property?.title ?? "Квартира #\(key)"
            let income = value.reduce(0) { $0 + $1.totalPrice }
            return (title, income)
        }
        .sorted { $0.income > $1.income }
    }

    var body: some View {
        List {
            Section("Общий доход") {
                Text("₸\(totalIncome)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Section("По квартирам") {
                if incomeByProperty.isEmpty {
                    Text("Пока нет данных")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(incomeByProperty, id: \.title) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text("₸\(item.income)")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Доход")
    }
}

struct OwnerTenantsView: View {
    let bookings: [BookingDTO]

    private var bookingsGroupedByTenantName: [(name: String, bookingsCount: Int, spent: Int)] {
        let grouped = Dictionary(grouping: bookings) { $0.tenantDisplayName }
        return grouped.map { name, items in
            (
                name: name,
                bookingsCount: items.count,
                spent: items.reduce(0) { $0 + $1.totalPrice }
            )
        }
        .sorted { $0.spent > $1.spent }
    }

    var body: some View {
        List {
            if bookingsGroupedByTenantName.isEmpty {
                Text("Пока никто не снял ваши квартиры")
                    .foregroundColor(.secondary)
            } else {
                ForEach(bookingsGroupedByTenantName, id: \.name) { tenant in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tenant.name)
                            .font(.headline)
                        Text("Бронирований: \(tenant.bookingsCount)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Оплачено: ₸\(tenant.spent)")
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Кто снял мою квартиру")
    }
}

struct CreatePropertyView: View {
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var address = ""
    @State private var price = ""
    @State private var rooms = ""
    @State private var description = ""
    @State private var amenities: [String] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var isUploadingPhoto = false
    @State private var showInvalidRoomsAlert = false

    let allAmenities = ["Wi-Fi", "Кухня", "Кондиционер", "Парковка", "Телевизор"]

    var onCreated: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(photoImages.isEmpty ? "Добавить фото квартиры" : "Изменить фото квартиры")
                        }
                    }

                    if !photoImages.isEmpty {
                        Text("Выбрано фото: \(photoImages.count)")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(photoImages.enumerated()), id: \.offset) { index, image in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 90)
                                            .clipped()
                                            .cornerRadius(10)

                                        Button {
                                            if index < photoItems.count {
                                                photoItems.remove(at: index)
                                            }
                                            photoImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.45))
                                                .clipShape(Circle())
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                TextField("Название", text: $title)
                TextField("Город", text: $location)
                TextField("Адрес", text: $address)
                TextField("Цена", text: $price)
                    .keyboardType(.numberPad)
                TextField("Комнаты", text: $rooms)
                    .keyboardType(.numberPad)
                TextField("Описание", text: $description)

                Section(header: Text("Удобства")) {
                    ForEach(allAmenities, id: \.self) { amenity in
                        Button {
                            toggleAmenity(amenity)
                        } label: {
                            HStack {
                                Text(amenity)
                                Spacer()
                                if amenities.contains(amenity) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Button("Создать") {
                    createProperty()
                }
                .disabled(isUploadingPhoto || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Int(rooms) ?? 0) <= 0)
            }
            .navigationTitle("Новая квартира")
            .alert("Укажите корректное количество комнат", isPresented: $showInvalidRoomsAlert) {
                Button("Ок", role: .cancel) {}
            } message: {
                Text("Количество комнат должно быть больше нуля")
            }
            .onChange(of: photoItems) { newItems in
                Task {
                    await loadSelectedPhotos(from: newItems)
                }
            }
        }
    }

    func toggleAmenity(_ amenity: String) {
        if amenities.contains(amenity) {
            amenities.removeAll { $0 == amenity }
        } else {
            amenities.append(amenity)
        }
    }

    func createProperty() {
        Task {
            do {
                isUploadingPhoto = true
                defer { isUploadingPhoto = false }

                guard let roomsCount = Int(rooms), roomsCount > 0 else {
                    showInvalidRoomsAlert = true
                    return
                }

                let imageUrls = try await uploadPhotosIfNeeded()

                try await APIClient.shared.createProperty(
                    title: title,
                    location: location,
                    address: address,
                    price: Int(price) ?? 0,
                    rooms: roomsCount,
                    description: description,
                    amenities: amenities,
                    imageUrls: imageUrls,
                    imageUrl: imageUrls.first
                )

                onCreated()
                dismiss()
            } catch {
                print("CREATE ERROR:", error)
            }
        }
    }

    func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        var loadedImages: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }
        photoImages = loadedImages
    }

    func uploadPhotosIfNeeded() async throws -> [String] {
        guard !photoImages.isEmpty else { return [] }
        let token = AuthService.shared.token ?? ""
        guard !token.isEmpty else { return [] }
        return try await APIClient.shared.uploadPropertyImages(images: photoImages, token: token)
    }
}

struct EditPropertyView: View {
    @Environment(\.dismiss) var dismiss

    let property: PropertyDTO
    var onUpdated: () -> Void

    @State private var title: String
    @State private var location: String
    @State private var address: String
    @State private var price: String
    @State private var description: String
    @State private var amenities: [String]
    @State private var rooms: String
    @State private var bathrooms: String
    @State private var existingImageUrls: [String]
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var newPhotoImages: [UIImage] = []
    @State private var isUploadingPhotos = false
    let allAmenities = ["Wi-Fi", "Кухня", "Кондиционер", "Парковка", "Телевизор"]

    init(property: PropertyDTO, onUpdated: @escaping () -> Void) {
        self.property = property
        self.onUpdated = onUpdated

        _title = State(initialValue: property.title)
        _location = State(initialValue: property.location)
        _address = State(initialValue: property.address ?? "")
        _price = State(initialValue: String(property.pricePerNight))
        _description = State(initialValue: property.description ?? "")
        _amenities = State(initialValue: property.amenities?.map { $0.name } ?? [])
        _rooms = State(initialValue: String(property.rooms ?? 1))
        _bathrooms = State(initialValue: String(property.bathrooms ?? 1))

        var urls: [String] = []
        if let imageUrls = property.imageUrls {
            for url in imageUrls where !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        if let imageUrl = property.imageUrl,
           !imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !urls.contains(imageUrl) {
            urls.append(imageUrl)
        }
        _existingImageUrls = State(initialValue: urls)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Недоступно для изменения") {
                    TextField("Название", text: $title)
                        .disabled(true)
                    TextField("Город", text: $location)
                        .disabled(true)
                    TextField("Адрес", text: $address)
                        .disabled(true)
                }

                Section("Фото квартиры") {
                    if !existingImageUrls.isEmpty {
                        Text("Текущие фото: \(existingImageUrls.count)")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(existingImageUrls.enumerated()), id: \.offset) { index, url in
                                    ZStack(alignment: .topTrailing) {
                                        AsyncImage(url: fullImageURL(for: url)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                            default:
                                                ZStack {
                                                    Color(.systemGray5)
                                                    Image(systemName: "photo")
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                        }
                                        .frame(width: 120, height: 90)
                                        .clipped()
                                        .cornerRadius(10)

                                        Button {
                                            existingImageUrls.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.45))
                                                .clipShape(Circle())
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    PhotosPicker(
                        selection: $photoItems,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Добавить новые фото")
                        }
                    }

                    if !newPhotoImages.isEmpty {
                        Text("Новые фото: \(newPhotoImages.count)")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(newPhotoImages.enumerated()), id: \.offset) { index, image in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 90)
                                            .clipped()
                                            .cornerRadius(10)

                                        Button {
                                            if index < photoItems.count {
                                                photoItems.remove(at: index)
                                            }
                                            newPhotoImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Color.black.opacity(0.45))
                                                .clipShape(Circle())
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                TextField("Цена", text: $price)
                    .keyboardType(.numberPad)
                TextField("Комнаты", text: $rooms)
                    .keyboardType(.numberPad)
                TextField("Ванные", text: $bathrooms)
                    .keyboardType(.numberPad)
                TextField("Описание", text: $description)

                Section(header: Text("Удобства")) {
                    ForEach(allAmenities, id: \.self) { amenity in
                        Button {
                            toggleAmenity(amenity)
                        } label: {
                            HStack {
                                Text(amenity)
                                Spacer()
                                if amenities.contains(amenity) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Button("Сохранить") {
                    updateProperty()
                }
                .disabled(isUploadingPhotos)
            }
            .navigationTitle("Редактирование")
            .onChange(of: photoItems) { newItems in
                Task {
                    await loadSelectedPhotos(from: newItems)
                }
            }
        }
    }

    func toggleAmenity(_ amenity: String) {
        if amenities.contains(amenity) {
            amenities.removeAll { $0 == amenity }
        } else {
            amenities.append(amenity)
        }
    }

    func updateProperty() {
        Task {
            do {
                isUploadingPhotos = true
                defer { isUploadingPhotos = false }

                let uploadedImageUrls = try await uploadNewPhotosIfNeeded()
                let finalImageUrls = existingImageUrls + uploadedImageUrls

                try await APIClient.shared.updateProperty(
                    id: property.id,
                    price: Int(price) ?? 0,
                    description: description,
                    amenities: amenities,
                    rooms: Int(rooms) ?? 1,
                    bathrooms: Int(bathrooms) ?? 1,
                    imageUrls: finalImageUrls,
                    imageUrl: finalImageUrls.first
                )

                onUpdated()
                dismiss()
            } catch {
                print("UPDATE ERROR:", error)
            }
        }
    }

    func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        var loadedImages: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedImages.append(image)
            }
        }
        newPhotoImages = loadedImages
    }

    func uploadNewPhotosIfNeeded() async throws -> [String] {
        guard !newPhotoImages.isEmpty else { return [] }
        let token = AuthService.shared.token ?? ""
        guard !token.isEmpty else { return [] }
        return try await APIClient.shared.uploadPropertyImages(images: newPhotoImages, token: token)
    }

    func fullImageURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }

        let normalizedPath = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return URL(string: "http://192.168.10.16:8000/\(normalizedPath)")
    }
}

#Preview {
    AdminView()
}
