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
        while true {
            $0.select(cases: .receive(ch: dataCh, block: { data in print("\(data) <-") }))
        }
    }

    go {
        print("start send data")
        for i in 1...10000 {
            $0.select(cases: .send(ch: dataCh, data: i, block: print("<- \(i)")))
        }
    }
}


Thread.sleep(forTimeInterval: 1)
