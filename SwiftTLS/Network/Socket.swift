//
//  Socket.swift
//  Chat
//
//  Created by Nico Schmidt on 17.02.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Foundation

enum SocketError : CustomStringConvertible {
    case PosixError(errno : Int32)
    
    var description : String {
        get {
            switch (self)
            {
            case let .PosixError(errno):
                return String.fromCString(strerror(errno))!
            }
        }
    }
}

protocol SocketProtocol
{
    func connect(address : IPAddress, completionBlock : ((SocketError?) -> ())?)
    func listen(address : IPAddress, acceptBlock : (clientSocket : SocketProtocol?, error : SocketError?) -> ())
    func read(count count : Int, completionBlock : ((data : [UInt8]?, error : SocketError?) -> ()))
    func write(data : [UInt8], completionBlock : ((SocketError?) -> ())?)
    func close()
}

class Socket : SocketProtocol
{
    private static var socketQueue : dispatch_queue_t = {
        return dispatch_queue_create("com.savoysoftware.socketQueue", DISPATCH_QUEUE_SERIAL)
    }()
    
    struct ReadRequest {
        let count : Int
        let completionBlock : (data : [UInt8]?, error : SocketError?) -> ()
    }
    
    var _readRequests : [ReadRequest] = []
    var _readBuffer : [UInt8] = [UInt8](count: 64 * 1024, repeatedValue: 0)
    
    var _socketConnectSource : dispatch_source_t?
    var _socketAcceptSource : dispatch_source_t?
    var _socketReadSource : dispatch_source_t?
    var _socketWriteSource : dispatch_source_t?

    var socketDescriptor : Int32?
    
    var isReadSourceRunning : Bool = false
    
    init()
    {
    }
    
    required init(socketDescriptor : Int32)
    {
        self.socketDescriptor = socketDescriptor
    }
    
    func createSocket(protocolFamily : sa_family_t) -> Int32?
    {
        return nil
    }
    
    deinit {
        self.close()
    }

    func connect(address : IPAddress, completionBlock : ((SocketError?) -> ())?)
    {
        self._connect(address, completionBlock: completionBlock)
    }
    
    func _connect(address : IPAddress, completionBlock : ((SocketError?) -> ())?)
    {
        if (socketDescriptor == nil) {
            socketDescriptor = createSocket(address.unsafeSockAddrPointer.memory.sa_family)
            if (socketDescriptor == nil) {
                if let block = completionBlock
                {
                    block(SocketError.PosixError(errno: errno))
                }
                
                return
            }
        }
        
        let socket = socketDescriptor!
        
        // make socket non-blocking
        let flags = NSC_getFileFlags(socket)
        NSC_setFileFlags(socket, flags | ~O_NONBLOCK)
        
        _socketConnectSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, UInt(socket), 0, Socket.socketQueue)
        if let socketConnectSource = _socketConnectSource {
            
            dispatch_source_set_registration_handler(socketConnectSource) {
                let addr = address.unsafeSockAddrPointer
                let status = Darwin.connect(socket, addr, socklen_t(addr.memory.sa_len))
                
                if status == 0
                {
                    if let block = completionBlock
                    {
                        block(nil)
                    }
                }
                else if (status < 0 && errno != EINPROGRESS)
                {
                    if let block = completionBlock
                    {
                        block(SocketError.PosixError(errno: errno))
                    }
                    
                    self.close()
                    return
                }
                else if (status < 0 && errno == EINPROGRESS)
                {

                }
            }
            
            dispatch_source_set_event_handler(socketConnectSource) {

                dispatch_suspend(socketConnectSource)
                
                var error : Int32 = 0
                var len = socklen_t(sizeof(Int32.Type))
                if (getsockopt(socket, SOL_SOCKET, SO_ERROR, &error, &len) < 0)
                {
                    if let block = completionBlock
                    {
                        block(SocketError.PosixError(errno: errno))
                    }
                    return
                }
                
                if (error != 0)
                {
                    if let block = completionBlock
                    {
                        block(SocketError.PosixError(errno: errno))
                    }
                    
                    self.close()
                    
                    return
                }
                
                if let block = completionBlock
                {
                    block(nil)
                }
            }
            
            dispatch_resume(socketConnectSource)
        }
    }
    
    func listen(address : IPAddress, acceptBlock : (clientSocket : SocketProtocol?, error : SocketError?) -> ())
    {
        self.socketDescriptor = createSocket(address.unsafeSockAddrPointer.memory.sa_family)
        
        if let socket = self.socketDescriptor {
            var result = Darwin.bind(socket, address.unsafeSockAddrPointer, socklen_t(address.unsafeSockAddrPointer.memory.sa_len))
            if result < 0 {
                acceptBlock(clientSocket: nil, error: SocketError.PosixError(errno: errno))
                return
            }

            result = Darwin.listen(socket, 5)
            if result < 0 {
                acceptBlock(clientSocket: nil, error: SocketError.PosixError(errno: errno))
                return
            }

            _socketAcceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socket), 0, Socket.socketQueue)
            if let acceptSource = _socketAcceptSource {
                dispatch_source_set_event_handler(acceptSource) {
                    let clientSocket = Darwin.accept(socket, nil, nil)
                    if clientSocket == Int32(-1) {
                        acceptBlock(clientSocket: nil, error: SocketError.PosixError(errno: errno))
                        return
                    }
                    
                    let socket = self.dynamicType(socketDescriptor: clientSocket)
                    acceptBlock(clientSocket: socket, error: nil)
                }
                
                dispatch_resume(acceptSource)
            }
        }
    }
    
    func sendTo(address : IPAddress?, data : [UInt8], completionBlock : ((numberOfBytesWritten : Int, error : SocketError?) -> ())? = nil)
    {
        if let socket = self.socketDescriptor {
            dispatch_async(Socket.socketQueue, {
                let numberOfBytesToWrite : Int = data.count
                var numberOfBytesWritten : Int
                if (address == nil) {
                    numberOfBytesWritten = self._write(socket, data, numberOfBytesToWrite)
                }
                else {
                    let addr = address!.unsafeSockAddrPointer
                    numberOfBytesWritten = data.withUnsafeBufferPointer {
                        (buffer : UnsafeBufferPointer<UInt8>) -> Int in
                        let bufferPointer = buffer.baseAddress
                        return sendto(socket, bufferPointer, numberOfBytesToWrite, Int32(0), addr, socklen_t(addr.memory.sa_len))
                    }
                }
                if (numberOfBytesWritten < 0)
                {
                    if (completionBlock != nil)
                    {
                        completionBlock!(numberOfBytesWritten: 0, error: SocketError.PosixError(errno: errno))
                    }
                }
                else if (numberOfBytesWritten == 0)
                {
                    NSLog("Could not write data")
                    if (completionBlock != nil)
                    {
                        completionBlock!(numberOfBytesWritten: 0, error: nil)
                    }
                }
                else
                {
                    if (completionBlock != nil)
                    {
                        completionBlock!(numberOfBytesWritten: numberOfBytesWritten, error: nil)
                    }
                }
            })
        }
    }

    func write(data : [UInt8], completionBlock : ((SocketError?) -> ())? = nil) {
        self._write(data, completionBlock: completionBlock)
    }
    
    internal func _write(data : [UInt8], completionBlock : ((SocketError?) -> ())? = nil)
    {
        let numberOfBytesToWrite = data.count
        self.sendTo(nil, data: data) {
            (numberOfBytesWritten, error) -> () in
            
            if numberOfBytesWritten < numberOfBytesToWrite {
                if let e = error {
                    print("Error: \(e)")
                }
            }
            
            if let block = completionBlock {
                if error != nil {
                    block(nil)
                }
                else {
                    block(nil)
                }
            }
        }
    }

    func write(string : String, completionBlock : ((SocketError?) -> ())? = nil) {
        let data = Array(string.nulTerminatedUTF8)
        self.write(data, completionBlock: completionBlock)
    }
    
    func read(count count : Int, completionBlock : ((data : [UInt8]?, error : SocketError?) -> ()))
    {
        return self._read(count: count, completionBlock: completionBlock)
    }
    
    internal func _read(count count : Int, completionBlock : ((data : [UInt8]?, error : SocketError?) -> ())) {
        if _socketReadSource == nil {
            self.setupSocketReadSource()
        }
        
        if let socketReadSource = _socketReadSource {
            dispatch_async(Socket.socketQueue) {

                self._readRequests.append(ReadRequest(count: count, completionBlock: completionBlock))
                
                self.resumeReadSource()
            }
        }
    }
    
    func close() {
        self._close()
    }
    
    internal func _close()
    {
        if let socket = socketDescriptor {
            _socketAcceptSource = nil
            _socketConnectSource = nil
            _socketReadSource = nil
            _socketWriteSource = nil
            
            Darwin.close(socket)
            
            socketDescriptor = nil
        }
    }
    
    private func suspendReadSource() {
        if self.isReadSourceRunning {
            if let source = _socketReadSource {
                dispatch_suspend(source)
                
                self.isReadSourceRunning = false
            }
        }
    }
    
    private func resumeReadSource() {
        if !self.isReadSourceRunning {
            if let source = _socketReadSource {
                dispatch_resume(source)
                
                self.isReadSourceRunning = true
            }
        }
    }
    
    private func setupSocketReadSource() {
        if let socket = socketDescriptor {
            _socketReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socket), 0, Socket.socketQueue)
            if let socketReadSource = _socketReadSource {
                dispatch_source_set_registration_handler(socketReadSource) {
                    if self._readRequests.count == 0 {
                        self.suspendReadSource()
                    }
                }
                
                dispatch_source_set_event_handler(socketReadSource, {
                    [unowned self] () -> Void in
                    
                    let availableBytes = Int(dispatch_source_get_data(socketReadSource))
                    var bytesRead = 0

                    while (self._readRequests.count > 0) {
                        
                        let readRequest = self._readRequests[0]
                        self._readRequests.removeAtIndex(0)
                        
                        let result = self._read(socket, &self._readBuffer, readRequest.count)
                        if result < 0 {
                            readRequest.completionBlock(data: nil, error: SocketError.PosixError(errno: errno))
                            return
                        }
                        else if result == 0 {
                            readRequest.completionBlock(data: nil, error: nil)
                            return
                        }
                        else {
                            readRequest.completionBlock(data: [UInt8](self._readBuffer[0..<result]), error: nil)
                            bytesRead += result
                        }
                        
                        if bytesRead >= availableBytes {
                            return
                        }
                    }
                    
                    if (self._readRequests.count == 0) {
                        self.suspendReadSource()
                    }
                })
                
                self.resumeReadSource()
            }
        }
    }
    
    func _read(socket: Int32, _ buffer: UnsafeMutablePointer<Void>, _ count: Int) -> Int
    {
        return Darwin.read(socket, buffer, count)
    }
    
    func _write(socket: Int32, _ buffer: UnsafePointer<Void>, _ count: Int) -> Int
    {
        return Darwin.write(socket, buffer, count)
    }
}

class TCPSocket : Socket
{
    override func createSocket(protocolFamily : sa_family_t) -> Int32?
    {
        let fd = socket(Int32(protocolFamily), SOCK_STREAM, IPPROTO_TCP)
        
        if fd < 0 {
            return nil
        }
        
        var yes : Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(sizeof(Int32.self)))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(sizeof(Int32.self)))
        
//        var action = sigaction()
//        action.sa_handler = 1
//        sigaction(SIGPIPE, &action, nil)
        
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(sizeof(Int32.self)))
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, socklen_t(sizeof(Int32.self)))
        
        return fd
    }

}

class UDPSocket : Socket
{
    override func createSocket(protocolFamily : sa_family_t) -> Int32?
    {
        let fd = socket(Int32(protocolFamily), SOCK_DGRAM, IPPROTO_UDP)

        if fd < 0 {
            return nil
        }
        
        return fd
    }
}