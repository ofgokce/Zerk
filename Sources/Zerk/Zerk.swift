//
//  Zerk.swift
//
//
//  Created by Ömer Faruk Gökce on 14.06.2022.
//

public final class Zerk {
    
    public static let standardStorage: DependencyRestoring = DependencyStorage()
    
    /// Store the dependencies to the standard storage of Zerk.
    public static var store: DependencyStoring { standardStorage as! DependencyStoring }
    
    public static func newStorage() -> DependencyStoring & DependencyRestoring {
        DependencyStorage()
    }
    
    private init() { }
}
