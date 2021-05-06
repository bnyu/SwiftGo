//
// Created by xuyue on 2021/4/24.
//

import Foundation
import Dispatch

//import Atomics

final class GoCase<T> {
    weak var prev: GoCase?
    var next: GoCase?
    var removed = false

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
            let x = Int(fastRand(n: UInt32(i + 1)))
            indices[i] = indices[x]
            indices[x] = i
        }
        return indices
    }

    // XorShift
    private func fastRand(n: UInt32) -> UInt32 {
        rands.0 ^= rands.0 << 17
        rands.0 = rands.0 ^ rands.1 ^ rands.0 >> 7 ^ rands.1 >> 16
        rands = (rands.1, rands.0)
        return UInt32((UInt64(rands.0 &+ rands.1) &* UInt64(n)) >> 32)
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

        // random
        let pullOrder = randIndex(count: cases.count)
        // avoid deadlock
        let lockOrder = cases.indices.sorted(by: { i, j in cases[i].locker.hash > cases[j].locker.hash })
        lockAll(cases, orders: lockOrder)

        // reset
        selectIndex = -1

        var closure: (() -> ())?
        loop: for i in pullOrder {
            let c = cases[i]
            switch c {
            case .send(let ch, let data, let block):
                if ch.send(data) {
                    closure = block
                    break loop
                }
            case .receive(let ch, let block):
                if let data = ch.receive() {
                    closure = {
                        block(data)
                    }
                    break loop
                }
            }
        }

        if let closure = closure {
            unlockAll(cases, orders: lockOrder)
            closure()
            return
        } else if let block = block {
            unlockAll(cases, orders: lockOrder)
            block()
            return
        }

        // waiting on all cases
        var waitCases: [GoCase<T>?] = Array(repeating: nil, count: pullOrder.count)
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

        unlockAll(cases, orders: lockOrder)
        suspend()
        // resumed by another goroutine
        // remove other waiting
        for i in lockOrder {
            let w = waitCases[i]!
            if w.removed {
                continue
            }
            let c = cases[i]
            c.locker.lock()
            switch c {
            case .send(let ch, _, _):
                ch.sendWait.remove(w)
            case .receive(let ch, _):
                ch.recvWait.remove(w)
            }
            c.locker.unlock()
        }

        let c = cases[selectIndex]
        let w = waitCases[selectIndex]!
        switch c {
        case .send(_, _, let block):
            block()
        case .receive(_, let block):
            if let data = w.data {
                block(data)
            } else {
                fatalError("received nil")
            }
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
