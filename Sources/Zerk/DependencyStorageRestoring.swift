//
//  DependencyStorageRestoring.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

extension DependencyStorage: DependencyRestoring {
    
    func restore<Dependency>() -> Dependency {
        let key = "\(Dependency.self)"
        if let dependency = storage[key] as? Dependency {
            return dependency
        } else if let builder = builders[key] {
            if let dependency = builder() as? Dependency {
                storage["\(Dependency.self)"] = dependency
                return dependency
            } else {
                fatalError("\(key) couldn't have been instantiated.")
            }
        } else {
            fatalError("\(key) has not been added as an injectable object.")
        }
    }
    
    func restore<Dependency>(_ dependency: Dependency.Type) -> Dependency {
        return restore()
    }
    
    func restoreOnce<Dependency>() -> Dependency {
        let key = "\(Dependency.self)"
        if let builder = builders[key],
           let dependency = builder() as? Dependency {
            return dependency
        } else {
            fatalError("\(key) couldn't have been instantiated.")
        }
    }
    
    func restoreOnce<Dependency>(_ dependency: Dependency.Type) -> Dependency {
        return restoreOnce()
    }
}
