// `@Published` for a class that declares its own `objectWillChange`. Combine's default getter
// reflects over every stored property (a conformance lookup per field type, slow on first open),
// and `@Published` does not send a declared publisher, so these classes use this wrapper instead.

import Combine

/// Sends the enclosing object's own `objectWillChange` before each set, then the new value on `$name`.
/// `$name` replays the current value on subscribe and emits while the old value is still stored, as `@Published` does.
/// Not synchronized, like `@Published`: set it from the enclosing class's own isolation (the main actor for views).
@propertyWrapper
struct DirectPublished<Value> {
    private final class Storage {
        var value: Value
        var subject: CurrentValueSubject<Value, Never>?
        init(_ value: Value) { self.value = value }
    }

    private let storage: Storage

    init(wrappedValue: Value) { storage = Storage(wrappedValue) }

    @available(*, unavailable, message: "@DirectPublished is only available on properties of an ObservableObject class")
    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }

    var projectedValue: AnyPublisher<Value, Never> {
        if let subject = storage.subject { return subject.eraseToAnyPublisher() }
        let subject = CurrentValueSubject<Value, Never>(storage.value)
        storage.subject = subject
        return subject.eraseToAnyPublisher()
    }

    static subscript<Enclosing: ObservableObject>(
        _enclosingInstance object: Enclosing,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<Enclosing, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Self>
    ) -> Value where Enclosing.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { object[keyPath: storageKeyPath].storage.value }
        set {
            object.objectWillChange.send()
            let storage = object[keyPath: storageKeyPath].storage
            storage.subject?.send(newValue)
            storage.value = newValue
        }
    }
}
