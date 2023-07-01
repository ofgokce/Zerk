import XCTest
@testable import Zerk

final class ZerkTests: XCTestCase {
    func testStandardStorage() throws {
        Zerk.store
            .transient(TransientTestClass() as TransientTestProtocol)
            .scoped(ScopedTestClass() as ScopedTestProtocol)
            .singleton(SingletonTestClass() as SingletonTestProtocol)
            .singleton(BasicTestClass() as BasicTestProtocol)
            .singleton {
                DependentTestClass(dependency: $0)
                as DependentTestProtocol
            }
            .singleton { storage, arguments in
                ArgumentativeTestClass(booleanArgument: arguments.booleanArgument,
                                       stringArgument: arguments.stringArgument,
                                       intArgument: arguments.intArgument)
                as ArgumentativeTestProtocol
            }
            .singleton({ storage, arguments in MultitypeTestClass() },
                       as: MultitypeTestProtocolA.self, MultitypeTestProtocolB.self)
        
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
