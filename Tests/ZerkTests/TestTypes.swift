//
//  File.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation
import Zerk

protocol DependencyProtocolA {
    var readOnlyProperty: Bool? { get }
    var readWriteProperty: Bool? { get set }
    func simpleMethod() -> Bool
    func parameterMethod(param: Int, _: Bool) -> Bool
}

class DependencyClassA: DependencyProtocolA {
    var readOnlyProperty: Bool? = true
    
    var readWriteProperty: Bool? = true
    
    func simpleMethod() -> Bool {
        return true
    }
    
    func parameterMethod(param: Int, _: Bool) -> Bool {
        return true
    }
}

protocol DependencyProtocolB {
    var readOnlyProperty: Bool? { get }
    var readWriteProperty: Bool? { get set }
}

class DependencyClassB: DependencyProtocolB {
    var readOnlyProperty: Bool?
    
    var readWriteProperty: Bool?
    
    init(dependency: DependencyProtocolA) {
        readOnlyProperty = dependency.readOnlyProperty
        readWriteProperty = dependency.readWriteProperty
    }
}

class DependentClass {
    @Injected var dependency: DependencyProtocolA
    
    @InjectedProperty(\DependencyProtocolA.readOnlyProperty)
    var readOnlyProperty: Bool?
    
    @InjectedWritableProperty(\DependencyProtocolA.readWriteProperty)
    var readWriteProperty: Bool?
    
    @InjectedUnwrappedProperty(\DependencyProtocolA.readOnlyProperty)
    var unwrappedReadOnlyProperty: Bool
    
    @InjectedUnwrappedWritableProperty(\DependencyProtocolA.readWriteProperty)
    var unwrappedReadWriteProperty: Bool
    
    @InjectedMethod(DependencyProtocolA.simpleMethod)
    var simpleMethod: () -> Bool
    
    @InjectedMethod(DependencyProtocolA.parameterMethod)
    var parameterMethod: (Int, Bool) -> Bool
}
