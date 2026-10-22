import SwiftData

extension PersistentModel {
    /// Sets `field` to `value` only if it differs, so a model whose values are unchanged stays
    /// clean and saves nothing.
    func update<Value: Equatable>(_ field: ReferenceWritableKeyPath<Self, Value>, to value: Value) {
        if self[keyPath: field] != value {
            self[keyPath: field] = value
        }
    }
}
