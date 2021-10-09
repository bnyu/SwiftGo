//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftGo open source project
// Copyright (c) 2021 XuYue and the SwiftGo project authors
// Licensed under Apache License v2.0
//
//===----------------------------------------------------------------------===//

import Dispatch


public struct Timer {
    public let c: Chan<DispatchTime>
    private let g: Goroutine

    public init(duration: DispatchTimeInterval) {
        let ch = Chan<DispatchTime>(1)
        c = ch
        g = Goroutine { g in
            g.sleep(duration)
            if g.isCancelled {
                return
            }
            g.send(to: ch, data: DispatchTime.now())
        }
        g.start()
    }

    public func stop() {
        g.cancel() //cancel send
        g.resume() //awake sleep
    }

    public static func after(_ duration: DispatchTimeInterval) -> Chan<DispatchTime> {
        Timer(duration: duration).c
    }
}

public struct Ticker {
    public let c: Chan<DispatchTime>
    private let g: Goroutine

    public init(duration: DispatchTimeInterval) {
        let ch = Chan<DispatchTime>(1)
        c = ch
        g = Goroutine { g in
            while true {
                g.sleep(duration)
                if g.isCancelled {
                    break
                }
                g.select(Case(ch, .send(data: DispatchTime.now())), default: {})
            }
        }
        g.start()
    }

    public func stop() {
        g.cancel()
        g.resume()
    }

    public static func tick(_ duration: DispatchTimeInterval) -> Chan<DispatchTime> {
        Ticker(duration: duration).c
    }
}
