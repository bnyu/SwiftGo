//
// Created by xuyue on 2021/5/1.
//

import Backtrace
import Foundation
import SwiftGo

// debug with lldb
Backtrace.install()

print("Hello SwiftGo")

let qb = Chan<Bool>(2)
let qc = Chan<Void>()

go { _ in
    let ch1 = Chan<Float>(20)
    let ch2 = Chan<[Int]>(2)

    print("start")
    go {
        print("start receive")
        var loop = true
        while loop {
            $0.select(
                    Case(ch1, .receive { data in
                        print(data!)
                    }),
                    Case(ch2, .receive { data in
                        print(data!)
                    }),
                    Case(qc, .receive { _ in
                        loop = false
                    })
            )
        }
        print("stop receive")
        $0.send(to: qb, data: true)
    }

    go {
        print("start send")
        var loop = true
        while loop {
            $0.select(
                    Case(ch1, .send(data: Float.random(in: 0..<100))),
                    Case(ch2, .send(data: [Int.random(in: 0...1000)])),
                    Case(ch1, .send(data: Float.random(in: -10...0))),
                    Case(qc, .receive { _ in
                        loop = false
                    })
            )
        }
        print("stop send")
        $0.send(to: qb, data: true)
    }

    go {
        let x: Float = $0.receive(from: ch1)
        $0.sleep(.milliseconds(100))
        $0.send(to: ch2, data: [Int(x + x), Int(x * x)])
        $0.sleep(.milliseconds(100))
        $0.select(Case(ch1, .send(data: 0)), default: {
            print()
        })
        $0.sleep(.milliseconds(200))
        close(qc)
        if $0.receive(from: qb) && $0.receive(from: qb) {
            print("------")
            $0.select(Case(ch2, .receive {
                if let data = $0 {
                    print("\(data)")
                }
            }), default: {
                print()
            })
            go { g in
                g.sleep(.seconds(2))
                print("done")
                close(ch1)
            }
            while true {
                guard let n = $0.receive(from: ch1) else {
                    break
                }
                print(n)
            }
        }
        print("finish")
    }
}


Thread.sleep(forTimeInterval: 3)
