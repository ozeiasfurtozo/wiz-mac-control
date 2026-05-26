import Darwin
import Foundation

enum WiZServiceError: LocalizedError {
    case socketCreationFailed
    case invalidAddress(String)
    case sendFailed(String)
    case noResponse(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed:
            return "Could not open a UDP socket."
        case .invalidAddress(let address):
            return "Invalid address: \(address)."
        case .sendFailed(let address):
            return "Failed to send command to \(address)."
        case .noResponse(let address):
            return "No response from \(address). Make sure the Mac and light are on the same network."
        case .invalidResponse:
            return "The light responded, but the response format was not recognized."
        }
    }
}

final class WiZUDPService {
    private let port: UInt16 = 38899
    private let receiveBufferSize = 8192

    func discover(timeout: TimeInterval = 2.0) async throws -> [WiZDevice] {
        try await Task.detached(priority: .userInitiated) {
            let command = #"{"method":"getSystemConfig","params":{}}"#
            let responses = try self.broadcast(command, timeout: timeout)

            var devicesByAddress: [String: WiZDevice] = [:]
            for response in responses {
                if let device = self.parseDevice(from: response.payload, ipAddress: response.ipAddress) {
                    devicesByAddress[device.ipAddress] = device
                }
            }

            return devicesByAddress.values.sorted { $0.ipAddress.localizedStandardCompare($1.ipAddress) == .orderedAscending }
        }.value
    }

    func getPilot(ipAddress: String) async throws -> WiZLightState {
        try await Task.detached(priority: .userInitiated) {
            let command = #"{"method":"getPilot","params":{}}"#
            let response = try self.send(command, to: ipAddress, timeout: 1.2)
            guard let state = self.parseLightState(from: response.payload) else {
                throw WiZServiceError.invalidResponse
            }
            return state
        }.value
    }

    func setPower(ipAddress: String, isOn: Bool) async throws {
        try await sendSetPilot(ipAddress: ipAddress, params: ["state": isOn])
    }

    func setDimming(ipAddress: String, dimming: Int) async throws {
        try await sendSetPilot(ipAddress: ipAddress, params: ["state": true, "dimming": dimming.clamped(to: 10...100)])
    }

    func setTemperature(ipAddress: String, kelvin: Int, dimming: Int) async throws {
        try await sendSetPilot(
            ipAddress: ipAddress,
            params: [
                "state": true,
                "temp": kelvin.clamped(to: 2200...6500),
                "dimming": dimming.clamped(to: 10...100)
            ]
        )
    }

    func setColor(ipAddress: String, red: Int, green: Int, blue: Int, dimming: Int) async throws {
        try await sendSetPilot(
            ipAddress: ipAddress,
            params: [
                "state": true,
                "r": red.clamped(to: 0...255),
                "g": green.clamped(to: 0...255),
                "b": blue.clamped(to: 0...255),
                "dimming": dimming.clamped(to: 10...100)
            ]
        )
    }

    func setScene(ipAddress: String, sceneId: Int, speed: Int, dimming: Int) async throws {
        try await sendSetPilot(
            ipAddress: ipAddress,
            params: [
                "state": true,
                "sceneId": sceneId,
                "speed": speed.clamped(to: 20...200),
                "dimming": dimming.clamped(to: 10...100)
            ]
        )
    }

    private func sendSetPilot(ipAddress: String, params: [String: Any]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let data = try JSONSerialization.data(withJSONObject: ["method": "setPilot", "params": params])
            let command = String(decoding: data, as: UTF8.self)
            _ = try self.send(command, to: ipAddress, timeout: 1.0)
        }.value
    }

    private struct UDPResponse {
        let ipAddress: String
        let payload: Data
    }

    private func broadcast(_ message: String, timeout: TimeInterval) throws -> [UDPResponse] {
        let fd = try makeSocket(enableBroadcast: true)
        defer { close(fd) }

        var sentAtLeastOnce = false
        for address in broadcastAddresses() {
            do {
                try sendMessage(message, to: address, fileDescriptor: fd)
                sentAtLeastOnce = true
            } catch {
                continue
            }
        }

        if !sentAtLeastOnce {
            throw WiZServiceError.sendFailed("broadcast")
        }

        return receiveResponses(fileDescriptor: fd, timeout: timeout, stopAfterFirst: false)
    }

    private func send(_ message: String, to ipAddress: String, timeout: TimeInterval) throws -> UDPResponse {
        let fd = try makeSocket(enableBroadcast: false)
        defer { close(fd) }

        try sendMessage(message, to: ipAddress, fileDescriptor: fd)
        let responses = receiveResponses(fileDescriptor: fd, timeout: timeout, stopAfterFirst: true)
        guard let response = responses.first else {
            throw WiZServiceError.noResponse(ipAddress)
        }
        return response
    }

    private func makeSocket(enableBroadcast: Bool) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw WiZServiceError.socketCreationFailed
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        if enableBroadcast {
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        }

        var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        return fd
    }

    private func sendMessage(_ message: String, to ipAddress: String, fileDescriptor fd: Int32) throws {
        guard let data = message.data(using: .utf8) else {
            throw WiZServiceError.sendFailed(ipAddress)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian

        guard inet_pton(AF_INET, ipAddress, &address.sin_addr) == 1 else {
            throw WiZServiceError.invalidAddress(ipAddress)
        }

        let sent = data.withUnsafeBytes { buffer -> ssize_t in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(fd, baseAddress, data.count, 0, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.stride))
                }
            }
        }

        guard sent == data.count else {
            throw WiZServiceError.sendFailed(ipAddress)
        }
    }

    private func receiveResponses(fileDescriptor fd: Int32, timeout: TimeInterval, stopAfterFirst: Bool) -> [UDPResponse] {
        let deadline = Date().addingTimeInterval(timeout)
        var responses: [UDPResponse] = []
        var seenPayloads = Set<String>()

        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: receiveBufferSize)
            let bufferCapacity = buffer.count
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let count = buffer.withUnsafeMutableBytes { bytes -> ssize_t in
                guard let baseAddress = bytes.baseAddress else {
                    return -1
                }
                return withUnsafeMutablePointer(to: &storage) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                        recvfrom(fd, baseAddress, bufferCapacity, 0, socketAddress, &length)
                    }
                }
            }

            if count <= 0 {
                continue
            }

            guard let ipAddress = ipAddress(from: storage) else {
                continue
            }

            let payload = Data(buffer.prefix(Int(count)))
            let dedupeKey = "\(ipAddress):\(String(decoding: payload, as: UTF8.self))"
            guard !seenPayloads.contains(dedupeKey) else {
                continue
            }
            seenPayloads.insert(dedupeKey)

            responses.append(UDPResponse(ipAddress: ipAddress, payload: payload))
            if stopAfterFirst {
                break
            }
        }

        return responses
    }

    private func broadcastAddresses() -> [String] {
        var addresses = Set(["255.255.255.255"])
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return Array(addresses)
        }

        defer { freeifaddrs(firstInterface) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  (flags & IFF_BROADCAST) != 0,
                  let addressPointer = current.pointee.ifa_addr,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET),
                  let broadcastPointer = current.pointee.ifa_dstaddr,
                  let address = ipAddress(from: broadcastPointer.pointee) else {
                continue
            }

            addresses.insert(address)
        }

        return Array(addresses)
    }

    private func ipAddress(from storage: sockaddr_storage) -> String? {
        guard storage.ss_family == sa_family_t(AF_INET) else {
            return nil
        }

        var copiedStorage = storage
        return withUnsafePointer(to: &copiedStorage) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipv4Pointer in
                var address = ipv4Pointer.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buffer)
            }
        }
    }

    private func ipAddress(from socketAddress: sockaddr) -> String? {
        guard socketAddress.sa_family == sa_family_t(AF_INET) else {
            return nil
        }

        var address = socketAddress
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipv4Pointer in
                var ipv4Address = ipv4Pointer.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &ipv4Address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buffer)
            }
        }
    }

    private func parseDevice(from data: Data, ipAddress: String) -> WiZDevice? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let result = object["result"] as? [String: Any] ?? object
        let mac = stringValue(result["mac"]) ?? stringValue(result["macAddr"]) ?? ""
        let moduleName = stringValue(result["moduleName"]) ?? stringValue(result["module"]) ?? ""
        let firmwareVersion = stringValue(result["fwVersion"]) ?? stringValue(result["firmwareVersion"]) ?? ""

        return WiZDevice(
            ipAddress: ipAddress,
            mac: mac,
            moduleName: moduleName,
            firmwareVersion: firmwareVersion
        )
    }

    private func parseLightState(from data: Data) -> WiZLightState? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let result = object["result"] as? [String: Any] ?? object
        var state = WiZLightState()

        if let isOn = result["state"] as? Bool {
            state.isOn = isOn
        }
        if let dimming = intValue(result["dimming"]) {
            state.dimming = dimming.clamped(to: 10...100)
        }
        if let temperature = intValue(result["temp"]) {
            state.temperature = temperature.clamped(to: 2200...6500)
        }
        if let red = intValue(result["r"]) {
            state.red = red.clamped(to: 0...255)
        }
        if let green = intValue(result["g"]) {
            state.green = green.clamped(to: 0...255)
        }
        if let blue = intValue(result["b"]) {
            state.blue = blue.clamped(to: 0...255)
        }
        if let sceneId = intValue(result["sceneId"]) {
            state.sceneId = sceneId
        }
        if let speed = intValue(result["speed"]) {
            state.speed = speed.clamped(to: 20...200)
        }

        return state
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let double as Double:
            return Int(double.rounded())
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
