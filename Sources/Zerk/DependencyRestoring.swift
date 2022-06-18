//
//  File.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

public protocol DependencyRestoring {
    
    /// This function restores the stored dependency instances.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restore<Dependency>() -> Dependency
    
    /// This function restores the stored dependency instances.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restore<Dependency>(_ dependency: Dependency.Type) -> Dependency
    
    /// This function restores the stored dependency instances to be used only once.
    /// The restored dependency is always a new instance and will not be stored.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restoreOnce<Dependency>() -> Dependency
    
    /// This function restores the stored dependency instances to be used only once.
    /// The restored dependency is always a new instance and will not be stored.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restoreOnce<Dependency>(_ dependency: Dependency.Type) -> Dependency
}

public extension DependencyRestoring {
    func restore<Dependency>() -> Dependency {
        fatalError("Function is not implemented")
    }
    func restore<Dependency>(_ dependency: Dependency.Type) -> Dependency {
        fatalError("Function is not implemented")
    }
    func restoreOnce<Dependency>() -> Dependency {
        fatalError("Function is not implemented")
    }
    func restoreOnce<Dependency>(_ dependency: Dependency.Type) -> Dependency {
        fatalError("Function is not implemented")
    }
}
