//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftGo open source project
// Copyright (c) 2021 XuYue and the SwiftGo project authors
// Licensed under Apache License v2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Dispatch

//import Atomics

let goroutines = DispatchQueue(label: "goroutines", qos: .background, attributes: .concurrent)

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
    private let locker = NSLock() //todo temp
    var selectIndex = -1
    var rands = Rand()

    private let semaphore: DispatchSemaphore
    private var execution: DispatchWorkItem!

    init(closure: @escaping (Goroutine) -> ()) {
        semaphore = DispatchSemaphore(value: 0)
        execution = DispatchWorkItem(block: {
            closure(self)
            self.execution = nil
        })
    }

    func start() {
        semaphore.setTarget(queue: goroutines)
        semaphore.activate()
        goroutines.async(execute: execution)
    }

    func suspend() {
        semaphore.wait()
    }

    func resume() {
        semaphore.signal()
    }

    func cancel() {
        execution?.cancel()
        execution = nil
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

    public func receive<T>(from ch: Chan<T>) -> T! {
        let gc: GoCase<T>
        do {
            ch.locker.lock()
            defer {
                ch.locker.unlock()
            }
            let (data, ok) = ch.receive()
            if ok {
                return data
            }
            gc = GoCase(self, index: 0)
            ch.recvWait.enqueue(gc)
            selectIndex = -1
        }
        suspend()
        return gc.data
    }

    public func sleep(_ interval: DispatchTimeInterval) {
        _ = semaphore.wait(timeout: DispatchTime.now() + interval)
    }

}

public func go(_ closure: @escaping (Goroutine) -> ()) {
    Goroutine(closure: closure).start()
}
