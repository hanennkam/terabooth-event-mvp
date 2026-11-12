import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the Windows Bridge API token outside app documents/logs.
abstract class BridgeTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// iOS Keychain-backed token store. The token is never written to diagnostics.
class KeychainBridgeTokenStore implements BridgeTokenStore {
  static const _key = 'terabooth.bridge.api_token';
  final FlutterSecureStorage _storage;

  KeychainBridgeTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
