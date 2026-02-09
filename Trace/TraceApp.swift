import SwiftUI
import SwiftData

@main
struct TraceApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Tutorial.self,      // 注册 Tutorial
            TraceStepModel.self // 注册 StepModel
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
