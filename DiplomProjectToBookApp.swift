//
//  DiplomProjectToBookApp.swift
//  DiplomProjectToBook
//
//  Created by Sanzhar  Zhabagin  on 03.03.2026.
//

import SwiftUI

@main
struct DiplomProjectToBookApp: App {
    @StateObject private var auth = AuthViewModel()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    if auth.user.isOwner {
                        AdminView()
                    } else {
                        MainTabView()
                    }
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
        }
    }
}
