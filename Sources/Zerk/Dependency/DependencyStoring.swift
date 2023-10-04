//
//  DependencyStoring.swift
//  
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

import Foundation

public protocol DependencyStoring {
    
    
    //MARK: Transient
    
    /// This function stores dependencies for dependency injection.
    /// Store dependencies as protocols for better testability.
    /// Since the parameter of this function is an autoclosure, the instance is only created when needed.
    ///
    /// Usage:
    ///
    ///     .store(dependencyInstance as DependencyProtocol)
    ///
    @discardableResult func transient<D>(_ builder: @escaping @autoclosure () -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency: $0)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T, D>(_ builder: @escaping (T) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, D>(_ builder: @escaping (T0, T1) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, D>(_ builder: @escaping (T0, T1, T2) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, D>(_ builder: @escaping (T0, T1, T2, T3) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, T4, D>(_ builder: @escaping (T0, T1, T2, T3, T4) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, T4, T5, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, T4, T5, T6, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, T4, T5, T6, T7, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, T4, T5, T6, T7, T8, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8, T9) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { storage -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore())
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<D>(_ builder: @escaping (_ storage: DependencyRestoring) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<D>(_ builder: @escaping (_ storage: DependencyRestoring, _ arguments: DependencyArguments) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<D>(_ types: Any.Type..., builder: @escaping @autoclosure () -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///     }
    ///
    @discardableResult func transient<D>(_ types: Any.Type..., builder: @escaping (_ storage: DependencyRestoring) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func transient<D>(_ types: Any.Type..., builder: @escaping (_ storage: DependencyRestoring, _ arguments: DependencyArguments) -> D) -> DependencyStoring
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    //MARK: - Scoped
    
    /// This function stores dependencies for dependency injection.
    /// Store dependencies as protocols for better testability.
    /// Since the parameter of this function is an autoclosure, the instance is only created when needed.
    ///
    /// Usage:
    ///
    ///     .store(dependencyInstance as DependencyProtocol)
    ///
    @discardableResult func scoped<D>(_ builder: @escaping @autoclosure () -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency: $0)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T, D>(_ builder: @escaping (T) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, D>(_ builder: @escaping (T0, T1) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, D>(_ builder: @escaping (T0, T1, T2) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, D>(_ builder: @escaping (T0, T1, T2, T3) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, T4, D>(_ builder: @escaping (T0, T1, T2, T3, T4) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, T4, T5, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, T4, T5, T6, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, T4, T5, T6, T7, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, T4, T5, T6, T7, T8, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8, T9) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { storage -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore())
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<D>(_ builder: @escaping (_ storage: DependencyRestoring) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<D>(_ builder: @escaping (_ storage: DependencyRestoring, _ arguments: DependencyArguments) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<D>(_ types: Any.Type..., builder: @escaping @autoclosure () -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///     }
    ///
    @discardableResult func scoped<D>(_ types: Any.Type..., builder: @escaping (_ storage: DependencyRestoring) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func scoped<D>(_ types: Any.Type..., builder: @escaping (_ storage: DependencyRestoring, _ arguments: DependencyArguments) -> D) -> DependencyStoring
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    //MARK: - Singleton
    
    /// This function stores dependencies for dependency injection.
    /// Store dependencies as protocols for better testability.
    /// Since the parameter of this function is an autoclosure, the instance is only created when needed.
    ///
    /// Usage:
    ///
    ///     .store(dependencyInstance as DependencyProtocol)
    ///
    @discardableResult func singleton<D>(_ builder: @escaping @autoclosure () -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency: $0)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T, D>(_ builder: @escaping (T) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, D>(_ builder: @escaping (T0, T1) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, D>(_ builder: @escaping (T0, T1, T2) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, D>(_ builder: @escaping (T0, T1, T2, T3) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, T4, D>(_ builder: @escaping (T0, T1, T2, T3, T4) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, T4, T5, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, T4, T5, T6, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, T4, T5, T6, T7, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, T4, T5, T6, T7, T8, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store {
    ///        DependentClass(dependency0: $0, dependency1: $1, dependency2: $2, dependency3: $3, dependency4: $4)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, D>(_ builder: @escaping (T0, T1, T2, T3, T4, T5, T6, T7, T8, T9) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    ///
    /// Usage:
    ///
    ///     .store { storage -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore())
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<D>(_ builder: @escaping (_ storage: DependencyRestoring) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<D>(_ builder: @escaping (_ storage: DependencyRestoring, _ arguments: DependencyArguments) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<D>(_ types: Any.Type..., builder: @escaping @autoclosure () -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///     }
    ///
    @discardableResult func singleton<D>(_ types: Any.Type..., builder: @escaping (_ storage: DependencyRestoring) -> D) -> DependencyStoring
    
    /// This function allows storing dependencies which are dependent to other stored dependencies with additional arguments that can be passed when being initialized.
    /// The dependencies needed by this dependency should be stored also.
    /// In order to remove any possibility of circular dependency, dependencies should only be one-way dependent to eachother. Otherwise there will definitely be an infinite loop.
    /// The argumentation naming is dynamic but required and will be checked in run-time.
    ///
    /// Usage:
    ///
    ///     .store { storage, arguments -> DependentProtocol in
    ///        return DependenentClass(dependency: storage.restore(), argument: arguments.argument)
    ///        as DependencyProtocol
    ///     }
    ///
    @discardableResult func singleton<D>(_ types: Any.Type..., builder: @escaping (_ storage: DependencyRestoring, _ arguments: DependencyArguments) -> D) -> DependencyStoring
}
