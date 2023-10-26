import XCTest
@testable import Zerk

final class ZerkTests: XCTestCase {
    func testStandardStorage() throws {
        
        let test = MainTestClass()
        
        //MARK: - Test transient, scoped and singleton dependencies
        
        XCTAssertFalse(test.transientDependency === test.transientDependency)
        
        XCTAssertTrue(test.scopedDependency === test.scopedDependency)
        XCTAssertFalse(test.scopedDependency === MainTestClass().scopedDependency)
        
        XCTAssertTrue(test.singletonDependency === test.singletonDependency)
        XCTAssertTrue(test.singletonDependency === MainTestClass().singletonDependency)
        
        
        //MARK: Test dependent dependency
        XCTAssertTrue(test.dependentDependency.dependency === test.basicDependency)
        
        
        //MARK: - Test argumentative dependency
        
        XCTAssertTrue(test.argumentativeDependency.booleanArgument)
        XCTAssertEqual(test.argumentativeDependency.stringArgument, "string")
        XCTAssertEqual(test.argumentativeDependency.intArgument, 1)
        
        
        //MARK: - Multitype dependency
        
        XCTAssertEqual(test.multitypeDependencyProtocolA.propertyA, "A")
        XCTAssertEqual(test.multitypeDependencyProtocolB.propertyB, "B")
        
        //MARK: - Dependency without protocol conformance
        XCTAssertEqual(test.dependencyWithoutProtocol.propertyA, "A")
        
        //MARK: - Dependency with optional init
        XCTAssertNotNil(test.dependencyWithOptionalInitParameter.basicTestInstance)
        
        
        //MARK: - Test read-only and read-write properties
        
        XCTAssertTrue(test.basicDependency.readOnlyProperty ?? false)
        
        XCTAssertNotNil(test.readOnlyProperty)
        XCTAssertTrue(test.unwrappedReadOnlyProperty)
        
        XCTAssertNotNil(test.readWriteProperty)
        XCTAssertTrue(test.unwrappedReadWriteProperty)
        
        test.readWriteProperty = false
        
        XCTAssertFalse(test.unwrappedReadWriteProperty)
        
    }
}
