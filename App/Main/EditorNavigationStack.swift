import SwiftUI

/// Present save/import errors from the active modal, not from the root view
/// underneath it. The root still handles errors when no editor is presented.
struct EditorNavigationStack<Content: View>: View {
    @EnvironmentObject private var store: TrackerStore
    @State private var editorID = UUID()
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        NavigationStack { content }
            .onAppear { store.registerEditor(editorID) }
            .onDisappear { store.unregisterEditor(editorID) }
            .alert("Changes were not saved", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "Please try again.") }
    }
}
