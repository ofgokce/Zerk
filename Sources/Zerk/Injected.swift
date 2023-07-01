//
//  Injected.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

internal class InjectionHolder<D> {
    
    private let arguments: DependencyArguments
    private let dependency: Dependency
    private var scopedInstance: D?
    
    var instance: D {
        get {
            switch dependency.lifeTime {
            case .transient, .singleton:
                return dependency.getInstance(with: arguments)
            case .scoped:
                if let instance = scopedInstance {
                    return instance
                } else {
                    let instance: D = dependency.getInstance(with: arguments)
                    scopedInstance = instance
                    return instance
                }
            }
        } set {
            dependency.instance = newValue
        }
    }
    
    init(from storage: DependencyRestoring,
         with arguments: DependencyArguments) {
        self.arguments = arguments
        self.dependency = storage.restore(D.self)
    }
}

/**
 This property wrapper is to be used for dependency injection.
 The dependencies are needed to be stored via the storage given in the initializers before being injected.
 
 - Restored from the standard storage:
 ```
 @Injected
 var dependency: DependencyType
 ```
 
 - Restored from a custom storage:
 ```
 @Injected(from: customStorage)
 var dependency: DependencyType
 ```
 
 - Restored with arguments:
 ```
 @Injected(with: .arguments(arg0: val0, arg1: val1)
 var dependency: DependencyType
 ```
 
 - Restored with arguments from a custom storage:
 ```
 @Injected(from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var dependency: DependencyType
 ```
 */
@propertyWrapper
public struct Injected<D> {
    private let holder: InjectionHolder<D>
    public var wrappedValue: D { holder.instance }
    
    /**
     Inject the whole dependency instance.
     - Parameters:
        - storage: The dependency storage from where the dependency will be restored. Zerk's default storage will be used if not given.
        - arguments: The arguments which will be used for instantiation of the dependency. Checked in runtime so make sure to use the correct naming and type.
    */
    public init(from storage: DependencyRestoring = Zerk.standardStorage,
                with arguments: DependencyArguments = .arguments) {
        self.holder = InjectionHolder(from: storage, with: arguments)
    }
}

/**
 This property wrapper is to be used for injecting only a get-only property of a dependency, not the whole dependency instance.
 The dependencies are needed to be stored via the storage given in the initializers before being injected.
 
 The keypath notation is important and the source type should be of type which has been used to store the dependency. (e.g.: `\DependencyType.propertyName`)
 
 The path on keypath can be leveled down. (e.g.: `\DependencyType.propertyName.subpropertyName` etc.)
 
 - Restored from the standard storage:
 ```
 @InjectedProperty(\DependencyType.propertyName)
 var property: PropertyType
 ```
 
 - Restored from a custom storage:
 ```
 @InjectedProperty(\DependencyType.propertyName, from: customStorage)
 var property: PropertyType
 ```
 
 - Restored with arguments:
 ```
 @InjectedProperty(\DependencyType.propertyName, with: .arguments(arg0: val0, arg1: val1)
 var property: PropertyType
 ```
 
 - Restored with arguments from a custom storage:
 ```
 @InjectedProperty(\DependencyType.propertyName, from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var property: PropertyType
 ```
 */
@propertyWrapper
public struct InjectedProperty<Source, Value> {
    private let holder: InjectionHolder<Source>
    private let keypath: KeyPath<Source, Value>
    public var wrappedValue: Value {
        get {
            holder.instance[keyPath: keypath]
        }
    }
    
    /**
     Inject only a get-only property of a dependency.
     - Parameters:
        - keypath: The keypath to the property of the dependency.
        - storage: The dependency storage from where the dependency will be restored. Zerk's default storage will be used if not given.
        - arguments: The arguments which will be used for instantiation of the dependency. Checked in runtime so make sure to use the correct naming and type.
    */
    public init(_ keypath: KeyPath<Source, Value>,
                from storage: DependencyRestoring = Zerk.standardStorage,
                with arguments: DependencyArguments = .arguments) {
        self.keypath = keypath
        self.holder = InjectionHolder(from: storage, with: arguments)
    }
}

/**
 This property wrapper is to be used for injecting only a mutable property of a dependency, not the whole dependency instance.
 The dependencies are needed to be stored via the storage given in the initializers before being injected.
 
 The keypath notation is important and the source type should be of type which has been used to store the dependency. (e.g.: `\DependencyType.propertyName`)
 
 The path on keypath can be leveled down. (e.g.: `\DependencyType.propertyName.subpropertyName` etc.)
 
 - Restored from the standard storage:
 ```
 @InjectedMutableProperty(\DependencyType.propertyName)
 var property: PropertyType
 ```
 
 - Restored from a custom storage:
 ```
 @InjectedMutableProperty(\DependencyType.propertyName, from: customStorage)
 var property: PropertyType
 ```
 
 - Restored with arguments:
 ```
 @InjectedMutableProperty(\DependencyType.propertyName, with: .arguments(arg0: val0, arg1: val1)
 var property: PropertyType
 ```
 
 - Restored with arguments from a custom storage:
 ```
 @InjectedMutableProperty(\DependencyType.propertyName, from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var property: PropertyType
 ```
 */
@propertyWrapper
public struct InjectedMutableProperty<Source, Value> {
    private let holder: InjectionHolder<Source>
    private let keypath: WritableKeyPath<Source, Value>
    public var wrappedValue: Value {
        get {
            holder.instance[keyPath: keypath]
        } set {
            holder.instance[keyPath: keypath] = newValue
        }
    }
    
    /**
     Inject only a mutable property of a dependency.
     - Parameters:
        - keypath: The keypath to the property of the dependency.
        - storage: The dependency storage from where the dependency will be restored. Zerk's default storage will be used if not given.
        - arguments: The arguments which will be used for instantiation of the dependency. Checked in runtime so make sure to use the correct naming and type.
    */
    public init(_ keypath: WritableKeyPath<Source, Value>,
                from storage: DependencyRestoring = Zerk.standardStorage,
                with arguments: DependencyArguments = .arguments) {
        self.keypath = keypath
        self.holder = InjectionHolder(from: storage, with: arguments)
    }
}

/**
 This property wrapper is to be used for injecting only an unwrapped optional get-only property, not the whole dependency instance. If a default value has been given, the injected property will be unwrapped by the given default value. Else the property will be force-unwrapped.
 The dependencies are needed to be stored via the storage given in the initializers before being injected.
 
 The keypath notation is important and the source type should be of type which has been used to store the dependency. (e.g.: `\DependencyType.propertyName`)
 
 The path on keypath can be leveled down. (e.g.: `\DependencyType.propertyName.subpropertyName` etc.)
 
 - Restored from the standard storage without a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored from the standard storage with a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, default: defaultvalue)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored from a custom storage without a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, from: customStorage)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored from a custom storage with a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, default: defaultvalue, from: customStorage)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments without a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments with a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, default: defaultvalue, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments from a custom storage without a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments from a custom storage with a default value:
 ```
 @InjectedUnwrappedProperty(\DependencyType.optionalPropertyName, default: defaultvalue, from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 */
@propertyWrapper
public struct InjectedUnwrappedProperty<Source, Value> {
    private let holder: InjectionHolder<Source>
    private let keypath: KeyPath<Source, Value?>
    private let `default`: Value?
    public var wrappedValue: Value {
        get {
            holder.instance[keyPath: keypath]
            ?? `default`
            ?? holder.instance[keyPath: keypath]!
        }
    }
    
    /**
     Inject only an unwrapped optional get-only property of a dependency.
     - Parameters:
        - keypath: The keypath to the optional property of the dependency.
        - default: The default value which will be used to unwrap the optional property if it's `nil`. The property will be force unwrapped if this isn't provided.
        - storage: The dependency storage from where the dependency will be restored. Zerk's default storage will be used if not given.
        - arguments: The arguments which will be used for instantiation of the dependency. Checked in runtime so make sure to use the correct naming and type.
    */
    public init(_ keypath: KeyPath<Source, Value?>,
                `default`: Value? = nil,
                from storage: DependencyRestoring = Zerk.standardStorage,
                with arguments: DependencyArguments = .arguments) {
        self.keypath = keypath
        self.default = `default`
        self.holder = InjectionHolder(from: storage, with: arguments)
    }
}

/**
 This property wrapper is to be used for injecting only an unwrapped optional mutable property, not the whole dependency instance. If a default value has been given, the injected property will be unwrapped by the given default value. Else the property will be force-unwrapped.
 The dependencies are needed to be stored via the storage given in the initializers before being injected.
 
 The keypath notation is important and the source type should be of type which has been used to store the dependency. (e.g.: `\DependencyType.propertyName`)
 
 The path on keypath can be leveled down. (e.g.: `\DependencyType.propertyName.subpropertyName` etc.)
 
 - Restored from the standard storage without a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored from the standard storage with a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, default: defaultvalue)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored from a custom storage without a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, from: customStorage)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored from a custom storage with a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, default: defaultvalue, from: customStorage)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments without a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments with a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, default: defaultvalue, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments from a custom storage without a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 
 - Restored with arguments from a custom storage with a default value:
 ```
 @InjectedUnwrappedMutableProperty(\DependencyType.optionalPropertyName, default: defaultvalue, from: customStorage, with: .arguments(arg0: val0, arg1: val1)
 var unwrappedProperty: PropertyType
 ```
 */
@propertyWrapper
public struct InjectedUnwrappedMutableProperty<Source, Value> {
    private let holder: InjectionHolder<Source>
    private let keypath: WritableKeyPath<Source, Value?>
    private let `default`: Value?
    public var wrappedValue: Value {
        get {
            holder.instance[keyPath: keypath]
            ?? `default`
            ?? holder.instance[keyPath: keypath]!
        } set {
            holder.instance[keyPath: keypath] = newValue
        }
    }
    
    /**
     Inject only an unwrapped optional mutable property of a dependency.
     - Parameters:
        - keypath: The keypath to the optional property of the dependency.
        - default: The default value which will be used to unwrap the optional property if it's `nil`. The property will be force unwrapped if this isn't provided.
        - storage: The dependency storage from where the dependency will be restored. Zerk's default storage will be used if not given.
        - arguments: The arguments which will be used for instantiation of the dependency. Checked in runtime so make sure to use the correct naming and type.
    */
    public init(_ keypath: WritableKeyPath<Source, Value?>,
                `default`: Value? = nil,
                from storage: DependencyRestoring = Zerk.standardStorage,
                with arguments: DependencyArguments = .arguments) {
        self.keypath = keypath
        self.`default` = `default`
        self.holder = InjectionHolder(from: storage, with: arguments)
    }
}

///// This property wrapper is to be used for injecting only the method, not the whole dependency instance.
///// As Swift currently doesn't support keypaths to methods, this wrapper had to be working in a different way.
///// For this to be working as needed, the initializer has to be given the function directly from the dependency type, with the parameter naming if necessary.
///// The dependencies are needed to be stored via the storage given in the initializers before being injected.
/////
///// Usage:
/////
/////     // If there is no similar named method or the method doesn't have any parameters in its signature:
/////     @InjectedMethod(Dependency.method)
/////     var method: (ParameterType0, ParameterType1, ...) -> ReturnType
/////
/////     // If there is similar named method(s) and the method has some parameters in its signature:
/////     @InjectedMethod(Dependency.method(_: parameter1: ...))
/////     var method: (ParameterType0, ParameterType1, ...) -> ReturnType
/////
/////     // Resored by a custom storage:
/////     @InjectedMethod(Dependency.method(_: parameter1: ...), restoredBy: someStorage)
/////     var method: (ParameterType0, ParameterType1, ...) -> ReturnType
/////
//@propertyWrapper
//public struct InjectedMethod<Source: Dependency, Method> {
//    private let holder: InjectionHolder<Source>
//    private let method: (Source) -> Method
//    public var wrappedValue: Method {
//        get {
//            method(holder.dependency)
//        }
//    }
//
//    /// Inject only a method of a dependency, resolved by the storage.
//    ///
//    public init(_ method: @escaping (Source) -> Method,
//                from storage: DependencyRestoring = Zerk.storage,
//                with arguments: DependencyArguments = .arguments) {
//        self.method = method
//        self.holder = InjectionHolder(from: storage, with: arguments)
//    }
//}
