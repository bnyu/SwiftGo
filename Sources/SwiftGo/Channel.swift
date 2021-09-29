//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftGo open source project
// Copyright (c) 2021 XuYue and the SwiftGo project authors
// Licensed under Apache License v2.0
//
//===----------------------------------------------------------------------===//

import Foundation

public final class Chan<T> {

    struct WaitGo {
        var first: GoCase<T>?
        var last: GoCase<T>?

        mutating func remove(_ value: GoCase<T>) {
            if let prev = value.prev {
                if let next = value.next {
                    next.prev = prev
                    prev.next = next
                    value.prev = nil
                    value.next = nil
                } else {
                    prev.next = nil
                    last = prev
                    value.prev = nil
                }
            } else if let next = value.next {
                first = next
                value.next = nil
            } else if first === value {
                first = nil
                last = nil
            }
        }

        mutating func dequeue() -> GoCase<T>? {
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
            return x
        }

        mutating func enqueue(_ value: GoCase<T>) {
            guard let last = last else {
                first = value
                last = value
                return
            }
            value.prev = last
            last.next = value
            self.last = value
        }
    }

    let locker = NSLock()
    private var closed = false
    private var count = 0
    private var buffer: Array<T?> = []
    private var sendIndex = 0
    private var recvIndex = 0
    var recvWait: WaitGo
    var sendWait: WaitGo

    let size: Int

    public init(_ size: Int = 0) {
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

    func dequeue(_ wg: inout WaitGo) -> GoCase<T>? {
        while let w = wg.dequeue() {
            w.dequeued = true
            if !w.g.trySelect(index: w.index) {
                continue
            }
            return w
        }
        return nil
    }

    func receive() -> (T?, Bool) { //return true means no need to wait (received or closed)
        if let w = dequeue(&sendWait) {
            defer {
                w.g.resume()
            }
            var data = w.data!
            if size > 0 { //full
                data = recvAndSend(data: data)
            }
            return (data, true)
        } else if count > 0 {
            return (dequeueBuff(), true)
        } else if closed {
            return (nil, true)
        }
        return (nil, false)
    }

    func send(_ data: T) -> Bool {
        if closed {
            fatalError("send to closed channel")
        }
        if let w = dequeue(&recvWait) {
            defer {
                w.g.resume()
            }
            w.data = data
            return true
        } else if size > count {
            enqueueBuff(data: data)
            return true
        }
        return false
    }

    func close() {
        if closed {
            fatalError("close closed channel")
        }
        closed = true
        if sendWait.first != nil {
            fatalError("close wait send channel")
        }
        if count > 0 {
            return
        }
        while true {
            if let w = dequeue(&recvWait) {
                w.g.resume()
            } else {
                break
            }
        }

    }

}

public func close<T>(_ ch: Chan<T>) {
    ch.locker.lock()
    defer {
        ch.locker.unlock()
    }
    ch.close()
}
