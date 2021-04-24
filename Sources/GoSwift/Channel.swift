//
// Created by xuyue on 2021/4/24.
//

import Foundation

prefix operator <-
infix operator <-

protocol Channel: SendChannel, ReceiveChannel {
}

protocol SendChannel {
    associatedtype Element
    static func <-(ch: Self, data: Element)
}

protocol ReceiveChannel {
    associatedtype Element
    static prefix func <-(ch: Self) -> Element?
}

final class Linked<U> {
    weak var prev: Linked<U>?
    var next: Linked<U>?
    let value: U

    init(_ value: U) {
        self.value = value
    }
}

public final class Chan<T> {

    struct GoCase {
        let g: Goroutine
        let caseIndex: Int
    }

    struct SendCase {
        let wait: GoCase
        let data: T

        init(_ g: Goroutine, caseIndex: Int = 0, _ data: T) {
            wait = GoCase(g: g, caseIndex: caseIndex)
            self.data = data
        }
    }

    struct ReceiveCase {
        let wait: GoCase
        var data: T?

        init(_ g: Goroutine, caseIndex: Int = 0) {
            wait = GoCase(g: g, caseIndex: caseIndex)
        }
    }

    struct WaitGo<U> {
        var first: Linked<U>?
        var last: Linked<U>?

        mutating func dequeue() -> U? {
            guard let x = first else {
                return nil
            }
            if let y = x.next {
                x.next = nil
                y.prev = nil
                first = y
            } else {
                first = nil
                last = nil
            }
            return x.value
        }

        mutating func enqueue(_ value: U) {
            let wg = Linked(value)
            guard let last = last else {
                first = wg
                last = wg
                return
            }
            last.next = wg
            self.last = wg
        }
    }

    let locker = NSLock()
    var count = 0
    private var buffer: Array<T?> = []
    private var sendIndex = 0
    private var recvIndex = 0
    var recvWait: WaitGo<ReceiveCase>
    var sendWait: WaitGo<SendCase>

    let size: Int

    init(_ size: Int = 0) {
        if size < 0 {
            fatalError("negative channel size")
        } else if size > 0 && T.self != Void.self {
            buffer = Array(repeating: nil, count: size)
        }
        recvWait = WaitGo()
        sendWait = WaitGo()
        self.size = size
    }

    func dequeueBuff() -> T {
        count -= 1
        if T.self == Void.self {
            return () as! T
        }
        let data = buffer[recvIndex]!
        buffer[recvIndex] = nil
        recvIndex += 1
        if recvIndex >= size {
            recvIndex = 0
        }
        return data
    }

    func enqueueBuff(data: T) {
        count += 1
        if T.self != Void.self {
            buffer[sendIndex] = data
            sendIndex += 1
            if sendIndex >= size {
                sendIndex = 0
            }
        }
    }

    //full
    func recvAndSend(data: T) -> T {
        if T.self == Void.self {
            return () as! T
        }
        let first = buffer[recvIndex]!
        buffer[recvIndex] = data
        recvIndex += 1
        if recvIndex >= size {
            recvIndex = 0
        }
        sendIndex = recvIndex
        return first
    }

    func receive() -> (T?, Bool) {
        if let w = sendWait.dequeue() {
            let data: T
            if size > 0 {
                data = recvAndSend(data: w.data)
            } else {
                data = w.data
            }
            w.wait.g.assume(caseIndex: w.wait.caseIndex)
            return (data, true)
        } else if count > 0 {
            return (dequeueBuff(), true)
        }
        return (nil, false)
    }

    func receive(current g: Goroutine, caseIndex: Int = 0) -> T? {
        let (data, ok) = receive()
        if ok {
            return data
        }
        recvWait.enqueue(ReceiveCase(g, caseIndex: caseIndex))
        g.supped()
        return g.message as? T
    }


    func send(_ data: T) -> Bool {
        if let w = recvWait.dequeue() {
            w.wait.g.message = data
            w.wait.g.assume(caseIndex: w.wait.caseIndex)
            return true
        } else if size > count {
            enqueueBuff(data: data)
            return true
        }
        return false
    }

    func send(current g: Goroutine, caseIndex: Int = 0, _ data: T) {
        if send(data) {
            return
        }
        sendWait.enqueue(SendCase(g, caseIndex: caseIndex, data))
        g.supped()
    }

}

extension Chan: Channel {
    typealias Element = T

    static prefix func <-(ch: Chan<T>) -> T? {
        fatalError("no implement <- operator yet")
    }

    static func <-(ch: Chan<T>, data: T) {
        fatalError("no implement <- operator yet")
    }
}

