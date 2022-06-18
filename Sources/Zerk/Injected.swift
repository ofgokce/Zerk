//
//  Injected.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

/// This property wrapper is to be used for dependency injection.
/// The dependencies are needed to be stored via the storage given in the initializers before being injected.
/// `wrappedValue` is read-only. This approach guarantees the dependency being globally same within the same storage.
///
/// Usage:
///
///     // Restored by the standard storage:
///     @Injected
///     var dependency: Dependency
///
///     // Restored by a custom storage:
///     @Injected(restoredBy: customStorage)
///     var dependency: Dependency
///
@propertyWrapper
public struct Injected<Value> {
    public let wrappedValue: Value
    
    /// Inject the whole dependency instance, resolved by the storage.
    ///
    public init(restoredBy dependencyStorage: DependencyRestoring = Zerk.storage) {
        self.wrappedValue = dependencyStorage.restore()
    }
}

/// This property wrapper is to be used for injecting only the property, not the whole dependency instance.
/// Injected properties are get-only.
/// The dependencies are needed to be stored via the storage given in the initializers before being injected.
///
/// Usage:
///
///     // Restored by the standard storage:
///     @InjectedProperty(\Dependency.property)
///     var property: PropertyType
///
///     // Restored by a custom storage:
///     @InjectedProperty(\Dependency.property, restoredBy: customStorage)
///     var property: PropertyType
///
@propertyWrapper
public struct InjectedProperty<Source, Value> {
    private var source: Source
    private let keypath: KeyPath<Source, Value>
    public var wrappedValue: Value {
        get {
            source[keyPath: keypath]
        }
    }
    
    /// Inject only a get-only property of a dependency, resolved by the storage.
    ///
    public init(_ keypath: KeyPath<Source, Value>,
                restoredBy dependencyStorage: DependencyRestoring = Zerk.storage) {
        self.source = dependencyStorage.restore()
        self.keypath = keypath
    }
}

/// This property wrapper is to be used for injecting only the property, not the whole dependency instance.
/// Injected properties are settable.
/// The dependencies are needed to be stored via the storage given in the initializers before being injected.
///
/// Usage:
///
///     // Restored by the standard storage:
///     @InjectedWritableProperty(\Dependency.property)
///     var property: PropertyType
///
///     // Restored by a custom storage:
///     @InjectedWritableProperty(\Dependency.property, restoredBy: customStorage)
///     var property: PropertyType
///
@propertyWrapper
public struct InjectedWritableProperty<Source, Value> {
    private var source: Source
    private let keypath: WritableKeyPath<Source, Value>
    public var wrappedValue: Value {
        get {
            source[keyPath: keypath]
        } set {
            source[keyPath: keypath] = newValue
        }
    }
    
    /// Inject only a writable property of a dependency, resolved by the storage.
    ///
    public init(_ keypath: WritableKeyPath<Source, Value>,
                restoredBy dependencyStorage: DependencyRestoring = Zerk.storage) {
        self.source = dependencyStorage.restore()
        self.keypath = keypath
    }
}

/// This property wrapper is to be used for injecting only the unwrapped optional property, not the whole dependency instance. If a default value has been given, the injected property will be unwrapped by the given default value. Else the property will be force-unwrapped.
/// Injected properties are get-only.
/// The dependencies are needed to be stored via the storage given in the initializers before being injected.
///
/// Usage:
///
///     // Restored by the standard storage, force-unwrapped:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty)
///     var property: PropertyType
///
///     // Restored by the standard storage, unwrapped with the given default value:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty, default: someValue)
///     var property: PropertyType
///
///     // Restored by a custom storage, force-unwrapped:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty, restoredBy: customStorage)
///     var property: PropertyType
///
///     // Restored by a custom storage, unwrapped with the given default value:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty, default: someValue, restoredBy: customStorage)
///     var property: PropertyType
///
@propertyWrapper
public struct InjectedUnwrappedProperty<Source, Value> {
    private var source: Source
    private let keypath: KeyPath<Source, Value?>
    private let `default`: Value?
    public var wrappedValue: Value {
        get {
            source[keyPath: keypath] ?? `default` ?? source[keyPath: keypath]!
        }
    }
    
    /// Inject only a get-only property of a dependency, resolved by the storage.
    ///
    public init(_ keypath: KeyPath<Source, Value?>,
                `default`: Value? = nil,
                restoredBy dependencyStorage: DependencyRestoring = Zerk.storage) {
        self.source = dependencyStorage.restore()
        self.keypath = keypath
        self.default = `default`
    }
}

/// This property wrapper is to be used for injecting only the unwrapped optional property, not the whole dependency instance. If a default value has been given, the injected property will be unwrapped by the given default value. Else the property will be force-unwrapped.
/// Injected properties are settable.
/// The dependencies are needed to be stored via the storage given in the initializers before being injected.
///
/// Usage:
///
///     // Restored by the standard storage, force-unwrapped:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty)
///     var property: PropertyType
///
///     // Restored by the standard storage, unwrapped with the given default value:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty, default: someValue)
///     var property: PropertyType
///
///     // Restored by a custom storage, force-unwrapped:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty, restoredBy: customStorage)
///     var property: PropertyType
///
///     // Restored by a custom storage, unwrapped with the given default value:
///     @InjectedUnwrappedProperty(\Dependency.optionalProperty, default: someValue, restoredBy: customStorage)
///     var property: PropertyType
///
@propertyWrapper
public struct InjectedUnwrappedWritableProperty<Source, Value> {
    private var source: Source
    private let keypath: WritableKeyPath<Source, Value?>
    private let `default`: Value?
    public var wrappedValue: Value {
        get {
            source[keyPath: keypath] ?? `default` ?? source[keyPath: keypath]!
        } set {
            source[keyPath: keypath] = newValue
        }
    }
    
    /// Inject only a get-only property of a dependency, resolved by the storage.
    ///
    public init(_ keypath: WritableKeyPath<Source, Value?>,
                `default`: Value? = nil,
                restoredBy dependencyStorage: DependencyRestoring = Zerk.storage) {
        self.source = dependencyStorage.restore()
        self.keypath = keypath
        self.default = `default`
    }
}

/// This property wrapper is to be used for injecting only the method, not the whole dependency instance.
/// As Swift currently doesn't support keypaths to methods, this wrapper had to be working in a different way.
/// For this to be working as needed, the initializer has to be given the function directly from the dependency type, with the parameter naming if necessary.
/// The dependencies are needed to be stored via the storage given in the initializers before being injected.
///
/// Usage:
///
///     // If there is no similar named method or the method doesn't have any parameters in its signature:
///     @InjectedMethod(Dependency.method)
///     var method: (ParameterType0, ParameterType1, ...) -> ReturnType
///
///     // If there is similar named method(s) and the method has some parameters in its signature:
///     @InjectedMethod(Dependency.method(_: parameter1: ...))
///     var method: (ParameterType0, ParameterType1, ...) -> ReturnType
///
///     // Resored by a custom storage:
///     @InjectedMethod(Dependency.method(_: parameter1: ...), restoredBy: someStorage)
///     var method: (ParameterType0, ParameterType1, ...) -> ReturnType
///
@propertyWrapper
public struct InjectedMethod<Source, Method> {
    
    public let wrappedValue: Method
    
    /// Inject only a method of a dependency, resolved by the storage.
    ///
    public init(_ method: (Source) -> Method,
                restoredBy dependencyStorage: DependencyRestoring = Zerk.storage) {
        wrappedValue = method(dependencyStorage.restore())
    }
}
