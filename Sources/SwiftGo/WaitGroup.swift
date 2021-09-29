//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftGo open source project
// Copyright (c) 2021 XuYue and the SwiftGo project authors
// Licensed under Apache License v2.0
//
//===----------------------------------------------------------------------===//

import Dispatch

public struct WaitGroup {
    let semaphore: DispatchSemaphore

    public init(_ n: Int) {
        semaphore = DispatchSemaphore(value: 1-n)
        semaphore.setTarget(queue: goroutines)
        semaphore.activate()
    }

    public func done() {
        semaphore.signal()
    }

    public func wait() {
        semaphore.wait()
    }

}
