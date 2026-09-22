import SwiftUI

/// Reports a failed collection write as an alert offering a retry.
///
/// A refresh that fails leaves the cache browsable and belongs in a status line. A write does not:
/// the user asked for it, is waiting on the outcome, and the copy is either in the collection or it
/// is not. That earns an interruption, and the interruption earns its keep by carrying the retry.
struct CollectionFailureAlert: ViewModifier {
    let editor: CollectionEditor?

    func body(content: Content) -> some View {
        content.alert(
            editor?.failure?.title ?? "",
            isPresented: Binding(
                get: { editor?.failure != nil },
                set: { if !$0 { editor?.clearFailure() } }
            ),
            presenting: editor?.failure
        ) { failure in
            if let retry = failure.retry {
                Button("Try Again") {
                    editor?.clearFailure()
                    Task { await retry() }
                }
            }
            Button(failure.retry == nil ? "OK" : "Cancel", role: .cancel) {
                editor?.clearFailure()
            }
        } message: { failure in
            Text(failure.message)
        }
    }
}

extension View {
    func collectionFailureAlert(_ editor: CollectionEditor?) -> some View {
        modifier(CollectionFailureAlert(editor: editor))
    }
}
