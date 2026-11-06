// Values kept per presentation id for analytics stamping, bounded so a long session cannot grow it
// without limit. The least recently written presentation goes first, so a live sheet is never dropped.

import Foundation

struct PresentationMap<Value: Sendable>: Sendable {
    private var values: [String: Value] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    subscript(presentationId: String) -> Value? {
        get { values[presentationId] }
        set {
            guard let newValue else {
                values.removeValue(forKey: presentationId)
                order.removeAll { $0 == presentationId }
                return
            }
            if values[presentationId] != nil {
                order.removeAll { $0 == presentationId }
            }
            order.append(presentationId)
            if order.count > capacity {
                values.removeValue(forKey: order.removeFirst())
            }
            values[presentationId] = newValue
        }
    }
}
