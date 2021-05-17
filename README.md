# SwiftGo

Introduce CSP into Swift, inspired by Golang

required Swift 5.0 or higher

This is not a stable version<code>0.0.2</code>, so please do not use it in production environment.  
Please feel free to summit a PR or an Issue.

## Introduction
#### Features
- Goroutines (lighter than threads)
- FIFO channel (with or without buffer)
- Select on channels (with or without default)

## Usage

Add `https://github.com/bnyu/SwiftGo.git` as a dependency in your `Package.swift`.

Then
```swift
import SwiftGo
```

### Example

- new goroutine
```swift
// create a new goroutine running in concurrent
go {
    // doing something here
}
```

- send and receive
```swift
// create a Int channel without buffer
let ch = Chan<Int>()
// create a Int channel with 10 capacity buffer
// let ch = Chan<Int>(10)

go {
    // ch <- 1
    $0.send(to: ch, data: 1)
    print("send ok")
}

go {
    // let data = <-ch
    let data = $0.receive(from: ch)
    print("received \(data)")
}
```

- select
```swift
let ch1 = Chan<Int>()
let ch2 = Chan<Int>(2)
let ch3 = Chan<Int>(3)

go {
    // select on cases
    $0.select(
            .receive(ch: ch1, block: { data in print("received \(data) from ch1") }),
            .receive(ch: ch2, block: { data in print("received \(data) from ch2") }),
            .send(ch: ch3, data: 33, block: print("send 33 to ch3")),
            .send(ch: ch3, data: 42, block: print("send 42 to ch3"))
    )
    // continue do something here
}

go {
    // select with default
    $0.select(
            .receive(ch: ch2, block: { data in print("received \(data) from ch2") }),
            .send(ch: ch3, data: 1, block: print("send 1 to ch3")),
            default: print("default action")
    )
    // continue do something here
}
```

## Dependencies
It uses [GCD](https://github.com/apple/swift-corelibs-libdispatch) to dispatch `goroutine` instead of `Thread`.
Similar to the role of GMP in Golang.  
It will use [Atomics](https://github.com/apple/swift-atomics) to replace `NSLocker` for select race(which does not support Windows yet)

## License
SwiftGo is licensed under the Apache License, Version 2.0. See [License](LICENSE) for the full license text.
