/// core/services/storage_service.dart
/// Centralised local storage service for EduPay.
///
/// STORAGE LAYERS:
///  1. FlutterSecureStorage — JWT tokens, refresh tokens (encrypted keychain)
///     PRD Section 10: "Local files stored in app-private directory"
///  2. Hive — message cache, fee records, download queue (fast local DB)
///  3. SharedPreferences — non-sensitive settings (theme, language)
///
/// PRD Reference: Section 10 — Security & Compliance
///   "Local files stored in app-private directory (not exposed to other apps)"
///   Secure storage uses AES-256 encryption on Android (EncryptedSharedPrefs)
///   and iOS Keychain.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:io' show Platform;

import '../constants/app_constants.dart';

class StorageService {
  StorageService() {
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true, // AES-256 on Android
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
  }

  late final FlutterSecureStorage _secureStorage;

  // ── Hive Initialisation ────────────────────────────────────────────────────
  static Future<void> initHive() async {
    await Hive.openBox<dynamic>(AppConstants.hiveMessages);
    await Hive.openBox<dynamic>(AppConstants.hiveFees);
    await Hive.openBox<dynamic>(AppConstants.hiveBatches);
    await Hive.openBox<dynamic>(AppConstants.hiveDownloads);
    await Hive.openBox<dynamic>(AppConstants.hiveSettings);
  }

  // ── JWT Token Operations ───────────────────────────────────────────────────

  /// Saves both access and refresh tokens to secure storage.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String refreshExpiry,
  }) async {
    await Future.wait([
      _secureStorage.write(
        key:   AppConstants.keyAccessToken,
        value: accessToken,
      ),
      _secureStorage.write(
        key:   AppConstants.keyRefreshToken,
        value: refreshToken,
      ),
      _secureStorage.write(
        key:   AppConstants.keyRefreshExpiry,
        value: refreshExpiry,
      ),
    ]);
  }

  /// Returns the stored JWT access token, or null if not logged in.
  Future<String?> getAccessToken() =>
      _secureStorage.read(key: AppConstants.keyAccessToken);

  /// Returns the stored refresh token, or null if not available.
  Future<String?> getRefreshToken() =>
      _secureStorage.read(key: AppConstants.keyRefreshToken);

  /// Returns the refresh token expiry ISO string.
  Future<String?> getRefreshExpiry() =>
      _secureStorage.read(key: AppConstants.keyRefreshExpiry);

  // ── User Profile ──────────────────────────────────────────────────────────

  /// Saves user profile after successful login/register.
  Future<void> saveUserProfile({
    required String id,
    required String name,
    required String email,
    required String role,
  }) async {
    await Future.wait([
      _secureStorage.write(key: AppConstants.keyUserId,    value: id),
      _secureStorage.write(key: AppConstants.keyUserName,  value: name),
      _secureStorage.write(key: AppConstants.keyUserEmail, value: email),
      _secureStorage.write(key: AppConstants.keyUserRole,  value: role),
    ]);
  }

  Future<String?> getUserId()    => _secureStorage.read(key: AppConstants.keyUserId);
  Future<String?> getUserName()  => _secureStorage.read(key: AppConstants.keyUserName);
  Future<String?> getUserEmail() => _secureStorage.read(key: AppConstants.keyUserEmail);
  Future<String?> getUserRole()  => _secureStorage.read(key: AppConstants.keyUserRole);

  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Device ID ─────────────────────────────────────────────────────────────
  /// Returns a stable device ID for refresh token per-device management.
  /// PRD Section 10: "Device token rotation on each login"
  ///
  /// Generated once per install and stored securely.
  Future<String> getDeviceId() async {
    final stored = await _secureStorage.read(key: AppConstants.keyDeviceId);
    if (stored != null && stored.isNotEmpty) return stored;

    // Generate a stable device-specific ID
    String deviceId;
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        deviceId = android.id; // Android hardware ID
      } else {
        final ios = await info.iosInfo;
        deviceId = ios.identifierForVendor ?? const Uuid().v4();
      }
    } catch (_) {
      deviceId = const Uuid().v4(); // Fallback
    }

    await _secureStorage.write(
      key:   AppConstants.keyDeviceId,
      value: deviceId,
    );
    return deviceId;
  }

  // ── Hive: Download Queue ───────────────────────────────────────────────────
  /// Saves a pending download to the local queue.
  /// PRD Section 11: "cache download queue in local DB"
  Future<void> queueDownload(Map<String, dynamic> downloadData) async {
    final box = Hive.box<dynamic>(AppConstants.hiveDownloads);
    final key = downloadData['file_record_id'] as String;
    await box.put(key, downloadData);
  }

  /// Removes a completed or failed download from the queue.
  Future<void> dequeueDownload(String fileRecordId) async {
    final box = Hive.box<dynamic>(AppConstants.hiveDownloads);
    await box.delete(fileRecordId);
  }

  /// Returns all pending downloads (e.g., on app restart after background kill).
  List<Map<String, dynamic>> getPendingDownloads() {
    final box = Hive.box<dynamic>(AppConstants.hiveDownloads);
    return box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── Hive: Downloaded Files Cache ──────────────────────────────────────────
  /// Records metadata of a successfully downloaded file.
  /// Flutter clients display files from this cache after server expiry.
  /// PRD Section 07: "Students continue to view the file from local storage"
  Future<void> saveDownloadedFileMeta(Map<String, dynamic> fileMeta) async {
    final box = Hive.box<dynamic>(AppConstants.hiveDownloads);
    final key = 'done_${fileMeta['file_record_id']}';
    await box.put(key, fileMeta);
  }

  /// Returns the local path for a downloaded file by file_record_id.
  String? getLocalFilePath(String fileRecordId) {
    final box  = Hive.box<dynamic>(AppConstants.hiveDownloads);
    final meta = box.get('done_$fileRecordId');
    if (meta is Map) {
      return meta['local_path'] as String?;
    }
    return null;
  }

  /// Checks if a file is already downloaded locally.
  bool isFileDownloaded(String fileRecordId) {
    return getLocalFilePath(fileRecordId) != null;
  }

  // ── Settings (SharedPreferences) ──────────────────────────────────────────
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> setBool(String key, bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(key, value);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await _prefs;
    return prefs.getBool(key);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  Future<String?> getString(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  // ── Clear All (Logout) ────────────────────────────────────────────────────
  /// Clears all sensitive data on logout.
  /// Keeps downloaded file cache (user can still view offline files).
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();

    // Clear message and fee caches
    await Hive.box<dynamic>(AppConstants.hiveMessages).clear();
    await Hive.box<dynamic>(AppConstants.hiveFees).clear();
    await Hive.box<dynamic>(AppConstants.hiveBatches).clear();
    // NOTE: hiveDownloads NOT cleared — preserves local file cache

    final prefs = await _prefs;
    await prefs.clear();
  }

  // ── Avatar ID storage ─────────────────────────────────────────────────────────
  // Add these methods to your existing StorageService class

  /// Save avatar_id to secure storage (persists across app restarts)
  Future<void> saveAvatarId(int avatarId) async {
    await _secureStorage.write(
      key:   AppConstants.keyAvatarId,
      value: avatarId.toString(),
    );
  }

  /// Read stored avatar_id — returns null if not set
  Future<int?> getAvatarId() async {
    final value = await _secureStorage.read(key: AppConstants.keyAvatarId);
    if (value == null) return null;
    return int.tryParse(value);
  }

  /// Save user name (separate from full profile save — for profile update)
  Future<void> saveUserName(String name) async {
    await _secureStorage.write(key: AppConstants.keyUserName, value: name);
  }

}