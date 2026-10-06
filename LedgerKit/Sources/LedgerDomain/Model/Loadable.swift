/// A screen's load state, modelled explicitly instead of with an optional that means "not loaded
/// yet" (engineering-standards §5): a store holds a `Loadable<Model>`, and its view draws one of
/// the four cases.
public enum Loadable<T> {
    /// Nothing has been asked for yet.
    case idle
    /// The value has been asked for and has not arrived.
    case loading
    /// The value arrived.
    case loaded(T)
    /// Loading failed. A store maps the error to what the screen says; a raw error is never shown
    /// (engineering-standards §8).
    case failed(any Error)
}

extension Loadable: Sendable where T: Sendable {}
