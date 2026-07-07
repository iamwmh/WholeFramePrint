//
//  WholeFramePrintApp.swift
//  WholeFramePrint
//

import SwiftUI

@main
struct WholeFramePrintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
