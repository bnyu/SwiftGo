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


// single select case
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


// todo: need variadic generics to refactor this
protocol AnyWait: AnyObject {
    var dequeued: Bool { get }
    var anyData: Any! { get }
}

extension GoCase: AnyWait {
    var anyData: Any! {
        data
    }
}

protocol AnyChannel: AnyObject {
    var address: Int { get } //memory address
    func getLocker() -> NSLocking
    func trySend(_ data: Any) -> Bool
    func tryRecv() -> Any?
}

extension Chan: AnyChannel {
    func getLocker() -> NSLocking {
        locker
    }

    var address: Int {
        locker.hash
    }

    func trySend(_ data: Any) -> Bool {
        send(data as! T)
    }

    func tryRecv() -> Any? {
        receive()
    }
}

protocol AnySelect {
    var anyChannel: AnyChannel { get } // can not define name with 'channel' ...
    func trySelect() -> (() -> ())?
    func beSelected(_: AnyWait) -> () -> ()
    func enWait(_ g: Goroutine, index: Int) -> AnyWait
    func deWait(_: AnyWait)
}


extension Case: AnySelect {
    var anyChannel: AnyChannel {
        channel
    }

    func trySelect() -> (() -> ())? {
        switch select {
        case .send(let data, let block):
            if anyChannel.trySend(data) {
                return block
            }
        case .receive(let block):
            if let data = anyChannel.tryRecv() {
                return {
                    block(data as! T)
                }
            }
        }
        return nil
    }

    func beSelected(_ wait: AnyWait) -> () -> () {
        switch select {
        case .send(_, let block):
            return block
        case .receive(let block):
            let data = wait.anyData
            return {
                block(data as! T)
            }
        }
    }

    func enWait(_ g: Goroutine, index: Int) -> AnyWait {
        let w: GoCase<T>
        switch select {
        case .send(let data, _):
            w = GoCase<T>(g, index: index, data: data)
            channel.sendWait.enqueue(w)
        case .receive:
            w = GoCase<T>(g, index: index)
            channel.recvWait.enqueue(w)
        }
        return w
    }

    func deWait(_ wait: AnyWait) {
        switch select {
        case .send:
            channel.sendWait.remove(wait as! GoCase<T>)
        case .receive:
            channel.recvWait.remove(wait as! GoCase<T>)
        }
    }
}

// multi select cases
extension Goroutine {

    func select<U: AnySelect>(_ cases: U...) {
        select(cases, nonBlock: false)()
    }

    func select<U: AnySelect>(_ cases: U..., default closure: @autoclosure () -> ()) {
        if let block = select(cases, nonBlock: true) {
            block()
        } else {
            closure()
        }
    }


    private func randIndex(count: Int) -> [Int] {
        var indices = Array(repeating: 0, count: count)
        for i in 1..<count {
            let x = Int(rands.fast(n: UInt32(i + 1)))
            indices[i] = indices[x]
            indices[x] = i
        }
        return indices
    }

    private func lockAll(_ cases: [AnySelect], orders: [Int]) {
        var p: AnyChannel?
        for i in orders {
            let l = cases[i].anyChannel
            if p !== l {
                l.getLocker().lock()
            }
            p = l
        }
    }

    private func unlockAll(_ cases: [AnySelect], orders: [Int]) {
        var p: AnyChannel?
        for i in orders {
            let l = cases[i].anyChannel
            if p !== l {
                l.getLocker().unlock()
            }
            p = l
        }
    }

    private func select(_ cases: [AnySelect], nonBlock: Bool = false) -> (() -> ())! {
        if cases.isEmpty {
            fatalError("select on empty case") // no need suspend forever
        } else if cases.count > UInt16.max {
            fatalError("select on too many cases")
        }

        // random indices
        let pullOrder = randIndex(count: cases.count)
        // avoid deadlock
        let lockOrder = cases.indices.sorted(by: { i, j in cases[i].anyChannel.address < cases[j].anyChannel.address })
        // maybe stores with cases? so T can be matched
        var waitCases: [AnyWait]
        // lock all in this block
        do {
            lockAll(cases, orders: lockOrder)
            defer {
                unlockAll(cases, orders: lockOrder)
            }

            for i in pullOrder {
                if let closure = cases[i].trySelect() {
                    return closure
                }
            }

            if nonBlock {
                return nil
            }

            // waiting on all cases
            waitCases = pullOrder.map { i in
                cases[i].enWait(self, index: i)
            }

            // reset, to prepare to be resumed
            selectIndex = -1
        }

        suspend()
        // resumed by another goroutine. it may call resume before than this call suspend(it's ok)
        // may multi cases dequeued but only one can call resume. need remove other waiting
        for i in lockOrder {
            let w = waitCases[i]
            if w.dequeued {
                continue
            }
            let c = cases[i]
            let locker = c.anyChannel.getLocker()
            locker.lock()
            defer {
                locker.unlock()
            }
            if w.dequeued {
                continue
            }
            c.deWait(w)
        }

        let c = cases[selectIndex]
        let w = waitCases[selectIndex]
        return c.beSelected(w)
    }
}
