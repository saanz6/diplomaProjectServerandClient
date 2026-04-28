// APIClient.swift
// Networking layer for DiplomProjectToBook

import Foundation
import UIKit

final class APIClient {
    static let shared = APIClient()
    private init() {}
    
    // Base URL from user
    private let baseURL = URL(string: "http://192.168.10.16:8000")!
    private let session = URLSession.shared
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            var dateStr = try container.decode(String.self)
            
            // 💥 FIX: обрезаем микросекунды до 3 знаков
            if let dotRange = dateStr.range(of: ".") {
                let afterDot = dateStr[dotRange.upperBound...]
                if afterDot.count > 3 {
                    let prefix = afterDot.prefix(3)
                    dateStr = String(dateStr[..<dotRange.upperBound]) + prefix
                }
            }
            
            if let date = formatter.date(from: dateStr) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(dateStr)"
            )
        }
        
        return d
    }()
    
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
    // MARK: - Helpers
    private func makeRequest(path: String, method: String = "GET", queryItems: [URLQueryItem]? = nil, body: (any Encodable)? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        return req
    }
    
    // MARK: - Properties
    func getProperties(location: String?) async throws -> [PropertyDTO] {
        var items: [URLQueryItem]? = nil
        if let location, !location.isEmpty, location != "Все" {
            items = [URLQueryItem(name: "location", value: location)]
        }
        let req = try makeRequest(path: "/properties", queryItems: items)
        let (data, _) = try await session.data(for: req)
        return try decoder.decode([PropertyDTO].self, from: data)
    }
    
    func getPropertyDetail(id: Int) async throws -> PropertyDTO {
        let req = try makeRequest(path: "/properties/\(id)")
        let (data, _) = try await session.data(for: req)
        return try decoder.decode(PropertyDTO.self, from: data)
    }
    
    // MARK: - Bookings
    func createBooking(_ payload: CreateBookingRequest, token: String) async throws -> BookingDTO {
        
        let url = baseURL.appendingPathComponent("bookings")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try encoder.encode(payload)
        
        let (data, _) = try await session.data(for: request)
        
        return try decoder.decode(BookingDTO.self, from: data)
    }
    // MARK: - Get Bookings
    func getBookings(token: String) async throws -> [BookingDTO] {
        
        let url = baseURL.appendingPathComponent("my/bookings")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        
        print("📦 BOOKINGS STATUS:", http.statusCode)
        print("📦 BOOKINGS RAW:", String(data: data, encoding: .utf8) ?? "nil")
        
        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(code: http.statusCode, message: "Ошибка загрузки бронирований")
        }
        
        return try decoder.decode([BookingDTO].self, from: data)
    }

    func getMyContracts(token: String) async throws -> [ContractDTO] {
        let url = baseURL.appendingPathComponent("my/contracts")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Ошибка загрузки договоров"
            )
        }

        return try decoder.decode([ContractDTO].self, from: data)
    }

    func cancelBooking(bookingId: Int, token: String) async throws -> BookingDTO {
        let url = baseURL.appendingPathComponent("bookings/\(bookingId)/cancel")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Ошибка отмены бронирования"
            )
        }

        return try decoder.decode(BookingDTO.self, from: data)
    }

    // MARK: - Owner statistics
    func getAllBookingsForOwner() async throws -> [BookingDTO] {
        let url = baseURL.appendingPathComponent("bookings")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let token = AuthService.shared.token ?? ""
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Ошибка загрузки статистики"
            )
        }

        return try decoder.decode([BookingDTO].self, from: data)
    }

    // MARK: - Property image upload
    func uploadPropertyImage(image: UIImage, token: String) async throws -> String {
        let url = baseURL.appendingPathComponent("properties/upload-image")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw APIClientError.serverError(code: 0, message: "Не удалось преобразовать фото квартиры")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image_file\"; filename=\"property.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Ошибка загрузки фото квартиры"
            )
        }

        struct PropertyImageUploadResponse: Decodable {
            let imageUrl: String
        }

        return try decoder.decode(PropertyImageUploadResponse.self, from: data).imageUrl
    }

    func uploadPropertyImages(images: [UIImage], token: String) async throws -> [String] {
        var urls: [String] = []
        for image in images {
            let url = try await uploadPropertyImage(image: image, token: token)
            urls.append(url)
        }
        return urls
    }
    // MARK: - Favorites
    func addFavorite(_ payload: CreateFavoriteRequest) async throws {
        let req = try makeRequest(path: "/favorites", method: "POST", body: payload)
        _ = try await session.data(for: req)
    }
    
    // MARK: - Amenities
    func getAmenities() async throws -> [AmenityDTO] {
        let req = try makeRequest(path: "/amenities")
        let (data, _) = try await session.data(for: req)
        return try decoder.decode([AmenityDTO].self, from: data)
    }
    // MARK: - Verification upload
    func uploadVerification(
        documentType: String,      // передавайте сюда documentType.apiValue
        documentImage: UIImage,
        selfieImage: UIImage,
        token: String
    ) async throws -> VerificationDTO? {
        
        let url = baseURL.appendingPathComponent("verification/upload")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // document_type
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"document_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(documentType)\r\n".data(using: .utf8)!)
        
        // document_file
        guard let documentData = documentImage.jpegData(compressionQuality: 0.8) else {
            throw APIClientError.serverError(code: 0, message: "Не удалось преобразовать фото документа")
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"document_file\"; filename=\"document.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(documentData)
        body.append("\r\n".data(using: .utf8)!)
        
        // selfie_file
        guard let selfieData = selfieImage.jpegData(compressionQuality: 0.8) else {
            throw APIClientError.serverError(code: 0, message: "Не удалось преобразовать селфи")
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"selfie_file\"; filename=\"selfie.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(selfieData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        
        print("✅ UPLOAD STATUS:", http.statusCode)
        print("📦 UPLOAD RAW:", String(data: data, encoding: .utf8) ?? "nil")
        print("🌐 URL:", url.absoluteString)
        
        if !(200...299).contains(http.statusCode) {
            let message = (try? decoder.decode(APIErrorResponse.self, from: data).detail)
            ?? (String(data: data, encoding: .utf8) ?? "Unknown error")
            throw APIClientError.serverError(code: http.statusCode, message: message)
        }
        
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Для upload null не ожидается — это ошибка конфигурации/роутинга
        if raw == "null" || data.isEmpty {
            throw APIClientError.unexpectedNullBody(endpoint: "/verification/upload")
        }
        
        return try decoder.decode(VerificationDTO.self, from: data)
    }
    
    // MARK: - Get verification status (может вернуть nil)
    func getVerificationStatus(token: String) async throws -> VerificationDTO? {
        let url = baseURL.appendingPathComponent("verification/status")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        
        print("✅ STATUS CHECK CODE:", http.statusCode)
        print("📦 STATUS CHECK RAW:", String(data: data, encoding: .utf8) ?? "nil")
        print("🌐 URL:", url.absoluteString)
        
        if !(200...299).contains(http.statusCode) {
            let message = (try? decoder.decode(APIErrorResponse.self, from: data).detail)
            ?? (String(data: data, encoding: .utf8) ?? "Unknown error")
            throw APIClientError.serverError(code: http.statusCode, message: message)
        }
        
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Нормально для этого endpoint
        if raw == "null" || data.isEmpty {
            return nil
        }
        
        return try decoder.decode(VerificationDTO.self, from: data)
    }

    // MARK: - Favorites

    func addFavorite(propertyId: Int, token: String) async throws {
        let url = baseURL.appendingPathComponent("favorites")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["property_id": propertyId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        print("⭐ ADD FAVORITE STATUS:", http.statusCode)
        print("⭐ ADD FAVORITE RAW:", String(data: data, encoding: .utf8) ?? "nil")

        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Ошибка"
            )
        }
    }

    func removeFavorite(propertyId: Int, token: String) async throws {
        let url = baseURL.appendingPathComponent("favorites/\(propertyId)")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func getFavorites(token: String) async throws -> [FavoriteDTO] {
        let url = baseURL.appendingPathComponent("favorites")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Current backend returns [PropertyDTO] for /favorites.
        // Keep fallback to legacy [FavoriteDTO] response for compatibility.
        if let properties = try? decoder.decode([PropertyDTO].self, from: data) {
            return properties.map { FavoriteDTO(propertyId: $0.id) }
        }

        return try decoder.decode([FavoriteDTO].self, from: data)
    }

    // MARK: - User Profile

    func getMe(token: String) async throws -> RemoteUser {
        let url = baseURL.appendingPathComponent("users/me")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "Ошибка загрузки профиля"
            )
        }

        print("👤 GET ME RAW:", String(data: data, encoding: .utf8) ?? "nil")

        return try decoder.decode(RemoteUser.self, from: data)
    }

    func updateProfile(
        email: String,
        phone: String?,
        token: String
    ) async throws -> RemoteUser {

        let url = baseURL.appendingPathComponent("users/me")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "phone": phone as Any
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        print("👤 UPDATE PROFILE STATUS:", http.statusCode)
        print("👤 UPDATE PROFILE RAW:", String(data: data, encoding: .utf8) ?? "nil")

        guard (200...299).contains(http.statusCode) else {
            throw APIClientError.serverError(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Ошибка обновления профиля"
            )
        }

        return try decoder.decode(RemoteUser.self, from: data)
    }
    
    func getMyProperties() async throws -> [PropertyDTO] {
        let token = AuthService.shared.token ?? ""

        var request = try makeRequest(path: "/my/properties")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await session.data(for: request)
        return try decoder.decode([PropertyDTO].self, from: data)
    }
    func createProperty(
        title: String,
        location: String,
        address: String,
        price: Int,
        rooms: Int,
        description: String,
        amenities: [String],
        imageUrls: [String] = [],
        imageUrl: String? = nil
    ) async throws {

        let token = AuthService.shared.token ?? ""

        var body: [String: Any] = [
            "title": title,
            "location": location,
            "address": address,
            "price_per_night": price,
            "rooms": rooms,
            "description": description,
            "amenities": amenities
        ]

        let normalizedImageUrls = imageUrls.filter { !$0.isEmpty }
        if !normalizedImageUrls.isEmpty {
            body["image_urls"] = normalizedImageUrls
        }

        if let imageUrl {
            body["image_url"] = imageUrl
        } else if let firstImageUrl = normalizedImageUrls.first {
            body["image_url"] = firstImageUrl
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("/properties"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    func updateProperty(
        id: Int,
        price: Int,
        description: String,
        amenities: [String],
        rooms: Int,
        bathrooms: Int,
        imageUrls: [String] = [],
        imageUrl: String? = nil
    ) async throws {

        let token = AuthService.shared.token ?? ""

        var body: [String: Any] = [
            "price_per_night": price,
            "description": description,
            "amenities": amenities,
            "rooms": rooms,
            "bathrooms": bathrooms
        ]

        let normalizedImageUrls = imageUrls.filter { !$0.isEmpty }
        if !normalizedImageUrls.isEmpty {
            body["image_urls"] = normalizedImageUrls
        }

        if let imageUrl {
            body["image_url"] = imageUrl
        } else if let firstImageUrl = normalizedImageUrls.first {
            body["image_url"] = firstImageUrl
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("/properties/\(id)"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
    func deleteProperty(id: Int) async throws {
        let token = AuthService.shared.token ?? ""

        var request = URLRequest(url: baseURL.appendingPathComponent("/properties/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

// Wrap any Encodable to avoid generic encode calls in helper
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}


struct APIErrorResponse: Decodable {
    let detail: String
}

enum APIClientError: LocalizedError {
    case invalidResponse
    case serverError(code: Int, message: String)
    case unexpectedNullBody(endpoint: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Неверный ответ сервера"
        case let .serverError(code, message):
            return "Ошибка сервера \(code): \(message)"
        case let .unexpectedNullBody(endpoint):
            return "Сервер вернул null для \(endpoint)"
        }
    }
}
