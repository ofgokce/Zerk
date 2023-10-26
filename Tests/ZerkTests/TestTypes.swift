//
//  File.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation
import Zerk

extension Zerk: AutoStoring {
    public static func autoStore() {
        Zerk.store
            .transient(TransientTestClass() as TransientTestProtocol)
            .scoped(ScopedTestClass() as ScopedTestProtocol)
            .singleton(SingletonTestClass() as SingletonTestProtocol)
            .singleton(BasicTestClass() as BasicTestProtocol)
            .singleton {
                DependentTestClass(dependency: $0)
                as DependentTestProtocol
            }
            .singleton { storage, arguments in
                ArgumentativeTestClass(booleanArgument: arguments.booleanArgument,
                                       stringArgument: arguments.stringArgument,
                                       intArgument: arguments.intArgument)
                as ArgumentativeTestProtocol
            }
            .singleton(MultitypeTestProtocolA.self, MultitypeTestProtocolB.self) { storage, arguments in
                MultitypeTestClass()
            }
            .singleton(ClassWithoutProtocol())
            .singleton {
                ClassWithOptionalInitParameter(basicTestInstance: $0)
                as ProtocolWithOptionalInitParameter
            }
    }
}

protocol TransientTestProtocol: AnyObject {
    
}

class TransientTestClass: TransientTestProtocol {
    
}

protocol ScopedTestProtocol: AnyObject {
    
}

class ScopedTestClass: ScopedTestProtocol {
    
}

protocol SingletonTestProtocol: AnyObject {
    
}

class SingletonTestClass: SingletonTestProtocol {
    
}

protocol BasicTestProtocol: AnyObject {
    var readOnlyProperty: Bool? { get }
    var readWriteProperty: Bool? { get set }
}

class BasicTestClass: BasicTestProtocol {
    var readOnlyProperty: Bool? = true
    var readWriteProperty: Bool? = true
}

protocol DependentTestProtocol {
    var dependency: BasicTestProtocol { get }
}

class DependentTestClass: DependentTestProtocol {
    let dependency: BasicTestProtocol
    
    init(dependency: BasicTestProtocol) {
        self.dependency = dependency
    }
}

protocol ArgumentativeTestProtocol {
    var booleanArgument: Bool { get }
    var stringArgument: String { get }
    var intArgument: Int { get }
}

class ArgumentativeTestClass: ArgumentativeTestProtocol {
    var booleanArgument: Bool
    var stringArgument: String
    var intArgument: Int
    
    init(booleanArgument: Bool, stringArgument: String, intArgument: Int) {
        self.booleanArgument = booleanArgument
        self.stringArgument = stringArgument
        self.intArgument = intArgument
    }
}

protocol MultitypeTestProtocolA {
    var propertyA: String { get }
}

protocol MultitypeTestProtocolB {
    var propertyB: String { get }
}

class MultitypeTestClass: MultitypeTestProtocolA, MultitypeTestProtocolB {
    var propertyA: String = "A"
    var propertyB: String = "B"
}

class ClassWithoutProtocol {
    var propertyA: String = "A"
}

protocol ProtocolWithOptionalInitParameter {
    var basicTestInstance: BasicTestProtocol? { get }
}

class ClassWithOptionalInitParameter: ProtocolWithOptionalInitParameter {
    var basicTestInstance: BasicTestProtocol?
    
    init(basicTestInstance: BasicTestProtocol?) {
        self.basicTestInstance = basicTestInstance
    }
}

class MainTestClass {
    
    @Injected
    var transientDependency: TransientTestProtocol
    
    @Injected
    var scopedDependency: ScopedTestProtocol
    
    @Injected
    var singletonDependency: SingletonTestProtocol
    
    @Injected
    var basicDependency: BasicTestProtocol
    
    @Injected
    var dependentDependency: DependentTestProtocol
    
    @Injected(with: .arguments(booleanArgument: true, stringArgument: "string", intArgument: 1))
    var argumentativeDependency: ArgumentativeTestProtocol
    
    @Injected
    var multitypeDependencyProtocolA: MultitypeTestProtocolA
    
    @Injected
    var multitypeDependencyProtocolB: MultitypeTestProtocolB
    
    @InjectedProperty(\BasicTestProtocol.readOnlyProperty)
    var readOnlyProperty: Bool?
    
    @InjectedMutableProperty(\BasicTestProtocol.readWriteProperty)
    var readWriteProperty: Bool?
    
    @InjectedUnwrappedProperty(\BasicTestProtocol.readOnlyProperty)
    var unwrappedReadOnlyProperty: Bool
    
    @InjectedUnwrappedMutableProperty(\BasicTestProtocol.readWriteProperty)
    var unwrappedReadWriteProperty: Bool
    
    @Injected
    var dependencyWithoutProtocol: ClassWithoutProtocol
    
    @Injected
    var dependencyWithOptionalInitParameter: ProtocolWithOptionalInitParameter
}
