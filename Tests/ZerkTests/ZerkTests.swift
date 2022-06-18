import XCTest
@testable import Zerk

final class ZerkTests: XCTestCase {
    func testStandardStorage() throws {
        Zerk.storage
            .store(DependencyClassA() as DependencyProtocolA)
            .store { dependency in
                return DependencyClassB(dependency: dependency) as DependencyProtocolB
            }
        
        let dependent = DependentClass()
        
        XCTAssertNotNil(dependent.readOnlyProperty)
        XCTAssertTrue(dependent.unwrappedReadOnlyProperty)
        
        XCTAssertNotNil(dependent.readWriteProperty)
        XCTAssertTrue(dependent.unwrappedReadWriteProperty)
        
        dependent.readWriteProperty = false
        
        XCTAssertFalse(dependent.unwrappedReadWriteProperty)
        
        XCTAssertTrue(dependent.simpleMethod())
        XCTAssertTrue(dependent.parameterMethod(1, true))
    }
    
    func testCustomStorage() throws {
        let storage = DependencyStorage()
        
        storage.store(DependencyClassA() as DependencyProtocolA)
        
        let dependency: DependencyProtocolA = storage.restore()
        
        XCTAssertTrue(dependency.readOnlyProperty ?? false)
    }
}
