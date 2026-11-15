/// Three-way merge of synced settings, as settings sync in editors does:
/// each side is compared with the copy both last agreed on (the base), so
/// a change made on only one side wins without asking, and only a setting
/// changed differently on both sides is a conflict. Objects merge field by
/// field, so changing the danmaku size here and its opacity elsewhere keeps
/// both.
library;

/// A setting (or one field of it) changed differently on both sides.
class SettingConflict {
  const SettingConflict(this.key, this.field, this.local, this.remote);

  /// The setting's key, and the field of an object setting, if any.
  final String key;
  final String? field;

  /// Each side's value; null where that side removed it (back to default).
  final Object? local, remote;

  String get id => field == null ? key : '$key.$field';
}

class SettingsMerge {
  const SettingsMerge(this.merged, this.conflicts);

  /// The merged settings, with each conflict holding this device's value
  /// until [resolve] picks.
  final Map<String, Object?> merged;
  final List<SettingConflict> conflicts;

  /// [merged] with each conflict in [useRemote] (by [SettingConflict.id])
  /// taking the remote value instead.
  Map<String, Object?> resolve(Set<String> useRemote) {
    final result = {
      for (final MapEntry(:key, :value) in merged.entries)
        key: value is Map ? {...value} : value,
    };
    for (final conflict in conflicts) {
      if (!useRemote.contains(conflict.id)) continue;
      if (conflict.field case final field?) {
        final target = (result[conflict.key] as Map?) ?? <String, Object?>{};
        if (conflict.remote == null) {
          target.remove(field);
        } else {
          target[field] = conflict.remote;
        }
        result[conflict.key] = target;
      } else {
        result[conflict.key] = conflict.remote;
      }
    }
    result.removeWhere((_, value) => value == null);
    return result;
  }
}

/// [atomic] keys compare their objects as a whole: a record whose fields
/// only make sense together, such as a place in an episode and its time.
SettingsMerge mergeSettings({
  required Map<String, Object?> base,
  required Map<String, Object?> local,
  required Map<String, Object?> remote,
  bool Function(String key)? atomic,
}) {
  final merged = <String, Object?>{};
  final conflicts = <SettingConflict>[];
  for (final key in {...base.keys, ...local.keys, ...remote.keys}) {
    final b = base[key], l = local[key], r = remote[key];
    if (sameJson(l, r) || sameJson(r, b)) {
      merged[key] = l;
    } else if (sameJson(l, b)) {
      merged[key] = r;
    } else if (l is Map &&
        r is Map &&
        (b == null || b is Map) &&
        !(atomic?.call(key) ?? false)) {
      final fields = <String, Object?>{};
      final baseFields = (b as Map?) ?? const {};
      for (final field in {...baseFields.keys, ...l.keys, ...r.keys}) {
        final fb = baseFields[field], fl = l[field], fr = r[field];
        if (sameJson(fl, fr) || sameJson(fr, fb)) {
          fields['$field'] = fl;
        } else if (sameJson(fl, fb)) {
          fields['$field'] = fr;
        } else {
          fields['$field'] = fl;
          conflicts.add(SettingConflict(key, '$field', fl, fr));
        }
      }
      fields.removeWhere((_, value) => value == null);
      merged[key] = fields;
    } else {
      merged[key] = l;
      conflicts.add(SettingConflict(key, null, l, r));
    }
  }
  merged.removeWhere((_, value) => value == null);
  return SettingsMerge(merged, conflicts);
}

/// Equal as JSON: maps by content whatever their order, numbers by value.
bool sameJson(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !sameJson(value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!sameJson(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}
