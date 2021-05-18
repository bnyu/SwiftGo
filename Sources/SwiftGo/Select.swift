import Foundation

public enum SelectCase<T> {
    case send(data: T, _ block: () -> ())
    case receive(_ block: (_ data: T) -> ())
}

public typealias Select<T> = (channel: Chan<T>, case: SelectCase<T>)


extension Chan {
    public func send(data: T, _ block: @escaping () -> ()) -> Select<T> {
        (self, .send(data: data, block))
    }

    public func receive(_ block: @escaping (T) -> ()) -> Select<T> {
        (self, .receive(block))
    }
}


func randIndex(_ rands: inout Rand, count: Int) -> [Int] {
    var indices = Array(repeating: 0, count: count)
    for i in 1..<count {
        let x = Int(rands.fast(n: UInt32(i + 1)))
        indices[i] = indices[x]
        indices[x] = i
    }
    return indices
}

extension Goroutine {

    public func select<T>(_ c: Select<T>) {
        let ch = c.channel
        switch c.case {
        case .send(let data, let block):
            send(to: ch, data: data)
            block()
        case .receive(let block):
            block(receive(from: ch))
        }
    }

    public func select<T>(_ c: Select<T>, default closure: @autoclosure () -> ()) {
        let ch = c.channel
        switch c.case {
        case .send(let data, let block):
            if send(ch: ch, data: data) {
                block()
            } else {
                closure()
            }
        case .receive(let block):
            if let data = receive(ch: ch) {
                block(data)
            } else {
                closure()
            }
        }
    }

}
