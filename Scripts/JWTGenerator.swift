#!/usr/bin/env swift
import Foundation
import CryptoKit

/// Zoom Video SDK JWT generator
/// 
/// Usage:
///   swift Scripts/JWTGenerator.swift <sessionName> <role> <sdkKey> <sdkSecret>
///
/// Example:
///   swift Scripts/JWTGenerator.swift TestSession12345 1 YourSDKKey YourSDKSecret

func main() {
    let sessionName: String
    let role: Int
    let sdkKey: String
    let sdkSecret: String

    if CommandLine.arguments.count >= 5 {
        sessionName = CommandLine.arguments[1]
        role = Int(CommandLine.arguments[2]) ?? 1
        sdkKey = CommandLine.arguments[3]
        sdkSecret = CommandLine.arguments[4]
    } else if let sn = ProcessInfo.processInfo.environment["SESSION_NAME"],
              let r = ProcessInfo.processInfo.environment["ROLE"].flatMap(Int.init),
              let key = ProcessInfo.processInfo.environment["SDK_KEY"],
              let secret = ProcessInfo.processInfo.environment["SDK_SECRET"] {
        sessionName = sn
        role = r
        sdkKey = key
        sdkSecret = secret
    } else {
        fputs("Usage: swift JWTGenerator.swift <sessionName> <role> <sdkKey> <sdkSecret>\n", stderr)
        fputs("   or set SESSION_NAME, ROLE, SDK_KEY, SDK_SECRET\n", stderr)
        exit(1)
    }

    let jwt = generateZoomJWT(sessionName: sessionName, role: role, sdkKey: sdkKey, sdkSecret: sdkSecret)
    print(jwt)
}

func generateZoomJWT(sessionName: String, role: Int, sdkKey: String, sdkSecret: String) -> String {
    let iat = Int(Date().timeIntervalSince1970) - 30
    let exp = iat + 60 * 60 * 2

    let header: [String: String] = ["alg": "HS256", "typ": "JWT"]
    let payload: [String: Any] = [
        "app_key": sdkKey,
        "tpc": sessionName,
        "role_type": role,
        "version": 1,
        "iat": iat,
        "exp": exp
    ]

    let headerB64 = base64URLEncoded(header)
    let payloadB64 = base64URLEncoded(payload)
    let signingInput = "\(headerB64).\(payloadB64)"

    let secretData = sdkSecret.data(using: .utf8)!
    let signature = hmacSHA256Base64URL(message: signingInput, key: secretData)
    return "\(signingInput).\(signature)"
}

private func base64URLEncoded(_ json: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: json)
    let str = String(data: data, encoding: .utf8)!
    return base64URLEncode(str.data(using: .utf8)!)
}

private func base64URLEncoded(_ json: [String: String]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: json)
    let str = String(data: data, encoding: .utf8)!
    return base64URLEncode(str.data(using: .utf8)!)
}

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func hmacSHA256Base64URL(message: String, key: Data) -> String {
    let messageData = message.data(using: .utf8)!
    let symKey = SymmetricKey(data: key)
    let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: symKey)
    return base64URLEncode(Data(signature))
}

main()
