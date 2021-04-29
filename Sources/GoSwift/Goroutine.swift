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

    var execute: DispatchWorkItem!

    init(closure: @escaping (Goroutine) -> ()) {
        execute = DispatchWorkItem(block: { closure(self) })
    }

    func start() {
        DispatchQueue.global().async(execute: execute)
    }

    func suspend() {
        execute.wait()
    }

    func resume() {
        execute.perform()
    }

    private func select(_ cases: [Select<Any>], _ block: (() -> ())?) {
        let indices = cases.indices

        var matched = false
        loop: for i in indices {
            let c = cases[i]
            switch c {
            case .send(let ch, let data, let block):
                if ch.send(data) {
                    defer {
                        block()
                    }
                    matched = true
                    break loop
                }
            case .receive(let ch, let block):
                let (data, ok) = ch.receive()
                if ok {
                    defer {
                        block(data)
                    }
                    matched = true
                    break loop
                }
            }
        }

        if matched {
            return
        }
        if let block = block {
            block()
            return
        }

        // waiting on all cases
        var waitCases: [GoCase<Any>?] = Array(repeating: nil, count: indices.count)
        for i in indices {
            let c = cases[i]
            switch c {
            case .send(let ch, let data, _):
                let gc = GoCase(self, index: i, data: data)
                waitCases[i] = gc
                ch.sendWait.enqueue(gc)
            case .receive(let ch, _):
                let gc = GoCase<Any>(self, index: i)
                waitCases[i] = gc
                ch.recvWait.enqueue(gc)
            }
        }
        suspend()
        // resumed by another goroutine
        // remove other waiting
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

        let c = cases[selectIndex]
        switch c {
        case .send(_, _, let block):
            block()
        case .receive(_, let block):
            block(message)
            message = nil
        }
    }

    public func select(cases: Select<Any>...) {
        select(cases, nil)
    }

    public func select(cases: Select<Any>..., default block: @escaping () -> ()) {
        select(cases, block)
    }

}


public enum Select<T> {
    case send(ch: Chan<T>, data: T, block: () -> ())
    case receive(ch: Chan<T>, block: (_ data: T?) -> ())
}

public func go(_ closure: @escaping (Goroutine) -> ()) {
    Goroutine(closure: closure).start()
}
