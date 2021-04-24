//
// Created by xuyue on 2021/4/24.
//

import Foundation
import Dispatch

public class Goroutine {
    var message: Any?

    //class func current() -> Goroutine {
    //
    //}

    init() {

    }

    func supped() {

    }

    func assume(caseIndex: Int) {

    }


    public func select(_ cases: (Select<Any>, () -> ())...) {

    }

    public func select(_ cases: (Select<Any>, () -> ())..., default: () -> ()) {

    }

}


public enum Select<T> {
    case send(ch: Chan<T>, data: T)
    case receive(ch: Chan<T>)
}


public func go(closure: (Goroutine) -> ()) {
    closure(Goroutine())
}
