//
//  DependencyStorageStoring.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

extension DependencyStorage: DependencyStoring {
    
    @discardableResult
    func store<Dependency>(_ dependencyBuilder: @escaping @autoclosure () -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = {
            return dependencyBuilder()
        }
        return self
    }
    
    @discardableResult
    func store<Dependency>(_ dependencyBuilder: @escaping (DependencyRestoring) -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = { [weak self] in
            guard let self = self else { return nil }
            return dependencyBuilder(self)
        }
        return self
    }
    
    @discardableResult
    func store<T, Dependency>(_ dependencyBuilder: @escaping (T) -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = { [weak self] in
            guard let self = self else { return nil }
            return dependencyBuilder(self.restore())
        }
        return self
    }
    
    @discardableResult
    func store<T0, T1, Dependency>(_ dependencyBuilder: @escaping (T0, T1) -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = { [weak self] in
            guard let self = self else { return nil }
            return dependencyBuilder(self.restore(),
                                     self.restore())
        }
        return self
    }
    
    @discardableResult
    func store<T0, T1, T2, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2) -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = { [weak self] in
            guard let self = self else { return nil }
            return dependencyBuilder(self.restore(),
                                     self.restore(),
                                     self.restore())
        }
        return self
    }
    
    @discardableResult
    func store<T0, T1, T2, T3, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2, T3) -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = { [weak self] in
            guard let self = self else { return nil }
            return dependencyBuilder(self.restore(),
                                     self.restore(),
                                     self.restore(),
                                     self.restore())
        }
        return self
    }
    
    @discardableResult
    func store<T0, T1, T2, T3, T4, Dependency>(_ dependencyBuilder: @escaping (T0, T1, T2, T3, T4) -> Dependency) -> DependencyStoring {
        builders["\(Dependency.self)"] = { [weak self] in
            guard let self = self else { return nil }
            return dependencyBuilder(self.restore(),
                                     self.restore(),
                                     self.restore(),
                                     self.restore(),
                                     self.restore())
        }
        return self
    }
}
