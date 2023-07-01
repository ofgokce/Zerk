//
//  File.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

public protocol DependencyRestoring {
    
    /// This function invokes the initialization of the dependency or restores the stored instance.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restore<D>() -> D
    
    /// This function invokes the initialization of the dependency with arguments used for its initialization.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restore<D>(with arguments: DependencyArguments) -> D
    
    /// Restore stored dependency as `Dependency` type. The dependency's instance can be get via its `getInstance` method.
    /// The dependencies are restored via their stored types (e.g. protocol) so make sure you call them by that.
    ///
    func restore<D>(_ dependency: D.Type) -> Dependency
}
