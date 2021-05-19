import Foundation

public enum SelectCase<T> {
    case send(data: T, _ block: () -> ())
    case receive(_ block: (_ data: T) -> ())
}

public struct Case<T> {
    let channel: Chan<T>
    let select: SelectCase<T>

    public init(_ ch: Chan<T>, _ c: SelectCase<T>) {
        channel = ch
        select = c
    }
}

extension Chan {
    public func send(data: T, _ block: @escaping () -> ()) -> Case<T> {
        Case(self, .send(data: data, block))
    }

    public func receive(_ block: @escaping (T) -> ()) -> Case<T> {
        Case(self, .receive(block))
    }
}


extension Goroutine {

    public func select<T>(_ c: Case<T>) {
        let ch = c.channel
        switch c.select {
        case .send(let data, let block):
            send(to: ch, data: data)
            block()
        case .receive(let block):
            block(receive(from: ch))
        }
    }

    public func select<T>(_ c: Case<T>, default closure: @autoclosure () -> ()) {
        let ch = c.channel
        switch c.select {
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
