//
// Created by xuyue on 2021/5/1.
//

import Foundation
import SwiftGo

let dataCh = Chan<Int>()
let quitCh = Chan<Int>()

print("Hello SwiftGo")

go { _ in
    print("start")
    go {
        print("start receive data")
        var loop = true
        while loop {
            $0.select(cases: .receive(ch: dataCh, block: { data in print("\(data!) <-") }),
                    .receive(ch: quitCh, block: { info in loop = false; print("quit cause \(info!)") })
            )
        }
    }

    print("prepare for something")

    go {
        print("start send data")
        for i in 1...10000 {
            $0.select(cases: .send(ch: dataCh, data: i, block: print("<- \(i)")))
        }
    }
}

Thread.sleep(forTimeInterval: 1000)

go {
    $0.sleep(milliseconds: 1000)
    $0.select(cases: .send(ch: quitCh, data: -1, block: print("send quit single")))
}

Thread.sleep(forTimeInterval: 10000)
