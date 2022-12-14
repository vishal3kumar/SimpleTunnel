# My Notes:

1) Update the code with new server address at: 

	SimpleTunnel/mac/ViewController.swift:
	
		config.serverAddress = "10.213.175.17:8890"
		
		
	check whether u need to update at:
	
		SimpleTunnel/PacketTunnel/PacketTunnelProvider.swif: NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelAddress)
		
2) You need to compile 'mac' project, this project include 'Application Extension' -> Packet Tunnel Provider (Please note this is different from System Extension: PacketTunnelProvider). 
3) Then you need to compile 'tunnel_server' which we have to run at tunnel destination server. 
4) Then run the tunnel server with below config file: 
	tunnel_server <port> <config-file>
	Config file sample: SimpleTunnel/tunnel_server/config.plist
	
	// enable IP forwarding and firewall in the kernel: refer: https://gist.github.com/ozel/93c48ff291b83ac648278f0562167b7e
	sudo sysctl -w net.inet.ip.forwarding=1
	sudo sysctl -w net.inet.ip.fw.enable=1

	//flush all FW rules 
	sudo pfctl -F all # or -F nat, for just the nat rules

	cat ./nat-rules 
	nat on en0 from 192.168.2.0/24 to any -> 10.213.175.17 #put this line in a text file

	// en0 is the interface pointing to the network with internet access
	// 10.213.175.17 is the local hostname or ip associated with the network that has internet access
	// 192.168.2.0/24 is a separate network that shall get internet via ozelmacpro on interface en0
	// final hint on this via https://discussions.apple.com/thread/6757798?start=0&tstart=0

	// load NAT rules from file
	sudo pfctl -f nat-rules -e

	// list all FW config
	sudo pfctl -s all
	
============================================

# SimpleTunnel: Customized Networking Using the NetworkExtension Framework

The SimpleTunnel project contains working examples of the four extension points provided by the Network Extension framework:

1. Packet Tunnel Provider

The Packet Tunnel Provider extension point is used to implemnt the client side of a custom network tunneling protocol that encapsulates network data in the form of IP packets. The PacketTunnel target in the SimpleTunnel project produces a sample Packet Tunnel Provider extension.

2. App Proxy Provider

The App Proxy Provider extension point is used to implement the client side of a custom network proxy protocol that encapsulates network data in the form of flows of application network data. Both TCP or stream-based and UDP or datagram-based flows of data are supported. The AppProxy target in the SimpleTunnel project produces a sample App Proxy Provider extension.

3. Filter Data Provider and Filter Control Provider

The two Filter Provider extension points are used to implement a dynamic, on-device network content filter. The Filter Data Provider extension is responsible for examining network data and making pass/block decisions. The Filter Data Provider extension sandbox prevents the extension from communicating over the network or writing to disk to prevent any leakage of network data. The Filter Control Provider extension can communicate using the network and write to the disk. It is responsible for updating the filtering rules on behalf of the Filter Data Provider extension.

The FilterDataProvider target in the SimpleTunnel project produces a sample Filter Data Provider extension. The FilterControlProvider target in the SimpleTunnel project produces a sample Filter Control Provider extension.e

All of the sample extensions are packaged into the SimpleTunnel app. The SimpleTunnel app contains code demonstrating how to configure and control the various types of Network Extension providers. The SimpleTunnel target in the SimpleTunnel project produces the SimpleTunnel app and all of the sample extensions.

The SimpleTunnel project contains both the client and server sides of a custom network tunneling protocol. The Packet Tunnel Provider and App Proxy Provider extensions implement the client side. The tunnel_server target produces a OS X command-line binary that implements the server side. The server is configured using a plist. A sample plist is included in the tunnel_erver source. To run the server, use this command:

**sudo tunnel_server \<port\> \<path-to-config-plist\>**
	
	

# Requirements

### Runtime

The NEProvider family of APIs require the following entitlement:

<key>com.apple.developer.networking.networkextension</key>
<array>
	<string>packet-tunnel-provider</string>
	<string>app-proxy-provider</string>
	<string>content-filter-provider</string>
</array>
</plist>

The SimpleTunnel.app and the provider extensions will not run if they are not code signed with this entitlement.

You can request this entitlement by sending an email to networkextension@apple.com.

The SimpleTunnel iOS products require iOS 9.0 or newer.
The SimpleTunnel OS X products require OS X 11.0 or newer.

### Build

SimpleTunnel requires Xcode 8.0 or newer.
The SimpleTunnel iOS targets require the iOS 9.0 SDK or newer.
The SimpleTunnel OS X targets require the OS X 11.0 SDK or newer.

Copyright (C) 2016 Apple Inc. All rights reserved.
