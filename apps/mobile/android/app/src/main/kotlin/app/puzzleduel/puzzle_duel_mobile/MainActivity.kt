package app.puzzleduel.puzzle_duel_mobile

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Locale

/**
 * Account- and server-origin-scoped, non-exportable AndroidKeyStore P-256 key.
 * Matches the iOS Secure Enclave / server's UTF-8 newline-delimited ECDSA
 * SHA-256 protocol. Never returns private-key material to Dart.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "pzd/device_signing"
    private val hexUuid = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    private val allowedOrigin = Regex("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    val playerId = requiredUuid(call, "playerId")
                    val origin = requiredOrigin(call)
                    val keyPair = loadOrCreateKey(playerId, origin)
                    when (call.method) {
                        "registerProof" -> {
                            val sessionId = requiredUuid(call, "sessionId")
                            val spki = keyPair.public.encoded
                            val keyHash = sha256(spki)
                            val payload = listOf(
                                "PZD-REGISTER-DEVICE-V1", playerId, sessionId, keyHash
                            ).joinToString("\n")
                            result.success(mapOf(
                                "spkiBase64Url" to b64(spki),
                                "signatureBase64Url" to sign(payload, keyPair.private)
                            ))
                        }
                        "signRecovery" -> {
                            val seriesId = requiredUuid(call, "seriesId")
                            val sessionId = requiredUuid(call, "newSessionId")
                            val credentialId = requiredUuid(call, "deviceCredentialId")
                            val challengeId = requiredUuid(call, "challengeId")
                            val nonce = call.argument<String>("nonce")
                                ?.takeIf { it.matches(Regex("^[A-Za-z0-9_-]{43}$")) }
                                ?: throw IllegalArgumentException("nonce")
                            val generation = call.argument<Number>("expectedWriterGeneration")
                                ?.toLong()?.takeIf { it >= 1 }
                                ?: throw IllegalArgumentException("generation")
                            val expiry = call.argument<Number>("expiresAtMs")
                                ?.toLong()?.takeIf { it > 0 }
                                ?: throw IllegalArgumentException("expiry")
                            val payload = listOf(
                                "PZD-RECOVER-WRITER-V1", playerId, seriesId, sessionId,
                                credentialId, challengeId, nonce, generation.toString(),
                                expiry.toString()
                            ).joinToString("\n")
                            result.success(sign(payload, keyPair.private))
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("DEVICE_SIGNING_UNAVAILABLE",
                        "Secure device signing is unavailable", null)
                }
            }
    }

    private fun requiredUuid(call: MethodCall, name: String): String =
        call.argument<String>(name)?.takeIf { hexUuid.matches(it) }
            ?.lowercase(Locale.ROOT) ?: throw IllegalArgumentException(name)

    private fun requiredOrigin(call: MethodCall): String {
        val origin = call.argument<String>("origin")
            ?: throw IllegalArgumentException("origin")
        // Android recovery deliberately supports staging HTTPS only; no
        // untrusted paths, user-info, query, fragments or cleartext.
        if (!allowedOrigin.matches(origin)) throw IllegalArgumentException("origin")
        return origin
    }

    private fun loadOrCreateKey(playerId: String, origin: String): java.security.KeyPair {
        val scope = sha256((origin + "|" + playerId).toByteArray(StandardCharsets.UTF_8))
        val alias = "pzd.securedevice." + scope
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getEntry(alias, null)
        if (existing is KeyStore.PrivateKeyEntry) {
            return java.security.KeyPair(existing.certificate.publicKey, existing.privateKey)
        }
        // Key stays inside AndroidKeyStore; do not downgrade to a normal
        // software-generated, exportable private key on an unavailable keystore.
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore"
        )
        generator.initialize(
            KeyGenParameterSpec.Builder(alias,
                KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false)
                .build()
        )
        return generator.generateKeyPair()
    }

    private fun sign(message: String, key: java.security.PrivateKey): String =
        b64(Signature.getInstance("SHA256withECDSA").run {
            initSign(key)
            update(message.toByteArray(StandardCharsets.UTF_8))
            sign() // ASN.1 DER ECDSA, identical wire format to iOS.
        })

    private fun sha256(data: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(data)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun b64(data: ByteArray): String =
        Base64.encodeToString(data, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
}
