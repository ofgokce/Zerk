//
//  DependencyStoring.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

public protocol DependencyStoring {
    
    /// This function stores dependencies for dependency injection.
    /// Store dependencies as protocols for better testability.
    /// Since the parameter of this function is an autoclosure, the instance is only created when needed.
    ///
    /// Usage:
    ///
    ///     .store(dependencyInstance as DependencyProtocol)
    ///
    @discardableResult func store<Dependency>(_ dependencyBuilder: @escaping @autoclosure () -> Dependency) -> DependencyStoring
    
    /// This function allows creation of dependencies which are dependent to another dependency.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { storage -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.resolve())
    ///     }
    ///
    @discardableResult func store<Dependency>(_ dependencyBuilder: @escaping (DependencyRestoring) -> Dependency) -> DependencyStoring
    
    /// This function allows creation of dependencies which are dependent to another dependency.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { dependency in
    ///        DependentClass(dependency: dependency)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func store<T, Dependency>(_ dependencyBuilder: @escaping (T) -> Dependency) -> DependencyStoring
    
    /// This function allows creation of dependencies which are dependent to another dependency.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { dependency0, dependency1 in
    ///        DependentClass(dependency0: dependency0, dependency1: dependency1)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func store<T0, T1, Dependency>(_ dependencyBuilder: @escaping (T0, T1) -> Dependency) -> DependencyStoring
    
    /// This function allows creation of dependencies which are dependent to another dependency.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { dependency0, dependency1, dependency2 in
    ///        DependentClass(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func store<T0, T1, T2, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2) -> Dependency) -> DependencyStoring
    
    /// This function allows creation of dependencies which are dependent to another dependency.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { dependency0, dependency1, dependency2, dependency3 in
    ///        DependentClass(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func store<T0, T1, T2, T3, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2, T3) -> Dependency) -> DependencyStoring
    
    /// This function allows creation of dependencies which are dependent to other dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { dependency0, dependency1, dependency2, dependency3, dependency4 in
    ///        DependentClass(dependency0: dependency0, dependency1: dependency1, dependency2: dependency2, dependency3: dependency3, dependency4: dependency4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func store<T0, T1, T2, T3, T4, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2, T3, T4) -> Dependency) -> DependencyStoring
}

public extension DependencyStoring {
    @discardableResult func store<Dependency>(_ dependencyBuilder: @escaping @autoclosure () -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
    @discardableResult func store<Dependency>(_ dependencyBuilder: @escaping (DependencyRestoring) -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
    @discardableResult func store<T, Dependency>(_ dependencyBuilder: @escaping (T) -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
    @discardableResult func store<T0, T1, Dependency>(_ dependencyBuilder: @escaping (T0, T1) -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
    @discardableResult func store<T0, T1, T2, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2) -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
    @discardableResult func store<T0, T1, T2, T3, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2, T3) -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
    @discardableResult func store<T0, T1, T2, T3, T4, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2, T3, T4) -> Dependency) -> DependencyStoring {
        fatalError("Function is not implemented")
    }
}
