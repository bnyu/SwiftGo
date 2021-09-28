# SwiftGo

Introduce CSP into Swift, inspired by Golang

required Swift 5.0 or higher

This is not a stable version<code>0.1.1</code>, so please do not use it in production environment.  
Please feel free to summit a PR or an Issue.

## Introduction
#### Features
- Goroutines (lighter than threads)
- FIFO channel (with or without buffer)
- Select on channels (with or without default)
- Close the channel

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
    // var data = <-ch
    let data = $0.receive(from: ch)
    print("received \(data!)")
}
```

- select
```swift
let ch1 = Chan<Int>()
let ch2 = Chan<Float>(12)
let ch3 = Chan<String>()

go {
    // select on cases
    $0.select(
            Case(ch1, .send(data: Int.random(in: 0...10))),
            Case(ch2, .send(data: Float.random(in: 0...5.0)) {
                print("send to ch2")
            }),
            Case(ch3, .receive { data in
                print("receive str: \(data!)")
            })
    )
    // continue do something here
}

go {
    // select with default
    $0.select(
            Case(ch1, .send(data: Int.random(in: 0...10))),
            Case(ch2, .send(data: Float.random(in: 0...5.0)) {
                print("send to ch2")
            }),
            default: {
                print("pass")
            }
    )
    // continue do something here
}
```
[example code](Sources/example/main.swift)

## Dependencies
It uses [Dispatch](https://github.com/apple/swift-corelibs-libdispatch) to dispatch `goroutines` instead of `Threads`.
Similar to the role of GMP in Golang.  
It will use [Atomics](https://github.com/apple/swift-atomics) to replace `NSLocker` for select race(which does not support Windows yet)

## License
SwiftGo is licensed under the Apache License, Version 2.0. See [License](LICENSE) for the full license text.
