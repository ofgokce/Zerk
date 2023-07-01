Zerk
========

[![CocoaPods Version](https://img.shields.io/cocoapods/v/Zerk.svg?style=flat)](http://cocoapods.org/pods/Zerk)
[![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg?style=flat)](https://github.com/apple/swift-package-manager)
[![License](https://img.shields.io/cocoapods/l/Zerk.svg?style=flat)](http://cocoapods.org/pods/Zerk)
[![Platforms](https://img.shields.io/badge/platform-iOS-lightgrey.svg)](http://cocoapods.org/pods/Zerk)
[![Swift Version](https://img.shields.io/badge/Swift-5.0-F16D39.svg?style=flat)](https://developer.apple.com/swift)

Zerk is a framework written for Swift which allows you to easily store and restore your dependencies following the [dependency injection pattern](https://en.wikipedia.org/wiki/Dependency_injection) and [clean coding principles](https://en.wikipedia.org/wiki/Robert_C._Martin). It removes the need for static methods and singletons and thus helps to create more managable and testable global or local dependencies.

## Features

- Zerk provides a way to store dependencies' initialization logic. The dependencies may be stored as short-, middle- or long-time living objects and are not initialized when stored. When a dependency is being called, if it hasn't been initialized before it will be initialized and only then the instance will be cached if it should to be used by upcoming calls.

- The stored dependencies can be restored easily and without any hussle so they can be injected via initializers, methods or properties.

- The dependencies may depend on other stored dependencies. They even can have argumentations to give when being initialized.

- With new `@Injected` keyword the injected dependencies are restored automatically, allowing an even more readable code.

- Also there are other keywords for injecting only the properties or methods of your dependencies, using the cutting-edge key path feature of Swift.

## Requirements

- iOS 9.0+
- Xcode 13+
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
    ...
    .package(url: "https://github.com/ofgokce/Zerk.git", from: "1.0.0")
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

Firstly the dependencies' initiation logic should be stored in a storage. For the most cases `Zerk.store` may be used to store all the dependencies.

The stored dependencies can only be restored by the types they have been stored as. The dependencies may be stored as multiple types which they conform but for any type given there should be one dependency. It is recommended to store them as protocols for better testability.

The dependencies can be stored with three life-time choices: 
 
 - Transient:
These dependencies are initialized every time they are being called.
 
 - Scoped:
These dependencies are initialized every time they are being restored by restore functions. This type is used by Zerk's property wrappers to ensure the instances live as long as their dependent object lives.
 
 - Singleton:
These dependencies are initialized only once when they are first called, then they are stored as instances in the storage and can be used globally.


The dependencies will be stored as a wrapper-class `Dependency` which is responsible for identification, creation, typecasting and instance holding of said dependencies. This class has a `getInstance(with:)` method which creates the instances if not yet created or returns the stored instances for singletons if already been instantiated.

- Storing dependencies which don't depend on others:

```swift
Zerk.store
    .transient(TransientDependencyClass() as TransientDependencyProtocol)
    .scoped(ScopedDependencyClass() as ScopedDependencyProtocol)
    .singleton(SingletonDependencyClass() as SingletonDependencyProtocol)
```

- Storing dependencies which depend on other dependencies:

```swift
Zerk.store
    .transient { dependency in
        DependentClassA(dependency: dependency) as DependentProtocolA
    }
    .scoped { dependency0, dependency1, dependency2, dependency3, dependency4 in
        DependentClassB(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4)
        as DependentProtocolB
    }
    .singleton {
        DependentClassC(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
        as DependentProtocolC
    }
```

- Storing dependencies which depend on other dependencies (restoring by storage):

```swift
Zerk.store
    .transient { storage in
        DependentClassA(dependency: storage.restore()) 
        as DependentProtocolA
    }
    .scoped { storage in
        DependentClassB(dependency0: storage.restore(), dependency1: storage.restore()) 
        as DependentProtocolB
    }
```

- Storing dependencies with argumentative init:

```swift
Zerk.store
    .transient { storage, arguments in
        ArgumentativeClassA(parameterName: arguments.parameterName) 
        as ArgumentativeProtocolA
    }
    .singleton { storage, arguments in
        ArgumentativeClassB(dependency: storage.restore(), parameterName0: arguments.parameterName0, parameterName1: arguments.customName) 
        as ArgumentativeProtocolB
    }
```

The argument names are not name-safe and not type-safe. Swift's [dynamicCallable](https://github.com/apple/swift-evolution/blob/main/proposals/0216-dynamic-callable.md) and [dynamicMemberLookup](https://github.com/apple/swift-evolution/blob/main/proposals/0195-dynamic-member-lookup.md) annotations have been used to provide this functionality. The namings and types used to store the dependencies should match those used to restore them. Otherwise there will be fatal errors thrown. For more information please check the documentations.

- For dependencies with multiple types (aliases):

```swift
Zerk.store
    .scoped({ _, _ in
        MultitypeClass()
    }, as: ProtocolA.self, ProtocolB.self, ProtocolC.self)
    .singleton({ storage, arguments in
        MultitypeClass(dependency: storage.restore(), parameterName0: arguments.parameterName0, parameterName1: arguments.customName)
    }, as: ProtocolA.self, ProtocolB.self, ProtocolC.self)
```

The dependency should be able to be typecasted to the types given here. Otherwise there will be fatal errors thrown.

And that's it! 

### Restoring

Now the `restore()`, `restore(with:)` and `restore(_:)` methods of the same storage can restore the stored dependencies. While the first two methods will return the typecasted instance of the dependency itself the latter one will return the wrapper instance of type `Dependency`.

```swift
let instanceA: DependencyProtocolA = Zerk.standardStorage.restore() // Returns the typecasted dependency instance
let instanceB: DependencyProtocolB = Zerk.standardStorage.restore(with: .arguments(argument0: value0, argument1: value1) // Returns the typecasted dependency instance, instantiated with the given arguments
```
OR

```swift
let dependency = Zerk.standardStorage.restore(DependencyProtocol) // Returns the wrapper instance
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

let someInstance = SomeClass(dependency: Zerk.standardStorage.restore())
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
someInstance.set(dependency: Zerk.standardStorage.restore())
```


- Property injection

```swift
class SomeClass {
    var dependency: DependencyProtocol?
}

let someInstance = SomeClass()
someInstance.dependency = Zerk.standardStorage.restore()
```

### Keyword Injection

Zerk provides new keywords to make the injection even easier and more readable.

- @Injected

Injects the whole dependency.

```swift
class SomeClass {
    @Injected var dependency: DependencyProtocol
}
```

To inject a dependency with argumentation:

```swift
class SomeClass {
    @Injected(with: .arguments(argument0: value0, argument1: value1)
    var dependency: DependencyProtocol
}
```


- @InjectedProperty

Injects a read-only property of a dependency. Keypath syntax is to be used.

```swift
class SomeClass {
    @InjectedProperty(\DependencyProtocol.someProperty) var someProperty: SomeType
}
```


- @InjectedMutableProperty

Injects a mutable property of a dependency.

```swift
class SomeClass {
    @InjectedMutableProperty(\DependencyProtocol.someProperty) var someProperty: SomeType
}
```


- @InjectedUnwrappedProperty & @InjectedUnwrappedMutableProperty

Unwraps and injects an optional property of a dependency. If a default value has been given, the injected property will be unwrapped by the given default value. Else the property will be force-unwrapped.

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

The dependencies must be stored before they are used.

The typical approach would be to store them in `AppDelegate`, better before exiting the `application:didFinishLaunchingWithOptions:` method.

```swift
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
        ...
        
        Zerk.store
            .transient( ... )
            .singleton { ... }
            ...
            
        ...
    }
}
```

In order to automatize the storing process without cluttering the AppDelegate, you may conform `Zerk` to `AutoStoring` protocol in an empty file. This protocol only has a `store()` function which will be called only once when the very first time any dependency restoration is needed. 

```swift
extension Zerk: AutoStoring {

    func store() {
    
        Zerk.store
            .transient( ... )
            .singleton { ... }
            ...
    }
}
```

## Notes

I have written most of this as a DI solution for a project I was working on which is being used by millions of users on AppStore. This is the backbones of that app. I just wanted to share it with the world so I have changed it a bit and made into a framework. The documentation might be somewhat bad since there was none before but I will be bettering it as I find the time to do so. I will also check and update the requirements and compatible platforms. 

Feel free to contact me if you have some ideas to make this better. It will be appreciated. Most importantly, have fun!

## Credits

The storage approach have been inspired by:

- [Swinject](https://github.com/Swinject/Swinject)

The multitypes (aliases) have been inspired by:

- [DependencyInjection](https://github.com/sebastianpixel/DependencyInjection)

## License

MIT license. See the [LICENSE file](LICENSE) for details.
