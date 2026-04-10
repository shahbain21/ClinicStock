//
//  RootView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/6/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        Group {
            if authManager.isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    Text("ClinicStock")
                        .font(.largeTitle.bold())
                    ProgressView("Loading...")
                }
            } else if authManager.isAuthenticated {
                CatalogSearchView()
            } else {
                TestLoginView()
            }
            
        }
    }
}

