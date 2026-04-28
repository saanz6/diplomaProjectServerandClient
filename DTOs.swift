// DTOs.swift
// Data Transfer Objects for DiplomProjectToBook

import Foundation

// MARK: - Properties
struct PropertyDTO: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let location: String
    let pricePerNight: Int
    let imageUrl: String?
    let imageUrls: [String]?
    let rooms: Int?
    let bathrooms: Int?
    let description: String?
    // let amenityIds: [Int]? // Removed as no longer used
    let rating: Double?
    let amenities: [AmenityDTO]?
    let address: String?
}

// MARK: - Bookings
struct BookingDTO: Codable, Identifiable {
    let id: Int
    let userId: Int
    let propertyId: Int
    let checkIn: String
    let checkOut: String
    let guests: Int
    let totalPrice: Int
    let status: String?
    let property: PropertyShortDTO?
    let user: BookingUserDTO?
}

struct BookingUserDTO: Codable {
    let id: Int
    let name: String
    let surname: String?
    let patronymic: String?
    let email: String
}

struct PropertyShortDTO: Codable {
    let id: Int
    let title: String
    let location: String
    let address: String?
}

struct CreateBookingRequest: Encodable {
    let propertyId: Int
    let checkIn: String
    let checkOut: String
    let guests: Int
    let totalPrice: Int
}

struct ContractDTO: Codable, Identifiable {
    let bookingId: Int
    let propertyTitle: String
    let checkIn: String
    let checkOut: String
    let createdAt: String
    let isActive: Bool
    let contractUrl: String

    var id: Int { bookingId }
}

// MARK: - Amenities
struct AmenityDTO: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

// MARK: - Favorites
struct CreateFavoriteRequest: Codable {
    let userId: Int
    let propertyId: Int
}

// MARK: - Mapping to UI models
extension Property {
    init(from dto: PropertyDTO) {
        let rawImagePaths = (dto.imageUrls ?? []) + (dto.imageUrl.map { [$0] } ?? [])
        var mergedImagePaths: [String] = []
        for path in rawImagePaths {
            let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty && !mergedImagePaths.contains(cleaned) {
                mergedImagePaths.append(cleaned)
            }
        }

        self.id = UUID()
        self.serverId = dto.id
        self.title = dto.title
        self.location = dto.location
        self.pricePerNight = dto.pricePerNight
        self.rating = dto.rating ?? 0
        self.imagePaths = mergedImagePaths
        self.rooms = dto.rooms ?? 1
        self.amenities = (dto.amenities ?? []).map { $0.name }
        self.address = dto.address
    }
}

struct VerificationDTO: Codable {
    let id: Int
    let userId: Int
    let documentType: String
    let documentUrl: String
    let selfieUrl: String
    let status: String
    let notes: String?
    let createdAt: String
    let updatedAt: String
}

struct FavoriteDTO: Codable {
    let propertyId: Int
}

extension BookingDTO {
    var tenantDisplayName: String {
        if let user {
            let parts = [user.surname, user.name, user.patronymic]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            let fullName = parts.joined(separator: " ")
            if !fullName.isEmpty {
                return fullName
            }
            return user.email
        }
        return "Пользователь #\(userId)"
    }
}
