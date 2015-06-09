//
//  TLSClientHello.swift
//  Chat
//
//  Created by Nico Schmidt on 15.03.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Foundation

class TLSClientHello : TLSHandshakeMessage
{
    var clientVersion : TLSProtocolVersion
    var random : Random
    var sessionID : SessionID?
    var rawCipherSuites : [UInt16]
    var cipherSuites : [CipherSuite] {
        get {
            var cipherSuites = [CipherSuite]()
            for rawCipherSuite in rawCipherSuites {
                if let cipherSuite = CipherSuite(rawValue: rawCipherSuite) {
                    cipherSuites.append(cipherSuite)
                }
            }
            
            return cipherSuites
        }
        
        set {
            rawCipherSuites = newValue.map {$0.rawValue}
        }
    }
    
    var compressionMethods : [CompressionMethod]
    
    init(clientVersion : TLSProtocolVersion, random : Random, sessionID : SessionID?, cipherSuites : [CipherSuite], compressionMethods : [CompressionMethod])
    {
        self.clientVersion = clientVersion
        self.random = random
        self.sessionID = sessionID
        self.rawCipherSuites = []
        self.compressionMethods = compressionMethods
        
        super.init(type: .Handshake(.ClientHello))
        
        self.cipherSuites = cipherSuites
    }
    
    required init?(inputStream : InputStreamType)
    {
        var clientVersion : TLSProtocolVersion?
        var random : Random?
        var sessionID : SessionID?
        var rawCipherSuites : [UInt16]?
        var compressionMethods : [CompressionMethod]?
        
        let (type, _) = TLSHandshakeMessage.readHeader(inputStream)
        
        if let t = type {
            if t == TLSHandshakeType.ClientHello {
                
                if let major : UInt8? = read(inputStream),
                    minor : UInt8? = read(inputStream),
                    cv = TLSProtocolVersion(major: major!, minor: minor!)
                {
                    clientVersion = cv
                }
                
                if let r = Random(inputStream: inputStream)
                {
                    random = r
                }
                
                if  let sessionIDSize : UInt8 = read(inputStream) {
                    if sessionIDSize > 0 {
                        if let rawSessionID : [UInt8] = read(inputStream, length: Int(sessionIDSize)) {
                            sessionID = SessionID(sessionID: rawSessionID)
                        }
                    }
                }
                
                if  let cipherSuitesSize : UInt16 = read(inputStream),
                    let rawCipherSuitesRead : [UInt16] = read(inputStream, length: Int(cipherSuitesSize) / sizeof(UInt16))
                {
                    rawCipherSuites = rawCipherSuitesRead
                }
                
                if  let compressionMethodsSize : UInt8 = read(inputStream),
                    let rawCompressionMethods : [UInt8] = read(inputStream, length: Int(compressionMethodsSize))
                {
                    compressionMethods = rawCompressionMethods.map {CompressionMethod(rawValue: $0)!}
                }
            }
        }
        
        if  let cv = clientVersion,
            let r = random,
            let cs = rawCipherSuites,
            let cm = compressionMethods
        {
            self.clientVersion = cv
            self.random = r
            self.sessionID = sessionID
            self.rawCipherSuites = cs
            self.compressionMethods = cm
            
            super.init(type: .Handshake(.ClientHello))
        }
        else {
            self.clientVersion = TLSProtocolVersion.TLS_v1_0
            self.random = Random()
            self.sessionID = nil
            self.rawCipherSuites = []
            self.compressionMethods = []
            
            super.init(type: .Handshake(.ClientHello))
            
            return nil
        }
    }
    
    override func writeTo<Target : OutputStreamType>(inout target: Target)
    {
        var buffer = DataBuffer()
        
        write(buffer, data: clientVersion.rawValue)
        
        random.writeTo(&buffer)
        
        if let session_id = sessionID {
            session_id.writeTo(&buffer)
        }
        else {
            write(buffer, data: UInt8(0))
        }
        
        write(buffer, data: UInt16(rawCipherSuites.count * sizeof(UInt16)))
        write(buffer, data: rawCipherSuites)
        
        write(buffer, data: UInt8(compressionMethods.count))
        write(buffer, data: compressionMethods.map { $0.rawValue})
        
        let data = buffer.buffer
        
        self.writeHeader(type: .ClientHello, bodyLength: data.count, target: &target)
        write(target, data: data)
    }
}
