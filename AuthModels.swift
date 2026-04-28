import Foundation

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct LoginResponse: Codable {
    let accessToken: String
    let tokenType: String
    let user: RemoteUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}

struct RemoteUser: Codable {
    let id: Int
    let email: String
    let phone: String?
    let name: String?
    let surname: String?
    let patronymic: String?
    let avatarUrl: String?
    let isVerified: Bool
    let createdAt: String
    let is_owner: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case phone
        case name
        case surname
        case patronymic
        case avatarUrl = "avatar_url"
        case isVerified = "is_verified"
        case createdAt = "created_at"
        case is_owner
    }
}

struct RegisterRequest: Codable {
    let name: String
    let surname: String
    let patronymic: String?
    let email: String
    let password: String
    let isOwner: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case surname
        case patronymic
        case email
        case password
        case isOwner = "is_owner"
    }
}

struct UserProfile: Codable, Equatable {
    var id: Int?
    var name: String
    var surname: String
    var patronymic: String?
    var email: String
    var phone: String?
    var avatarURL: URL?
    var isVerified: Bool
    var isOwner: Bool
}

extension UserProfile {
    static let placeholder = UserProfile(
        id: nil,
        name: "Имя",
        surname: "Фамилия",
        patronymic: nil,
        email: "user@example.com",
        phone: nil,
        avatarURL: nil,
        isVerified: false,
        isOwner: false
    )
}
extension UserProfile {
    init(from remote: RemoteUser) {
        self.id = remote.id
        self.name = remote.name ?? ""
        self.surname = remote.surname ?? ""
        self.patronymic = remote.patronymic
        self.email = remote.email
        self.phone = remote.phone

        if let urlString = remote.avatarUrl,
           let url = URL(string: urlString) {
            self.avatarURL = url
        } else {
            self.avatarURL = nil
        }

        self.isVerified = remote.isVerified
        self.isOwner = remote.is_owner ?? false
    }
}

extension UserProfile {
    var fullName: String {
        [surname, name, patronymic]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

