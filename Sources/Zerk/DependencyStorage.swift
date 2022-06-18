//
//  DependencyStorage.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//



/// This class stores instances for dependency injection.
/// The stored dependencies will not be instantiated until they are called.
/// Injected dependencies are stored as builder methods until the very first time they are called, then they are stored as instances and can be used globally.
///
/// Usage:
///
///     // Setting the standard storage
///     DependencyStorage.standard
///        .store(dependencyInstance1 as DependencyProtocol1)
///        .store(dependencyInstance2 as DependencyProtocol2)
///        .store { storage in
///            DependencyClass3(dependency: storage.resolve())
///            as DependencyProtocol3
///        }
///        .store { dependency in
///            DependencyClass4(dependency: dependency)
///            as DependencyProtocol4
///        }
///
internal class DependencyStorage {
    
    public private(set) static var standard = DependencyStorage()
    
    internal var storage: [String: Any] = [:]
    
    internal var builders: [String: () -> Any?] = [:]
}
