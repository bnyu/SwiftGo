//
// Created by xuyue on 2021/5/1.
//

import Backtrace
import Foundation
import SwiftGo

// debug with lldb
Backtrace.install()

print("Hello SwiftGo")

let dataCh = Chan<Int>()
let quitCh = Chan<Int>()

go { _ in
    print("start")
    go {
        print("start receive data")
        var loop = true
        while loop {
            $0.select(.receive(ch: dataCh, block: { data in print("\(data) <-") }),
                    .receive(ch: quitCh, block: { info in loop = false; print("quit with \(info)") })
            )
        }
    }

    go {
        print("start send data")
        for i in 1...10000 {
            $0.select(.send(ch: dataCh, data: i, block: print("<- \(i)")),
                    .send(ch: dataCh, data: -i, block: print("<- \(-i)")))
        }
    }
}

go {
    $0.sleep(milliseconds: 999)
    $0.select(.send(ch: quitCh, data: 0, block: print("send quit single")))
}


Thread.sleep(forTimeInterval: 1000)
