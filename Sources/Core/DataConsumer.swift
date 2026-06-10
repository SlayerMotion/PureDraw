//
//  DataConsumer.swift
//  PureDraw
//

/// Receives raw bytes from graphics producers (encoders, renderers) without
/// binding them to a destination. The `CGDataConsumer` equivalent.
///
/// The default consumer accumulates everything written into `data`; the
/// sink-based consumer forwards each write to a callback instead, for
/// streaming to files, sockets, or hashes without buffering.
public final class DataConsumer {
    /// Bytes accumulated by an in-memory consumer. Stays empty when the
    /// consumer was created with a sink.
    public private(set) var data: [UInt8] = []

    private let sink: (([UInt8]) -> Void)?

    /// An in-memory consumer; written bytes accumulate in `data`.
    public init() {
        sink = nil
    }

    /// A consumer that forwards every write to `sink`.
    public init(sink: @escaping ([UInt8]) -> Void) {
        self.sink = sink
    }

    /// Writes bytes to the destination.
    public func write(_ bytes: [UInt8]) {
        if let sink {
            sink(bytes)
        } else {
            data.append(contentsOf: bytes)
        }
    }
}
