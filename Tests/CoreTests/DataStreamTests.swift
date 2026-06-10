//
//  DataStreamTests.swift
//  PureDraw
//

@testable import Core
import Testing
import Validation

struct DataStreamTests {
    @Test func memoryProviderReturnsItsBuffer() throws {
        let provider = DataProvider(data: [1, 2, 3, 4])
        #expect(try provider.data() == [1, 2, 3, 4])
    }

    @Test func loaderProviderProducesOnDemand() throws {
        let provider = DataProvider { [UInt8](repeating: 7, count: 3) }
        #expect(try provider.data() == [7, 7, 7])
    }

    @Test func loaderProviderPropagatesErrors() {
        let provider = DataProvider { throw ValidationError(reason: "unavailable", at: []) }
        #expect(throws: ValidationError.self) {
            _ = try provider.data()
        }
    }

    @Test func memoryConsumerAccumulatesWrites() {
        let consumer = DataConsumer()
        consumer.write([1, 2])
        consumer.write([3])
        #expect(consumer.data == [1, 2, 3])
    }

    @Test func sinkConsumerForwardsWrites() {
        var received: [[UInt8]] = []
        let consumer = DataConsumer { received.append($0) }
        consumer.write([9, 8])
        consumer.write([7])
        #expect(received == [[9, 8], [7]])
        #expect(consumer.data.isEmpty)
    }

    @Test func imageInitializesFromProvider() throws {
        let pixels = [UInt8](repeating: 255, count: 16)
        let image = try Image(width: 2, height: 2, provider: DataProvider(data: pixels))
        #expect(image.data == pixels)
    }
}
