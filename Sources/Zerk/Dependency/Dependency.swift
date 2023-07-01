//
//  Dependency.swift
//  
//
//  Created by Ömer Faruk Gökce on 30.06.2023.
//

import Foundation

public enum DependencyLifeTime {
    case transient, scoped, singleton
}

public class Dependency {
    
    public let lifeTime: DependencyLifeTime
    
    private let builder: (DependencyArguments) -> Any?
    
    internal var instance: Any?
    
    public init<D>(lifeTime: DependencyLifeTime,
            builder: @escaping (DependencyArguments) -> D) {
        self.lifeTime = lifeTime
        self.builder = builder
    }
    
    /// Get the instance of the stored dependency object. If it's not yet instantiated or if it's not a singleton, it will be first and then the instance will be returned.
    public func getInstance<D>(with arguments: DependencyArguments = .arguments) -> D {
        if lifeTime == .singleton, let instance = instance {
            return casted(instance)
        } else {
            return build(with: arguments)
        }
    }
    
    private func build<D>(with arguments: DependencyArguments) -> D {
        if let instance = builder(arguments) {
            if lifeTime == .singleton {
                self.instance = instance
            }
            return casted(instance)
        } else {
            fatalError("\(D.self) couldn't have been instantiated with arguments \(arguments.args).")
        }
    }
    
    private func casted<D>(_ instance: Any) -> D {
        if let instance = instance as? D {
            return instance
        } else {
            fatalError("\(type(of: instance)) have already been initialized but couldn't have been typecasted to \(D.self).")
        }
    }
}
