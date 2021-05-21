//
// Created by xuyue on 2021/5/1.
//

import Backtrace
import Foundation
import SwiftGo

// debug with lldb
Backtrace.install()

print("Hello SwiftGo")

let ch1 = Chan<Int>(10)
let ch2 = Chan<Float>()
let qs = Chan<String>()
let qr = Chan<String>()

go { _ in
    print("start")
    go {
        print("start receive data")
        var loop = true
        while loop {
            $0.select(
                    Case(ch1, .receive { data in
                        print("\(data) <-")
                    }),
                    Case(ch2, .receive { data in
                        print("\(data) <-")
                    }),
                    Case(qr, .receive { data in
                        loop = false
                        print("stop receive cause \(data)")
                    })
            )
        }
    }

    go {
        print("start send data")
        var loop = true
        while loop {
            $0.select(
                    Case(ch1, .send(data: Int.random(in: -10...10)) {
                    }),
                    Case(ch1, .send(data: Int.random(in: 100...200)) {
                    }),
                    Case(ch2, .send(data: Float.random(in: 0...5.0)) {
                    }),
                    Case(qs, .receive { data in
                        loop = false
                        print("stop send cause \(data)")
                    })
            )
        }
    }

    go {
        $0.sleep(milliseconds: 1000)
        $0.send(to: qs, data: "times up")
        print("------")
    }
}

go {
    $0.sleep(milliseconds: 1000)
    $0.send(to: qr, data: "times up")
    print("------")
}


Thread.sleep(forTimeInterval: 1000)
