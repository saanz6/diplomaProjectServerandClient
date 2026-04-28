import Foundation
import SwiftUI
import Combine
import AuthenticationServices
import GoogleSignIn

@MainActor
final class AuthViewModel: ObservableObject {
    @AppStorage("authToken") private var storedToken: String = ""
    @AppStorage("authEmail") private var storedEmail: String = ""
    @AppStorage("authPhone") private var storedPhone: String = ""
    @AppStorage("authName") private var storedName: String = ""
    @AppStorage("authSurname") private var storedSurname: String = ""
    @AppStorage("authGivenName") private var storedGivenName: String = ""
    @AppStorage("authPatronymic") private var storedPatronymic: String = ""
    @AppStorage("user_is_owner") private var storedIsOwner: Bool = false
    @AppStorage("user_is_verified") private var storedIsVerified: Bool = false
    
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: AuthService

    init(service: AuthService = AuthViewModel.defaultService) {
        self.service = service
    }

    nonisolated(unsafe) static var defaultService: AuthService {
        AuthService()
    }

    var isAuthenticated: Bool { !storedToken.isEmpty }

    var token: String? { isAuthenticated ? storedToken : nil }

    var user: UserProfile {
        let resolvedName = storedGivenName.isEmpty && storedSurname.isEmpty && storedPatronymic.isEmpty
            ? parseLegacyNameParts(from: storedName)
            : (surname: storedSurname, name: storedGivenName, patronymic: storedPatronymic.isEmpty ? nil : storedPatronymic)

        if resolvedName.name.isEmpty && resolvedName.surname.isEmpty && storedEmail.isEmpty {
            return .placeholder
        }

        return UserProfile(
            id: nil,
            name: resolvedName.name,
            surname: resolvedName.surname,
            patronymic: resolvedName.patronymic,
            email: storedEmail.isEmpty ? "user@example.com" : storedEmail,
            phone: storedPhone.isEmpty ? nil : storedPhone,
            avatarURL: nil,
            isVerified: storedIsVerified,
            isOwner: storedIsOwner
        )
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await service.login(email: email, password: password)
            print("IS OWNER FROM SERVER:", response.user.is_owner as Any)
            storedToken = response.accessToken
            persistUser(from: response.user)
        } catch {
            if let authErr = error as? AuthError { errorMessage = authErr.localizedDescription } else { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func register(
        name: String,
        surname: String,
        patronymic: String?,
        email: String,
        password: String,
        isOwner: Bool
    ) async{
        isLoading = true
        errorMessage = nil
        do {
            try await service.register(
                name: name,
                surname: surname,
                patronymic: patronymic,
                email: email,
                password: password,
                isOwner: isOwner
            )
            // After successful registration, auto-login for convenience
            try await Task.sleep(nanoseconds: 100_000_000)
            let response = try await service.login(email: email, password: password)
            storedToken = response.accessToken
            persistUser(from: response.user)
        } catch {
            if let authErr = error as? AuthError { errorMessage = authErr.localizedDescription } else { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    func logout() {
        storedToken = ""
        storedEmail = ""
        storedPhone = ""
        storedName = ""
        storedSurname = ""
        storedGivenName = ""
        storedPatronymic = ""
        storedIsOwner = false
        storedIsVerified = false
    }

    func refreshCurrentUser() async {
        guard !storedToken.isEmpty else { return }

        do {
            let remote = try await APIClient.shared.getMe(token: storedToken)
            persistUser(from: remote)
        } catch {
            print("REFRESH USER ERROR:", error)
        }
    }

    func loginWithApple(credential: ASAuthorizationAppleIDCredential) async {
        isLoading = true
        errorMessage = nil
        do {
            // Extract user info from Apple credential
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let emailFromApple = credential.email
            // You would normally send `credential.identityToken` to your backend to create/login the user
            // For demo purposes, we store a local token string if available
            if let tokenData = credential.identityToken, let tokenString = String(data: tokenData, encoding: .utf8) {
                storedToken = tokenString
            } else {
                // Fallback demo token if identityToken is not provided on subsequent sign-ins
                storedToken = UUID().uuidString
            }

            if let emailFromApple {
                storedEmail = emailFromApple
            }
            if !fullName.isEmpty {
                storedName = fullName
            }
        } catch {
            if let authErr = error as? AuthError { errorMessage = authErr.localizedDescription } else { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    /// Sign in with Google using an ID token from GoogleSignIn SDK.
    /// The backend endpoint `/auth/google` should return a JSON with `access_token`, `token_type`, and `user` fields.
    func loginWithGoogle(idToken: String? = nil, userEmail: String? = nil, userName: String? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            // Require an ID token from Google Sign-In SDK
            guard let idToken, !idToken.isEmpty else {
                throw NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить Google ID Token"])
            }

            // Build request to your backend
            struct GoogleAuthRequest: Encodable { let id_token: String }
            struct GoogleAuthUser: Decodable { let id: Int; let name: String; let email: String; let auth_provider: String?; let avatar_url: String?; let is_verified: Bool?; let is_owner: Bool? }
            struct GoogleAuthResponse: Decodable { let access_token: String; let token_type: String; let user: GoogleAuthUser }

            // Replace with your base URL if needed
            let url = URL(string: "http://192.168.10.16:8000/auth/google")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(GoogleAuthRequest(id_token: idToken))

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                throw NSError(domain: "Auth", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Сервер вернул ошибку (\(http.statusCode)): \(serverMessage)"])
            }

            let decoded = try JSONDecoder().decode(GoogleAuthResponse.self, from: data)

            // Persist session
            storedToken = decoded.access_token
            persistUser(from: RemoteUser(
                id: decoded.user.id,
                email: decoded.user.email,
                phone: nil,
                name: decoded.user.name,
                surname: nil,
                patronymic: nil,
                avatarUrl: decoded.user.avatar_url,
                isVerified: decoded.user.is_verified ?? false,
                createdAt: "",
                is_owner: decoded.user.is_owner
            ))
        } catch {
            if let authErr = error as? AuthError { errorMessage = authErr.localizedDescription } else { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }

    private func persistUser(from remote: RemoteUser) {
        storedEmail = remote.email
        storedPhone = remote.phone ?? ""
        storedIsOwner = remote.is_owner ?? false
        storedIsVerified = remote.isVerified
        storedGivenName = remote.name ?? ""
        storedSurname = remote.surname ?? ""
        storedPatronymic = remote.patronymic ?? ""

        let fullName = [remote.surname, remote.name, remote.patronymic]
            .compactMap { $0 }
            .joined(separator: " ")
        storedName = fullName.isEmpty ? (remote.name ?? "Пользователь") : fullName
    }

    private func parseLegacyNameParts(from fullName: String) -> (surname: String, name: String, patronymic: String?) {
        let parts = fullName
            .split(separator: " ")
            .map { String($0) }

        let surname = parts.count > 0 ? parts[0] : ""
        let name = parts.count > 1 ? parts[1] : ""
        let patronymic = parts.count > 2 ? parts[2] : nil
        return (surname, name, patronymic)
    }
}
