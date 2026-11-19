import 'dart:math';

import '../ids/uuid_v7.dart';
import '../prefs/device_store.dart';

/// The signed-in person. [name] and [phone] come from the sign-in provider
/// and can be corrected in set-up.
class Account {
  const Account({required this.id, this.email, this.name = '', this.phone});

  factory Account.fromJson(Map<String, Object?> json) => Account(
    id: json['id']! as String,
    email: json['email'] as String?,
    name: json['name'] as String? ?? '',
    phone: json['phone'] as String?,
  );

  final String id;
  final String? email;
  final String name;
  final String? phone;

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'phone': phone,
  };
}

abstract interface class AuthGateway {
  /// Signs in and returns who; throws when the person cancels or it fails.
  Future<Account> signIn();

  Future<void> signOut();
}

/// Stands in for Google sign-in: one local test account per phone, the same
/// one every time, with no network.
// shortcut: no real account and no server session; B6 replaces this with
// Google sign-in through Supabase once the OAuth client ids exist.
class TestAccountAuth implements AuthGateway {
  TestAccountAuth(this._store, {Random? random})
    : _random = random ?? Random.secure();

  final DeviceStore _store;
  final Random _random;
  static const _key = 'auth.test_account_id';

  @override
  Future<Account> signIn() async {
    var id = _store.get(_key) as String?;
    if (id == null) {
      id = uuidV7(DateTime.now(), _random);
      await _store.set(_key, id);
    }
    return Account(id: id);
  }

  @override
  Future<void> signOut() async {}
}
