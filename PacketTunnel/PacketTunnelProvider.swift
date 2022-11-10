/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the PacketTunnelProvider class. The PacketTunnelProvider class is a sub-class of NEPacketTunnelProvider, and is the integration point between the Network Extension framework and the SimpleTunnel tunneling protocol.
*/

import NetworkExtension
import SimpleTunnelServices
import os.log

let log = OSLog(subsystem: "com.mcafee.CMF.networkextension", category: "app")


/// A packet tunnel provider object.
class PacketTunnelProvider: NEPacketTunnelProvider, TunnelDelegate, ClientTunnelConnectionDelegate {

	// MARK: Properties

	/// A reference to the tunnel object.
	var tunnel: ClientTunnel?

	/// The single logical flow of packets through the tunnel.
	var tunnelConnection: ClientTunnelConnection?

	/// The completion handler to call when the tunnel is fully established.
	var pendingStartCompletion: ((Error?) -> Void)?

	/// The completion handler to call when the tunnel is fully disconnected.
	var pendingStopCompletion: (() -> Void)?

	// MARK: NEPacketTunnelProvider

	/// Begin the process of establishing the tunnel.
	override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
		let newTunnel = ClientTunnel()
		newTunnel.delegate = self

        //os_log(.fault, log: log, "staring tunnel...........")
        //os_log(.error, log: log, "staring tunnel...........")
        NSLog("Creating tunnel...: Starting Tunnel");

        
		if let error = newTunnel.startTunnel(self) {
			completionHandler(error as NSError)
		}
		else {
			// Save the completion handler for when the tunnel is fully established.
			pendingStartCompletion = completionHandler
			tunnel = newTunnel
		}
	}

	/// Begin the process of stopping the tunnel.
	override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
		// Clear out any pending start completion handler.
		pendingStartCompletion = nil

		// Save the completion handler for when the tunnel is fully disconnected.
		pendingStopCompletion = completionHandler
		tunnel?.closeTunnel()
	}

	/// Handle IPC messages from the app.
	override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
		guard let messageString = NSString(data: messageData, encoding: String.Encoding.utf8.rawValue) else {
			completionHandler?(nil)
			return
		}

		simpleTunnelLog("Got a message from the app: \(messageString)")

		let responseData = "Hello app".data(using: String.Encoding.utf8)
		completionHandler?(responseData)
	}

	// MARK: TunnelDelegate

	/// Handle the event of the tunnel connection being established.
	func tunnelDidOpen(_ targetTunnel: Tunnel) {
		// Open the logical flow of packets through the tunnel.
		let newConnection = ClientTunnelConnection(tunnel: tunnel!, clientPacketFlow: packetFlow, connectionDelegate: self)
		newConnection.open()
		tunnelConnection = newConnection
	}

	/// Handle the event of the tunnel connection being closed.
	func tunnelDidClose(_ targetTunnel: Tunnel) {
		if pendingStartCompletion != nil {
			// Closed while starting, call the start completion handler with the appropriate error.
			pendingStartCompletion?(tunnel?.lastError)
			pendingStartCompletion = nil
		}
		else if pendingStopCompletion != nil {
			// Closed as the result of a call to stopTunnelWithReason, call the stop completion handler.
			pendingStopCompletion?()
			pendingStopCompletion = nil
		}
		else {
			// Closed as the result of an error on the tunnel connection, cancel the tunnel.
			cancelTunnelWithError(tunnel?.lastError)
		}
		tunnel = nil
	}

	/// Handle the server sending a configuration.
	func tunnelDidSendConfiguration(_ targetTunnel: Tunnel, configuration: [String : AnyObject]) {
	}

	// MARK: ClientTunnelConnectionDelegate

	/// Handle the event of the logical flow of packets being established through the tunnel.
	func tunnelConnectionDidOpen(_ connection: ClientTunnelConnection, configuration: [NSObject: AnyObject]) {

		// Create the virtual interface settings.
		guard let settings = createTunnelSettingsFromConfiguration(configuration) else {
			pendingStartCompletion?(SimpleTunnelError.internalError )
			pendingStartCompletion = nil
			return
		}

		// Set the virtual interface settings.
        NSLog("Creating tunnel...Set the virtual interface settings")
		setTunnelNetworkSettings(settings) { error in
			var startError: Error?
			if let error = error {
				simpleTunnelLog("Failed to set the tunnel network settings: \(error)")
				startError = SimpleTunnelError.badConfiguration
			}
			else {
				// Now we can start reading and writing packets to/from the virtual interface.
				self.tunnelConnection?.startHandlingPackets()
			}

			// Now the tunnel is fully established, call the start completion handler.
			self.pendingStartCompletion?(startError)
			self.pendingStartCompletion = nil
		}
	}

	/// Handle the event of the logical flow of packets being torn down.
	func tunnelConnectionDidClose(_ connection: ClientTunnelConnection, error: Error?) {
		tunnelConnection = nil
		tunnel?.closeTunnelWithError(error)
	}

	/// Create the tunnel network settings to be applied to the virtual interface.
	func createTunnelSettingsFromConfiguration(_ configuration: [NSObject: AnyObject]) -> NEPacketTunnelNetworkSettings? {
		guard let tunnelAddress = tunnel?.remoteHost,
			let address = getValueFromPlist(configuration, keyArray: [.IPv4, .Address]) as? String,
			let netmask = getValueFromPlist(configuration, keyArray: [.IPv4, .Netmask]) as? String
			else { return nil }
        
        /*
         Sample config:
         Creating tunnel... createTunnelSettingsFromConfiguration: configuration: {
             DNS =     {
                 SearchDomains =         (
                 );
                 Servers =         (
                     "10.212.24.222"
                 );
             };
             IPv4 =     {
                 Address = "192.168.2.2";
                 Netmask = "255.255.255.255";
             };
         }
         
         */
        NSLog("Creating tunnel... createTunnelSettingsFromConfiguration: configuration: %@", configuration);
        
        NSLog("Creating tunnel... tunnelAddress: %@", tunnelAddress);
		let newSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelAddress)
		var fullTunnel = true

        NSLog("Creating tunnel... ipv4Settings222: %@, netmask: %@", address, netmask);
		newSettings.ipv4Settings = NEIPv4Settings(addresses: [address], subnetMasks: [netmask])

		if let routes = getValueFromPlist(configuration, keyArray: [.IPv4, .Routes]) as? [[String: AnyObject]] {
			var includedRoutes = [NEIPv4Route]()
			for route in routes {
				if let netAddress = route[SettingsKey.Address.rawValue] as? String,
					let netMask = route[SettingsKey.Netmask.rawValue] as? String
				{
                    NSLog("Creating tunnel... includedRoutes: %@", netAddress);
					includedRoutes.append(NEIPv4Route(destinationAddress: netAddress, subnetMask: netMask))
				}
			}
            
			newSettings.ipv4Settings?.includedRoutes = includedRoutes
			fullTunnel = false
		}
		else {
			// No routes specified, use the default route.
			/*newSettings.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
            fullTunnel = true*/
            
            /* Hard  code the routes */
            var includedRoutes = [NEIPv4Route]()
            var excludedRoutes = [NEIPv4Route]()
            NSLog("Creating tunnel... includedRoutes: 20.20.20.0");
            //includedRoutes.append(NEIPv4Route(destinationAddress: "142.250.195.0", subnetMask: "255.255.255.0"))
            includedRoutes.append(NEIPv4Route(destinationAddress: "20.20.20.0", subnetMask: "255.255.255.0"))
            excludedRoutes.append(NEIPv4Route(destinationAddress: "20.20.20.10", subnetMask: "255.255.255.255"))

            newSettings.ipv4Settings?.includedRoutes = includedRoutes
            newSettings.ipv4Settings?.excludedRoutes = excludedRoutes

		}

		if let DNSDictionary = configuration[SettingsKey.DNS.rawValue as NSString] as? [String: AnyObject],
			let DNSServers = DNSDictionary[SettingsKey.Servers.rawValue] as? [String]
		{
            NSLog("Creating tunnel... Configurating DNS from server configuration: %@", DNSServers);
			newSettings.dnsSettings = NEDNSSettings(servers: DNSServers)
			if let DNSSearchDomains = DNSDictionary[SettingsKey.SearchDomains.rawValue] as? [String] {
				newSettings.dnsSettings?.searchDomains = DNSSearchDomains
				if !fullTunnel {
					newSettings.dnsSettings?.matchDomains = DNSSearchDomains
				}
			}
        }
        // let us hard code the dns for testing
        NSLog("Creating tunnel... let us hard code the dns for testing");
        //newSettings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
        newSettings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8"])
        newSettings.dnsSettings?.searchDomains = ["test1", "test2.com", "test3.com", "ttest1.com"]
        newSettings.dnsSettings?.matchDomains = ["test4.com", "test5.com", "test6.com", "test1.com"]
        newSettings.dnsSettings?.matchDomainsNoSearch = true
        

		newSettings.tunnelOverheadBytes = 150
        os_log("Creating tunnel...: Did setup tunnel settings: %{public}@, error: %{public}@", "\(newSettings)")

		return newSettings
	}
}
