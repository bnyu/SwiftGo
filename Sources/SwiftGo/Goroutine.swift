//
// Created by xuyue on 2021/4/24.
//

import Foundation
import Dispatch

//import Atomics

final class GoCase<T> {
    weak var prev: GoCase?
    var next: GoCase?
    var dequeued = false

    let g: Goroutine
    let index: Int
    var data: T?

    init(_ g: Goroutine, index: Int = 0) {
        self.g = g
        self.index = index
    }

    convenience init(_ g: Goroutine, index: Int = 0, data: T) {
        self.init(g, index: index)
        self.data = data
    }
}

public final class Goroutine {
    private var selectIndex = -1
    private let locker = NSLock() //todo temp

    private var rands = (UInt32(0), UInt32(0))

    private let semaphore: DispatchSemaphore
    private var execution: DispatchWorkItem!

    init(closure: @escaping (Goroutine) -> ()) {
        semaphore = DispatchSemaphore(value: 0)
        execution = DispatchWorkItem(block: { closure(self) })
    }

    func start() {
        initRand(&rands)

        let queue = DispatchQueue.global()
        semaphore.setTarget(queue: queue)
        semaphore.activate()
        queue.async(execute: execution)
    }

    func suspend() {
        semaphore.wait()
    }

    func resume() {
        semaphore.signal()
    }

    func trySelect(index: Int) -> Bool {
        if selectIndex >= 0 {
            return false
        }
        //todo use lock temp
        locker.lock()
        defer {
            locker.unlock()
        }
        if selectIndex >= 0 {
            return false
        }
        selectIndex = index
        return true
    }

    private func randIndex(count: Int) -> [Int] {
        var indices = Array(repeating: 0, count: count)
        for i in 1..<count {
            let x = Int(fastRand(&rands, n: UInt32(i + 1)))
            indices[i] = indices[x]
            indices[x] = i
        }
        return indices
    }

    private func lockAll<T>(_ cases: [Select<T>], orders: [Int]) {
        var p: NSLock?
        for i in orders {
            let l = cases[i].locker
            if p !== l {
                l.lock()
            }
            p = l
        }
    }

    private func unlockAll<T>(_ cases: [Select<T>], orders: [Int]) {
        var p: NSLock?
        for i in orders {
            let l = cases[i].locker
            if p !== l {
                l.unlock()
            }
            p = l
        }
    }

    public func send<T>(to ch: Chan<T>, data: T) {
        do {
            ch.locker.lock()
            defer {
                ch.locker.unlock()
            }
            if ch.send(data) {
                return
            }
            let gc = GoCase(self, index: 0, data: data)
            ch.sendWait.enqueue(gc)
            selectIndex = -1
        }
        suspend()
    }

    public func receive<T>(from ch: Chan<T>) -> T {
        let gc: GoCase<T>
        do {
            ch.locker.lock()
            defer {
                ch.locker.unlock()
            }
            if let data = ch.receive() {
                return data
            }
            gc = GoCase(self, index: 0)
            ch.recvWait.enqueue(gc)
            selectIndex = -1
        }
        suspend()
        return gc.data!
    }

    private func send<T>(ch: Chan<T>, data: T) -> Bool {
        ch.locker.lock()
        defer {
            ch.locker.unlock()
        }
        if ch.send(data) {
            return true
        }
        return false
    }

    private func receive<T>(ch: Chan<T>) -> T? {
        ch.locker.lock()
        defer {
            ch.locker.unlock()
        }
        if let data = ch.receive() {
            return data
        }
        return nil
    }

    // need variadic generics?
    private func select<T>(_ cases: [Select<T>], nonBlock: Bool = false) -> (() -> ())! {
        if cases.isEmpty {
            fatalError("select on empty case") // no need suspend forever
        } else if cases.count > UInt16.max {
            fatalError("select on too many cases")
        }

        // random indices
        let pullOrder = randIndex(count: cases.count)
        // avoid deadlock
        let lockOrder = cases.indices.sorted(by: { i, j in cases[i].locker.hash > cases[j].locker.hash })
        // maybe stores with cases? so T can be matched
        var waitCases: [GoCase<T>?]! = nil
        // lock all in this block
        do {
            lockAll(cases, orders: lockOrder)
            defer {
                unlockAll(cases, orders: lockOrder)
            }

            for i in pullOrder {
                let c = cases[i]
                switch c {
                case .send(let ch, let data, let block):
                    if ch.send(data) {
                        return block
                    }
                case .receive(let ch, let block):
                    if let data = ch.receive() {
                        return {
                            block(data)
                        }
                    }
                }
            }

            if nonBlock {
                return nil
            }

            // waiting on all cases
            waitCases = Array(repeating: nil, count: pullOrder.count)
            for i in pullOrder {
                let c = cases[i]
                switch c {
                case .send(let ch, let data, _):
                    let gc = GoCase(self, index: i, data: data)
                    waitCases[i] = gc
                    ch.sendWait.enqueue(gc)
                case .receive(let ch, _):
                    let gc = GoCase<T>(self, index: i)
                    waitCases[i] = gc
                    ch.recvWait.enqueue(gc)
                }
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
            switch c {
            case .send(let ch, _, _):
                ch.sendWait.remove(w)
            case .receive(let ch, _):
                ch.recvWait.remove(w)
            }
        }

        let c = cases[selectIndex]
        let w = waitCases[selectIndex]!
        switch c {
        case .send(_, _, let block):
            return block
        case .receive(_, let block):
            guard let data = w.data else {
                fatalError("received nil")
            }
            return {
                block(data)
            }
        }
    }

    public func select<T>(cases: Select<T>...) {
        select(cases, nonBlock: false)()
    }

    public func select<T>(cases: Select<T>..., default closure: @autoclosure () -> ()) {
        if let closure = select(cases, nonBlock: true) {
            closure()
        } else {
            closure()
        }
    }

    public func select<T>(_ c: Select<T>) {
        switch c {
        case .send(let ch, let data, let block):
            send(to: ch, data: data)
            block()
        case .receive(let ch, let block):
            block(receive(from: ch))
        }
    }

    public func select<T>(_ c: Select<T>, default closure: @autoclosure () -> ()) {
        switch c {
        case .send(let ch, let data, let block):
            if send(ch: ch, data: data) {
                block()
            } else {
                closure()
            }
        case .receive(let ch, let block):
            if let data = receive(ch: ch) {
                block(data)
            } else {
                closure()
            }
        }
    }

    public func sleep(milliseconds: Int) {
        _ = semaphore.wait(timeout: DispatchTime.now() + DispatchTimeInterval.milliseconds(milliseconds))
    }

}


@inlinable func initRand(_ rands: inout (UInt32, UInt32)) {
    func memoryAddress(_ p: UnsafeRawPointer) -> UInt {
        UInt(bitPattern: p)
    }

    let p = memoryAddress(&rands)
    rands.0 = UInt32(p >> 32)
    rands.1 = UInt32(p & (UInt.max >> 32))
    if rands.0 | rands.1 == 0 {
        rands.1 = UInt32(p == 0 ? 1 : p)
    }
}

// XorShift(copied from golang), see below
// https://www.jstatsoft.org/article/view/v008i14/xorshift.pdf
// https://lemire.me/blog/2016/06/27/a-fast-alternative-to-the-modulo-reduction/
@inlinable func fastRand(_ rands: inout (UInt32, UInt32), n: UInt32) -> UInt32 {
    rands.0 ^= rands.0 << 17
    rands.0 = rands.0 ^ rands.1 ^ rands.0 >> 7 ^ rands.1 >> 16
    (rands.0, rands.1) = (rands.1, rands.0)
    return UInt32((UInt64(rands.0 &+ rands.1) &* UInt64(n)) >> 32)
}

public enum Select<T> {
    case send(ch: Chan<T>, data: T, block: @autoclosure () -> ())
    case receive(ch: Chan<T>, block: (_ data: T) -> ())

    var locker: NSLock {
        switch self {
        case .send(let ch, _, _):
            return ch.locker
        case .receive(let ch, _):
            return ch.locker
        }
    }
}

public func go(_ closure: @escaping (Goroutine) -> ()) {
    Goroutine(closure: closure).start()
}
