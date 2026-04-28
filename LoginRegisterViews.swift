import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct LoginView: View {

    @EnvironmentObject var auth: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showRegister = false

    var isValidEmail: Bool {
        email.contains("@") && email.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {

                Section(header: Text("Вход")) {

                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)

                    SecureField("Пароль", text: $password)

                }

                if let error = auth.errorMessage {

                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }

                }

                Section {

                    Button {

                        Task {
                            await auth.login(email: email, password: password)
                        }

                    } label: {

                        if auth.isLoading {
                            ProgressView()
                        } else {
                            Text("Войти")
                        }

                    }
                    .disabled(email.isEmpty || password.isEmpty || !isValidEmail || auth.isLoading)

                }

                Section {
                    Button {
                        Task {
                            await auth.signInWithGoogleAction()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle")
                            Text("Войти через Google")
                        }
                    }
                    .disabled(auth.isLoading)
                }

                Section {

                    Button("Нет аккаунта? Зарегистрироваться") {
                        showRegister = true
                    }

                }

            }
            .navigationTitle("Авторизация")
            .sheet(isPresented: $showRegister) {

                RegisterView()
                    .environmentObject(auth)
            }
        }
    }
}

struct RegisterView: View {
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var surname = ""
    @State private var patronymic = ""
    @State private var isOwner = false
    @State private var email = ""
    @State private var password = ""

    var isValidEmail: Bool {
        // Basic email validation
        email.contains("@") && email.contains(".")
    }

    var isValidPassword: Bool {
        password.count >= 6
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя", text: $name)
                    TextField("Фамилия", text: $surname)
                    TextField("Отчество (необязательно)", text: $patronymic)
                    Toggle("Я сдаю квартиру (владелец)", isOn: $isOwner)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled(true)
                    SecureField("Пароль", text: $password)
                } header: { Text("Регистрация") }

                if let error = auth.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await auth.register(
                                name: name,
                                surname: surname,
                                patronymic: patronymic.isEmpty ? nil : patronymic,
                                email: email,
                                password: password,
                                isOwner: isOwner
                            )
                            if auth.isAuthenticated {
                                dismiss()
                            }
                        }
                    } label: {
                        if auth.isLoading {
                            ProgressView()
                        } else {
                            Text("Создать аккаунт")
                        }
                    }
                    .disabled(name.isEmpty || surname.isEmpty || email.isEmpty || password.isEmpty || !isValidEmail || !isValidPassword || auth.isLoading)
                }
            }
            .navigationTitle("Регистрация")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    LoginView().environmentObject(AuthViewModel())
}

extension AuthViewModel {
    @MainActor
    func signInWithGoogleAction() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // 1) Find a presenting view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = windowScene.keyWindow?.rootViewController else {
                throw NSError(domain: "Auth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Не удалось найти контроллер для показа Google Sign-In"]) }

            // 2) Present Google Sign-In
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)

            // 3) Extract id token (backend expects id_token)
            guard let idToken = signInResult.user.idToken?.tokenString, idToken.isEmpty == false else {
                throw NSError(domain: "Auth", code: -12, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить id_token от Google"]) }

            // 4) Delegate backend login + state persistence to AuthViewModel's unified flow
            await self.loginWithGoogle(idToken: idToken,
                                       userEmail: signInResult.user.profile?.email,
                                       userName: signInResult.user.profile?.name)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
