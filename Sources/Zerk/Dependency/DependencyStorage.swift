//
//  DependencyStorage.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

/**
 This is the standard storage class provided by Zerk which would be used in most cases.
 The stored dependencies will not be instantiated until they are called.
 
 The dependencies should conform to one of the three protocols: `TransientDependency`, `ScopedDependency` or `SingletonDependency`
 
 - TransientDependency:
    Dependencies of this type are initialized every time they are being called.
 
 - ScopedDependency:
    Dependencies of this type are initialized every time they are being restored by restore functions. This type is used by Zerk's property wrappers to ensure the instance live as long as their dependent object lives.
 
 - SingletonDependency:
    Dependencies of this type are initialized only once when they are first called, then they are stored as instances in the storage and can be used globally.
 */
class DependencyStorage {
    
    internal var dependencies: [ObjectIdentifier: Dependency] = [:]
    
    private let lock = NSLock()
    
}

extension DependencyStorage {
    
    private static var didAutoStore: Bool = false
    
    private static func checkAutoStoring() {
        if let zerk = Zerk.self as? AutoStoring.Type, !didAutoStore {
            zerk.store()
            didAutoStore = true
        }
    }
}

extension DependencyStorage: DependencyRestoring {
    
    //MARK: - Restoring
    func restore<D>() -> D {
        restore(D.self)
            .getInstance()
    }
    
    func restore<D>(with arguments: DependencyArguments) -> D {
        restore(D.self)
            .getInstance(with: arguments)
    }
    
    func restore<D>(_ dependency: D.Type) -> Dependency {
        
        lock.lock(); defer { lock.unlock() }
        
        DependencyStorage.checkAutoStoring()
        
        let identifier = ObjectIdentifier(D.self)
        if let dependency = dependencies[identifier] {
            return dependency
        } else {
            fatalError("\(D.self) has not been stored as an injectable object.")
        }
    }
}

extension DependencyStorage: DependencyStoring {
    
    //MARK: - Storing transients
    func transient<D>(_ builder: @autoclosure @escaping () -> D) -> DependencyStoring {
        transient { _ in
            builder()
        }
    }
    
    func transient<T, D>(_ builder: @escaping (T) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore())
        }
    }
    
    func transient<T0, T1, D>(_ builder: @escaping (T0, T1) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, D>(_ builder: @escaping (T0, T1, T2) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, D>(_ builder: @escaping (T0, T1, T2, T3) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, T4, D>(_ builder: @escaping (T0, T1, T2, T3, T4) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, T4, T5, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, T4, T5, T6, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, T4, T5, T6, T7, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, T4, T5, T6, T7, T8, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8, T9) -> D) -> DependencyStoring {
        transient { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func transient<D>(_ builder: @escaping (DependencyRestoring) -> D) -> DependencyStoring {
        transient { storage, _ in
            builder(storage)
        }
    }
    
    func transient<D>(_ builder: @escaping (DependencyRestoring, DependencyArguments) -> D) -> DependencyStoring {
        transient(builder, as: D.self)
    }
    
    func transient<D>(_ builder: @escaping (DependencyRestoring, DependencyArguments) -> D, as types: Any.Type...) -> DependencyStoring {
        store(lifeTime: .transient, types: types, builder: builder)
    }
    
    //MARK: - Storing scopeds
    func scoped<D>(_ builder: @autoclosure @escaping () -> D) -> DependencyStoring {
        scoped { _ in
            builder()
        }
    }
    
    func scoped<T, D>(_ builder: @escaping (T) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore())
        }
    }
    
    func scoped<T0, T1, D>(_ builder: @escaping (T0, T1) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, D>(_ builder: @escaping (T0, T1, T2) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, D>(_ builder: @escaping (T0, T1, T2, T3) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, T4, D>(_ builder: @escaping (T0, T1, T2, T3, T4) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, T4, T5, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, T4, T5, T6, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, T4, T5, T6, T7, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, T4, T5, T6, T7, T8, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8, T9) -> D) -> DependencyStoring {
        scoped { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func scoped<D>(_ builder: @escaping (DependencyRestoring) -> D) -> DependencyStoring {
        scoped { storage, _ in
            builder(storage)
        }
    }
    
    func scoped<D>(_ builder: @escaping (DependencyRestoring, DependencyArguments) -> D) -> DependencyStoring {
        scoped(builder, as: D.self)
    }
    
    func scoped<D>(_ builder: @escaping (DependencyRestoring, DependencyArguments) -> D, as types: Any.Type...) -> DependencyStoring {
        store(lifeTime: .scoped, types: types, builder: builder)
    }
    
    //MARK: - Storing singletons
    func singleton<D>(_ builder: @autoclosure @escaping () -> D) -> DependencyStoring {
        singleton { _ in
            builder()
        }
    }
    
    func singleton<T, D>(_ builder: @escaping (T) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore())
        }
    }
    
    func singleton<T0, T1, D>(_ builder: @escaping (T0, T1) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, D>(_ builder: @escaping (T0, T1, T2) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, D>(_ builder: @escaping (T0, T1, T2, T3) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, T4, D>(_ builder: @escaping (T0, T1, T2, T3, T4) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, T4, T5, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, T4, T5, T6, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, T4, T5, T6, T7, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, T4, T5, T6, T7, T8, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8, T9) -> D) -> DependencyStoring {
        singleton { storage in
            builder(storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore(),
                    storage.restore())
        }
    }
    
    func singleton<D>(_ builder: @escaping (DependencyRestoring) -> D) -> DependencyStoring {
        singleton { storage, _ in
            builder(storage)
        }
    }
    
    func singleton<D>(_ builder: @escaping (DependencyRestoring, DependencyArguments) -> D) -> DependencyStoring {
        singleton(builder, as: D.self)
    }
    
    func singleton<D>(_ builder: @escaping (DependencyRestoring, DependencyArguments) -> D, as types: Any.Type...) -> DependencyStoring {
        store(lifeTime: .singleton, types: types, builder: builder)
    }
    
    
    //MARK: - Storing all
    private func store(lifeTime: DependencyLifeTime,
                       types: [Any.Type],
                       builder: @escaping (DependencyRestoring, DependencyArguments) -> Any?) -> DependencyStoring {
        
        lock.lock(); defer { lock.unlock() }
        
        let dependency = Dependency(lifeTime: lifeTime) { [weak self] arguments in
            guard let self = self else {
                fatalError("DependencyStorage has not been initialized or has been removed from memory")
            }
            return builder(self, arguments)
        }
        
        for type in types {
            let identifier = ObjectIdentifier(type)
            dependencies[identifier] = dependency
        }
        
        return self
    }
}
