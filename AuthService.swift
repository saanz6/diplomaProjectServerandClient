import Foundation

enum AuthError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case statusCode(Int)
    case decoding
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Неверный адрес сервера"
        case .invalidResponse: return "Некорректный ответ сервера"
        case .statusCode(let code): return "Ошибка сервера: \(code)"
        case .decoding: return "Ошибка обработки данных"
        case .unknown(let err): return err.localizedDescription
        }
    }
}

final class AuthService {
    private let baseURL = URL(string: "http://192.168.10.16:8000")!
    private let session: URLSession
    static let shared = AuthService()
    private let tokenKey = "auth_token"

    var token: String? {
        get {
            UserDefaults.standard.string(forKey: tokenKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: tokenKey)
        }
    }
    
    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(email: String, password: String) async throws -> LoginResponse {
        let endpoint = URL(string: "/login", relativeTo: baseURL)
        guard let url = endpoint else { throw AuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = LoginRequest(email: email, password: password)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.statusCode(http.statusCode) }

        let result = try JSONDecoder().decode(LoginResponse.self, from: data)

        // сохраняем токен
        self.token = result.accessToken

        return result
    }

    func register(
        name: String,
        surname: String,
        patronymic: String?,
        email: String,
        password: String,
        isOwner: Bool
    ) async throws {
        let endpoint = URL(string: "/users", relativeTo: baseURL)
        guard let url = endpoint else { throw AuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = RegisterRequest(
            name: name,
            surname: surname,
            patronymic: patronymic,
            email: email,
            password: password,
            isOwner: isOwner
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AuthError.statusCode(http.statusCode) }
    }
}
