import 'dart:convert';

import 'package:drift/drift.dart';

import '../access/access.dart';
import 'database.dart';

/// [userId]'s role and permissions on [farmId]; none until the membership is
/// on the phone.
Stream<Access> watchAccess(AppDatabase db, String farmId, String userId) => db
    .customSelect(
      'SELECT role, permissions FROM farm_members WHERE farm_id = ? '
      'AND user_id = ? AND deleted_at IS NULL',
      variables: [Variable.withString(farmId), Variable.withString(userId)],
      readsFrom: {db.farmMembers},
    )
    .watchSingleOrNull()
    .map(
      (r) => r == null
          ? Access.none
          : Access(
              r.read<String>('role'),
              (jsonDecode(r.read<String>('permissions')) as Map)
                  .cast<String, Object?>(),
            ),
    );
