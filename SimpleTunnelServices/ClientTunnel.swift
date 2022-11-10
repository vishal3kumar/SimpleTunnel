/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ClientTunnel class. The ClientTunnel class implements the client side of the SimpleTunnel tunneling protocol.
*/

import Foundation
import NetworkExtension

/// Make NEVPNStatus convertible to a string
extension NWTCPConnectionState: CustomStringConvertible {
	public var description: String {
		switch self {
			case .cancelled: return "Cancelled"
			case .connected: return "Connected"
			case .connecting: return "Connecting"
			case .disconnected: return "Disconnected"
			case .invalid: return "Invalid"
			case .waiting: return "Waiting"
        @unknown default:
            fatalError()
        }
	}
}
public extension String {
    func to(index:Int) ->String{
        return String(self[..<self.index(self.startIndex, offsetBy:index)])
        
    }
    func to(index:String.Index) ->String{
        return String(self[..<index])
        
    }
    func from(index:Int) ->String{
        return String(self[self.index(self.startIndex, offsetBy:index)...])
        
    }
    func from(index:String.Index) ->String{
        return String(self[index...])
        
    }
    
}
/// The client-side implementation of the SimpleTunnel protocol.
open class ClientTunnel: Tunnel {

	// MARK: Properties

	/// The tunnel connection.
	open var connection: NWTCPConnection?

	/// The last error that occurred on the tunnel.
	open var lastError: Error?

	/// The previously-received incomplete message data.
	var previousData: NSMutableData?

	/// The address of the tunnel server.
	open var remoteHost: String?

	// MARK: Interface

	/// Start the TCP connection to the tunnel server.
	open func startTunnel(_ provider: NETunnelProvider) -> SimpleTunnelError? {

		guard let serverAddress = provider.protocolConfiguration.serverAddress else {
			return .badConfiguration
		}

		let endpoint: NWEndpoint

		if let colonRange = serverAddress.rangeOfCharacter(from: CharacterSet(charactersIn: ":"), options: [], range: nil) {
			// The server is specified in the configuration as <host>:<port>.
            let hostname = serverAddress[serverAddress.startIndex..<colonRange.lowerBound]
            let portString = serverAddress[serverAddress.index(after: colonRange.lowerBound)..<serverAddress.endIndex]
           

			guard !hostname.isEmpty && !portString.isEmpty else {
				return .badConfiguration
			}
            simpleTunnelLog("Got on the tunnel server address: \(hostname):\(portString)")
            endpoint = NWHostEndpoint(hostname:String(hostname), port:String(portString))
		}
		else {
			// The server is specified in the configuration as a Bonjour service name.
			endpoint = NWBonjourServiceEndpoint(name: serverAddress, type:Tunnel.serviceType, domain:Tunnel.serviceDomain)
		}

		// Kick off the connection to the server.
		connection = provider.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)

		// Register for notificationes when the connection status changes.
        
		connection!.addObserver(self, forKeyPath: "state", options: .initial, context: &ClientTunnel.observerContext)
        //connection!.addObserver(self, forKeyPath: "state", options: .initial, context: &connection)
		return nil
	}

	/// Close the tunnel.
	open func closeTunnelWithError(_ error: Error?) {
		lastError = error
		closeTunnel()
	}

    private static var observerContext = 0
	/// Read a SimpleTunnel packet from the tunnel connection.
	func readNextPacket() {
		guard let targetConnection = connection else {
			closeTunnelWithError(SimpleTunnelError.badConnection )
			return
		}

		// First, read the total length of the packet.
		targetConnection.readMinimumLength(MemoryLayout<UInt32>.size, maximumLength: MemoryLayout<UInt32>.size) { data, error in
			if let readError = error {
				simpleTunnelLog("Got an error on the tunnel connection: \(readError)")
				self.closeTunnelWithError(readError)
				return
			}

            guard let data = data else  {return }
			let lengthData = data

			guard lengthData.count == MemoryLayout<UInt32>.size else {
				simpleTunnelLog("Length data length (\(lengthData.count)) != sizeof(UInt32) (\(MemoryLayout<UInt32>.size)")
				self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
				return
			}

			var totalLength: UInt32 = 0
			(lengthData as NSData).getBytes(&totalLength, length: MemoryLayout<UInt32>.size)

			if totalLength > UInt32(Tunnel.maximumMessageSize) {
				simpleTunnelLog("Got a length that is too big: \(totalLength)")
				self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
				return
			}

			totalLength -= UInt32(MemoryLayout<UInt32>.size)

			// Second, read the packet payload.
			targetConnection.readMinimumLength(Int(totalLength), maximumLength: Int(totalLength)) { data, error in
				if let payloadReadError = error {
					simpleTunnelLog("Got an error on the tunnel connection: \(payloadReadError)")
					self.closeTunnelWithError(payloadReadError as NSError?)
					return
				}

                guard let data = data else {return}
				let payloadData = data

				guard payloadData.count == Int(totalLength) else {
					simpleTunnelLog("Payload data length (\(payloadData.count)) != payload length (\(totalLength)")
					self.closeTunnelWithError(SimpleTunnelError.internalError)
					return
				}

				_ = self.handlePacket(payloadData)

				self.readNextPacket()
			}
		}
	}

	/// Send a message to the tunnel server.
	open func sendMessage(_ messageProperties: [String: Any], completionHandler: @escaping (Error?) -> Void) {
		guard let messageData = serializeMessage(messageProperties) else {
			completionHandler(SimpleTunnelError.internalError )
			return
		}

        connection?.write(messageData, completionHandler: completionHandler )
	}

	// MARK: NSObject

	/// Handle changes to the tunnel connection state.
	open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		//http://michael-brown.net/2017/swift-and-kvo-context-variables/
        //stop reason = Simultaneous accesses to 0x1037010e8, but modification requires exclusive access
        //context?.assumingMemoryBound(to: Optional<NWTCPConnection>.self).pointee == connection
        guard keyPath == "state" &&  &ClientTunnel.observerContext == context else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}

		simpleTunnelLog("Tunnel connection state changed to \(connection!.state)")

		switch connection!.state {
			case .connected:
				if let remoteAddress = self.connection!.remoteAddress as? NWHostEndpoint {
					remoteHost = remoteAddress.hostname
				}

				// Start reading messages from the tunnel connection.
				readNextPacket()

				// Let the delegate know that the tunnel is open
				delegate?.tunnelDidOpen(self)

			case .disconnected:
				closeTunnelWithError(connection!.error as NSError?)

			case .cancelled:
				connection!.removeObserver(self, forKeyPath:"state", context:&connection)
				connection = nil
				delegate?.tunnelDidClose(self)

			default:
				break
		}
	}

	// MARK: Tunnel

	/// Close the tunnel.
	override open func closeTunnel() {
		super.closeTunnel()
		// Close the tunnel connection.
		if let TCPConnection = connection {
			TCPConnection.cancel()
		}

	}

	/// Write data to the tunnel connection.
	override func writeDataToTunnel(_ data: Data, startingAtOffset: Int) -> Int {
		connection?.write(data) { error in
			if error != nil {
				self.closeTunnelWithError(error as NSError?)
			}
		}
		return data.count
	}

	/// Handle a message received from the tunnel server.
	override func handleMessage(_ commandType: TunnelCommand, properties: [String: AnyObject], connection: Connection?) -> Bool {
		var success = true
        NSLog("Creating tunnel...message recieved from server2");
		switch commandType {
			case .openResult:
                NSLog("Creating tunnel...cmd recvd: openResult");
				// A logical connection was opened successfully.
				guard let targetConnection = connection,
					let resultCodeNumber = properties[TunnelMessageKey.ResultCode.rawValue] as? Int,
					let resultCode = TunnelConnectionOpenResult(rawValue: resultCodeNumber)
					else
				{
					success = false
					break
				}

				targetConnection.handleOpenCompleted(resultCode, properties:properties as [NSObject : AnyObject])

			case .fetchConfiguration:
                NSLog("Creating tunnel...cmd recvd: tunnelDidSendConfiguration");
				guard let configuration = properties[TunnelMessageKey.Configuration.rawValue] as? [String: AnyObject]
					else { break }

				delegate?.tunnelDidSendConfiguration(self, configuration: configuration)
			
			default:
				simpleTunnelLog("Creating tunnel...Tunnel received an invalid command")
				success = false
		}
		return success
	}

	/// Send a FetchConfiguration message on the tunnel connection.
	open func sendFetchConfiguation() {
		let properties = createMessagePropertiesForConnection(0, commandType: .fetchConfiguration)
		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a fetch configuration message")
		}
	}
}
