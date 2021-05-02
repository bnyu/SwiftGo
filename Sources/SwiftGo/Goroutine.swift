//
// Created by xuyue on 2021/4/24.
//

import Foundation
import Dispatch

final class GoCase<T> {
    weak var prev: GoCase?
    var next: GoCase?

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
    var message: Any?
    var selectIndex = -1

    private var rands = (UInt32(0), UInt32(0))

    private let semaphore: DispatchSemaphore
    private var execution: DispatchWorkItem!

    init(closure: @escaping (Goroutine) -> ()) {
        semaphore = DispatchSemaphore(value: 0)
        execution = DispatchWorkItem(block: { closure(self) })
    }

    func start() {
        let prt = memoryAddress(&rands)
        rands.0 = UInt32(prt >> 32)
        rands.1 = UInt32(prt & (UInt.max >> 32))
        if rands.0 == 0 { //32bit machine
            rands.0 = UInt32(prt >> 16)
            rands.1 = UInt32((prt << 16) >> 16)
        }

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

    private func randIndex(count: Int) -> [Int] {
        var indices = Array(repeating: 0, count: count)
        for i in 1..<count {
            let n = Int(fastRand(n: UInt32(i + 1)))
            indices[n] = indices[i]
            indices[i] = n
        }
        return indices
    }

    // XorShift
    private func fastRand(n: UInt32) -> UInt32 {
        rands.0 ^= rands.0 << 17
        rands.0 = rands.0 ^ rands.1 ^ rands.0 >> 7 ^ rands.1 >> 16
        rands = (rands.1, rands.0)
        return UInt32((UInt64(rands.0 + rands.1) &* UInt64(n)) >> 32)
    }

    private func lockAll(list: [NSLock]) {
        var p: NSLock?
        for l in list {
            if p !== l {
                l.lock()
            }
            p = l
        }
    }

    private func unlockAll(list: [NSLock]) {
        var p: NSLock?
        for l in list {
            if p !== l {
                l.unlock()
            }
            p = l
        }
    }

    // need variadic generics?
    private func select<T>(_ cases: [Select<T>], _ block: (() -> ())?) {
        if cases.isEmpty {
            if let block = block {
                block()
                return
            }
            // block forever
            suspend()
            return
        }

        var lockers = cases.map { c in
            c.locker()
        }
        // avoid deadlock
        lockers.sort(by: { l1, l2 in l1.hash > l2.hash })
        lockAll(list: lockers)

        let indices = randIndex(count: cases.count)

        var closure: (() -> ())?
        loop: for i in indices {
            let c = cases[i]
            switch c {
            case .send(let ch, let data, let block):
                if ch.send(data) {
                    closure = block
                    break loop
                }
            case .receive(let ch, let block):
                let (data, ok) = ch.receive()
                if ok {
                    closure = {
                        block(data)
                    }
                    break loop
                }
            }
        }

        if let closure = closure {
            unlockAll(list: lockers)
            closure()
            return
        } else if let block = block {
            unlockAll(list: lockers)
            block()
            return
        }

        // waiting on all cases
        var waitCases: [GoCase<T>?] = Array(repeating: nil, count: indices.count)
        for i in indices {
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

        unlockAll(list: lockers)
        suspend()
        // resumed by another goroutine
        // remove other waiting
        lockAll(list: lockers)
        for i in indices {
            if i != selectIndex {
                let c = cases[i]
                let w = waitCases[i]!
                switch c {
                case .send(let ch, _, _):
                    ch.sendWait.remove(w)
                case .receive(let ch, _):
                    ch.recvWait.remove(w)
                }
            }
        }
        unlockAll(list: lockers)

        let c = cases[selectIndex]
        switch c {
        case .send(_, _, let block):
            block()
        case .receive(_, let block):
            block(message as? T)
            message = nil
        }
    }

    public func select<T>(cases: Select<T>...) {
        select(cases, nil)
    }

    public func select<T>(cases: Select<T>..., default block: @escaping () -> ()) {
        select(cases, block)
    }

    public func sleep(milliseconds: Int) {
        _ = semaphore.wait(timeout: DispatchTime.now() + DispatchTimeInterval.milliseconds(milliseconds))
    }

}

@inlinable func memoryAddress(_ p: UnsafeRawPointer) -> UInt {
    UInt(bitPattern: p)
}

public enum Select<T> {
    case send(ch: Chan<T>, data: T, block: @autoclosure () -> ())
    case receive(ch: Chan<T>, block: (_ data: T?) -> ())

    fileprivate func locker() -> NSLock {
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
