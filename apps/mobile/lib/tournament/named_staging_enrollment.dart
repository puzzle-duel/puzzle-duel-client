import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:puzzle_duel_mobile/tournament/guest_auth.dart';
import 'package:puzzle_duel_mobile/tournament/guest_secure_store.dart';

/// Staging-only enrollment. Code stays in transient widget state, never logs,
/// runtime configuration, app assets, local JSON, or CI artifacts.
class NamedStagingEnrollmentScreen extends StatefulWidget {
  const NamedStagingEnrollmentScreen({
    super.key, required this.origin, required this.store,
    required this.slot, required this.onEnrolled,
  });
  final String origin;
  final SecureGuestCredentialStore store;
  final String slot;
  final Future<void> Function() onEnrolled;

  @override
  State<NamedStagingEnrollmentScreen> createState() => _NamedStagingEnrollmentScreenState();
}

class _NamedStagingEnrollmentScreenState extends State<NamedStagingEnrollmentScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _redeem() async {
    final code = _controller.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code)) {
      setState(() => _error = 'INVALID_ENROLLMENT_CODE');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    var phase = 'connect';
    try {
      final base = Uri.parse(widget.origin);
      if (base.scheme != 'https' || base.host.isEmpty || base.userInfo.isNotEmpty ||
          base.hasQuery || base.hasFragment ||
          (base.path.isNotEmpty && base.path != '/')) {
        throw const GuestAuthException('STAGING_HTTPS_REQUIRED');
      }
      final request = await client.postUrl(base.resolve('/v1/auth/guest?named-enrollment=1'))
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.headers.set('cache-control', 'no-store');
      final bytes = utf8.encode(jsonEncode({'code': code}));
      request.contentLength = bytes.length;
      request.add(bytes);
      phase = 'response';
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b))
          .timeout(const Duration(seconds: 12));
      if (body.length > 16384) throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      if (response.statusCode == 503) {
        throw const GuestAuthException('ENROLLMENT_SERVER_UNAVAILABLE');
      }
      if (response.statusCode == 429) {
        throw const GuestAuthException('ENROLLMENT_RATE_LIMITED');
      }
      if (response.statusCode != 200) {
        throw const GuestAuthException('ENROLLMENT_REJECTED');
      }
      phase = 'decode';
      final json = jsonDecode(utf8.decode(body));
      if (json is! Map<String, dynamic>) throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      final refresh = json['refreshToken'];
      final subject = json['playerId'];
      final access = json['accessToken'];
      if (refresh is! String || !RegExp(r'^[A-Za-z0-9_-]{64}$').hasMatch(refresh) ||
          subject is! String ||
          !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(subject) ||
          access is! String) {
        throw const GuestAuthException('INVALID_AUTH_RESPONSE');
      }
      final parsed = GuestAccess(
          accessToken: access, expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)));
      if (parsed.sessionVaultBinding != 'staging-guest:$subject') {
        throw const GuestAuthException('NAMED_PLAYER_IDENTITY_MISMATCH');
      }
      // Save identity first and token last; startup fails closed if interrupted.
      phase = 'keychain';
      await widget.store.writeNamedPlayerId(subject);
      if (await widget.store.readNamedPlayerId() != subject) {
        throw const GuestAuthException('SECURE_STORE_VERIFY_FAILED');
      }
      await persistVerifiedGuestCredential(widget.store, refresh);
      _controller.clear();
      phase = 'startup';
      await widget.onEnrolled();
    } on GuestAuthException catch (e) {
      if (mounted) setState(() => _error = e.code);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'ENROLLMENT_NETWORK_TIMEOUT');
    } on SocketException {
      if (mounted) setState(() => _error = 'ENROLLMENT_NETWORK_UNAVAILABLE');
    } on HandshakeException {
      if (mounted) setState(() => _error = 'ENROLLMENT_TLS_FAILED');
    } on PlatformException {
      // Do not log Keychain exception text, codes, device IDs or credentials.
      if (mounted) setState(() => _error = 'ENROLLMENT_KEYCHAIN_UNAVAILABLE');
    } on FormatException {
      if (mounted) setState(() => _error = 'ENROLLMENT_RESPONSE_FORMAT_INVALID');
    } catch (_) {
      // Phase names only; never expose raw exceptions, HTTP bodies or secrets.
      if (mounted) setState(() => _error = switch (phase) {
        'connect' || 'response' => 'ENROLLMENT_NETWORK_UNAVAILABLE',
        'decode' => 'ENROLLMENT_RESPONSE_FORMAT_INVALID',
        'keychain' => 'ENROLLMENT_KEYCHAIN_UNAVAILABLE',
        'startup' => 'ENROLLMENT_STARTUP_UNAVAILABLE',
        _ => 'ENROLLMENT_UNAVAILABLE',
      });
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Puzzle Duel Staging',
    home: Scaffold(
      appBar: AppBar(title: const Text('Staging device pairing')),
      body: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.slot == 'gokhan' ? 'Gökhan Aydın' : 'Serap Nazlı Aydın'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            enabled: !_busy,
            autocorrect: false,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'One-time pairing code'),
          ),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, key: const Key('named-enrollment-error')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _redeem,
            child: _busy ? const CircularProgressIndicator() : const Text('Pair iPhone'),
          ),
        ]),
      )),
    ),
  );
}
