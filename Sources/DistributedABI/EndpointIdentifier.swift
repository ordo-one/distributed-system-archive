// Copyright 2024 Ordo One AB
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0

// TODO: this should not be here, and its members should not be public it is only here because
// of poor Error enum separation
public struct EndpointIdentifier: Hashable, Codable, CustomStringConvertible, Sendable {
    // keep the side flag in the lower bits for more efficient ULEB128 encoding
    public static let serviceFlag: UInt32 = 0x00000001

    public typealias InstanceIdentifier = UInt32

    public let channelID: UInt32 // 0 - local
    public let instanceID: UInt32

    public var description: String {
        let side = ((instanceID & Self.serviceFlag) == 0) ? "C" : "S"
        return "\(side):\(channelID):\(instanceID >> 1)"
    }

    public static func instanceIdentifierDescription(_ instanceID: UInt32) -> String {
        let side = ((instanceID & Self.serviceFlag) == 0) ? "C" : "S"
        return "\(side):X:\(instanceID >> 1)"
    }

    public init(_ channelID: UInt32, _ instanceID: UInt32) {
        self.channelID = channelID
        self.instanceID = instanceID
    }

    public func makeClientEndpoint() -> EndpointIdentifier {
        assert((instanceID & Self.serviceFlag) != 0)
        return .init(channelID, instanceID ^ Self.serviceFlag)
    }

    public func makeServiceEndpoint() -> EndpointIdentifier {
        assert((instanceID & Self.serviceFlag) == 0)
        return .init(channelID, instanceID | Self.serviceFlag)
    }

    public static func makeServiceEndpoint(_ channelID: UInt32, _ instanceID: UInt32) -> EndpointIdentifier {
        return .init(channelID, instanceID | Self.serviceFlag)
    }
}
