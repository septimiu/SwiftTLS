//
//  TSLTests.swift
//  Chat
//
//  Created by Nico Schmidt on 14.03.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Cocoa
import XCTest

class TSLTests: XCTestCase {

    var opensslServer : NSTask?
    
    override func setUp() {
        super.setUp()
//        opensslServer = NSTask.launchedTaskWithLaunchPath("/usr/bin/openssl", arguments: ["s_server",  "-cert", "SwiftTLSTests/mycert.pem", "-www",  "-debug", "-cipher", "ALL:NULL" ])
    }
    
    override func tearDown() {
        super.tearDown()
        opensslServer?.terminate()
    }

    func test_connectTLS() {
        var expectation = self.expectationWithDescription("successfully connected")

        // wait for server to be up
        sleep(1)
        
        var socket = TLSSocket(protocolVersion: TLSProtocolVersion.TLS_v1_0)
//        var host = "195.50.155.66"
//        var host = "85.13.137.205" // nschmidt.name
        var host = "127.0.0.1"
        var port = 4433
//        var port = 443
        
        socket.connect(IPAddress.addressWithString(host, port: port)!, completionBlock: { (error : SocketError?) -> () in
            socket.write([UInt8]("GET / HTTP/1.1\r\nHost: nschmidt.name\r\n\r\n".utf8), completionBlock: { (error : SocketError?) -> () in
                socket.read(count: 4096, completionBlock: { (data, error) -> () in
                    println("\(NSString(bytes: data!, length: data!.count, encoding: NSUTF8StringEncoding)!)")
                    socket.close()
                    expectation.fulfill()
                })
            })
            
            return
        })
        
        self.waitForExpectationsWithTimeout(50.0, handler: { (error : NSError!) -> Void in
        })
    }
    
    func test_listen_whenClientConnects_callsAcceptBlock()
    {
        var serverIdentity = Identity(name: "Internet Widgits Pty Ltd")

        var server = TLSSocket(protocolVersion: .TLS_v1_2, isClient: false, identity: serverIdentity!)
        var address = IPv4Address.localAddress()
        address.port = UInt16(12345)
        
        let expectation = self.expectationWithDescription("accept connection successfully")
        server.listen(address, acceptBlock: { (clientSocket, error) -> () in
            if clientSocket != nil {
                expectation.fulfill()
            }
            else {
                XCTFail("Connect failed")
            }
        })
        
        var client = TLSSocket(protocolVersion: .TLS_v1_2)
        client.connect(address, completionBlock: { (error: SocketError?) -> () in
            println("\(error)")
        })
        
        self.waitForExpectationsWithTimeout(50.0, handler: { (error : NSError!) -> Void in
        })
        
    }
    
//    func test_sendDoubleClientHello__triggersAlert()
//    {
//        class MyContext : TLSContext
//        {
//            override func _didReceiveHandshakeMessage(message : TLSHandshakeMessage, completionBlock: ((TLSContextError?) -> ())?)
//            {
//                if message.handshakeType == .Certificate {
//                    self.sendClientHello()
//                }
//            }
//        }
//        
//        var version = TLSProtocolVersion.TLS_v1_0
//        
//        var socket = TLSSocket(protocolVersion: version)
//        var myContext = MyContext(protocolVersion: version, dataProvider: socket, isClient: true)
//        socket.context = myContext
//        var host = "127.0.0.1"
//        var port = 4433
//        
//        socket.connect(IPAddress.addressWithString(host, port: port)!) { (error : TLSSocketError?) -> () in
//        }
//        
//        var expectation = self.expectationWithDescription("successfully connected")
//        self.waitForExpectationsWithTimeout(50.0, handler: { (error : NSError!) -> Void in
//        })
//
//    }

}