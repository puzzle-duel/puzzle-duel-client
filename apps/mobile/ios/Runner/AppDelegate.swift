import Flutter
import UIKit
import Security
import CryptoKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PzdDeviceSigning")
    PzdDeviceSigning.register(with: registrar)
  }
}

/**
 * Account- and origin-scoped, on-device P-256 signing.
 * Keys are Secure Enclave protected, non-exportable, and this-device-only.
 * No raw signing key or session secret crosses the Flutter channel.
 */
final class PzdDeviceSigning: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pzd/device_signing",
      binaryMessenger: registrar.messenger()
    )
    let instance = PzdDeviceSigning()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let playerId = arguments["playerId"] as? String,
          let origin = arguments["origin"] as? String,
          !playerId.isEmpty, !origin.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: nil, details: nil))
      return
    }

    do {
      let privateKey = try key(for: playerId, origin: origin)
      switch call.method {
      case "registerProof":
        guard let sessionId = arguments["sessionId"] as? String else {
          throw DeviceSigningError.invalidArgument
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
          throw DeviceSigningError.keyUnavailable
        }
        var error: Unmanaged<CFError>?
        guard let x963 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
          throw DeviceSigningError.keyUnavailable
        }
        // P-256 SPKI DER prefix (id-ecPublicKey + prime256v1 + BIT STRING).
        let prefix = Data([
          0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
          0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
          0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
          0x42, 0x00
        ])
        guard x963.count == 65, x963.first == 0x04 else {
          throw DeviceSigningError.keyUnavailable
        }
        let spki = prefix + x963
        let keyHash = SHA256.hash(data: spki).map {
          String(format: "%02x", $0)
        }.joined()
        let message = [
          "PZD-REGISTER-DEVICE-V1",
          playerId.lowercased(),
          sessionId.lowercased(),
          keyHash
        ].joined(separator: "\n")
        result([
          "spkiBase64Url": base64Url(spki),
          "signatureBase64Url": base64Url(try sign(message, with: privateKey))
        ])
      case "signRecovery":
        guard let seriesId = arguments["seriesId"] as? String,
              let sessionId = arguments["newSessionId"] as? String,
              let deviceCredentialId = arguments["deviceCredentialId"] as? String,
              let challengeId = arguments["challengeId"] as? String,
              let nonce = arguments["nonce"] as? String,
              let generation = arguments["expectedWriterGeneration"] as? Int,
              let expiresAtMs = arguments["expiresAtMs"] as? Int64 else {
          throw DeviceSigningError.invalidArgument
        }
        let message = [
          "PZD-RECOVER-WRITER-V1",
          playerId.lowercased(),
          seriesId.lowercased(),
          sessionId.lowercased(),
          deviceCredentialId.lowercased(),
          challengeId.lowercased(),
          nonce,
          String(generation),
          String(expiresAtMs)
        ].joined(separator: "\n")
        result(base64Url(try sign(message, with: privateKey)))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(
        code: "DEVICE_SIGNING_UNAVAILABLE",
        message: "Secure device signing is unavailable",
        details: nil
      ))
    }
  }

  private enum DeviceSigningError: Error {
    case invalidArgument
    case keyUnavailable
  }

  private func base64Url(_ value: Data) -> String {
    value.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func sign(_ message: String, with key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      key,
      .ecdsaSignatureMessageX962SHA256,
      Data(message.utf8) as CFData,
      &error
    ) as Data? else {
      throw DeviceSigningError.keyUnavailable
    }
    return signature // Native ASN.1 DER; server verifies SHA-256 ECDSA DER.
  }

  private func key(for playerId: String, origin: String) throws -> SecKey {
    let scope = SHA256.hash(data: Data((origin + "|" + playerId).utf8))
      .map { String(format: "%02x", $0) }.joined()
    let tag = Data(("pzd.securedevice." + scope).utf8)
    let lookup: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true
    ]
    var existing: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &existing)
    if status == errSecSuccess, let found = existing {
      return (found as! SecKey)
    }
    guard status == errSecItemNotFound else {
      throw DeviceSigningError.keyUnavailable
    }

    var accessError: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(
      kCFAllocatorDefault,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      .privateKeyUsage,
      &accessError
    ) else {
      throw DeviceSigningError.keyUnavailable
    }
    let attrs: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessControl as String: access
      ]
    ]
    var createError: Unmanaged<CFError>?
    guard let created = SecKeyCreateRandomKey(attrs as CFDictionary, &createError) else {
      // Fail closed: never substitute an exportable key on physical devices.
      throw DeviceSigningError.keyUnavailable
    }
    return created
  }
}
