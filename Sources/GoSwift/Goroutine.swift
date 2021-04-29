//
// Created by xuyue on 2021/4/24.
//

import Foundation
import Dispatch

public class Goroutine {
    var message: Any?
    var selectCases: [Select<Any>] = []
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

    func suspend(cases: [Select<Any>]) {
        selectCases = cases
        suspend()
    }

    func resume() {
        execute.perform()
    }

    func resume(index: Int) {
        selectIndex = index
        resume()
    }

    private func removeAllWaiting() {
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
        for i in indices {
            let c = cases[i]
            switch c {
            case .send(let ch, let data, _):
                ch.sendWaitEnqueue(self, index: i, data: data)
            case .receive(let ch, _):
                ch.recvWaitEnqueue(self, index: i)
            }
        }
        suspend(cases: cases)
        // resumed by another goroutine
        // remove waiting
        removeAllWaiting()
        message = nil
        selectCases = []

        let c = cases[selectIndex]
        switch c {
        case .send(_, _, let block):
            block()
        case .receive(_, let block):
            block(message)
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
