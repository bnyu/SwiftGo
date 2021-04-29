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
        let index: Int
        var data: T?
    }

    struct WaitGo {
        var first: Linked<GoCase>?
        var last: Linked<GoCase>?

        mutating func dequeue() -> GoCase? {
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

        mutating func enqueue(_ value: GoCase) {
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
    var recvWait: WaitGo
    var sendWait: WaitGo

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

    func recvWaitEnqueue(_ g: Goroutine, index: Int = 0) {
        recvWait.enqueue(GoCase(g: g, index: index, data: nil))
    }

    func sendWaitEnqueue(_ g: Goroutine, index: Int = 0, data: T) {
        sendWait.enqueue(GoCase(g: g, index: index, data: data))
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
            if var data = w.data {
                if size > 0 {
                    data = recvAndSend(data: data)
                }
                w.g.resume(index: w.index)
                return (data, true)
            } else {
                fatalError("received nil data")
            }
        } else if count > 0 {
            return (dequeueBuff(), true)
        }
        return (nil, false)
    }

    func receive(current g: Goroutine, index: Int = 0) -> T? {
        var (data, ok) = receive()
        if ok {
            return data
        }
        recvWaitEnqueue(g)
        g.suspend()
        let message = g.message
        if message is T? {
            data = message as? T
            g.message = nil
            return data
        }
        fatalError("receive data wrong type")
    }


    func send(_ data: T) -> Bool {
        if let w = recvWait.dequeue() {
            w.g.message = data
            w.g.resume(index: w.index)
            return true
        } else if size > count {
            enqueueBuff(data: data)
            return true
        }
        return false
    }

    func send(current g: Goroutine, _ data: T) {
        if send(data) {
            return
        }
        sendWaitEnqueue(g, data: data)
        g.suspend()
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

