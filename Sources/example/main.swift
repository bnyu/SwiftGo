//
// Created by xuyue on 2021/5/1.
//

import SwiftGo

print("Hello SwiftGo")

let wg = WaitGroup(1)

let qb = Chan<Bool>(2)
let qc = Chan<Void>()

go {
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

    let x: Float = $0.receive(from: ch1)
    $0.sleep(.milliseconds(100))
    $0.send(to: ch2, data: [Int(x + x), Int(x * x)])
    $0.sleep(.milliseconds(100))
    $0.select(Case(ch1, .send(data: 0)), default: {
        print()
    })
    $0.sleep(.milliseconds(200))
    close(qc)
    if $0.receive(from: qb) {
        print("------")
        $0.select(Case(ch2, .receive {
            if let data = $0 {
                print("\(data)")
            }
        }), default: {
            print()
        })
        go { _ in
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
    wg.done()
}

print("wait")
wg.wait()
print("exit")
