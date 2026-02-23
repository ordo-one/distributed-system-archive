/// Defines protocol used to serialize distributed function call arguments or result type
/// **Important:** Protocol requirements is subject to change, API compatibility is not guaranteed at this moment of time
/// **Note:** In future we plan to extend this protocol and provide an argument - a buffer for serialization of the object in place
public protocol Serializable {
    /// Calls a closure and pass the raw buffer pointer to serialized object, which is guaranteed to be valid during the closure call lifetime
    /// - Parameter body: A closure with an `UnsafeMutableBufferPointer` parameter that points to memory where the object is serialized
    func withUnsafeBytesSerialization<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result
}
