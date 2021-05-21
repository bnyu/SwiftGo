import Foundation

public enum SelectCase<T> {
    case send(data: T, _ block: () -> () = {
    })
    case receive(_ block: (_ data: T) -> () = { _ in
    })
}

//public struct Case<T> {
//    let channel: Chan<T>
//    let select: SelectCase<T>
//
//    public init(_ ch: Chan<T>, _ c: SelectCase<T>) {
//        channel = ch
//        select = c
//    }
//}

//// single select case
//extension Goroutine {
//
//    public func select<T>(_ c: Case<T>) {
//        let ch = c.channel
//        switch c.select {
//        case .send(let data, let block):
//            send(to: ch, data: data)
//            block()
//        case .receive(let block):
//            block(receive(from: ch))
//        }
//    }
//
//    public func select<T>(_ c: Case<T>, default closure: @autoclosure () -> ()) {
//        let ch = c.channel
//        switch c.select {
//        case .send(let data, let block):
//            if send(ch: ch, data: data) {
//                block()
//            } else {
//                closure()
//            }
//        case .receive(let block):
//            if let data = receive(ch: ch) {
//                block(data)
//            } else {
//                closure()
//            }
//        }
//    }
//
//}

// todo: type erased for now (current swift 5.4)
public typealias Case = AnyCase


protocol AnyGoCase {
    var dequeued: Bool { get }
}

extension GoCase: AnyGoCase {
}

public struct AnyCase {
    enum SelectKind {
        case send
        case receive
    }

    let anyChannel: Any
    let selectKind: SelectKind

    let locker: AnyObject & NSLocking
    let hash: Int

    let trySelect: () -> (() -> ())?
    let beSelected: (AnyGoCase) -> () -> ()

    let enWait: (Goroutine, Int) -> AnyGoCase
    let deWait: (AnyGoCase) -> ()


    public init<T>(_ ch: Chan<T>, _ c: SelectCase<T>) {
        anyChannel = ch
        locker = ch.locker
        hash = ch.locker.hash
        switch c {
        case .send(let data, let block):
            selectKind = .send
            enWait = { g, i in
                let gc: GoCase<T> = GoCase(g, index: i, data: data)
                ch.sendWait.enqueue(gc)
                return gc
            }
            deWait = { gc in
                ch.sendWait.remove(gc as! GoCase<T>)
            }
            trySelect = {
                if ch.send(data) {
                    return block
                }
                return nil
            }
            beSelected = { _ in
                block
            }
        case .receive(let block):
            selectKind = .receive
            enWait = { g, i in
                let gc: GoCase<T> = GoCase(g, index: i)
                ch.recvWait.enqueue(gc)
                return gc
            }
            deWait = { gc in
                ch.recvWait.remove(gc as! GoCase<T>)
            }
            trySelect = {
                if let data = ch.receive() {
                    return {
                        block(data)
                    }
                }
                return nil
            }
            beSelected = { gc in
                {
                    block((gc as! GoCase<T>).data!)
                }
            }
        }
    }
}

// multi select cases
extension Goroutine {

    public func select(_ cases: AnyCase...) {
        select(cases, nonBlock: false)()
    }

    public func select(_ cases: AnyCase..., default closure: () -> ()) {
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

    private func lockAll(_ cases: [AnyCase], orders: [Int]) {
        var p: (AnyObject & NSLocking)?
        for i in orders {
            let l = cases[i].locker
            if p !== l {
                l.lock()
                p = l
            }
        }
    }

    private func unlockAll(_ cases: [AnyCase], orders: [Int]) {
        var p: (AnyObject & NSLocking)?
        for i in orders {
            let l = cases[i].locker
            if p !== l {
                l.unlock()
                p = l
            }
        }
    }

    private func select(_ cases: [AnyCase], nonBlock: Bool = false) -> (() -> ())! {
        if cases.isEmpty {
            fatalError("select on empty case") // no need suspend forever
        } else if cases.count > UInt16.max {
            fatalError("select on too many cases")
        }

        // random indices
        let pullOrder = randIndex(count: cases.count)
        // avoid deadlock
        let lockOrder = cases.indices.sorted(by: { i, j in cases[i].hash < cases[j].hash })
        // maybe stores with cases? so T can be matched
        var waitCases: [AnyGoCase?]
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
            waitCases = [AnyGoCase?].init(repeating: nil, count: cases.count)
            for i in pullOrder {
                waitCases[i] = cases[i].enWait(self, i)
            }

            // reset, to prepare to be resumed
            selectIndex = -1
        }

        suspend()
        // resumed by another goroutine. it may call resume before than this call suspend(it's ok)
        // may multi cases dequeued but only one can call resume. need remove other waiting
        for i in lockOrder {
            let w = waitCases[i]!
            if w.dequeued {
                continue
            }
            let c = cases[i]
            c.locker.lock()
            defer {
                c.locker.unlock()
            }
            if w.dequeued {
                continue
            }
            c.deWait(w)
        }

        let c = cases[selectIndex]
        let w = waitCases[selectIndex]!
        return c.beSelected(w)
    }
}
