import SwiftUI
import PhotosUI
import Vision
import Combine
import UIKit
import SafariServices

struct ProfileView: View {
    
    @EnvironmentObject var auth: AuthViewModel
    @State private var user: UserProfile = .placeholder
    
    var body: some View {
        NavigationStack {
            List {
                
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 70, height: 70)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(user.fullName)
                                .font(.headline)

                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Аккаунт") {
                    
                    NavigationLink {
                        PersonalDataView()
                            .environmentObject(auth)
                    } label: {
                        Label("Личные данные", systemImage: "person.text.rectangle")
                    }
                    
                    NavigationLink {
                        UserVerificationView()
                            .environmentObject(auth)
                    } label: {
                        Label("Верификация пользователя", systemImage: "checkmark.shield")
                    }
                    
                    NavigationLink {
                        ContractsView()
                    } label: {
                        Label("Мои договоры", systemImage: "doc.text")
                    }
                }
                
                Section("Приложение") {
                    
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Label("Выйти", systemImage: "arrow.right.square")
                    }
                }
            }
            .navigationTitle("Профиль")
            .onAppear {
                Task {
                    await auth.refreshCurrentUser()
                    syncProfileFromAuth()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PROFILE_UPDATED"))) { _ in
                Task {
                    await auth.refreshCurrentUser()
                    syncProfileFromAuth()
                }
            }
        }
        .sheet(isPresented: .constant(!auth.isAuthenticated)) {
            LoginView()
                .environmentObject(auth)
        }
    }

    private func syncProfileFromAuth() {
        user = auth.user
    }

    func loadProfile() {
        Task {
            do {
                let token = AuthService.shared.token ?? ""
                let remote = try await APIClient.shared.getMe(token: token)
                let profile = UserProfile(from: remote)

                await MainActor.run {
                    self.user = profile
                }

            } catch {
                print("LOAD PROFILE ERROR:", error)
            }
        }
    }
}

struct PersonalDataView: View {
    
    @EnvironmentObject var auth: AuthViewModel

    @State private var name: String = ""
    @State private var surname: String = ""
    @State private var patronymic: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    
    var body: some View {
        Form {
            
            Section("Основная информация") {
                TextField("Имя", text: $name)
                    .disabled(true)
                TextField("Фамилия", text: $surname)
                    .disabled(true)
                TextField("Отчество (необязательно)", text: $patronymic)
                    .disabled(true)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                TextField("Телефон", text: $phone)
                    .keyboardType(.phonePad)
            }
            
            Section {
                Button("Сохранить") {
                    Task {
                        do {
                            let token = AuthService.shared.token ?? ""

                            _ = try await APIClient.shared.updateProfile(
                                email: email,
                                phone: phone.isEmpty ? nil : phone,
                                token: token
                            )

                            NotificationCenter.default.post(name: NSNotification.Name("PROFILE_UPDATED"), object: nil)

                        } catch {
                            print("UPDATE PROFILE ERROR:", error)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await auth.refreshCurrentUser()
                syncFieldsFromAuth()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PROFILE_UPDATED"))) { _ in
            Task {
                await auth.refreshCurrentUser()
                syncFieldsFromAuth()
            }
        }
        .navigationTitle("Личные данные")
    }

    private func syncFieldsFromAuth() {
        self.name = auth.user.name
        self.surname = auth.user.surname
        self.patronymic = auth.user.patronymic ?? ""
        self.email = auth.user.email
        self.phone = auth.user.phone ?? ""
    }
}

//struct VerificationView: View {
//    
//    @State private var isVerified: Bool = false
//    
//    var body: some View {
//        VStack(spacing: 24) {
//            
//            Image(systemName: isVerified ? "checkmark.shield.fill" : "exclamationmark.shield")
//                .font(.system(size: 80))
//                .foregroundColor(isVerified ? .green : .orange)
//            
//            Text(isVerified ? "Ваш аккаунт подтвержден" : "Аккаунт не подтвержден")
//                .font(.title3)
//                .fontWeight(.semibold)
//            
//            Text("Для бронирования жилья необходимо подтвердить личность.")
//                .multilineTextAlignment(.center)
//                .foregroundColor(.gray)
//                .padding(.horizontal)
//            
//            Button {
//                isVerified = true
//            } label: {
//                Text("Пройти верификацию")
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(.blue)
//                    .foregroundColor(.white)
//                    .cornerRadius(12)
//            }
//            .padding(.horizontal)
//        }
//        .navigationTitle("Верификация")
//        .padding()
//    }
//}

struct ContractsView: View {
    private enum ContractsFilter {
        case active
        case inactive
    }

    @State private var contracts: [ContractDTO] = []
    @State private var isLoading = false
    @State private var selectedURL: URL?
    @State private var selectedFilter: ContractsFilter = .active

    private var filteredContracts: [ContractDTO] {
        switch selectedFilter {
        case .active:
            return contracts.filter { $0.isActive }
        case .inactive:
            return contracts.filter { !$0.isActive }
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Button {
                        selectedFilter = .active
                    } label: {
                        Text("Активные")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedFilter == .active ? Color.blue : Color(.systemGray5))
                            .foregroundColor(selectedFilter == .active ? .white : .primary)
                            .cornerRadius(18)
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedFilter = .inactive
                    } label: {
                        Text("Неактивные")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedFilter == .inactive ? Color.blue : Color(.systemGray5))
                            .foregroundColor(selectedFilter == .inactive ? .white : .primary)
                            .cornerRadius(18)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Загрузка договоров...")
                    Spacer()
                }
            } else if filteredContracts.isEmpty {
                Text(selectedFilter == .active ? "Нет активных договоров" : "Нет неактивных договоров")
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredContracts) { contract in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(contract.propertyTitle)
                            .font(.headline)

                        Text("Период: \(contract.checkIn) - \(contract.checkOut)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Создан: \(contract.createdAt)")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        Button("Открыть договор") {
                            let token = AuthService.shared.token ?? ""
                            if var components = URLComponents(string: contract.contractUrl) {
                                var items = components.queryItems ?? []
                                items.append(URLQueryItem(name: "token", value: token))
                                components.queryItems = items
                                selectedURL = components.url
                            } else {
                                selectedURL = URL(string: contract.contractUrl)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Мои договоры")
        .onAppear {
            loadContracts()
        }
        .refreshable {
            loadContracts()
        }
        .sheet(
            isPresented: Binding(
                get: { selectedURL != nil },
                set: { if !$0 { selectedURL = nil } }
            )
        ) {
            if let url = selectedURL {
                SafariView(url: url)
            }
        }
    }

    private func loadContracts() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let token = AuthService.shared.token ?? ""
                let data = try await APIClient.shared.getMyContracts(token: token)
                await MainActor.run {
                    contracts = data
                }
            } catch {
                print("LOAD CONTRACTS ERROR:", error)
            }
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct SettingsView: View {
    
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    
    var body: some View {
        Form {
            
            Section("Настройки приложения") {
                
                Toggle("Уведомления", isOn: $notificationsEnabled)
                
                Toggle("Темная тема", isOn: $darkModeEnabled)
            }
            
            Section("Информация") {
                Text("Версия приложения 1.0")
            }
        }
        .navigationTitle("Настройки")
    }
}

enum DocumentType: String, CaseIterable, Identifiable {
    case passport = "Паспорт"
    case idCard = "ID карта"
    case driver = "Водительские права"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .passport: return "passport"
        case .idCard: return "idCard"
        case .driver: return "driver"
        }
    }
}

struct UserVerificationView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var documentItem: PhotosPickerItem?
    @State private var documentImage: UIImage?

    @State private var showFaceCamera = false
    @State private var selfieImage: UIImage?
    @State private var documentType: DocumentType = .idCard

    @State private var step = 1
    @State private var resultText: String?
    @State private var isLoading = false
    @State private var verificationStatus: String? = nil
    @State private var isVerified = false
    var body: some View {

        ScrollView {

            VStack(spacing: 25) {

                Text("Верификация личности")
                    .font(.title2)
                    .bold()

                // 🔥 Сначала показываем статус

                if verificationStatus == nil {

                    ProgressView("Проверка статуса...")

                } else if verificationStatus == "approved" {

                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.green)

                        Text("Вы успешно верифицированы")
                            .font(.title3)
                            .bold()
                    }

                } else if verificationStatus == "pending" {

                    VStack(spacing: 16) {
                        ProgressView()

                        Text("⏳ Ваша верификация на проверке")
                            .font(.headline)

                        Text("Обычно это занимает некоторое время")
                            .foregroundColor(.gray)
                    }

                } else if verificationStatus == "rejected" {

                    VStack(spacing: 16) {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.red)

                        Text("Верификация отклонена")
                            .font(.title3)
                            .bold()

                        Text(resultText ?? "Причина отказа появится здесь")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                } else if verificationStatus == "none" || verificationStatus == "error" {

                    // 🔥 КРАСИВЫЙ ЭКРАН ДЛЯ НЕВЕРИФИЦИРОВАННЫХ

                    VStack(spacing: 20) {

                        Image(systemName: "person.crop.rectangle.badge.questionmark")
                            .font(.system(size: 70))
                            .foregroundColor(.blue)

                        Text("Вы еще не верифицированы")
                            .font(.title3)
                            .bold()

                        Text("Для бронирования жилья необходимо подтвердить личность")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button {
                            // 🔥 Переходим к процессу верификации
                            verificationStatus = "start"
                            step = 1
                        } label: {
                            Text("Пройти верификацию")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.top, 30)

                } else {

                    // 🔥 FLOW (когда можно проходить заново)

                    if step == 1 {

                        Picker("Тип документа", selection: $documentType) {
                            ForEach(DocumentType.allCases) { type in
                                Text(type.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)

                        PhotosPicker(selection: $documentItem, matching: .images) {

                            Text("Загрузить документ")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)

                        }

                        if let documentImage {

                            Image(uiImage: documentImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 220)

                        }

                        Button {

                            Task { await verifyDocument() }

                        } label: {

                            if isLoading { ProgressView() }
                            else { Text("Проверить документ") }

                        }
                        .disabled(documentImage == nil)

                    }

                    if step == 2 {

                        Text("Документ подтвержден ✅")

                        Button("Сделать селфи") {
                            showFaceCamera = true
                        }

                        if let selfieImage {

                            Image(uiImage: selfieImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 220)

                            Button("Отправить верификацию") {
                                let hasFace = detectFace(in: selfieImage)
                                if hasFace {
                                    uploadVerification()
                                } else {
                                    resultText = "❌ На селфи не обнаружено лицо"
                                }
                            }
                        }
                    }

                    if let resultText {

                        Text(resultText)
                            .padding()
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(10)

                        if verificationStatus == "rejected" {
                            Text("Если хотите, подайте заявку повторно после исправления данных.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                        }

                    }

                }

            }
            .padding()

        }
        .sheet(isPresented: $showFaceCamera) {
            FaceCameraView(capturedImage: $selfieImage)
        }
        .onAppear {
            checkVerificationStatus()
        }
        .onChange(of: documentItem) { newItem in

            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {

                    documentImage = img

                }
            }

        }

    }
    func detectFace(in image: UIImage) -> Bool {

        guard let cgImage = image.cgImage else { return false }

        let request = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage)

        do {
            try handler.perform([request])

            let results = request.results as? [VNFaceObservation] ?? []

            return !results.isEmpty

        } catch {

            print("Face detection error:", error)
            return false

        }

    }
    // OCR CHECK

    func verifyDocument() async {

        guard let image = documentImage,
              let cgImage = image.cgImage else { return }

        isLoading = true

        let request = VNRecognizeTextRequest { request, _ in

            DispatchQueue.main.async {

                isLoading = false

                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    resultText = "Не удалось распознать документ"
                    return
                }

                let text = results
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .lowercased()

                if analyzeDocument(text: text) {

                    resultText = "✅ Документ выглядит настоящим"
                    step = 2

                } else {

                    resultText = "❌ Документ не прошел проверку"

                }

            }

        }

        request.recognitionLanguages = ["ru-RU","en-US"]
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage)

        DispatchQueue.global().async {
            try? handler.perform([request])
        }

    }

    func analyzeDocument(text: String) -> Bool {

        switch documentType {

        case .passport:
            return text.contains("passport") || text.contains("паспорт")

        case .idCard:
            return text.contains("удостоверение") || text.contains("identity")

        case .driver:
            return text.contains("driver") || text.contains("license")

        }

    }

    func uploadVerification() {

        guard let documentImage, let selfieImage else { return }

        Task {

            do {

                let token = AuthService.shared.token ?? ""

                // 🔥 1. Проверяем статус
                let statusResponse = try await APIClient.shared.getVerificationStatus(token: token)

                if let status = statusResponse?.status {

                    switch status {

                    case "pending":
                        resultText = "⏳ Верификация уже на проверке"
                        return

                    case "approved":
                        resultText = "✅ Вы уже верифицированы"
                        isVerified = true
                        Task {
                            await auth.refreshCurrentUser()
                            NotificationCenter.default.post(name: NSNotification.Name("PROFILE_UPDATED"), object: nil)
                        }
                        return

                    case "rejected":
                        // можно отправлять заново
                        break

                    default:
                        break
                    }
                }

                // 🔥 2. Если можно — отправляем
                let result = try await APIClient.shared.uploadVerification(
                    documentType: documentType.rawValue,
                    documentImage: documentImage,
                    selfieImage: selfieImage,
                    token: token
                )

                // 🔥 FIX: сервер возвращает null → не декодим
                if let result {
                    verificationStatus = result.status
                    resultText = "✅ Верификация отправлена\nСтатус: \(result.status)"
                    if result.status == "approved" {
                        Task {
                            await auth.refreshCurrentUser()
                                NotificationCenter.default.post(name: NSNotification.Name("PROFILE_UPDATED"), object: nil)
                        }
                    }
                } else {
                    verificationStatus = "pending"
                    resultText = "✅ Верификация отправлена\nОжидайте проверки"
                }

            } catch {

                resultText = "❌ Ошибка: \(error.localizedDescription)"
                print("UPLOAD ERROR:", error)

            }
        }
    }
    func checkVerificationStatus() {

        Task {

            do {

                let token = AuthService.shared.token ?? ""

                let status = try await APIClient.shared.getVerificationStatus(token: token)

                // 👇 ВАЖНО: всегда обновляем состояние
                if let status {

                    verificationStatus = status.status

                    switch status.status {

                    case "approved":
                        isVerified = true
                        resultText = "✅ Вы успешно верифицированы"
                        Task {
                            await auth.refreshCurrentUser()
                            NotificationCenter.default.post(name: NSNotification.Name("PROFILE_UPDATED"), object: nil)
                        }

                    case "rejected":
                        let reason = (status.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        resultText = reason.isEmpty ? "❌ Отклонено без комментария" : "❌ Причина отказа: \(reason)"
                        verificationStatus = "rejected"

                    case "pending":
                        resultText = "⏳ На проверке"

                    default:
                        verificationStatus = "none"
                    }

                } else {

                    // 👇 ВОТ ЭТО ТЫ НЕ СДЕЛАЛ
                    verificationStatus = "none"
                    resultText = "Вы еще не проходили верификацию"

                }

            } catch {

                verificationStatus = "none"
                resultText = nil
                print("STATUS ERROR:", error)

            }
        }
    }

}

#Preview {
    ProfileView()
        .environmentObject(AuthViewModel())
}
