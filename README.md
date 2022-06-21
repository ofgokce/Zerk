Zerk
========

[![CocoaPods Version](https://img.shields.io/cocoapods/v/Zerk.svg?style=flat)](http://cocoapods.org/pods/Zerk)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg?style=flat)](https://github.com/apple/swift-package-manager)
[![License](https://img.shields.io/cocoapods/l/Zerk.svg?style=flat)](http://cocoapods.org/pods/Zerk)
[![Platforms](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](http://cocoapods.org/pods/Zerk)
[![Swift Version](https://img.shields.io/badge/Swift-4.2--5.4-F16D39.svg?style=flat)](https://developer.apple.com/swift)

Zerk is a framework written for Swift which allows you to easily store and restore your dependencies following the [dependency injection pattern](https://en.wikipedia.org/wiki/Dependency_injection) and [clean coding principles](https://en.wikipedia.org/wiki/Robert_C._Martin). It removes the need for static methods and singletons and thus helps to create more managable and testable global or local dependencies.

## Features

- Zerk provides a way to store dependencies' initialization logic. The dependencies are not initialized when stored. When the dependency is being called, if it hasn't been initialized before it will be initialized and only then the instance will be cached to be used by upcoming calls.

- The stored dependencies can be restored easily and without any hussle so they can be injected via initializers, methods or properties.

- With new @Injected keyword the injected dependencies are restored automatically, allowing an even more readable code.

- Also there are other keywords for injecting only the properties or methods of your dependencies, using the cutting-edge key path feature of Swift.

## Requirements

- iOS 9.0+
- Xcode 10.2+
- Swift 5.0+
- CocoaPods 1.1.1+ (if used)

## Installation

Zerk is available through [CocoaPods](https://cocoapods.org) and [Swift Package Manager](https://swift.org/package-manager/).

### CocoaPods

To install Zerk with CocoaPods, add the following lines to your `Podfile`.

```ruby
source 'https://cdn.cocoapods.org/'
platform :ios, '9.0'
use_frameworks!

pod 'Zerk'

```

Then run `pod install` command. For details of the installation and usage of CocoaPods, visit [its official website](https://cocoapods.org).

### Swift Package Manager

in `Package.swift` add the following:

```swift
dependencies: [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
    .package(url: "https://github.com/ofgokce/Zerk.git", from: "0.1.1")
],
targets: [
    .target(
        name: "MyProject",
        dependencies: [..., "Zerk"]
    )
    ...
]
```

## Basic Usage

### Storing

Firstly the dependencies should be stored in a storage, for most cases `Zerk.storage` will be the one.

The stored dependencies can only be restored by the types they have been stored as. It is recommended to store them as protocols for better testability.

- For dependencies which doesn't depend on others:

```swift
Zerk.storage
    .store(dependencyInstance as DependencyProtocol)
```

- For dependencies which depend on other dependencies:

```swift
Zerk.storage
    .store { dependency in
        DependentClassA(dependency: dependency) as DependentProtocolA
    }
    .store { dependency0, dependency1, dependency2, dependency3, dependency4 in
        DependentClassB(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4)
        as DependentProtocolB
    }
```

- For dependencies which depend on other dependencies (restoring by storage):

```swift
Zerk.storage
    .store { storage in
        DependenentClass(dependency: storage.restore()) as DependentProtocol
    }
```

And that's it! 

### Restoring

Now the `restore()` or `restore(_:)` methods of the same storage can restore the stored dependencies.

```swift
let dependency: DependencyProtocol = Zerk.storage.restore()
```
OR

```swift
let dependency = Zerk.storage.restore(DependencyProtocol.self)
```

### Basic Injection

There are several ways of injecting a dependency to a type. 

- Initializer injection

```swift
class SomeClass {
    private let dependency: DependencyProtocol
    init(dependency: DependencyProtocol) {
        self.dependency = dependency
        ...
    }
}

let someInstance = SomeClass(dependency: Zerk.storage.restore())
```

- Method injection

```swift
class SomeClass {
    private var dependency: DependencyProtocol?
    func set(dependency: DependencyProtocol) {
        self.dependency = dependency
    }
}

let someInstance = SomeClass()
someInstance.set(dependency: Zerk.storage.restore())
```

- Property injection

```swift
class SomeClass {
    var dependency: DependencyProtocol?
}

let someInstance = SomeClass()
someInstance.dependency = Zerk.storage.restore()
```

### Keyword Injection

Zerk provides new keywords to make the injection even easier and more readable.

- @Injected

Injects the dependency.

```swift
class SomeClass {
    @Injected var dependency: DependencyProtocol
}
```

- @InjectedProperty

Injects a read-only property of a dependency. Keypath syntax is to be used.

```swift
class SomeClass {
    @InjectedProperty(\DependencyProtocol.someProperty) var someProperty: SomeType
}
```

- @InjectedWritableProperty

Injects a read-write property of a dependency.

```swift
class SomeClass {
    @InjectedWritableProperty(\DependencyProtocol.someProperty) var someProperty: SomeType
}
```

- @InjectedUnwrappedProperty & @InjectedUnwrappedWritableProperty

Unwraps and injects a read-only optional property of a dependency. If a default value has been given, the injected property will be unwrapped by the given default value. Else the property will be force-unwrapped.

```swift
class SomeClass {
    @InjectedUnwrappedProperty(\DependencyProtocol.someProperty, default: someValue) var someProperty: SomeType
}
```

- @InjectedMethod

Injects a method of a dependency. As Swift currently doesn't support keypaths to methods, this wrapper had to be working in a different way.

```swift
class SomeClass {
    @InjectedMethod(DependencyProtocol.someMethod) var someMethod: (ParameterTypes) -> (ReturnTypes)
}
```

OR

```swift
class SomeClass {
    @InjectedMethod(DependencyProtocol.someMethod(_:someParameter:)) var someMethod: (ParameterTypes) -> (ReturnTypes)
}
```

## Where to Store Dependencies

The dependencies must be stored before they are used. The typical approach would be to store them in `AppDelegate`, better before exiting the `application:didFinishLaunchingWithOptions:` method.

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
        ...
        
        Zerk.storage
            .store( ... )
            .store { ... }
            ...
            
        ...
    }
}
```

## Notes

I have written most of this as a DI solution for a project I was working on which is being used by millions of users on AppStore. This is the backbones of that app. I just wanted to share it with the world so I have changed it a bit and made into a framework. The documentation might be somewhat bad since there was none before but I will be bettering it as I find the time to do so. I will also check the requirements, I don't really know what are the minimums for this project. Feel free to contact me if you have some ideas to make this better. It will be appreciated. Most importantly, have fun!

## Credits

The storage approach and storing methods have been inspired by:

- [Swinject](https://cocoapods.org/pods/Swinject)

## License

MIT license. See the [LICENSE file](LICENSE) for details.
