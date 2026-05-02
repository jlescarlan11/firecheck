// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $EnumeratorsTable extends Enumerators
    with TableInfo<$EnumeratorsTable, Enumerator> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EnumeratorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, username, displayName, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'enumerators';
  @override
  VerificationContext validateIntegrity(Insertable<Enumerator> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Enumerator map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Enumerator(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $EnumeratorsTable createAlias(String alias) {
    return $EnumeratorsTable(attachedDatabase, alias);
  }
}

class Enumerator extends DataClass implements Insertable<Enumerator> {
  final String id;
  final String username;
  final String displayName;
  final DateTime createdAt;
  const Enumerator(
      {required this.id,
      required this.username,
      required this.displayName,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  EnumeratorsCompanion toCompanion(bool nullToAbsent) {
    return EnumeratorsCompanion(
      id: Value(id),
      username: Value(username),
      displayName: Value(displayName),
      createdAt: Value(createdAt),
    );
  }

  factory Enumerator.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Enumerator(
      id: serializer.fromJson<String>(json['id']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Enumerator copyWith(
          {String? id,
          String? username,
          String? displayName,
          DateTime? createdAt}) =>
      Enumerator(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        createdAt: createdAt ?? this.createdAt,
      );
  Enumerator copyWithCompanion(EnumeratorsCompanion data) {
    return Enumerator(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Enumerator(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, username, displayName, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Enumerator &&
          other.id == this.id &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.createdAt == this.createdAt);
}

class EnumeratorsCompanion extends UpdateCompanion<Enumerator> {
  final Value<String> id;
  final Value<String> username;
  final Value<String> displayName;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const EnumeratorsCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EnumeratorsCompanion.insert({
    required String id,
    required String username,
    required String displayName,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        username = Value(username),
        displayName = Value(displayName),
        createdAt = Value(createdAt);
  static Insertable<Enumerator> custom({
    Expression<String>? id,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EnumeratorsCompanion copyWith(
      {Value<String>? id,
      Value<String>? username,
      Value<String>? displayName,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return EnumeratorsCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnumeratorsCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AssignmentsTable extends Assignments
    with TableInfo<$AssignmentsTable, Assignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enumeratorIdMeta =
      const VerificationMeta('enumeratorId');
  @override
  late final GeneratedColumn<String> enumeratorId = GeneratedColumn<String>(
      'enumerator_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _campaignIdMeta =
      const VerificationMeta('campaignId');
  @override
  late final GeneratedColumn<String> campaignId = GeneratedColumn<String>(
      'campaign_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _boundaryPolygonGeojsonMeta =
      const VerificationMeta('boundaryPolygonGeojson');
  @override
  late final GeneratedColumn<String> boundaryPolygonGeojson =
      GeneratedColumn<String>('boundary_polygon_geojson', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _downloadedAtMeta =
      const VerificationMeta('downloadedAt');
  @override
  late final GeneratedColumn<DateTime> downloadedAt = GeneratedColumn<DateTime>(
      'downloaded_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _submittedAtMeta =
      const VerificationMeta('submittedAt');
  @override
  late final GeneratedColumn<DateTime> submittedAt = GeneratedColumn<DateTime>(
      'submitted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('assigned'));
  static const VerificationMeta _closedRemotelyMeta =
      const VerificationMeta('closedRemotely');
  @override
  late final GeneratedColumn<bool> closedRemotely = GeneratedColumn<bool>(
      'closed_remotely', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("closed_remotely" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _driveModifiedTimeMeta =
      const VerificationMeta('driveModifiedTime');
  @override
  late final GeneratedColumn<String> driveModifiedTime =
      GeneratedColumn<String>('drive_modified_time', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _driveFolderIdMeta =
      const VerificationMeta('driveFolderId');
  @override
  late final GeneratedColumn<String> driveFolderId = GeneratedColumn<String>(
      'drive_folder_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _driveFolderPathMeta =
      const VerificationMeta('driveFolderPath');
  @override
  late final GeneratedColumn<String> driveFolderPath = GeneratedColumn<String>(
      'drive_folder_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _driveFolderUrlMeta =
      const VerificationMeta('driveFolderUrl');
  @override
  late final GeneratedColumn<String> driveFolderUrl = GeneratedColumn<String>(
      'drive_folder_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _driveUploadConfirmedAtMeta =
      const VerificationMeta('driveUploadConfirmedAt');
  @override
  late final GeneratedColumn<DateTime> driveUploadConfirmedAt =
      GeneratedColumn<DateTime>('drive_upload_confirmed_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        enumeratorId,
        campaignId,
        boundaryPolygonGeojson,
        downloadedAt,
        submittedAt,
        status,
        closedRemotely,
        createdAt,
        driveModifiedTime,
        driveFolderId,
        driveFolderPath,
        driveFolderUrl,
        driveUploadConfirmedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assignments';
  @override
  VerificationContext validateIntegrity(Insertable<Assignment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('enumerator_id')) {
      context.handle(
          _enumeratorIdMeta,
          enumeratorId.isAcceptableOrUnknown(
              data['enumerator_id']!, _enumeratorIdMeta));
    } else if (isInserting) {
      context.missing(_enumeratorIdMeta);
    }
    if (data.containsKey('campaign_id')) {
      context.handle(
          _campaignIdMeta,
          campaignId.isAcceptableOrUnknown(
              data['campaign_id']!, _campaignIdMeta));
    } else if (isInserting) {
      context.missing(_campaignIdMeta);
    }
    if (data.containsKey('boundary_polygon_geojson')) {
      context.handle(
          _boundaryPolygonGeojsonMeta,
          boundaryPolygonGeojson.isAcceptableOrUnknown(
              data['boundary_polygon_geojson']!, _boundaryPolygonGeojsonMeta));
    } else if (isInserting) {
      context.missing(_boundaryPolygonGeojsonMeta);
    }
    if (data.containsKey('downloaded_at')) {
      context.handle(
          _downloadedAtMeta,
          downloadedAt.isAcceptableOrUnknown(
              data['downloaded_at']!, _downloadedAtMeta));
    }
    if (data.containsKey('submitted_at')) {
      context.handle(
          _submittedAtMeta,
          submittedAt.isAcceptableOrUnknown(
              data['submitted_at']!, _submittedAtMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('closed_remotely')) {
      context.handle(
          _closedRemotelyMeta,
          closedRemotely.isAcceptableOrUnknown(
              data['closed_remotely']!, _closedRemotelyMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('drive_modified_time')) {
      context.handle(
          _driveModifiedTimeMeta,
          driveModifiedTime.isAcceptableOrUnknown(
              data['drive_modified_time']!, _driveModifiedTimeMeta));
    }
    if (data.containsKey('drive_folder_id')) {
      context.handle(
          _driveFolderIdMeta,
          driveFolderId.isAcceptableOrUnknown(
              data['drive_folder_id']!, _driveFolderIdMeta));
    }
    if (data.containsKey('drive_folder_path')) {
      context.handle(
          _driveFolderPathMeta,
          driveFolderPath.isAcceptableOrUnknown(
              data['drive_folder_path']!, _driveFolderPathMeta));
    }
    if (data.containsKey('drive_folder_url')) {
      context.handle(
          _driveFolderUrlMeta,
          driveFolderUrl.isAcceptableOrUnknown(
              data['drive_folder_url']!, _driveFolderUrlMeta));
    }
    if (data.containsKey('drive_upload_confirmed_at')) {
      context.handle(
          _driveUploadConfirmedAtMeta,
          driveUploadConfirmedAt.isAcceptableOrUnknown(
              data['drive_upload_confirmed_at']!, _driveUploadConfirmedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Assignment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Assignment(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      enumeratorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}enumerator_id'])!,
      campaignId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}campaign_id'])!,
      boundaryPolygonGeojson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}boundary_polygon_geojson'])!,
      downloadedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}downloaded_at']),
      submittedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}submitted_at']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      closedRemotely: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}closed_remotely'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      driveModifiedTime: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}drive_modified_time']),
      driveFolderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}drive_folder_id']),
      driveFolderPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}drive_folder_path']),
      driveFolderUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}drive_folder_url']),
      driveUploadConfirmedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}drive_upload_confirmed_at']),
    );
  }

  @override
  $AssignmentsTable createAlias(String alias) {
    return $AssignmentsTable(attachedDatabase, alias);
  }
}

class Assignment extends DataClass implements Insertable<Assignment> {
  final String id;
  final String enumeratorId;
  final String campaignId;
  final String boundaryPolygonGeojson;
  final DateTime? downloadedAt;
  final DateTime? submittedAt;
  final String status;
  final bool closedRemotely;
  final DateTime createdAt;
  final String? driveModifiedTime;
  final String? driveFolderId;
  final String? driveFolderPath;
  final String? driveFolderUrl;
  final DateTime? driveUploadConfirmedAt;
  const Assignment(
      {required this.id,
      required this.enumeratorId,
      required this.campaignId,
      required this.boundaryPolygonGeojson,
      this.downloadedAt,
      this.submittedAt,
      required this.status,
      required this.closedRemotely,
      required this.createdAt,
      this.driveModifiedTime,
      this.driveFolderId,
      this.driveFolderPath,
      this.driveFolderUrl,
      this.driveUploadConfirmedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['enumerator_id'] = Variable<String>(enumeratorId);
    map['campaign_id'] = Variable<String>(campaignId);
    map['boundary_polygon_geojson'] = Variable<String>(boundaryPolygonGeojson);
    if (!nullToAbsent || downloadedAt != null) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt);
    }
    if (!nullToAbsent || submittedAt != null) {
      map['submitted_at'] = Variable<DateTime>(submittedAt);
    }
    map['status'] = Variable<String>(status);
    map['closed_remotely'] = Variable<bool>(closedRemotely);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || driveModifiedTime != null) {
      map['drive_modified_time'] = Variable<String>(driveModifiedTime);
    }
    if (!nullToAbsent || driveFolderId != null) {
      map['drive_folder_id'] = Variable<String>(driveFolderId);
    }
    if (!nullToAbsent || driveFolderPath != null) {
      map['drive_folder_path'] = Variable<String>(driveFolderPath);
    }
    if (!nullToAbsent || driveFolderUrl != null) {
      map['drive_folder_url'] = Variable<String>(driveFolderUrl);
    }
    if (!nullToAbsent || driveUploadConfirmedAt != null) {
      map['drive_upload_confirmed_at'] =
          Variable<DateTime>(driveUploadConfirmedAt);
    }
    return map;
  }

  AssignmentsCompanion toCompanion(bool nullToAbsent) {
    return AssignmentsCompanion(
      id: Value(id),
      enumeratorId: Value(enumeratorId),
      campaignId: Value(campaignId),
      boundaryPolygonGeojson: Value(boundaryPolygonGeojson),
      downloadedAt: downloadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(downloadedAt),
      submittedAt: submittedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedAt),
      status: Value(status),
      closedRemotely: Value(closedRemotely),
      createdAt: Value(createdAt),
      driveModifiedTime: driveModifiedTime == null && nullToAbsent
          ? const Value.absent()
          : Value(driveModifiedTime),
      driveFolderId: driveFolderId == null && nullToAbsent
          ? const Value.absent()
          : Value(driveFolderId),
      driveFolderPath: driveFolderPath == null && nullToAbsent
          ? const Value.absent()
          : Value(driveFolderPath),
      driveFolderUrl: driveFolderUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(driveFolderUrl),
      driveUploadConfirmedAt: driveUploadConfirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(driveUploadConfirmedAt),
    );
  }

  factory Assignment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Assignment(
      id: serializer.fromJson<String>(json['id']),
      enumeratorId: serializer.fromJson<String>(json['enumeratorId']),
      campaignId: serializer.fromJson<String>(json['campaignId']),
      boundaryPolygonGeojson:
          serializer.fromJson<String>(json['boundaryPolygonGeojson']),
      downloadedAt: serializer.fromJson<DateTime?>(json['downloadedAt']),
      submittedAt: serializer.fromJson<DateTime?>(json['submittedAt']),
      status: serializer.fromJson<String>(json['status']),
      closedRemotely: serializer.fromJson<bool>(json['closedRemotely']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      driveModifiedTime:
          serializer.fromJson<String?>(json['driveModifiedTime']),
      driveFolderId: serializer.fromJson<String?>(json['driveFolderId']),
      driveFolderPath: serializer.fromJson<String?>(json['driveFolderPath']),
      driveFolderUrl: serializer.fromJson<String?>(json['driveFolderUrl']),
      driveUploadConfirmedAt:
          serializer.fromJson<DateTime?>(json['driveUploadConfirmedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'enumeratorId': serializer.toJson<String>(enumeratorId),
      'campaignId': serializer.toJson<String>(campaignId),
      'boundaryPolygonGeojson':
          serializer.toJson<String>(boundaryPolygonGeojson),
      'downloadedAt': serializer.toJson<DateTime?>(downloadedAt),
      'submittedAt': serializer.toJson<DateTime?>(submittedAt),
      'status': serializer.toJson<String>(status),
      'closedRemotely': serializer.toJson<bool>(closedRemotely),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'driveModifiedTime': serializer.toJson<String?>(driveModifiedTime),
      'driveFolderId': serializer.toJson<String?>(driveFolderId),
      'driveFolderPath': serializer.toJson<String?>(driveFolderPath),
      'driveFolderUrl': serializer.toJson<String?>(driveFolderUrl),
      'driveUploadConfirmedAt':
          serializer.toJson<DateTime?>(driveUploadConfirmedAt),
    };
  }

  Assignment copyWith(
          {String? id,
          String? enumeratorId,
          String? campaignId,
          String? boundaryPolygonGeojson,
          Value<DateTime?> downloadedAt = const Value.absent(),
          Value<DateTime?> submittedAt = const Value.absent(),
          String? status,
          bool? closedRemotely,
          DateTime? createdAt,
          Value<String?> driveModifiedTime = const Value.absent(),
          Value<String?> driveFolderId = const Value.absent(),
          Value<String?> driveFolderPath = const Value.absent(),
          Value<String?> driveFolderUrl = const Value.absent(),
          Value<DateTime?> driveUploadConfirmedAt = const Value.absent()}) =>
      Assignment(
        id: id ?? this.id,
        enumeratorId: enumeratorId ?? this.enumeratorId,
        campaignId: campaignId ?? this.campaignId,
        boundaryPolygonGeojson:
            boundaryPolygonGeojson ?? this.boundaryPolygonGeojson,
        downloadedAt:
            downloadedAt.present ? downloadedAt.value : this.downloadedAt,
        submittedAt: submittedAt.present ? submittedAt.value : this.submittedAt,
        status: status ?? this.status,
        closedRemotely: closedRemotely ?? this.closedRemotely,
        createdAt: createdAt ?? this.createdAt,
        driveModifiedTime: driveModifiedTime.present
            ? driveModifiedTime.value
            : this.driveModifiedTime,
        driveFolderId:
            driveFolderId.present ? driveFolderId.value : this.driveFolderId,
        driveFolderPath: driveFolderPath.present
            ? driveFolderPath.value
            : this.driveFolderPath,
        driveFolderUrl:
            driveFolderUrl.present ? driveFolderUrl.value : this.driveFolderUrl,
        driveUploadConfirmedAt: driveUploadConfirmedAt.present
            ? driveUploadConfirmedAt.value
            : this.driveUploadConfirmedAt,
      );
  Assignment copyWithCompanion(AssignmentsCompanion data) {
    return Assignment(
      id: data.id.present ? data.id.value : this.id,
      enumeratorId: data.enumeratorId.present
          ? data.enumeratorId.value
          : this.enumeratorId,
      campaignId:
          data.campaignId.present ? data.campaignId.value : this.campaignId,
      boundaryPolygonGeojson: data.boundaryPolygonGeojson.present
          ? data.boundaryPolygonGeojson.value
          : this.boundaryPolygonGeojson,
      downloadedAt: data.downloadedAt.present
          ? data.downloadedAt.value
          : this.downloadedAt,
      submittedAt:
          data.submittedAt.present ? data.submittedAt.value : this.submittedAt,
      status: data.status.present ? data.status.value : this.status,
      closedRemotely: data.closedRemotely.present
          ? data.closedRemotely.value
          : this.closedRemotely,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      driveModifiedTime: data.driveModifiedTime.present
          ? data.driveModifiedTime.value
          : this.driveModifiedTime,
      driveFolderId: data.driveFolderId.present
          ? data.driveFolderId.value
          : this.driveFolderId,
      driveFolderPath: data.driveFolderPath.present
          ? data.driveFolderPath.value
          : this.driveFolderPath,
      driveFolderUrl: data.driveFolderUrl.present
          ? data.driveFolderUrl.value
          : this.driveFolderUrl,
      driveUploadConfirmedAt: data.driveUploadConfirmedAt.present
          ? data.driveUploadConfirmedAt.value
          : this.driveUploadConfirmedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Assignment(')
          ..write('id: $id, ')
          ..write('enumeratorId: $enumeratorId, ')
          ..write('campaignId: $campaignId, ')
          ..write('boundaryPolygonGeojson: $boundaryPolygonGeojson, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('status: $status, ')
          ..write('closedRemotely: $closedRemotely, ')
          ..write('createdAt: $createdAt, ')
          ..write('driveModifiedTime: $driveModifiedTime, ')
          ..write('driveFolderId: $driveFolderId, ')
          ..write('driveFolderPath: $driveFolderPath, ')
          ..write('driveFolderUrl: $driveFolderUrl, ')
          ..write('driveUploadConfirmedAt: $driveUploadConfirmedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      enumeratorId,
      campaignId,
      boundaryPolygonGeojson,
      downloadedAt,
      submittedAt,
      status,
      closedRemotely,
      createdAt,
      driveModifiedTime,
      driveFolderId,
      driveFolderPath,
      driveFolderUrl,
      driveUploadConfirmedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Assignment &&
          other.id == this.id &&
          other.enumeratorId == this.enumeratorId &&
          other.campaignId == this.campaignId &&
          other.boundaryPolygonGeojson == this.boundaryPolygonGeojson &&
          other.downloadedAt == this.downloadedAt &&
          other.submittedAt == this.submittedAt &&
          other.status == this.status &&
          other.closedRemotely == this.closedRemotely &&
          other.createdAt == this.createdAt &&
          other.driveModifiedTime == this.driveModifiedTime &&
          other.driveFolderId == this.driveFolderId &&
          other.driveFolderPath == this.driveFolderPath &&
          other.driveFolderUrl == this.driveFolderUrl &&
          other.driveUploadConfirmedAt == this.driveUploadConfirmedAt);
}

class AssignmentsCompanion extends UpdateCompanion<Assignment> {
  final Value<String> id;
  final Value<String> enumeratorId;
  final Value<String> campaignId;
  final Value<String> boundaryPolygonGeojson;
  final Value<DateTime?> downloadedAt;
  final Value<DateTime?> submittedAt;
  final Value<String> status;
  final Value<bool> closedRemotely;
  final Value<DateTime> createdAt;
  final Value<String?> driveModifiedTime;
  final Value<String?> driveFolderId;
  final Value<String?> driveFolderPath;
  final Value<String?> driveFolderUrl;
  final Value<DateTime?> driveUploadConfirmedAt;
  final Value<int> rowid;
  const AssignmentsCompanion({
    this.id = const Value.absent(),
    this.enumeratorId = const Value.absent(),
    this.campaignId = const Value.absent(),
    this.boundaryPolygonGeojson = const Value.absent(),
    this.downloadedAt = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.closedRemotely = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.driveModifiedTime = const Value.absent(),
    this.driveFolderId = const Value.absent(),
    this.driveFolderPath = const Value.absent(),
    this.driveFolderUrl = const Value.absent(),
    this.driveUploadConfirmedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AssignmentsCompanion.insert({
    required String id,
    required String enumeratorId,
    required String campaignId,
    required String boundaryPolygonGeojson,
    this.downloadedAt = const Value.absent(),
    this.submittedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.closedRemotely = const Value.absent(),
    required DateTime createdAt,
    this.driveModifiedTime = const Value.absent(),
    this.driveFolderId = const Value.absent(),
    this.driveFolderPath = const Value.absent(),
    this.driveFolderUrl = const Value.absent(),
    this.driveUploadConfirmedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        enumeratorId = Value(enumeratorId),
        campaignId = Value(campaignId),
        boundaryPolygonGeojson = Value(boundaryPolygonGeojson),
        createdAt = Value(createdAt);
  static Insertable<Assignment> custom({
    Expression<String>? id,
    Expression<String>? enumeratorId,
    Expression<String>? campaignId,
    Expression<String>? boundaryPolygonGeojson,
    Expression<DateTime>? downloadedAt,
    Expression<DateTime>? submittedAt,
    Expression<String>? status,
    Expression<bool>? closedRemotely,
    Expression<DateTime>? createdAt,
    Expression<String>? driveModifiedTime,
    Expression<String>? driveFolderId,
    Expression<String>? driveFolderPath,
    Expression<String>? driveFolderUrl,
    Expression<DateTime>? driveUploadConfirmedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (enumeratorId != null) 'enumerator_id': enumeratorId,
      if (campaignId != null) 'campaign_id': campaignId,
      if (boundaryPolygonGeojson != null)
        'boundary_polygon_geojson': boundaryPolygonGeojson,
      if (downloadedAt != null) 'downloaded_at': downloadedAt,
      if (submittedAt != null) 'submitted_at': submittedAt,
      if (status != null) 'status': status,
      if (closedRemotely != null) 'closed_remotely': closedRemotely,
      if (createdAt != null) 'created_at': createdAt,
      if (driveModifiedTime != null) 'drive_modified_time': driveModifiedTime,
      if (driveFolderId != null) 'drive_folder_id': driveFolderId,
      if (driveFolderPath != null) 'drive_folder_path': driveFolderPath,
      if (driveFolderUrl != null) 'drive_folder_url': driveFolderUrl,
      if (driveUploadConfirmedAt != null)
        'drive_upload_confirmed_at': driveUploadConfirmedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AssignmentsCompanion copyWith(
      {Value<String>? id,
      Value<String>? enumeratorId,
      Value<String>? campaignId,
      Value<String>? boundaryPolygonGeojson,
      Value<DateTime?>? downloadedAt,
      Value<DateTime?>? submittedAt,
      Value<String>? status,
      Value<bool>? closedRemotely,
      Value<DateTime>? createdAt,
      Value<String?>? driveModifiedTime,
      Value<String?>? driveFolderId,
      Value<String?>? driveFolderPath,
      Value<String?>? driveFolderUrl,
      Value<DateTime?>? driveUploadConfirmedAt,
      Value<int>? rowid}) {
    return AssignmentsCompanion(
      id: id ?? this.id,
      enumeratorId: enumeratorId ?? this.enumeratorId,
      campaignId: campaignId ?? this.campaignId,
      boundaryPolygonGeojson:
          boundaryPolygonGeojson ?? this.boundaryPolygonGeojson,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      submittedAt: submittedAt ?? this.submittedAt,
      status: status ?? this.status,
      closedRemotely: closedRemotely ?? this.closedRemotely,
      createdAt: createdAt ?? this.createdAt,
      driveModifiedTime: driveModifiedTime ?? this.driveModifiedTime,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      driveFolderPath: driveFolderPath ?? this.driveFolderPath,
      driveFolderUrl: driveFolderUrl ?? this.driveFolderUrl,
      driveUploadConfirmedAt:
          driveUploadConfirmedAt ?? this.driveUploadConfirmedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (enumeratorId.present) {
      map['enumerator_id'] = Variable<String>(enumeratorId.value);
    }
    if (campaignId.present) {
      map['campaign_id'] = Variable<String>(campaignId.value);
    }
    if (boundaryPolygonGeojson.present) {
      map['boundary_polygon_geojson'] =
          Variable<String>(boundaryPolygonGeojson.value);
    }
    if (downloadedAt.present) {
      map['downloaded_at'] = Variable<DateTime>(downloadedAt.value);
    }
    if (submittedAt.present) {
      map['submitted_at'] = Variable<DateTime>(submittedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (closedRemotely.present) {
      map['closed_remotely'] = Variable<bool>(closedRemotely.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (driveModifiedTime.present) {
      map['drive_modified_time'] = Variable<String>(driveModifiedTime.value);
    }
    if (driveFolderId.present) {
      map['drive_folder_id'] = Variable<String>(driveFolderId.value);
    }
    if (driveFolderPath.present) {
      map['drive_folder_path'] = Variable<String>(driveFolderPath.value);
    }
    if (driveFolderUrl.present) {
      map['drive_folder_url'] = Variable<String>(driveFolderUrl.value);
    }
    if (driveUploadConfirmedAt.present) {
      map['drive_upload_confirmed_at'] =
          Variable<DateTime>(driveUploadConfirmedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssignmentsCompanion(')
          ..write('id: $id, ')
          ..write('enumeratorId: $enumeratorId, ')
          ..write('campaignId: $campaignId, ')
          ..write('boundaryPolygonGeojson: $boundaryPolygonGeojson, ')
          ..write('downloadedAt: $downloadedAt, ')
          ..write('submittedAt: $submittedAt, ')
          ..write('status: $status, ')
          ..write('closedRemotely: $closedRemotely, ')
          ..write('createdAt: $createdAt, ')
          ..write('driveModifiedTime: $driveModifiedTime, ')
          ..write('driveFolderId: $driveFolderId, ')
          ..write('driveFolderPath: $driveFolderPath, ')
          ..write('driveFolderUrl: $driveFolderUrl, ')
          ..write('driveUploadConfirmedAt: $driveUploadConfirmedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FeaturesTable extends Features with TableInfo<$FeaturesTable, Feature> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeaturesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _assignmentIdMeta =
      const VerificationMeta('assignmentId');
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
      'assignment_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _featureTypeMeta =
      const VerificationMeta('featureType');
  @override
  late final GeneratedColumn<String> featureType = GeneratedColumn<String>(
      'feature_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _geometryGeojsonMeta =
      const VerificationMeta('geometryGeojson');
  @override
  late final GeneratedColumn<String> geometryGeojson = GeneratedColumn<String>(
      'geometry_geojson', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isNewMeta = const VerificationMeta('isNew');
  @override
  late final GeneratedColumn<bool> isNew = GeneratedColumn<bool>(
      'is_new', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_new" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('unfilled'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        assignmentId,
        featureType,
        geometryGeojson,
        isNew,
        status,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'features';
  @override
  VerificationContext validateIntegrity(Insertable<Feature> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assignment_id')) {
      context.handle(
          _assignmentIdMeta,
          assignmentId.isAcceptableOrUnknown(
              data['assignment_id']!, _assignmentIdMeta));
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('feature_type')) {
      context.handle(
          _featureTypeMeta,
          featureType.isAcceptableOrUnknown(
              data['feature_type']!, _featureTypeMeta));
    } else if (isInserting) {
      context.missing(_featureTypeMeta);
    }
    if (data.containsKey('geometry_geojson')) {
      context.handle(
          _geometryGeojsonMeta,
          geometryGeojson.isAcceptableOrUnknown(
              data['geometry_geojson']!, _geometryGeojsonMeta));
    } else if (isInserting) {
      context.missing(_geometryGeojsonMeta);
    }
    if (data.containsKey('is_new')) {
      context.handle(
          _isNewMeta, isNew.isAcceptableOrUnknown(data['is_new']!, _isNewMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Feature map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Feature(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      assignmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}assignment_id'])!,
      featureType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}feature_type'])!,
      geometryGeojson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}geometry_geojson'])!,
      isNew: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_new'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FeaturesTable createAlias(String alias) {
    return $FeaturesTable(attachedDatabase, alias);
  }
}

class Feature extends DataClass implements Insertable<Feature> {
  final String id;
  final String assignmentId;
  final String featureType;
  final String geometryGeojson;
  final bool isNew;
  final String status;
  final DateTime createdAt;
  const Feature(
      {required this.id,
      required this.assignmentId,
      required this.featureType,
      required this.geometryGeojson,
      required this.isNew,
      required this.status,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assignment_id'] = Variable<String>(assignmentId);
    map['feature_type'] = Variable<String>(featureType);
    map['geometry_geojson'] = Variable<String>(geometryGeojson);
    map['is_new'] = Variable<bool>(isNew);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FeaturesCompanion toCompanion(bool nullToAbsent) {
    return FeaturesCompanion(
      id: Value(id),
      assignmentId: Value(assignmentId),
      featureType: Value(featureType),
      geometryGeojson: Value(geometryGeojson),
      isNew: Value(isNew),
      status: Value(status),
      createdAt: Value(createdAt),
    );
  }

  factory Feature.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Feature(
      id: serializer.fromJson<String>(json['id']),
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      featureType: serializer.fromJson<String>(json['featureType']),
      geometryGeojson: serializer.fromJson<String>(json['geometryGeojson']),
      isNew: serializer.fromJson<bool>(json['isNew']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assignmentId': serializer.toJson<String>(assignmentId),
      'featureType': serializer.toJson<String>(featureType),
      'geometryGeojson': serializer.toJson<String>(geometryGeojson),
      'isNew': serializer.toJson<bool>(isNew),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Feature copyWith(
          {String? id,
          String? assignmentId,
          String? featureType,
          String? geometryGeojson,
          bool? isNew,
          String? status,
          DateTime? createdAt}) =>
      Feature(
        id: id ?? this.id,
        assignmentId: assignmentId ?? this.assignmentId,
        featureType: featureType ?? this.featureType,
        geometryGeojson: geometryGeojson ?? this.geometryGeojson,
        isNew: isNew ?? this.isNew,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
      );
  Feature copyWithCompanion(FeaturesCompanion data) {
    return Feature(
      id: data.id.present ? data.id.value : this.id,
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      featureType:
          data.featureType.present ? data.featureType.value : this.featureType,
      geometryGeojson: data.geometryGeojson.present
          ? data.geometryGeojson.value
          : this.geometryGeojson,
      isNew: data.isNew.present ? data.isNew.value : this.isNew,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Feature(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('featureType: $featureType, ')
          ..write('geometryGeojson: $geometryGeojson, ')
          ..write('isNew: $isNew, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, assignmentId, featureType, geometryGeojson, isNew, status, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Feature &&
          other.id == this.id &&
          other.assignmentId == this.assignmentId &&
          other.featureType == this.featureType &&
          other.geometryGeojson == this.geometryGeojson &&
          other.isNew == this.isNew &&
          other.status == this.status &&
          other.createdAt == this.createdAt);
}

class FeaturesCompanion extends UpdateCompanion<Feature> {
  final Value<String> id;
  final Value<String> assignmentId;
  final Value<String> featureType;
  final Value<String> geometryGeojson;
  final Value<bool> isNew;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FeaturesCompanion({
    this.id = const Value.absent(),
    this.assignmentId = const Value.absent(),
    this.featureType = const Value.absent(),
    this.geometryGeojson = const Value.absent(),
    this.isNew = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FeaturesCompanion.insert({
    required String id,
    required String assignmentId,
    required String featureType,
    required String geometryGeojson,
    this.isNew = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        assignmentId = Value(assignmentId),
        featureType = Value(featureType),
        geometryGeojson = Value(geometryGeojson),
        createdAt = Value(createdAt);
  static Insertable<Feature> custom({
    Expression<String>? id,
    Expression<String>? assignmentId,
    Expression<String>? featureType,
    Expression<String>? geometryGeojson,
    Expression<bool>? isNew,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (featureType != null) 'feature_type': featureType,
      if (geometryGeojson != null) 'geometry_geojson': geometryGeojson,
      if (isNew != null) 'is_new': isNew,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FeaturesCompanion copyWith(
      {Value<String>? id,
      Value<String>? assignmentId,
      Value<String>? featureType,
      Value<String>? geometryGeojson,
      Value<bool>? isNew,
      Value<String>? status,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return FeaturesCompanion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      featureType: featureType ?? this.featureType,
      geometryGeojson: geometryGeojson ?? this.geometryGeojson,
      isNew: isNew ?? this.isNew,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (featureType.present) {
      map['feature_type'] = Variable<String>(featureType.value);
    }
    if (geometryGeojson.present) {
      map['geometry_geojson'] = Variable<String>(geometryGeojson.value);
    }
    if (isNew.present) {
      map['is_new'] = Variable<bool>(isNew.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeaturesCompanion(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('featureType: $featureType, ')
          ..write('geometryGeojson: $geometryGeojson, ')
          ..write('isNew: $isNew, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FeatureGeometryRevisionsTable extends FeatureGeometryRevisions
    with TableInfo<$FeatureGeometryRevisionsTable, FeatureGeometryRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeatureGeometryRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _featureIdMeta =
      const VerificationMeta('featureId');
  @override
  late final GeneratedColumn<String> featureId = GeneratedColumn<String>(
      'feature_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _prevGeojsonMeta =
      const VerificationMeta('prevGeojson');
  @override
  late final GeneratedColumn<String> prevGeojson = GeneratedColumn<String>(
      'prev_geojson', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _newGeojsonMeta =
      const VerificationMeta('newGeojson');
  @override
  late final GeneratedColumn<String> newGeojson = GeneratedColumn<String>(
      'new_geojson', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _editedByMeta =
      const VerificationMeta('editedBy');
  @override
  late final GeneratedColumn<String> editedBy = GeneratedColumn<String>(
      'edited_by', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _editedAtMeta =
      const VerificationMeta('editedAt');
  @override
  late final GeneratedColumn<DateTime> editedAt = GeneratedColumn<DateTime>(
      'edited_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _overrideReasonMeta =
      const VerificationMeta('overrideReason');
  @override
  late final GeneratedColumn<String> overrideReason = GeneratedColumn<String>(
      'override_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        featureId,
        prevGeojson,
        newGeojson,
        editedBy,
        editedAt,
        overrideReason,
        syncStatus,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feature_geometry_revisions';
  @override
  VerificationContext validateIntegrity(
      Insertable<FeatureGeometryRevision> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('feature_id')) {
      context.handle(_featureIdMeta,
          featureId.isAcceptableOrUnknown(data['feature_id']!, _featureIdMeta));
    } else if (isInserting) {
      context.missing(_featureIdMeta);
    }
    if (data.containsKey('prev_geojson')) {
      context.handle(
          _prevGeojsonMeta,
          prevGeojson.isAcceptableOrUnknown(
              data['prev_geojson']!, _prevGeojsonMeta));
    } else if (isInserting) {
      context.missing(_prevGeojsonMeta);
    }
    if (data.containsKey('new_geojson')) {
      context.handle(
          _newGeojsonMeta,
          newGeojson.isAcceptableOrUnknown(
              data['new_geojson']!, _newGeojsonMeta));
    } else if (isInserting) {
      context.missing(_newGeojsonMeta);
    }
    if (data.containsKey('edited_by')) {
      context.handle(_editedByMeta,
          editedBy.isAcceptableOrUnknown(data['edited_by']!, _editedByMeta));
    } else if (isInserting) {
      context.missing(_editedByMeta);
    }
    if (data.containsKey('edited_at')) {
      context.handle(_editedAtMeta,
          editedAt.isAcceptableOrUnknown(data['edited_at']!, _editedAtMeta));
    } else if (isInserting) {
      context.missing(_editedAtMeta);
    }
    if (data.containsKey('override_reason')) {
      context.handle(
          _overrideReasonMeta,
          overrideReason.isAcceptableOrUnknown(
              data['override_reason']!, _overrideReasonMeta));
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FeatureGeometryRevision map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FeatureGeometryRevision(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      featureId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}feature_id'])!,
      prevGeojson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prev_geojson'])!,
      newGeojson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}new_geojson'])!,
      editedBy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}edited_by'])!,
      editedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}edited_at'])!,
      overrideReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}override_reason']),
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FeatureGeometryRevisionsTable createAlias(String alias) {
    return $FeatureGeometryRevisionsTable(attachedDatabase, alias);
  }
}

class FeatureGeometryRevision extends DataClass
    implements Insertable<FeatureGeometryRevision> {
  final String id;
  final String featureId;
  final String prevGeojson;
  final String newGeojson;
  final String editedBy;
  final DateTime editedAt;
  final String? overrideReason;
  final String syncStatus;
  final DateTime createdAt;
  const FeatureGeometryRevision(
      {required this.id,
      required this.featureId,
      required this.prevGeojson,
      required this.newGeojson,
      required this.editedBy,
      required this.editedAt,
      this.overrideReason,
      required this.syncStatus,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['feature_id'] = Variable<String>(featureId);
    map['prev_geojson'] = Variable<String>(prevGeojson);
    map['new_geojson'] = Variable<String>(newGeojson);
    map['edited_by'] = Variable<String>(editedBy);
    map['edited_at'] = Variable<DateTime>(editedAt);
    if (!nullToAbsent || overrideReason != null) {
      map['override_reason'] = Variable<String>(overrideReason);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FeatureGeometryRevisionsCompanion toCompanion(bool nullToAbsent) {
    return FeatureGeometryRevisionsCompanion(
      id: Value(id),
      featureId: Value(featureId),
      prevGeojson: Value(prevGeojson),
      newGeojson: Value(newGeojson),
      editedBy: Value(editedBy),
      editedAt: Value(editedAt),
      overrideReason: overrideReason == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideReason),
      syncStatus: Value(syncStatus),
      createdAt: Value(createdAt),
    );
  }

  factory FeatureGeometryRevision.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FeatureGeometryRevision(
      id: serializer.fromJson<String>(json['id']),
      featureId: serializer.fromJson<String>(json['featureId']),
      prevGeojson: serializer.fromJson<String>(json['prevGeojson']),
      newGeojson: serializer.fromJson<String>(json['newGeojson']),
      editedBy: serializer.fromJson<String>(json['editedBy']),
      editedAt: serializer.fromJson<DateTime>(json['editedAt']),
      overrideReason: serializer.fromJson<String?>(json['overrideReason']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'featureId': serializer.toJson<String>(featureId),
      'prevGeojson': serializer.toJson<String>(prevGeojson),
      'newGeojson': serializer.toJson<String>(newGeojson),
      'editedBy': serializer.toJson<String>(editedBy),
      'editedAt': serializer.toJson<DateTime>(editedAt),
      'overrideReason': serializer.toJson<String?>(overrideReason),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FeatureGeometryRevision copyWith(
          {String? id,
          String? featureId,
          String? prevGeojson,
          String? newGeojson,
          String? editedBy,
          DateTime? editedAt,
          Value<String?> overrideReason = const Value.absent(),
          String? syncStatus,
          DateTime? createdAt}) =>
      FeatureGeometryRevision(
        id: id ?? this.id,
        featureId: featureId ?? this.featureId,
        prevGeojson: prevGeojson ?? this.prevGeojson,
        newGeojson: newGeojson ?? this.newGeojson,
        editedBy: editedBy ?? this.editedBy,
        editedAt: editedAt ?? this.editedAt,
        overrideReason:
            overrideReason.present ? overrideReason.value : this.overrideReason,
        syncStatus: syncStatus ?? this.syncStatus,
        createdAt: createdAt ?? this.createdAt,
      );
  FeatureGeometryRevision copyWithCompanion(
      FeatureGeometryRevisionsCompanion data) {
    return FeatureGeometryRevision(
      id: data.id.present ? data.id.value : this.id,
      featureId: data.featureId.present ? data.featureId.value : this.featureId,
      prevGeojson:
          data.prevGeojson.present ? data.prevGeojson.value : this.prevGeojson,
      newGeojson:
          data.newGeojson.present ? data.newGeojson.value : this.newGeojson,
      editedBy: data.editedBy.present ? data.editedBy.value : this.editedBy,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
      overrideReason: data.overrideReason.present
          ? data.overrideReason.value
          : this.overrideReason,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FeatureGeometryRevision(')
          ..write('id: $id, ')
          ..write('featureId: $featureId, ')
          ..write('prevGeojson: $prevGeojson, ')
          ..write('newGeojson: $newGeojson, ')
          ..write('editedBy: $editedBy, ')
          ..write('editedAt: $editedAt, ')
          ..write('overrideReason: $overrideReason, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, featureId, prevGeojson, newGeojson,
      editedBy, editedAt, overrideReason, syncStatus, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeatureGeometryRevision &&
          other.id == this.id &&
          other.featureId == this.featureId &&
          other.prevGeojson == this.prevGeojson &&
          other.newGeojson == this.newGeojson &&
          other.editedBy == this.editedBy &&
          other.editedAt == this.editedAt &&
          other.overrideReason == this.overrideReason &&
          other.syncStatus == this.syncStatus &&
          other.createdAt == this.createdAt);
}

class FeatureGeometryRevisionsCompanion
    extends UpdateCompanion<FeatureGeometryRevision> {
  final Value<String> id;
  final Value<String> featureId;
  final Value<String> prevGeojson;
  final Value<String> newGeojson;
  final Value<String> editedBy;
  final Value<DateTime> editedAt;
  final Value<String?> overrideReason;
  final Value<String> syncStatus;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FeatureGeometryRevisionsCompanion({
    this.id = const Value.absent(),
    this.featureId = const Value.absent(),
    this.prevGeojson = const Value.absent(),
    this.newGeojson = const Value.absent(),
    this.editedBy = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.overrideReason = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FeatureGeometryRevisionsCompanion.insert({
    required String id,
    required String featureId,
    required String prevGeojson,
    required String newGeojson,
    required String editedBy,
    required DateTime editedAt,
    this.overrideReason = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        featureId = Value(featureId),
        prevGeojson = Value(prevGeojson),
        newGeojson = Value(newGeojson),
        editedBy = Value(editedBy),
        editedAt = Value(editedAt),
        createdAt = Value(createdAt);
  static Insertable<FeatureGeometryRevision> custom({
    Expression<String>? id,
    Expression<String>? featureId,
    Expression<String>? prevGeojson,
    Expression<String>? newGeojson,
    Expression<String>? editedBy,
    Expression<DateTime>? editedAt,
    Expression<String>? overrideReason,
    Expression<String>? syncStatus,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (featureId != null) 'feature_id': featureId,
      if (prevGeojson != null) 'prev_geojson': prevGeojson,
      if (newGeojson != null) 'new_geojson': newGeojson,
      if (editedBy != null) 'edited_by': editedBy,
      if (editedAt != null) 'edited_at': editedAt,
      if (overrideReason != null) 'override_reason': overrideReason,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FeatureGeometryRevisionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? featureId,
      Value<String>? prevGeojson,
      Value<String>? newGeojson,
      Value<String>? editedBy,
      Value<DateTime>? editedAt,
      Value<String?>? overrideReason,
      Value<String>? syncStatus,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return FeatureGeometryRevisionsCompanion(
      id: id ?? this.id,
      featureId: featureId ?? this.featureId,
      prevGeojson: prevGeojson ?? this.prevGeojson,
      newGeojson: newGeojson ?? this.newGeojson,
      editedBy: editedBy ?? this.editedBy,
      editedAt: editedAt ?? this.editedAt,
      overrideReason: overrideReason ?? this.overrideReason,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (featureId.present) {
      map['feature_id'] = Variable<String>(featureId.value);
    }
    if (prevGeojson.present) {
      map['prev_geojson'] = Variable<String>(prevGeojson.value);
    }
    if (newGeojson.present) {
      map['new_geojson'] = Variable<String>(newGeojson.value);
    }
    if (editedBy.present) {
      map['edited_by'] = Variable<String>(editedBy.value);
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<DateTime>(editedAt.value);
    }
    if (overrideReason.present) {
      map['override_reason'] = Variable<String>(overrideReason.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeatureGeometryRevisionsCompanion(')
          ..write('id: $id, ')
          ..write('featureId: $featureId, ')
          ..write('prevGeojson: $prevGeojson, ')
          ..write('newGeojson: $newGeojson, ')
          ..write('editedBy: $editedBy, ')
          ..write('editedAt: $editedAt, ')
          ..write('overrideReason: $overrideReason, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubmissionsTable extends Submissions
    with TableInfo<$SubmissionsTable, Submission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubmissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _featureIdMeta =
      const VerificationMeta('featureId');
  @override
  late final GeneratedColumn<String> featureId = GeneratedColumn<String>(
      'feature_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _submittedByMeta =
      const VerificationMeta('submittedBy');
  @override
  late final GeneratedColumn<String> submittedBy = GeneratedColumn<String>(
      'submitted_by', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _doesNotExistMeta =
      const VerificationMeta('doesNotExist');
  @override
  late final GeneratedColumn<bool> doesNotExist = GeneratedColumn<bool>(
      'does_not_exist', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("does_not_exist" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _remarksMeta =
      const VerificationMeta('remarks');
  @override
  late final GeneratedColumn<String> remarks = GeneratedColumn<String>(
      'remarks', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _syncStatusMeta =
      const VerificationMeta('syncStatus');
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
      'sync_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('draft'));
  static const VerificationMeta _overrideReasonMeta =
      const VerificationMeta('overrideReason');
  @override
  late final GeneratedColumn<String> overrideReason = GeneratedColumn<String>(
      'override_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        featureId,
        submittedBy,
        doesNotExist,
        remarks,
        syncStatus,
        overrideReason,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'submissions';
  @override
  VerificationContext validateIntegrity(Insertable<Submission> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('feature_id')) {
      context.handle(_featureIdMeta,
          featureId.isAcceptableOrUnknown(data['feature_id']!, _featureIdMeta));
    } else if (isInserting) {
      context.missing(_featureIdMeta);
    }
    if (data.containsKey('submitted_by')) {
      context.handle(
          _submittedByMeta,
          submittedBy.isAcceptableOrUnknown(
              data['submitted_by']!, _submittedByMeta));
    }
    if (data.containsKey('does_not_exist')) {
      context.handle(
          _doesNotExistMeta,
          doesNotExist.isAcceptableOrUnknown(
              data['does_not_exist']!, _doesNotExistMeta));
    }
    if (data.containsKey('remarks')) {
      context.handle(_remarksMeta,
          remarks.isAcceptableOrUnknown(data['remarks']!, _remarksMeta));
    }
    if (data.containsKey('sync_status')) {
      context.handle(
          _syncStatusMeta,
          syncStatus.isAcceptableOrUnknown(
              data['sync_status']!, _syncStatusMeta));
    }
    if (data.containsKey('override_reason')) {
      context.handle(
          _overrideReasonMeta,
          overrideReason.isAcceptableOrUnknown(
              data['override_reason']!, _overrideReasonMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Submission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Submission(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      featureId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}feature_id'])!,
      submittedBy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}submitted_by']),
      doesNotExist: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}does_not_exist'])!,
      remarks: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}remarks']),
      syncStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sync_status'])!,
      overrideReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}override_reason']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SubmissionsTable createAlias(String alias) {
    return $SubmissionsTable(attachedDatabase, alias);
  }
}

class Submission extends DataClass implements Insertable<Submission> {
  final String id;
  final String featureId;
  final String? submittedBy;
  final bool doesNotExist;
  final String? remarks;
  final String syncStatus;
  final String? overrideReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Submission(
      {required this.id,
      required this.featureId,
      this.submittedBy,
      required this.doesNotExist,
      this.remarks,
      required this.syncStatus,
      this.overrideReason,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['feature_id'] = Variable<String>(featureId);
    if (!nullToAbsent || submittedBy != null) {
      map['submitted_by'] = Variable<String>(submittedBy);
    }
    map['does_not_exist'] = Variable<bool>(doesNotExist);
    if (!nullToAbsent || remarks != null) {
      map['remarks'] = Variable<String>(remarks);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || overrideReason != null) {
      map['override_reason'] = Variable<String>(overrideReason);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SubmissionsCompanion toCompanion(bool nullToAbsent) {
    return SubmissionsCompanion(
      id: Value(id),
      featureId: Value(featureId),
      submittedBy: submittedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(submittedBy),
      doesNotExist: Value(doesNotExist),
      remarks: remarks == null && nullToAbsent
          ? const Value.absent()
          : Value(remarks),
      syncStatus: Value(syncStatus),
      overrideReason: overrideReason == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideReason),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Submission.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Submission(
      id: serializer.fromJson<String>(json['id']),
      featureId: serializer.fromJson<String>(json['featureId']),
      submittedBy: serializer.fromJson<String?>(json['submittedBy']),
      doesNotExist: serializer.fromJson<bool>(json['doesNotExist']),
      remarks: serializer.fromJson<String?>(json['remarks']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      overrideReason: serializer.fromJson<String?>(json['overrideReason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'featureId': serializer.toJson<String>(featureId),
      'submittedBy': serializer.toJson<String?>(submittedBy),
      'doesNotExist': serializer.toJson<bool>(doesNotExist),
      'remarks': serializer.toJson<String?>(remarks),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'overrideReason': serializer.toJson<String?>(overrideReason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Submission copyWith(
          {String? id,
          String? featureId,
          Value<String?> submittedBy = const Value.absent(),
          bool? doesNotExist,
          Value<String?> remarks = const Value.absent(),
          String? syncStatus,
          Value<String?> overrideReason = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Submission(
        id: id ?? this.id,
        featureId: featureId ?? this.featureId,
        submittedBy: submittedBy.present ? submittedBy.value : this.submittedBy,
        doesNotExist: doesNotExist ?? this.doesNotExist,
        remarks: remarks.present ? remarks.value : this.remarks,
        syncStatus: syncStatus ?? this.syncStatus,
        overrideReason:
            overrideReason.present ? overrideReason.value : this.overrideReason,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Submission copyWithCompanion(SubmissionsCompanion data) {
    return Submission(
      id: data.id.present ? data.id.value : this.id,
      featureId: data.featureId.present ? data.featureId.value : this.featureId,
      submittedBy:
          data.submittedBy.present ? data.submittedBy.value : this.submittedBy,
      doesNotExist: data.doesNotExist.present
          ? data.doesNotExist.value
          : this.doesNotExist,
      remarks: data.remarks.present ? data.remarks.value : this.remarks,
      syncStatus:
          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
      overrideReason: data.overrideReason.present
          ? data.overrideReason.value
          : this.overrideReason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Submission(')
          ..write('id: $id, ')
          ..write('featureId: $featureId, ')
          ..write('submittedBy: $submittedBy, ')
          ..write('doesNotExist: $doesNotExist, ')
          ..write('remarks: $remarks, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('overrideReason: $overrideReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, featureId, submittedBy, doesNotExist,
      remarks, syncStatus, overrideReason, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Submission &&
          other.id == this.id &&
          other.featureId == this.featureId &&
          other.submittedBy == this.submittedBy &&
          other.doesNotExist == this.doesNotExist &&
          other.remarks == this.remarks &&
          other.syncStatus == this.syncStatus &&
          other.overrideReason == this.overrideReason &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SubmissionsCompanion extends UpdateCompanion<Submission> {
  final Value<String> id;
  final Value<String> featureId;
  final Value<String?> submittedBy;
  final Value<bool> doesNotExist;
  final Value<String?> remarks;
  final Value<String> syncStatus;
  final Value<String?> overrideReason;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SubmissionsCompanion({
    this.id = const Value.absent(),
    this.featureId = const Value.absent(),
    this.submittedBy = const Value.absent(),
    this.doesNotExist = const Value.absent(),
    this.remarks = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.overrideReason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubmissionsCompanion.insert({
    required String id,
    required String featureId,
    this.submittedBy = const Value.absent(),
    this.doesNotExist = const Value.absent(),
    this.remarks = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.overrideReason = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        featureId = Value(featureId),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Submission> custom({
    Expression<String>? id,
    Expression<String>? featureId,
    Expression<String>? submittedBy,
    Expression<bool>? doesNotExist,
    Expression<String>? remarks,
    Expression<String>? syncStatus,
    Expression<String>? overrideReason,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (featureId != null) 'feature_id': featureId,
      if (submittedBy != null) 'submitted_by': submittedBy,
      if (doesNotExist != null) 'does_not_exist': doesNotExist,
      if (remarks != null) 'remarks': remarks,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (overrideReason != null) 'override_reason': overrideReason,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubmissionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? featureId,
      Value<String?>? submittedBy,
      Value<bool>? doesNotExist,
      Value<String?>? remarks,
      Value<String>? syncStatus,
      Value<String?>? overrideReason,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return SubmissionsCompanion(
      id: id ?? this.id,
      featureId: featureId ?? this.featureId,
      submittedBy: submittedBy ?? this.submittedBy,
      doesNotExist: doesNotExist ?? this.doesNotExist,
      remarks: remarks ?? this.remarks,
      syncStatus: syncStatus ?? this.syncStatus,
      overrideReason: overrideReason ?? this.overrideReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (featureId.present) {
      map['feature_id'] = Variable<String>(featureId.value);
    }
    if (submittedBy.present) {
      map['submitted_by'] = Variable<String>(submittedBy.value);
    }
    if (doesNotExist.present) {
      map['does_not_exist'] = Variable<bool>(doesNotExist.value);
    }
    if (remarks.present) {
      map['remarks'] = Variable<String>(remarks.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (overrideReason.present) {
      map['override_reason'] = Variable<String>(overrideReason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubmissionsCompanion(')
          ..write('id: $id, ')
          ..write('featureId: $featureId, ')
          ..write('submittedBy: $submittedBy, ')
          ..write('doesNotExist: $doesNotExist, ')
          ..write('remarks: $remarks, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('overrideReason: $overrideReason, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BuildingAttributesTable extends BuildingAttributes
    with TableInfo<$BuildingAttributesTable, BuildingAttribute> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BuildingAttributesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _submissionIdMeta =
      const VerificationMeta('submissionId');
  @override
  late final GeneratedColumn<String> submissionId = GeneratedColumn<String>(
      'submission_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cbmsIdMeta = const VerificationMeta('cbmsId');
  @override
  late final GeneratedColumn<String> cbmsId = GeneratedColumn<String>(
      'cbms_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _buildingNameMeta =
      const VerificationMeta('buildingName');
  @override
  late final GeneratedColumn<String> buildingName = GeneratedColumn<String>(
      'building_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ra9514TypeMeta =
      const VerificationMeta('ra9514Type');
  @override
  late final GeneratedColumn<String> ra9514Type = GeneratedColumn<String>(
      'ra_9514_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _storeysMeta =
      const VerificationMeta('storeys');
  @override
  late final GeneratedColumn<int> storeys = GeneratedColumn<int>(
      'storeys', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _materialMeta =
      const VerificationMeta('material');
  @override
  late final GeneratedColumn<String> material = GeneratedColumn<String>(
      'material', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _costIsExactMeta =
      const VerificationMeta('costIsExact');
  @override
  late final GeneratedColumn<bool> costIsExact = GeneratedColumn<bool>(
      'cost_is_exact', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("cost_is_exact" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _costAmountMeta =
      const VerificationMeta('costAmount');
  @override
  late final GeneratedColumn<double> costAmount = GeneratedColumn<double>(
      'cost_amount', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _costEstimateRangeMeta =
      const VerificationMeta('costEstimateRange');
  @override
  late final GeneratedColumn<String> costEstimateRange =
      GeneratedColumn<String>('cost_estimate_range', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fireFightingFacilitiesJsonMeta =
      const VerificationMeta('fireFightingFacilitiesJson');
  @override
  late final GeneratedColumn<String> fireFightingFacilitiesJson =
      GeneratedColumn<String>(
          'fire_fighting_facilities_json', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _fireLoadJsonMeta =
      const VerificationMeta('fireLoadJson');
  @override
  late final GeneratedColumn<String> fireLoadJson = GeneratedColumn<String>(
      'fire_load_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  @override
  List<GeneratedColumn> get $columns => [
        submissionId,
        cbmsId,
        buildingName,
        ra9514Type,
        storeys,
        material,
        costIsExact,
        costAmount,
        costEstimateRange,
        fireFightingFacilitiesJson,
        fireLoadJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'building_attributes';
  @override
  VerificationContext validateIntegrity(Insertable<BuildingAttribute> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('submission_id')) {
      context.handle(
          _submissionIdMeta,
          submissionId.isAcceptableOrUnknown(
              data['submission_id']!, _submissionIdMeta));
    } else if (isInserting) {
      context.missing(_submissionIdMeta);
    }
    if (data.containsKey('cbms_id')) {
      context.handle(_cbmsIdMeta,
          cbmsId.isAcceptableOrUnknown(data['cbms_id']!, _cbmsIdMeta));
    }
    if (data.containsKey('building_name')) {
      context.handle(
          _buildingNameMeta,
          buildingName.isAcceptableOrUnknown(
              data['building_name']!, _buildingNameMeta));
    }
    if (data.containsKey('ra_9514_type')) {
      context.handle(
          _ra9514TypeMeta,
          ra9514Type.isAcceptableOrUnknown(
              data['ra_9514_type']!, _ra9514TypeMeta));
    }
    if (data.containsKey('storeys')) {
      context.handle(_storeysMeta,
          storeys.isAcceptableOrUnknown(data['storeys']!, _storeysMeta));
    }
    if (data.containsKey('material')) {
      context.handle(_materialMeta,
          material.isAcceptableOrUnknown(data['material']!, _materialMeta));
    }
    if (data.containsKey('cost_is_exact')) {
      context.handle(
          _costIsExactMeta,
          costIsExact.isAcceptableOrUnknown(
              data['cost_is_exact']!, _costIsExactMeta));
    }
    if (data.containsKey('cost_amount')) {
      context.handle(
          _costAmountMeta,
          costAmount.isAcceptableOrUnknown(
              data['cost_amount']!, _costAmountMeta));
    }
    if (data.containsKey('cost_estimate_range')) {
      context.handle(
          _costEstimateRangeMeta,
          costEstimateRange.isAcceptableOrUnknown(
              data['cost_estimate_range']!, _costEstimateRangeMeta));
    }
    if (data.containsKey('fire_fighting_facilities_json')) {
      context.handle(
          _fireFightingFacilitiesJsonMeta,
          fireFightingFacilitiesJson.isAcceptableOrUnknown(
              data['fire_fighting_facilities_json']!,
              _fireFightingFacilitiesJsonMeta));
    }
    if (data.containsKey('fire_load_json')) {
      context.handle(
          _fireLoadJsonMeta,
          fireLoadJson.isAcceptableOrUnknown(
              data['fire_load_json']!, _fireLoadJsonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {submissionId};
  @override
  BuildingAttribute map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BuildingAttribute(
      submissionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}submission_id'])!,
      cbmsId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cbms_id']),
      buildingName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}building_name']),
      ra9514Type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}ra_9514_type']),
      storeys: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}storeys']),
      material: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}material']),
      costIsExact: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}cost_is_exact'])!,
      costAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}cost_amount']),
      costEstimateRange: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}cost_estimate_range']),
      fireFightingFacilitiesJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}fire_fighting_facilities_json'])!,
      fireLoadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}fire_load_json'])!,
    );
  }

  @override
  $BuildingAttributesTable createAlias(String alias) {
    return $BuildingAttributesTable(attachedDatabase, alias);
  }
}

class BuildingAttribute extends DataClass
    implements Insertable<BuildingAttribute> {
  final String submissionId;
  final String? cbmsId;
  final String? buildingName;
  final String? ra9514Type;
  final int? storeys;
  final String? material;
  final bool costIsExact;
  final double? costAmount;
  final String? costEstimateRange;
  final String fireFightingFacilitiesJson;
  final String fireLoadJson;
  const BuildingAttribute(
      {required this.submissionId,
      this.cbmsId,
      this.buildingName,
      this.ra9514Type,
      this.storeys,
      this.material,
      required this.costIsExact,
      this.costAmount,
      this.costEstimateRange,
      required this.fireFightingFacilitiesJson,
      required this.fireLoadJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['submission_id'] = Variable<String>(submissionId);
    if (!nullToAbsent || cbmsId != null) {
      map['cbms_id'] = Variable<String>(cbmsId);
    }
    if (!nullToAbsent || buildingName != null) {
      map['building_name'] = Variable<String>(buildingName);
    }
    if (!nullToAbsent || ra9514Type != null) {
      map['ra_9514_type'] = Variable<String>(ra9514Type);
    }
    if (!nullToAbsent || storeys != null) {
      map['storeys'] = Variable<int>(storeys);
    }
    if (!nullToAbsent || material != null) {
      map['material'] = Variable<String>(material);
    }
    map['cost_is_exact'] = Variable<bool>(costIsExact);
    if (!nullToAbsent || costAmount != null) {
      map['cost_amount'] = Variable<double>(costAmount);
    }
    if (!nullToAbsent || costEstimateRange != null) {
      map['cost_estimate_range'] = Variable<String>(costEstimateRange);
    }
    map['fire_fighting_facilities_json'] =
        Variable<String>(fireFightingFacilitiesJson);
    map['fire_load_json'] = Variable<String>(fireLoadJson);
    return map;
  }

  BuildingAttributesCompanion toCompanion(bool nullToAbsent) {
    return BuildingAttributesCompanion(
      submissionId: Value(submissionId),
      cbmsId:
          cbmsId == null && nullToAbsent ? const Value.absent() : Value(cbmsId),
      buildingName: buildingName == null && nullToAbsent
          ? const Value.absent()
          : Value(buildingName),
      ra9514Type: ra9514Type == null && nullToAbsent
          ? const Value.absent()
          : Value(ra9514Type),
      storeys: storeys == null && nullToAbsent
          ? const Value.absent()
          : Value(storeys),
      material: material == null && nullToAbsent
          ? const Value.absent()
          : Value(material),
      costIsExact: Value(costIsExact),
      costAmount: costAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(costAmount),
      costEstimateRange: costEstimateRange == null && nullToAbsent
          ? const Value.absent()
          : Value(costEstimateRange),
      fireFightingFacilitiesJson: Value(fireFightingFacilitiesJson),
      fireLoadJson: Value(fireLoadJson),
    );
  }

  factory BuildingAttribute.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BuildingAttribute(
      submissionId: serializer.fromJson<String>(json['submissionId']),
      cbmsId: serializer.fromJson<String?>(json['cbmsId']),
      buildingName: serializer.fromJson<String?>(json['buildingName']),
      ra9514Type: serializer.fromJson<String?>(json['ra9514Type']),
      storeys: serializer.fromJson<int?>(json['storeys']),
      material: serializer.fromJson<String?>(json['material']),
      costIsExact: serializer.fromJson<bool>(json['costIsExact']),
      costAmount: serializer.fromJson<double?>(json['costAmount']),
      costEstimateRange:
          serializer.fromJson<String?>(json['costEstimateRange']),
      fireFightingFacilitiesJson:
          serializer.fromJson<String>(json['fireFightingFacilitiesJson']),
      fireLoadJson: serializer.fromJson<String>(json['fireLoadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'submissionId': serializer.toJson<String>(submissionId),
      'cbmsId': serializer.toJson<String?>(cbmsId),
      'buildingName': serializer.toJson<String?>(buildingName),
      'ra9514Type': serializer.toJson<String?>(ra9514Type),
      'storeys': serializer.toJson<int?>(storeys),
      'material': serializer.toJson<String?>(material),
      'costIsExact': serializer.toJson<bool>(costIsExact),
      'costAmount': serializer.toJson<double?>(costAmount),
      'costEstimateRange': serializer.toJson<String?>(costEstimateRange),
      'fireFightingFacilitiesJson':
          serializer.toJson<String>(fireFightingFacilitiesJson),
      'fireLoadJson': serializer.toJson<String>(fireLoadJson),
    };
  }

  BuildingAttribute copyWith(
          {String? submissionId,
          Value<String?> cbmsId = const Value.absent(),
          Value<String?> buildingName = const Value.absent(),
          Value<String?> ra9514Type = const Value.absent(),
          Value<int?> storeys = const Value.absent(),
          Value<String?> material = const Value.absent(),
          bool? costIsExact,
          Value<double?> costAmount = const Value.absent(),
          Value<String?> costEstimateRange = const Value.absent(),
          String? fireFightingFacilitiesJson,
          String? fireLoadJson}) =>
      BuildingAttribute(
        submissionId: submissionId ?? this.submissionId,
        cbmsId: cbmsId.present ? cbmsId.value : this.cbmsId,
        buildingName:
            buildingName.present ? buildingName.value : this.buildingName,
        ra9514Type: ra9514Type.present ? ra9514Type.value : this.ra9514Type,
        storeys: storeys.present ? storeys.value : this.storeys,
        material: material.present ? material.value : this.material,
        costIsExact: costIsExact ?? this.costIsExact,
        costAmount: costAmount.present ? costAmount.value : this.costAmount,
        costEstimateRange: costEstimateRange.present
            ? costEstimateRange.value
            : this.costEstimateRange,
        fireFightingFacilitiesJson:
            fireFightingFacilitiesJson ?? this.fireFightingFacilitiesJson,
        fireLoadJson: fireLoadJson ?? this.fireLoadJson,
      );
  BuildingAttribute copyWithCompanion(BuildingAttributesCompanion data) {
    return BuildingAttribute(
      submissionId: data.submissionId.present
          ? data.submissionId.value
          : this.submissionId,
      cbmsId: data.cbmsId.present ? data.cbmsId.value : this.cbmsId,
      buildingName: data.buildingName.present
          ? data.buildingName.value
          : this.buildingName,
      ra9514Type:
          data.ra9514Type.present ? data.ra9514Type.value : this.ra9514Type,
      storeys: data.storeys.present ? data.storeys.value : this.storeys,
      material: data.material.present ? data.material.value : this.material,
      costIsExact:
          data.costIsExact.present ? data.costIsExact.value : this.costIsExact,
      costAmount:
          data.costAmount.present ? data.costAmount.value : this.costAmount,
      costEstimateRange: data.costEstimateRange.present
          ? data.costEstimateRange.value
          : this.costEstimateRange,
      fireFightingFacilitiesJson: data.fireFightingFacilitiesJson.present
          ? data.fireFightingFacilitiesJson.value
          : this.fireFightingFacilitiesJson,
      fireLoadJson: data.fireLoadJson.present
          ? data.fireLoadJson.value
          : this.fireLoadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BuildingAttribute(')
          ..write('submissionId: $submissionId, ')
          ..write('cbmsId: $cbmsId, ')
          ..write('buildingName: $buildingName, ')
          ..write('ra9514Type: $ra9514Type, ')
          ..write('storeys: $storeys, ')
          ..write('material: $material, ')
          ..write('costIsExact: $costIsExact, ')
          ..write('costAmount: $costAmount, ')
          ..write('costEstimateRange: $costEstimateRange, ')
          ..write('fireFightingFacilitiesJson: $fireFightingFacilitiesJson, ')
          ..write('fireLoadJson: $fireLoadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      submissionId,
      cbmsId,
      buildingName,
      ra9514Type,
      storeys,
      material,
      costIsExact,
      costAmount,
      costEstimateRange,
      fireFightingFacilitiesJson,
      fireLoadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BuildingAttribute &&
          other.submissionId == this.submissionId &&
          other.cbmsId == this.cbmsId &&
          other.buildingName == this.buildingName &&
          other.ra9514Type == this.ra9514Type &&
          other.storeys == this.storeys &&
          other.material == this.material &&
          other.costIsExact == this.costIsExact &&
          other.costAmount == this.costAmount &&
          other.costEstimateRange == this.costEstimateRange &&
          other.fireFightingFacilitiesJson == this.fireFightingFacilitiesJson &&
          other.fireLoadJson == this.fireLoadJson);
}

class BuildingAttributesCompanion extends UpdateCompanion<BuildingAttribute> {
  final Value<String> submissionId;
  final Value<String?> cbmsId;
  final Value<String?> buildingName;
  final Value<String?> ra9514Type;
  final Value<int?> storeys;
  final Value<String?> material;
  final Value<bool> costIsExact;
  final Value<double?> costAmount;
  final Value<String?> costEstimateRange;
  final Value<String> fireFightingFacilitiesJson;
  final Value<String> fireLoadJson;
  final Value<int> rowid;
  const BuildingAttributesCompanion({
    this.submissionId = const Value.absent(),
    this.cbmsId = const Value.absent(),
    this.buildingName = const Value.absent(),
    this.ra9514Type = const Value.absent(),
    this.storeys = const Value.absent(),
    this.material = const Value.absent(),
    this.costIsExact = const Value.absent(),
    this.costAmount = const Value.absent(),
    this.costEstimateRange = const Value.absent(),
    this.fireFightingFacilitiesJson = const Value.absent(),
    this.fireLoadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BuildingAttributesCompanion.insert({
    required String submissionId,
    this.cbmsId = const Value.absent(),
    this.buildingName = const Value.absent(),
    this.ra9514Type = const Value.absent(),
    this.storeys = const Value.absent(),
    this.material = const Value.absent(),
    this.costIsExact = const Value.absent(),
    this.costAmount = const Value.absent(),
    this.costEstimateRange = const Value.absent(),
    this.fireFightingFacilitiesJson = const Value.absent(),
    this.fireLoadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : submissionId = Value(submissionId);
  static Insertable<BuildingAttribute> custom({
    Expression<String>? submissionId,
    Expression<String>? cbmsId,
    Expression<String>? buildingName,
    Expression<String>? ra9514Type,
    Expression<int>? storeys,
    Expression<String>? material,
    Expression<bool>? costIsExact,
    Expression<double>? costAmount,
    Expression<String>? costEstimateRange,
    Expression<String>? fireFightingFacilitiesJson,
    Expression<String>? fireLoadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (submissionId != null) 'submission_id': submissionId,
      if (cbmsId != null) 'cbms_id': cbmsId,
      if (buildingName != null) 'building_name': buildingName,
      if (ra9514Type != null) 'ra_9514_type': ra9514Type,
      if (storeys != null) 'storeys': storeys,
      if (material != null) 'material': material,
      if (costIsExact != null) 'cost_is_exact': costIsExact,
      if (costAmount != null) 'cost_amount': costAmount,
      if (costEstimateRange != null) 'cost_estimate_range': costEstimateRange,
      if (fireFightingFacilitiesJson != null)
        'fire_fighting_facilities_json': fireFightingFacilitiesJson,
      if (fireLoadJson != null) 'fire_load_json': fireLoadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BuildingAttributesCompanion copyWith(
      {Value<String>? submissionId,
      Value<String?>? cbmsId,
      Value<String?>? buildingName,
      Value<String?>? ra9514Type,
      Value<int?>? storeys,
      Value<String?>? material,
      Value<bool>? costIsExact,
      Value<double?>? costAmount,
      Value<String?>? costEstimateRange,
      Value<String>? fireFightingFacilitiesJson,
      Value<String>? fireLoadJson,
      Value<int>? rowid}) {
    return BuildingAttributesCompanion(
      submissionId: submissionId ?? this.submissionId,
      cbmsId: cbmsId ?? this.cbmsId,
      buildingName: buildingName ?? this.buildingName,
      ra9514Type: ra9514Type ?? this.ra9514Type,
      storeys: storeys ?? this.storeys,
      material: material ?? this.material,
      costIsExact: costIsExact ?? this.costIsExact,
      costAmount: costAmount ?? this.costAmount,
      costEstimateRange: costEstimateRange ?? this.costEstimateRange,
      fireFightingFacilitiesJson:
          fireFightingFacilitiesJson ?? this.fireFightingFacilitiesJson,
      fireLoadJson: fireLoadJson ?? this.fireLoadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (submissionId.present) {
      map['submission_id'] = Variable<String>(submissionId.value);
    }
    if (cbmsId.present) {
      map['cbms_id'] = Variable<String>(cbmsId.value);
    }
    if (buildingName.present) {
      map['building_name'] = Variable<String>(buildingName.value);
    }
    if (ra9514Type.present) {
      map['ra_9514_type'] = Variable<String>(ra9514Type.value);
    }
    if (storeys.present) {
      map['storeys'] = Variable<int>(storeys.value);
    }
    if (material.present) {
      map['material'] = Variable<String>(material.value);
    }
    if (costIsExact.present) {
      map['cost_is_exact'] = Variable<bool>(costIsExact.value);
    }
    if (costAmount.present) {
      map['cost_amount'] = Variable<double>(costAmount.value);
    }
    if (costEstimateRange.present) {
      map['cost_estimate_range'] = Variable<String>(costEstimateRange.value);
    }
    if (fireFightingFacilitiesJson.present) {
      map['fire_fighting_facilities_json'] =
          Variable<String>(fireFightingFacilitiesJson.value);
    }
    if (fireLoadJson.present) {
      map['fire_load_json'] = Variable<String>(fireLoadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BuildingAttributesCompanion(')
          ..write('submissionId: $submissionId, ')
          ..write('cbmsId: $cbmsId, ')
          ..write('buildingName: $buildingName, ')
          ..write('ra9514Type: $ra9514Type, ')
          ..write('storeys: $storeys, ')
          ..write('material: $material, ')
          ..write('costIsExact: $costIsExact, ')
          ..write('costAmount: $costAmount, ')
          ..write('costEstimateRange: $costEstimateRange, ')
          ..write('fireFightingFacilitiesJson: $fireFightingFacilitiesJson, ')
          ..write('fireLoadJson: $fireLoadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoadAttributesTable extends RoadAttributes
    with TableInfo<$RoadAttributesTable, RoadAttribute> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoadAttributesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _submissionIdMeta =
      const VerificationMeta('submissionId');
  @override
  late final GeneratedColumn<String> submissionId = GeneratedColumn<String>(
      'submission_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isBridgeMeta =
      const VerificationMeta('isBridge');
  @override
  late final GeneratedColumn<bool> isBridge = GeneratedColumn<bool>(
      'is_bridge', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_bridge" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _roadNameMeta =
      const VerificationMeta('roadName');
  @override
  late final GeneratedColumn<String> roadName = GeneratedColumn<String>(
      'road_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _widthMetersMeta =
      const VerificationMeta('widthMeters');
  @override
  late final GeneratedColumn<double> widthMeters = GeneratedColumn<double>(
      'width_meters', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _roadFeaturesJsonMeta =
      const VerificationMeta('roadFeaturesJson');
  @override
  late final GeneratedColumn<String> roadFeaturesJson = GeneratedColumn<String>(
      'road_features_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('[]'));
  static const VerificationMeta _othersDescriptionMeta =
      const VerificationMeta('othersDescription');
  @override
  late final GeneratedColumn<String> othersDescription =
      GeneratedColumn<String>('others_description', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        submissionId,
        isBridge,
        roadName,
        widthMeters,
        roadFeaturesJson,
        othersDescription
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'road_attributes';
  @override
  VerificationContext validateIntegrity(Insertable<RoadAttribute> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('submission_id')) {
      context.handle(
          _submissionIdMeta,
          submissionId.isAcceptableOrUnknown(
              data['submission_id']!, _submissionIdMeta));
    } else if (isInserting) {
      context.missing(_submissionIdMeta);
    }
    if (data.containsKey('is_bridge')) {
      context.handle(_isBridgeMeta,
          isBridge.isAcceptableOrUnknown(data['is_bridge']!, _isBridgeMeta));
    }
    if (data.containsKey('road_name')) {
      context.handle(_roadNameMeta,
          roadName.isAcceptableOrUnknown(data['road_name']!, _roadNameMeta));
    }
    if (data.containsKey('width_meters')) {
      context.handle(
          _widthMetersMeta,
          widthMeters.isAcceptableOrUnknown(
              data['width_meters']!, _widthMetersMeta));
    }
    if (data.containsKey('road_features_json')) {
      context.handle(
          _roadFeaturesJsonMeta,
          roadFeaturesJson.isAcceptableOrUnknown(
              data['road_features_json']!, _roadFeaturesJsonMeta));
    }
    if (data.containsKey('others_description')) {
      context.handle(
          _othersDescriptionMeta,
          othersDescription.isAcceptableOrUnknown(
              data['others_description']!, _othersDescriptionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {submissionId};
  @override
  RoadAttribute map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoadAttribute(
      submissionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}submission_id'])!,
      isBridge: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_bridge'])!,
      roadName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}road_name']),
      widthMeters: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}width_meters']),
      roadFeaturesJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}road_features_json'])!,
      othersDescription: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}others_description']),
    );
  }

  @override
  $RoadAttributesTable createAlias(String alias) {
    return $RoadAttributesTable(attachedDatabase, alias);
  }
}

class RoadAttribute extends DataClass implements Insertable<RoadAttribute> {
  final String submissionId;
  final bool isBridge;
  final String? roadName;
  final double? widthMeters;
  final String roadFeaturesJson;
  final String? othersDescription;
  const RoadAttribute(
      {required this.submissionId,
      required this.isBridge,
      this.roadName,
      this.widthMeters,
      required this.roadFeaturesJson,
      this.othersDescription});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['submission_id'] = Variable<String>(submissionId);
    map['is_bridge'] = Variable<bool>(isBridge);
    if (!nullToAbsent || roadName != null) {
      map['road_name'] = Variable<String>(roadName);
    }
    if (!nullToAbsent || widthMeters != null) {
      map['width_meters'] = Variable<double>(widthMeters);
    }
    map['road_features_json'] = Variable<String>(roadFeaturesJson);
    if (!nullToAbsent || othersDescription != null) {
      map['others_description'] = Variable<String>(othersDescription);
    }
    return map;
  }

  RoadAttributesCompanion toCompanion(bool nullToAbsent) {
    return RoadAttributesCompanion(
      submissionId: Value(submissionId),
      isBridge: Value(isBridge),
      roadName: roadName == null && nullToAbsent
          ? const Value.absent()
          : Value(roadName),
      widthMeters: widthMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(widthMeters),
      roadFeaturesJson: Value(roadFeaturesJson),
      othersDescription: othersDescription == null && nullToAbsent
          ? const Value.absent()
          : Value(othersDescription),
    );
  }

  factory RoadAttribute.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoadAttribute(
      submissionId: serializer.fromJson<String>(json['submissionId']),
      isBridge: serializer.fromJson<bool>(json['isBridge']),
      roadName: serializer.fromJson<String?>(json['roadName']),
      widthMeters: serializer.fromJson<double?>(json['widthMeters']),
      roadFeaturesJson: serializer.fromJson<String>(json['roadFeaturesJson']),
      othersDescription:
          serializer.fromJson<String?>(json['othersDescription']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'submissionId': serializer.toJson<String>(submissionId),
      'isBridge': serializer.toJson<bool>(isBridge),
      'roadName': serializer.toJson<String?>(roadName),
      'widthMeters': serializer.toJson<double?>(widthMeters),
      'roadFeaturesJson': serializer.toJson<String>(roadFeaturesJson),
      'othersDescription': serializer.toJson<String?>(othersDescription),
    };
  }

  RoadAttribute copyWith(
          {String? submissionId,
          bool? isBridge,
          Value<String?> roadName = const Value.absent(),
          Value<double?> widthMeters = const Value.absent(),
          String? roadFeaturesJson,
          Value<String?> othersDescription = const Value.absent()}) =>
      RoadAttribute(
        submissionId: submissionId ?? this.submissionId,
        isBridge: isBridge ?? this.isBridge,
        roadName: roadName.present ? roadName.value : this.roadName,
        widthMeters: widthMeters.present ? widthMeters.value : this.widthMeters,
        roadFeaturesJson: roadFeaturesJson ?? this.roadFeaturesJson,
        othersDescription: othersDescription.present
            ? othersDescription.value
            : this.othersDescription,
      );
  RoadAttribute copyWithCompanion(RoadAttributesCompanion data) {
    return RoadAttribute(
      submissionId: data.submissionId.present
          ? data.submissionId.value
          : this.submissionId,
      isBridge: data.isBridge.present ? data.isBridge.value : this.isBridge,
      roadName: data.roadName.present ? data.roadName.value : this.roadName,
      widthMeters:
          data.widthMeters.present ? data.widthMeters.value : this.widthMeters,
      roadFeaturesJson: data.roadFeaturesJson.present
          ? data.roadFeaturesJson.value
          : this.roadFeaturesJson,
      othersDescription: data.othersDescription.present
          ? data.othersDescription.value
          : this.othersDescription,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoadAttribute(')
          ..write('submissionId: $submissionId, ')
          ..write('isBridge: $isBridge, ')
          ..write('roadName: $roadName, ')
          ..write('widthMeters: $widthMeters, ')
          ..write('roadFeaturesJson: $roadFeaturesJson, ')
          ..write('othersDescription: $othersDescription')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(submissionId, isBridge, roadName, widthMeters,
      roadFeaturesJson, othersDescription);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoadAttribute &&
          other.submissionId == this.submissionId &&
          other.isBridge == this.isBridge &&
          other.roadName == this.roadName &&
          other.widthMeters == this.widthMeters &&
          other.roadFeaturesJson == this.roadFeaturesJson &&
          other.othersDescription == this.othersDescription);
}

class RoadAttributesCompanion extends UpdateCompanion<RoadAttribute> {
  final Value<String> submissionId;
  final Value<bool> isBridge;
  final Value<String?> roadName;
  final Value<double?> widthMeters;
  final Value<String> roadFeaturesJson;
  final Value<String?> othersDescription;
  final Value<int> rowid;
  const RoadAttributesCompanion({
    this.submissionId = const Value.absent(),
    this.isBridge = const Value.absent(),
    this.roadName = const Value.absent(),
    this.widthMeters = const Value.absent(),
    this.roadFeaturesJson = const Value.absent(),
    this.othersDescription = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoadAttributesCompanion.insert({
    required String submissionId,
    this.isBridge = const Value.absent(),
    this.roadName = const Value.absent(),
    this.widthMeters = const Value.absent(),
    this.roadFeaturesJson = const Value.absent(),
    this.othersDescription = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : submissionId = Value(submissionId);
  static Insertable<RoadAttribute> custom({
    Expression<String>? submissionId,
    Expression<bool>? isBridge,
    Expression<String>? roadName,
    Expression<double>? widthMeters,
    Expression<String>? roadFeaturesJson,
    Expression<String>? othersDescription,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (submissionId != null) 'submission_id': submissionId,
      if (isBridge != null) 'is_bridge': isBridge,
      if (roadName != null) 'road_name': roadName,
      if (widthMeters != null) 'width_meters': widthMeters,
      if (roadFeaturesJson != null) 'road_features_json': roadFeaturesJson,
      if (othersDescription != null) 'others_description': othersDescription,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoadAttributesCompanion copyWith(
      {Value<String>? submissionId,
      Value<bool>? isBridge,
      Value<String?>? roadName,
      Value<double?>? widthMeters,
      Value<String>? roadFeaturesJson,
      Value<String?>? othersDescription,
      Value<int>? rowid}) {
    return RoadAttributesCompanion(
      submissionId: submissionId ?? this.submissionId,
      isBridge: isBridge ?? this.isBridge,
      roadName: roadName ?? this.roadName,
      widthMeters: widthMeters ?? this.widthMeters,
      roadFeaturesJson: roadFeaturesJson ?? this.roadFeaturesJson,
      othersDescription: othersDescription ?? this.othersDescription,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (submissionId.present) {
      map['submission_id'] = Variable<String>(submissionId.value);
    }
    if (isBridge.present) {
      map['is_bridge'] = Variable<bool>(isBridge.value);
    }
    if (roadName.present) {
      map['road_name'] = Variable<String>(roadName.value);
    }
    if (widthMeters.present) {
      map['width_meters'] = Variable<double>(widthMeters.value);
    }
    if (roadFeaturesJson.present) {
      map['road_features_json'] = Variable<String>(roadFeaturesJson.value);
    }
    if (othersDescription.present) {
      map['others_description'] = Variable<String>(othersDescription.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoadAttributesCompanion(')
          ..write('submissionId: $submissionId, ')
          ..write('isBridge: $isBridge, ')
          ..write('roadName: $roadName, ')
          ..write('widthMeters: $widthMeters, ')
          ..write('roadFeaturesJson: $roadFeaturesJson, ')
          ..write('othersDescription: $othersDescription, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HouseholdSurveysTable extends HouseholdSurveys
    with TableInfo<$HouseholdSurveysTable, HouseholdSurvey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HouseholdSurveysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _submissionIdMeta =
      const VerificationMeta('submissionId');
  @override
  late final GeneratedColumn<String> submissionId = GeneratedColumn<String>(
      'submission_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _constructionDetailsJsonMeta =
      const VerificationMeta('constructionDetailsJson');
  @override
  late final GeneratedColumn<String> constructionDetailsJson =
      GeneratedColumn<String>('construction_details_json', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('{}'));
  static const VerificationMeta _kaayusanJsonMeta =
      const VerificationMeta('kaayusanJson');
  @override
  late final GeneratedColumn<String> kaayusanJson = GeneratedColumn<String>(
      'kaayusan_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _koneksyongElektrikalJsonMeta =
      const VerificationMeta('koneksyongElektrikalJson');
  @override
  late final GeneratedColumn<String> koneksyongElektrikalJson =
      GeneratedColumn<String>('koneksyong_elektrikal_json', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('{}'));
  static const VerificationMeta _kusinaJsonMeta =
      const VerificationMeta('kusinaJson');
  @override
  late final GeneratedColumn<String> kusinaJson = GeneratedColumn<String>(
      'kusina_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _daananOLabasanJsonMeta =
      const VerificationMeta('daananOLabasanJson');
  @override
  late final GeneratedColumn<String> daananOLabasanJson =
      GeneratedColumn<String>('daanan_o_labasan_json', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('{}'));
  static const VerificationMeta _lebelNgKahinaanMeta =
      const VerificationMeta('lebelNgKahinaan');
  @override
  late final GeneratedColumn<String> lebelNgKahinaan = GeneratedColumn<String>(
      'lebel_ng_kahinaan', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _safetySuggestionsMeta =
      const VerificationMeta('safetySuggestions');
  @override
  late final GeneratedColumn<String> safetySuggestions =
      GeneratedColumn<String>('safety_suggestions', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _homeownerAcknowledgedMeta =
      const VerificationMeta('homeownerAcknowledged');
  @override
  late final GeneratedColumn<bool> homeownerAcknowledged =
      GeneratedColumn<bool>('homeowner_acknowledged', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("homeowner_acknowledged" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        submissionId,
        constructionDetailsJson,
        kaayusanJson,
        koneksyongElektrikalJson,
        kusinaJson,
        daananOLabasanJson,
        lebelNgKahinaan,
        safetySuggestions,
        homeownerAcknowledged,
        completedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'household_surveys';
  @override
  VerificationContext validateIntegrity(Insertable<HouseholdSurvey> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('submission_id')) {
      context.handle(
          _submissionIdMeta,
          submissionId.isAcceptableOrUnknown(
              data['submission_id']!, _submissionIdMeta));
    } else if (isInserting) {
      context.missing(_submissionIdMeta);
    }
    if (data.containsKey('construction_details_json')) {
      context.handle(
          _constructionDetailsJsonMeta,
          constructionDetailsJson.isAcceptableOrUnknown(
              data['construction_details_json']!,
              _constructionDetailsJsonMeta));
    }
    if (data.containsKey('kaayusan_json')) {
      context.handle(
          _kaayusanJsonMeta,
          kaayusanJson.isAcceptableOrUnknown(
              data['kaayusan_json']!, _kaayusanJsonMeta));
    }
    if (data.containsKey('koneksyong_elektrikal_json')) {
      context.handle(
          _koneksyongElektrikalJsonMeta,
          koneksyongElektrikalJson.isAcceptableOrUnknown(
              data['koneksyong_elektrikal_json']!,
              _koneksyongElektrikalJsonMeta));
    }
    if (data.containsKey('kusina_json')) {
      context.handle(
          _kusinaJsonMeta,
          kusinaJson.isAcceptableOrUnknown(
              data['kusina_json']!, _kusinaJsonMeta));
    }
    if (data.containsKey('daanan_o_labasan_json')) {
      context.handle(
          _daananOLabasanJsonMeta,
          daananOLabasanJson.isAcceptableOrUnknown(
              data['daanan_o_labasan_json']!, _daananOLabasanJsonMeta));
    }
    if (data.containsKey('lebel_ng_kahinaan')) {
      context.handle(
          _lebelNgKahinaanMeta,
          lebelNgKahinaan.isAcceptableOrUnknown(
              data['lebel_ng_kahinaan']!, _lebelNgKahinaanMeta));
    }
    if (data.containsKey('safety_suggestions')) {
      context.handle(
          _safetySuggestionsMeta,
          safetySuggestions.isAcceptableOrUnknown(
              data['safety_suggestions']!, _safetySuggestionsMeta));
    }
    if (data.containsKey('homeowner_acknowledged')) {
      context.handle(
          _homeownerAcknowledgedMeta,
          homeownerAcknowledged.isAcceptableOrUnknown(
              data['homeowner_acknowledged']!, _homeownerAcknowledgedMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {submissionId};
  @override
  HouseholdSurvey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HouseholdSurvey(
      submissionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}submission_id'])!,
      constructionDetailsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}construction_details_json'])!,
      kaayusanJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kaayusan_json'])!,
      koneksyongElektrikalJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}koneksyong_elektrikal_json'])!,
      kusinaJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}kusina_json'])!,
      daananOLabasanJson: attachedDatabase.typeMapping.read(DriftSqlType.string,
          data['${effectivePrefix}daanan_o_labasan_json'])!,
      lebelNgKahinaan: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}lebel_ng_kahinaan']),
      safetySuggestions: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}safety_suggestions']),
      homeownerAcknowledged: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}homeowner_acknowledged'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at']),
    );
  }

  @override
  $HouseholdSurveysTable createAlias(String alias) {
    return $HouseholdSurveysTable(attachedDatabase, alias);
  }
}

class HouseholdSurvey extends DataClass implements Insertable<HouseholdSurvey> {
  final String submissionId;
  final String constructionDetailsJson;
  final String kaayusanJson;
  final String koneksyongElektrikalJson;
  final String kusinaJson;
  final String daananOLabasanJson;
  final String? lebelNgKahinaan;
  final String? safetySuggestions;
  final bool homeownerAcknowledged;
  final DateTime? completedAt;
  const HouseholdSurvey(
      {required this.submissionId,
      required this.constructionDetailsJson,
      required this.kaayusanJson,
      required this.koneksyongElektrikalJson,
      required this.kusinaJson,
      required this.daananOLabasanJson,
      this.lebelNgKahinaan,
      this.safetySuggestions,
      required this.homeownerAcknowledged,
      this.completedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['submission_id'] = Variable<String>(submissionId);
    map['construction_details_json'] =
        Variable<String>(constructionDetailsJson);
    map['kaayusan_json'] = Variable<String>(kaayusanJson);
    map['koneksyong_elektrikal_json'] =
        Variable<String>(koneksyongElektrikalJson);
    map['kusina_json'] = Variable<String>(kusinaJson);
    map['daanan_o_labasan_json'] = Variable<String>(daananOLabasanJson);
    if (!nullToAbsent || lebelNgKahinaan != null) {
      map['lebel_ng_kahinaan'] = Variable<String>(lebelNgKahinaan);
    }
    if (!nullToAbsent || safetySuggestions != null) {
      map['safety_suggestions'] = Variable<String>(safetySuggestions);
    }
    map['homeowner_acknowledged'] = Variable<bool>(homeownerAcknowledged);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  HouseholdSurveysCompanion toCompanion(bool nullToAbsent) {
    return HouseholdSurveysCompanion(
      submissionId: Value(submissionId),
      constructionDetailsJson: Value(constructionDetailsJson),
      kaayusanJson: Value(kaayusanJson),
      koneksyongElektrikalJson: Value(koneksyongElektrikalJson),
      kusinaJson: Value(kusinaJson),
      daananOLabasanJson: Value(daananOLabasanJson),
      lebelNgKahinaan: lebelNgKahinaan == null && nullToAbsent
          ? const Value.absent()
          : Value(lebelNgKahinaan),
      safetySuggestions: safetySuggestions == null && nullToAbsent
          ? const Value.absent()
          : Value(safetySuggestions),
      homeownerAcknowledged: Value(homeownerAcknowledged),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory HouseholdSurvey.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HouseholdSurvey(
      submissionId: serializer.fromJson<String>(json['submissionId']),
      constructionDetailsJson:
          serializer.fromJson<String>(json['constructionDetailsJson']),
      kaayusanJson: serializer.fromJson<String>(json['kaayusanJson']),
      koneksyongElektrikalJson:
          serializer.fromJson<String>(json['koneksyongElektrikalJson']),
      kusinaJson: serializer.fromJson<String>(json['kusinaJson']),
      daananOLabasanJson:
          serializer.fromJson<String>(json['daananOLabasanJson']),
      lebelNgKahinaan: serializer.fromJson<String?>(json['lebelNgKahinaan']),
      safetySuggestions:
          serializer.fromJson<String?>(json['safetySuggestions']),
      homeownerAcknowledged:
          serializer.fromJson<bool>(json['homeownerAcknowledged']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'submissionId': serializer.toJson<String>(submissionId),
      'constructionDetailsJson':
          serializer.toJson<String>(constructionDetailsJson),
      'kaayusanJson': serializer.toJson<String>(kaayusanJson),
      'koneksyongElektrikalJson':
          serializer.toJson<String>(koneksyongElektrikalJson),
      'kusinaJson': serializer.toJson<String>(kusinaJson),
      'daananOLabasanJson': serializer.toJson<String>(daananOLabasanJson),
      'lebelNgKahinaan': serializer.toJson<String?>(lebelNgKahinaan),
      'safetySuggestions': serializer.toJson<String?>(safetySuggestions),
      'homeownerAcknowledged': serializer.toJson<bool>(homeownerAcknowledged),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  HouseholdSurvey copyWith(
          {String? submissionId,
          String? constructionDetailsJson,
          String? kaayusanJson,
          String? koneksyongElektrikalJson,
          String? kusinaJson,
          String? daananOLabasanJson,
          Value<String?> lebelNgKahinaan = const Value.absent(),
          Value<String?> safetySuggestions = const Value.absent(),
          bool? homeownerAcknowledged,
          Value<DateTime?> completedAt = const Value.absent()}) =>
      HouseholdSurvey(
        submissionId: submissionId ?? this.submissionId,
        constructionDetailsJson:
            constructionDetailsJson ?? this.constructionDetailsJson,
        kaayusanJson: kaayusanJson ?? this.kaayusanJson,
        koneksyongElektrikalJson:
            koneksyongElektrikalJson ?? this.koneksyongElektrikalJson,
        kusinaJson: kusinaJson ?? this.kusinaJson,
        daananOLabasanJson: daananOLabasanJson ?? this.daananOLabasanJson,
        lebelNgKahinaan: lebelNgKahinaan.present
            ? lebelNgKahinaan.value
            : this.lebelNgKahinaan,
        safetySuggestions: safetySuggestions.present
            ? safetySuggestions.value
            : this.safetySuggestions,
        homeownerAcknowledged:
            homeownerAcknowledged ?? this.homeownerAcknowledged,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
      );
  HouseholdSurvey copyWithCompanion(HouseholdSurveysCompanion data) {
    return HouseholdSurvey(
      submissionId: data.submissionId.present
          ? data.submissionId.value
          : this.submissionId,
      constructionDetailsJson: data.constructionDetailsJson.present
          ? data.constructionDetailsJson.value
          : this.constructionDetailsJson,
      kaayusanJson: data.kaayusanJson.present
          ? data.kaayusanJson.value
          : this.kaayusanJson,
      koneksyongElektrikalJson: data.koneksyongElektrikalJson.present
          ? data.koneksyongElektrikalJson.value
          : this.koneksyongElektrikalJson,
      kusinaJson:
          data.kusinaJson.present ? data.kusinaJson.value : this.kusinaJson,
      daananOLabasanJson: data.daananOLabasanJson.present
          ? data.daananOLabasanJson.value
          : this.daananOLabasanJson,
      lebelNgKahinaan: data.lebelNgKahinaan.present
          ? data.lebelNgKahinaan.value
          : this.lebelNgKahinaan,
      safetySuggestions: data.safetySuggestions.present
          ? data.safetySuggestions.value
          : this.safetySuggestions,
      homeownerAcknowledged: data.homeownerAcknowledged.present
          ? data.homeownerAcknowledged.value
          : this.homeownerAcknowledged,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HouseholdSurvey(')
          ..write('submissionId: $submissionId, ')
          ..write('constructionDetailsJson: $constructionDetailsJson, ')
          ..write('kaayusanJson: $kaayusanJson, ')
          ..write('koneksyongElektrikalJson: $koneksyongElektrikalJson, ')
          ..write('kusinaJson: $kusinaJson, ')
          ..write('daananOLabasanJson: $daananOLabasanJson, ')
          ..write('lebelNgKahinaan: $lebelNgKahinaan, ')
          ..write('safetySuggestions: $safetySuggestions, ')
          ..write('homeownerAcknowledged: $homeownerAcknowledged, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      submissionId,
      constructionDetailsJson,
      kaayusanJson,
      koneksyongElektrikalJson,
      kusinaJson,
      daananOLabasanJson,
      lebelNgKahinaan,
      safetySuggestions,
      homeownerAcknowledged,
      completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HouseholdSurvey &&
          other.submissionId == this.submissionId &&
          other.constructionDetailsJson == this.constructionDetailsJson &&
          other.kaayusanJson == this.kaayusanJson &&
          other.koneksyongElektrikalJson == this.koneksyongElektrikalJson &&
          other.kusinaJson == this.kusinaJson &&
          other.daananOLabasanJson == this.daananOLabasanJson &&
          other.lebelNgKahinaan == this.lebelNgKahinaan &&
          other.safetySuggestions == this.safetySuggestions &&
          other.homeownerAcknowledged == this.homeownerAcknowledged &&
          other.completedAt == this.completedAt);
}

class HouseholdSurveysCompanion extends UpdateCompanion<HouseholdSurvey> {
  final Value<String> submissionId;
  final Value<String> constructionDetailsJson;
  final Value<String> kaayusanJson;
  final Value<String> koneksyongElektrikalJson;
  final Value<String> kusinaJson;
  final Value<String> daananOLabasanJson;
  final Value<String?> lebelNgKahinaan;
  final Value<String?> safetySuggestions;
  final Value<bool> homeownerAcknowledged;
  final Value<DateTime?> completedAt;
  final Value<int> rowid;
  const HouseholdSurveysCompanion({
    this.submissionId = const Value.absent(),
    this.constructionDetailsJson = const Value.absent(),
    this.kaayusanJson = const Value.absent(),
    this.koneksyongElektrikalJson = const Value.absent(),
    this.kusinaJson = const Value.absent(),
    this.daananOLabasanJson = const Value.absent(),
    this.lebelNgKahinaan = const Value.absent(),
    this.safetySuggestions = const Value.absent(),
    this.homeownerAcknowledged = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HouseholdSurveysCompanion.insert({
    required String submissionId,
    this.constructionDetailsJson = const Value.absent(),
    this.kaayusanJson = const Value.absent(),
    this.koneksyongElektrikalJson = const Value.absent(),
    this.kusinaJson = const Value.absent(),
    this.daananOLabasanJson = const Value.absent(),
    this.lebelNgKahinaan = const Value.absent(),
    this.safetySuggestions = const Value.absent(),
    this.homeownerAcknowledged = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : submissionId = Value(submissionId);
  static Insertable<HouseholdSurvey> custom({
    Expression<String>? submissionId,
    Expression<String>? constructionDetailsJson,
    Expression<String>? kaayusanJson,
    Expression<String>? koneksyongElektrikalJson,
    Expression<String>? kusinaJson,
    Expression<String>? daananOLabasanJson,
    Expression<String>? lebelNgKahinaan,
    Expression<String>? safetySuggestions,
    Expression<bool>? homeownerAcknowledged,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (submissionId != null) 'submission_id': submissionId,
      if (constructionDetailsJson != null)
        'construction_details_json': constructionDetailsJson,
      if (kaayusanJson != null) 'kaayusan_json': kaayusanJson,
      if (koneksyongElektrikalJson != null)
        'koneksyong_elektrikal_json': koneksyongElektrikalJson,
      if (kusinaJson != null) 'kusina_json': kusinaJson,
      if (daananOLabasanJson != null)
        'daanan_o_labasan_json': daananOLabasanJson,
      if (lebelNgKahinaan != null) 'lebel_ng_kahinaan': lebelNgKahinaan,
      if (safetySuggestions != null) 'safety_suggestions': safetySuggestions,
      if (homeownerAcknowledged != null)
        'homeowner_acknowledged': homeownerAcknowledged,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HouseholdSurveysCompanion copyWith(
      {Value<String>? submissionId,
      Value<String>? constructionDetailsJson,
      Value<String>? kaayusanJson,
      Value<String>? koneksyongElektrikalJson,
      Value<String>? kusinaJson,
      Value<String>? daananOLabasanJson,
      Value<String?>? lebelNgKahinaan,
      Value<String?>? safetySuggestions,
      Value<bool>? homeownerAcknowledged,
      Value<DateTime?>? completedAt,
      Value<int>? rowid}) {
    return HouseholdSurveysCompanion(
      submissionId: submissionId ?? this.submissionId,
      constructionDetailsJson:
          constructionDetailsJson ?? this.constructionDetailsJson,
      kaayusanJson: kaayusanJson ?? this.kaayusanJson,
      koneksyongElektrikalJson:
          koneksyongElektrikalJson ?? this.koneksyongElektrikalJson,
      kusinaJson: kusinaJson ?? this.kusinaJson,
      daananOLabasanJson: daananOLabasanJson ?? this.daananOLabasanJson,
      lebelNgKahinaan: lebelNgKahinaan ?? this.lebelNgKahinaan,
      safetySuggestions: safetySuggestions ?? this.safetySuggestions,
      homeownerAcknowledged:
          homeownerAcknowledged ?? this.homeownerAcknowledged,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (submissionId.present) {
      map['submission_id'] = Variable<String>(submissionId.value);
    }
    if (constructionDetailsJson.present) {
      map['construction_details_json'] =
          Variable<String>(constructionDetailsJson.value);
    }
    if (kaayusanJson.present) {
      map['kaayusan_json'] = Variable<String>(kaayusanJson.value);
    }
    if (koneksyongElektrikalJson.present) {
      map['koneksyong_elektrikal_json'] =
          Variable<String>(koneksyongElektrikalJson.value);
    }
    if (kusinaJson.present) {
      map['kusina_json'] = Variable<String>(kusinaJson.value);
    }
    if (daananOLabasanJson.present) {
      map['daanan_o_labasan_json'] = Variable<String>(daananOLabasanJson.value);
    }
    if (lebelNgKahinaan.present) {
      map['lebel_ng_kahinaan'] = Variable<String>(lebelNgKahinaan.value);
    }
    if (safetySuggestions.present) {
      map['safety_suggestions'] = Variable<String>(safetySuggestions.value);
    }
    if (homeownerAcknowledged.present) {
      map['homeowner_acknowledged'] =
          Variable<bool>(homeownerAcknowledged.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HouseholdSurveysCompanion(')
          ..write('submissionId: $submissionId, ')
          ..write('constructionDetailsJson: $constructionDetailsJson, ')
          ..write('kaayusanJson: $kaayusanJson, ')
          ..write('koneksyongElektrikalJson: $koneksyongElektrikalJson, ')
          ..write('kusinaJson: $kusinaJson, ')
          ..write('daananOLabasanJson: $daananOLabasanJson, ')
          ..write('lebelNgKahinaan: $lebelNgKahinaan, ')
          ..write('safetySuggestions: $safetySuggestions, ')
          ..write('homeownerAcknowledged: $homeownerAcknowledged, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhotosTable extends Photos with TableInfo<$PhotosTable, Photo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _submissionIdMeta =
      const VerificationMeta('submissionId');
  @override
  late final GeneratedColumn<String> submissionId = GeneratedColumn<String>(
      'submission_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _storagePathMeta =
      const VerificationMeta('storagePath');
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
      'storage_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _capturedAtMeta =
      const VerificationMeta('capturedAt');
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
      'captured_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _gpsLatMeta = const VerificationMeta('gpsLat');
  @override
  late final GeneratedColumn<double> gpsLat = GeneratedColumn<double>(
      'gps_lat', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _gpsLngMeta = const VerificationMeta('gpsLng');
  @override
  late final GeneratedColumn<double> gpsLng = GeneratedColumn<double>(
      'gps_lng', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _uploadStatusMeta =
      const VerificationMeta('uploadStatus');
  @override
  late final GeneratedColumn<String> uploadStatus = GeneratedColumn<String>(
      'upload_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        submissionId,
        localPath,
        storagePath,
        capturedAt,
        gpsLat,
        gpsLng,
        uploadStatus,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'photos';
  @override
  VerificationContext validateIntegrity(Insertable<Photo> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('submission_id')) {
      context.handle(
          _submissionIdMeta,
          submissionId.isAcceptableOrUnknown(
              data['submission_id']!, _submissionIdMeta));
    } else if (isInserting) {
      context.missing(_submissionIdMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('storage_path')) {
      context.handle(
          _storagePathMeta,
          storagePath.isAcceptableOrUnknown(
              data['storage_path']!, _storagePathMeta));
    }
    if (data.containsKey('captured_at')) {
      context.handle(
          _capturedAtMeta,
          capturedAt.isAcceptableOrUnknown(
              data['captured_at']!, _capturedAtMeta));
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('gps_lat')) {
      context.handle(_gpsLatMeta,
          gpsLat.isAcceptableOrUnknown(data['gps_lat']!, _gpsLatMeta));
    }
    if (data.containsKey('gps_lng')) {
      context.handle(_gpsLngMeta,
          gpsLng.isAcceptableOrUnknown(data['gps_lng']!, _gpsLngMeta));
    }
    if (data.containsKey('upload_status')) {
      context.handle(
          _uploadStatusMeta,
          uploadStatus.isAcceptableOrUnknown(
              data['upload_status']!, _uploadStatusMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Photo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Photo(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      submissionId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}submission_id'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path'])!,
      storagePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}storage_path']),
      capturedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}captured_at'])!,
      gpsLat: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}gps_lat']),
      gpsLng: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}gps_lng']),
      uploadStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}upload_status'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $PhotosTable createAlias(String alias) {
    return $PhotosTable(attachedDatabase, alias);
  }
}

class Photo extends DataClass implements Insertable<Photo> {
  final String id;
  final String submissionId;
  final String localPath;
  final String? storagePath;
  final DateTime capturedAt;
  final double? gpsLat;
  final double? gpsLng;
  final String uploadStatus;
  final DateTime createdAt;
  const Photo(
      {required this.id,
      required this.submissionId,
      required this.localPath,
      this.storagePath,
      required this.capturedAt,
      this.gpsLat,
      this.gpsLng,
      required this.uploadStatus,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['submission_id'] = Variable<String>(submissionId);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || storagePath != null) {
      map['storage_path'] = Variable<String>(storagePath);
    }
    map['captured_at'] = Variable<DateTime>(capturedAt);
    if (!nullToAbsent || gpsLat != null) {
      map['gps_lat'] = Variable<double>(gpsLat);
    }
    if (!nullToAbsent || gpsLng != null) {
      map['gps_lng'] = Variable<double>(gpsLng);
    }
    map['upload_status'] = Variable<String>(uploadStatus);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PhotosCompanion toCompanion(bool nullToAbsent) {
    return PhotosCompanion(
      id: Value(id),
      submissionId: Value(submissionId),
      localPath: Value(localPath),
      storagePath: storagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(storagePath),
      capturedAt: Value(capturedAt),
      gpsLat:
          gpsLat == null && nullToAbsent ? const Value.absent() : Value(gpsLat),
      gpsLng:
          gpsLng == null && nullToAbsent ? const Value.absent() : Value(gpsLng),
      uploadStatus: Value(uploadStatus),
      createdAt: Value(createdAt),
    );
  }

  factory Photo.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Photo(
      id: serializer.fromJson<String>(json['id']),
      submissionId: serializer.fromJson<String>(json['submissionId']),
      localPath: serializer.fromJson<String>(json['localPath']),
      storagePath: serializer.fromJson<String?>(json['storagePath']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      gpsLat: serializer.fromJson<double?>(json['gpsLat']),
      gpsLng: serializer.fromJson<double?>(json['gpsLng']),
      uploadStatus: serializer.fromJson<String>(json['uploadStatus']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'submissionId': serializer.toJson<String>(submissionId),
      'localPath': serializer.toJson<String>(localPath),
      'storagePath': serializer.toJson<String?>(storagePath),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'gpsLat': serializer.toJson<double?>(gpsLat),
      'gpsLng': serializer.toJson<double?>(gpsLng),
      'uploadStatus': serializer.toJson<String>(uploadStatus),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Photo copyWith(
          {String? id,
          String? submissionId,
          String? localPath,
          Value<String?> storagePath = const Value.absent(),
          DateTime? capturedAt,
          Value<double?> gpsLat = const Value.absent(),
          Value<double?> gpsLng = const Value.absent(),
          String? uploadStatus,
          DateTime? createdAt}) =>
      Photo(
        id: id ?? this.id,
        submissionId: submissionId ?? this.submissionId,
        localPath: localPath ?? this.localPath,
        storagePath: storagePath.present ? storagePath.value : this.storagePath,
        capturedAt: capturedAt ?? this.capturedAt,
        gpsLat: gpsLat.present ? gpsLat.value : this.gpsLat,
        gpsLng: gpsLng.present ? gpsLng.value : this.gpsLng,
        uploadStatus: uploadStatus ?? this.uploadStatus,
        createdAt: createdAt ?? this.createdAt,
      );
  Photo copyWithCompanion(PhotosCompanion data) {
    return Photo(
      id: data.id.present ? data.id.value : this.id,
      submissionId: data.submissionId.present
          ? data.submissionId.value
          : this.submissionId,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      storagePath:
          data.storagePath.present ? data.storagePath.value : this.storagePath,
      capturedAt:
          data.capturedAt.present ? data.capturedAt.value : this.capturedAt,
      gpsLat: data.gpsLat.present ? data.gpsLat.value : this.gpsLat,
      gpsLng: data.gpsLng.present ? data.gpsLng.value : this.gpsLng,
      uploadStatus: data.uploadStatus.present
          ? data.uploadStatus.value
          : this.uploadStatus,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Photo(')
          ..write('id: $id, ')
          ..write('submissionId: $submissionId, ')
          ..write('localPath: $localPath, ')
          ..write('storagePath: $storagePath, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('gpsLat: $gpsLat, ')
          ..write('gpsLng: $gpsLng, ')
          ..write('uploadStatus: $uploadStatus, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, submissionId, localPath, storagePath,
      capturedAt, gpsLat, gpsLng, uploadStatus, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Photo &&
          other.id == this.id &&
          other.submissionId == this.submissionId &&
          other.localPath == this.localPath &&
          other.storagePath == this.storagePath &&
          other.capturedAt == this.capturedAt &&
          other.gpsLat == this.gpsLat &&
          other.gpsLng == this.gpsLng &&
          other.uploadStatus == this.uploadStatus &&
          other.createdAt == this.createdAt);
}

class PhotosCompanion extends UpdateCompanion<Photo> {
  final Value<String> id;
  final Value<String> submissionId;
  final Value<String> localPath;
  final Value<String?> storagePath;
  final Value<DateTime> capturedAt;
  final Value<double?> gpsLat;
  final Value<double?> gpsLng;
  final Value<String> uploadStatus;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PhotosCompanion({
    this.id = const Value.absent(),
    this.submissionId = const Value.absent(),
    this.localPath = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.gpsLat = const Value.absent(),
    this.gpsLng = const Value.absent(),
    this.uploadStatus = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhotosCompanion.insert({
    required String id,
    required String submissionId,
    required String localPath,
    this.storagePath = const Value.absent(),
    required DateTime capturedAt,
    this.gpsLat = const Value.absent(),
    this.gpsLng = const Value.absent(),
    this.uploadStatus = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        submissionId = Value(submissionId),
        localPath = Value(localPath),
        capturedAt = Value(capturedAt),
        createdAt = Value(createdAt);
  static Insertable<Photo> custom({
    Expression<String>? id,
    Expression<String>? submissionId,
    Expression<String>? localPath,
    Expression<String>? storagePath,
    Expression<DateTime>? capturedAt,
    Expression<double>? gpsLat,
    Expression<double>? gpsLng,
    Expression<String>? uploadStatus,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (submissionId != null) 'submission_id': submissionId,
      if (localPath != null) 'local_path': localPath,
      if (storagePath != null) 'storage_path': storagePath,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (gpsLat != null) 'gps_lat': gpsLat,
      if (gpsLng != null) 'gps_lng': gpsLng,
      if (uploadStatus != null) 'upload_status': uploadStatus,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhotosCompanion copyWith(
      {Value<String>? id,
      Value<String>? submissionId,
      Value<String>? localPath,
      Value<String?>? storagePath,
      Value<DateTime>? capturedAt,
      Value<double?>? gpsLat,
      Value<double?>? gpsLng,
      Value<String>? uploadStatus,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return PhotosCompanion(
      id: id ?? this.id,
      submissionId: submissionId ?? this.submissionId,
      localPath: localPath ?? this.localPath,
      storagePath: storagePath ?? this.storagePath,
      capturedAt: capturedAt ?? this.capturedAt,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (submissionId.present) {
      map['submission_id'] = Variable<String>(submissionId.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (gpsLat.present) {
      map['gps_lat'] = Variable<double>(gpsLat.value);
    }
    if (gpsLng.present) {
      map['gps_lng'] = Variable<double>(gpsLng.value);
    }
    if (uploadStatus.present) {
      map['upload_status'] = Variable<String>(uploadStatus.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhotosCompanion(')
          ..write('id: $id, ')
          ..write('submissionId: $submissionId, ')
          ..write('localPath: $localPath, ')
          ..write('storagePath: $storagePath, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('gpsLat: $gpsLat, ')
          ..write('gpsLng: $gpsLng, ')
          ..write('uploadStatus: $uploadStatus, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Ra9514TypesTable extends Ra9514Types
    with TableInfo<$Ra9514TypesTable, Ra9514Type> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Ra9514TypesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
      'code', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _labelEnMeta =
      const VerificationMeta('labelEn');
  @override
  late final GeneratedColumn<String> labelEn = GeneratedColumn<String>(
      'label_en', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _labelTlMeta =
      const VerificationMeta('labelTl');
  @override
  late final GeneratedColumn<String> labelTl = GeneratedColumn<String>(
      'label_tl', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [code, labelEn, labelTl, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ra_9514_types';
  @override
  VerificationContext validateIntegrity(Insertable<Ra9514Type> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
          _codeMeta, code.isAcceptableOrUnknown(data['code']!, _codeMeta));
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('label_en')) {
      context.handle(_labelEnMeta,
          labelEn.isAcceptableOrUnknown(data['label_en']!, _labelEnMeta));
    } else if (isInserting) {
      context.missing(_labelEnMeta);
    }
    if (data.containsKey('label_tl')) {
      context.handle(_labelTlMeta,
          labelTl.isAcceptableOrUnknown(data['label_tl']!, _labelTlMeta));
    } else if (isInserting) {
      context.missing(_labelTlMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  Ra9514Type map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ra9514Type(
      code: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}code'])!,
      labelEn: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label_en'])!,
      labelTl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label_tl'])!,
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $Ra9514TypesTable createAlias(String alias) {
    return $Ra9514TypesTable(attachedDatabase, alias);
  }
}

class Ra9514Type extends DataClass implements Insertable<Ra9514Type> {
  final String code;
  final String labelEn;
  final String labelTl;
  final int sortOrder;
  const Ra9514Type(
      {required this.code,
      required this.labelEn,
      required this.labelTl,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['label_en'] = Variable<String>(labelEn);
    map['label_tl'] = Variable<String>(labelTl);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  Ra9514TypesCompanion toCompanion(bool nullToAbsent) {
    return Ra9514TypesCompanion(
      code: Value(code),
      labelEn: Value(labelEn),
      labelTl: Value(labelTl),
      sortOrder: Value(sortOrder),
    );
  }

  factory Ra9514Type.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ra9514Type(
      code: serializer.fromJson<String>(json['code']),
      labelEn: serializer.fromJson<String>(json['labelEn']),
      labelTl: serializer.fromJson<String>(json['labelTl']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'labelEn': serializer.toJson<String>(labelEn),
      'labelTl': serializer.toJson<String>(labelTl),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Ra9514Type copyWith(
          {String? code, String? labelEn, String? labelTl, int? sortOrder}) =>
      Ra9514Type(
        code: code ?? this.code,
        labelEn: labelEn ?? this.labelEn,
        labelTl: labelTl ?? this.labelTl,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  Ra9514Type copyWithCompanion(Ra9514TypesCompanion data) {
    return Ra9514Type(
      code: data.code.present ? data.code.value : this.code,
      labelEn: data.labelEn.present ? data.labelEn.value : this.labelEn,
      labelTl: data.labelTl.present ? data.labelTl.value : this.labelTl,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ra9514Type(')
          ..write('code: $code, ')
          ..write('labelEn: $labelEn, ')
          ..write('labelTl: $labelTl, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, labelEn, labelTl, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ra9514Type &&
          other.code == this.code &&
          other.labelEn == this.labelEn &&
          other.labelTl == this.labelTl &&
          other.sortOrder == this.sortOrder);
}

class Ra9514TypesCompanion extends UpdateCompanion<Ra9514Type> {
  final Value<String> code;
  final Value<String> labelEn;
  final Value<String> labelTl;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const Ra9514TypesCompanion({
    this.code = const Value.absent(),
    this.labelEn = const Value.absent(),
    this.labelTl = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Ra9514TypesCompanion.insert({
    required String code,
    required String labelEn,
    required String labelTl,
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : code = Value(code),
        labelEn = Value(labelEn),
        labelTl = Value(labelTl);
  static Insertable<Ra9514Type> custom({
    Expression<String>? code,
    Expression<String>? labelEn,
    Expression<String>? labelTl,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (labelEn != null) 'label_en': labelEn,
      if (labelTl != null) 'label_tl': labelTl,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Ra9514TypesCompanion copyWith(
      {Value<String>? code,
      Value<String>? labelEn,
      Value<String>? labelTl,
      Value<int>? sortOrder,
      Value<int>? rowid}) {
    return Ra9514TypesCompanion(
      code: code ?? this.code,
      labelEn: labelEn ?? this.labelEn,
      labelTl: labelTl ?? this.labelTl,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (labelEn.present) {
      map['label_en'] = Variable<String>(labelEn.value);
    }
    if (labelTl.present) {
      map['label_tl'] = Variable<String>(labelTl.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('Ra9514TypesCompanion(')
          ..write('code: $code, ')
          ..write('labelEn: $labelEn, ')
          ..write('labelTl: $labelTl, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncJobsTable extends SyncJobs with TableInfo<$SyncJobsTable, SyncJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityTypeMeta =
      const VerificationMeta('entityType');
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
      'entity_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _entityIdMeta =
      const VerificationMeta('entityId');
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
      'entity_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _blocksOnSubmissionIdMeta =
      const VerificationMeta('blocksOnSubmissionId');
  @override
  late final GeneratedColumn<String> blocksOnSubmissionId =
      GeneratedColumn<String>('blocks_on_submission_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nextRetryAtMeta =
      const VerificationMeta('nextRetryAt');
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
      'next_retry_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entityType,
        entityId,
        status,
        blocksOnSubmissionId,
        attempts,
        lastError,
        nextRetryAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_jobs';
  @override
  VerificationContext validateIntegrity(Insertable<SyncJob> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
          _entityTypeMeta,
          entityType.isAcceptableOrUnknown(
              data['entity_type']!, _entityTypeMeta));
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(_entityIdMeta,
          entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta));
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('blocks_on_submission_id')) {
      context.handle(
          _blocksOnSubmissionIdMeta,
          blocksOnSubmissionId.isAcceptableOrUnknown(
              data['blocks_on_submission_id']!, _blocksOnSubmissionIdMeta));
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
          _nextRetryAtMeta,
          nextRetryAt.isAcceptableOrUnknown(
              data['next_retry_at']!, _nextRetryAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncJob(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      entityType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_type'])!,
      entityId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity_id'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      blocksOnSubmissionId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}blocks_on_submission_id']),
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      nextRetryAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}next_retry_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $SyncJobsTable createAlias(String alias) {
    return $SyncJobsTable(attachedDatabase, alias);
  }
}

class SyncJob extends DataClass implements Insertable<SyncJob> {
  final String id;
  final String entityType;
  final String entityId;
  final String status;
  final String? blocksOnSubmissionId;
  final int attempts;
  final String? lastError;
  final DateTime? nextRetryAt;
  final DateTime createdAt;
  const SyncJob(
      {required this.id,
      required this.entityType,
      required this.entityId,
      required this.status,
      this.blocksOnSubmissionId,
      required this.attempts,
      this.lastError,
      this.nextRetryAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || blocksOnSubmissionId != null) {
      map['blocks_on_submission_id'] = Variable<String>(blocksOnSubmissionId);
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncJobsCompanion toCompanion(bool nullToAbsent) {
    return SyncJobsCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      status: Value(status),
      blocksOnSubmissionId: blocksOnSubmissionId == null && nullToAbsent
          ? const Value.absent()
          : Value(blocksOnSubmissionId),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      createdAt: Value(createdAt),
    );
  }

  factory SyncJob.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncJob(
      id: serializer.fromJson<String>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      status: serializer.fromJson<String>(json['status']),
      blocksOnSubmissionId:
          serializer.fromJson<String?>(json['blocksOnSubmissionId']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'status': serializer.toJson<String>(status),
      'blocksOnSubmissionId': serializer.toJson<String?>(blocksOnSubmissionId),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncJob copyWith(
          {String? id,
          String? entityType,
          String? entityId,
          String? status,
          Value<String?> blocksOnSubmissionId = const Value.absent(),
          int? attempts,
          Value<String?> lastError = const Value.absent(),
          Value<DateTime?> nextRetryAt = const Value.absent(),
          DateTime? createdAt}) =>
      SyncJob(
        id: id ?? this.id,
        entityType: entityType ?? this.entityType,
        entityId: entityId ?? this.entityId,
        status: status ?? this.status,
        blocksOnSubmissionId: blocksOnSubmissionId.present
            ? blocksOnSubmissionId.value
            : this.blocksOnSubmissionId,
        attempts: attempts ?? this.attempts,
        lastError: lastError.present ? lastError.value : this.lastError,
        nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
        createdAt: createdAt ?? this.createdAt,
      );
  SyncJob copyWithCompanion(SyncJobsCompanion data) {
    return SyncJob(
      id: data.id.present ? data.id.value : this.id,
      entityType:
          data.entityType.present ? data.entityType.value : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      status: data.status.present ? data.status.value : this.status,
      blocksOnSubmissionId: data.blocksOnSubmissionId.present
          ? data.blocksOnSubmissionId.value
          : this.blocksOnSubmissionId,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      nextRetryAt:
          data.nextRetryAt.present ? data.nextRetryAt.value : this.nextRetryAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncJob(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('status: $status, ')
          ..write('blocksOnSubmissionId: $blocksOnSubmissionId, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entityType, entityId, status,
      blocksOnSubmissionId, attempts, lastError, nextRetryAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncJob &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.status == this.status &&
          other.blocksOnSubmissionId == this.blocksOnSubmissionId &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.nextRetryAt == this.nextRetryAt &&
          other.createdAt == this.createdAt);
}

class SyncJobsCompanion extends UpdateCompanion<SyncJob> {
  final Value<String> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> status;
  final Value<String?> blocksOnSubmissionId;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime?> nextRetryAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SyncJobsCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.status = const Value.absent(),
    this.blocksOnSubmissionId = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncJobsCompanion.insert({
    required String id,
    required String entityType,
    required String entityId,
    this.status = const Value.absent(),
    this.blocksOnSubmissionId = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        entityType = Value(entityType),
        entityId = Value(entityId),
        createdAt = Value(createdAt);
  static Insertable<SyncJob> custom({
    Expression<String>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? status,
    Expression<String>? blocksOnSubmissionId,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? nextRetryAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (status != null) 'status': status,
      if (blocksOnSubmissionId != null)
        'blocks_on_submission_id': blocksOnSubmissionId,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncJobsCompanion copyWith(
      {Value<String>? id,
      Value<String>? entityType,
      Value<String>? entityId,
      Value<String>? status,
      Value<String?>? blocksOnSubmissionId,
      Value<int>? attempts,
      Value<String?>? lastError,
      Value<DateTime?>? nextRetryAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return SyncJobsCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      status: status ?? this.status,
      blocksOnSubmissionId: blocksOnSubmissionId ?? this.blocksOnSubmissionId,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (blocksOnSubmissionId.present) {
      map['blocks_on_submission_id'] =
          Variable<String>(blocksOnSubmissionId.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncJobsCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('status: $status, ')
          ..write('blocksOnSubmissionId: $blocksOnSubmissionId, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineTilePacksTable extends OfflineTilePacks
    with TableInfo<$OfflineTilePacksTable, OfflineTilePack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineTilePacksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _assignmentIdMeta =
      const VerificationMeta('assignmentId');
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
      'assignment_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mapboxPackIdMeta =
      const VerificationMeta('mapboxPackId');
  @override
  late final GeneratedColumn<String> mapboxPackId = GeneratedColumn<String>(
      'mapbox_pack_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _regionBoundsGeojsonMeta =
      const VerificationMeta('regionBoundsGeojson');
  @override
  late final GeneratedColumn<String> regionBoundsGeojson =
      GeneratedColumn<String>('region_bounds_geojson', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _downloadedBytesMeta =
      const VerificationMeta('downloadedBytes');
  @override
  late final GeneratedColumn<int> downloadedBytes = GeneratedColumn<int>(
      'downloaded_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalBytesMeta =
      const VerificationMeta('totalBytes');
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
      'total_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('downloading'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        assignmentId,
        mapboxPackId,
        regionBoundsGeojson,
        downloadedBytes,
        totalBytes,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_tile_packs';
  @override
  VerificationContext validateIntegrity(Insertable<OfflineTilePack> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assignment_id')) {
      context.handle(
          _assignmentIdMeta,
          assignmentId.isAcceptableOrUnknown(
              data['assignment_id']!, _assignmentIdMeta));
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('mapbox_pack_id')) {
      context.handle(
          _mapboxPackIdMeta,
          mapboxPackId.isAcceptableOrUnknown(
              data['mapbox_pack_id']!, _mapboxPackIdMeta));
    }
    if (data.containsKey('region_bounds_geojson')) {
      context.handle(
          _regionBoundsGeojsonMeta,
          regionBoundsGeojson.isAcceptableOrUnknown(
              data['region_bounds_geojson']!, _regionBoundsGeojsonMeta));
    } else if (isInserting) {
      context.missing(_regionBoundsGeojsonMeta);
    }
    if (data.containsKey('downloaded_bytes')) {
      context.handle(
          _downloadedBytesMeta,
          downloadedBytes.isAcceptableOrUnknown(
              data['downloaded_bytes']!, _downloadedBytesMeta));
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
          _totalBytesMeta,
          totalBytes.isAcceptableOrUnknown(
              data['total_bytes']!, _totalBytesMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineTilePack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineTilePack(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      assignmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}assignment_id'])!,
      mapboxPackId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mapbox_pack_id']),
      regionBoundsGeojson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}region_bounds_geojson'])!,
      downloadedBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}downloaded_bytes'])!,
      totalBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_bytes'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
    );
  }

  @override
  $OfflineTilePacksTable createAlias(String alias) {
    return $OfflineTilePacksTable(attachedDatabase, alias);
  }
}

class OfflineTilePack extends DataClass implements Insertable<OfflineTilePack> {
  final String id;
  final String assignmentId;
  final String? mapboxPackId;
  final String regionBoundsGeojson;
  final int downloadedBytes;
  final int totalBytes;
  final String status;
  const OfflineTilePack(
      {required this.id,
      required this.assignmentId,
      this.mapboxPackId,
      required this.regionBoundsGeojson,
      required this.downloadedBytes,
      required this.totalBytes,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assignment_id'] = Variable<String>(assignmentId);
    if (!nullToAbsent || mapboxPackId != null) {
      map['mapbox_pack_id'] = Variable<String>(mapboxPackId);
    }
    map['region_bounds_geojson'] = Variable<String>(regionBoundsGeojson);
    map['downloaded_bytes'] = Variable<int>(downloadedBytes);
    map['total_bytes'] = Variable<int>(totalBytes);
    map['status'] = Variable<String>(status);
    return map;
  }

  OfflineTilePacksCompanion toCompanion(bool nullToAbsent) {
    return OfflineTilePacksCompanion(
      id: Value(id),
      assignmentId: Value(assignmentId),
      mapboxPackId: mapboxPackId == null && nullToAbsent
          ? const Value.absent()
          : Value(mapboxPackId),
      regionBoundsGeojson: Value(regionBoundsGeojson),
      downloadedBytes: Value(downloadedBytes),
      totalBytes: Value(totalBytes),
      status: Value(status),
    );
  }

  factory OfflineTilePack.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineTilePack(
      id: serializer.fromJson<String>(json['id']),
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      mapboxPackId: serializer.fromJson<String?>(json['mapboxPackId']),
      regionBoundsGeojson:
          serializer.fromJson<String>(json['regionBoundsGeojson']),
      downloadedBytes: serializer.fromJson<int>(json['downloadedBytes']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assignmentId': serializer.toJson<String>(assignmentId),
      'mapboxPackId': serializer.toJson<String?>(mapboxPackId),
      'regionBoundsGeojson': serializer.toJson<String>(regionBoundsGeojson),
      'downloadedBytes': serializer.toJson<int>(downloadedBytes),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'status': serializer.toJson<String>(status),
    };
  }

  OfflineTilePack copyWith(
          {String? id,
          String? assignmentId,
          Value<String?> mapboxPackId = const Value.absent(),
          String? regionBoundsGeojson,
          int? downloadedBytes,
          int? totalBytes,
          String? status}) =>
      OfflineTilePack(
        id: id ?? this.id,
        assignmentId: assignmentId ?? this.assignmentId,
        mapboxPackId:
            mapboxPackId.present ? mapboxPackId.value : this.mapboxPackId,
        regionBoundsGeojson: regionBoundsGeojson ?? this.regionBoundsGeojson,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        status: status ?? this.status,
      );
  OfflineTilePack copyWithCompanion(OfflineTilePacksCompanion data) {
    return OfflineTilePack(
      id: data.id.present ? data.id.value : this.id,
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      mapboxPackId: data.mapboxPackId.present
          ? data.mapboxPackId.value
          : this.mapboxPackId,
      regionBoundsGeojson: data.regionBoundsGeojson.present
          ? data.regionBoundsGeojson.value
          : this.regionBoundsGeojson,
      downloadedBytes: data.downloadedBytes.present
          ? data.downloadedBytes.value
          : this.downloadedBytes,
      totalBytes:
          data.totalBytes.present ? data.totalBytes.value : this.totalBytes,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineTilePack(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('mapboxPackId: $mapboxPackId, ')
          ..write('regionBoundsGeojson: $regionBoundsGeojson, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, assignmentId, mapboxPackId,
      regionBoundsGeojson, downloadedBytes, totalBytes, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineTilePack &&
          other.id == this.id &&
          other.assignmentId == this.assignmentId &&
          other.mapboxPackId == this.mapboxPackId &&
          other.regionBoundsGeojson == this.regionBoundsGeojson &&
          other.downloadedBytes == this.downloadedBytes &&
          other.totalBytes == this.totalBytes &&
          other.status == this.status);
}

class OfflineTilePacksCompanion extends UpdateCompanion<OfflineTilePack> {
  final Value<String> id;
  final Value<String> assignmentId;
  final Value<String?> mapboxPackId;
  final Value<String> regionBoundsGeojson;
  final Value<int> downloadedBytes;
  final Value<int> totalBytes;
  final Value<String> status;
  final Value<int> rowid;
  const OfflineTilePacksCompanion({
    this.id = const Value.absent(),
    this.assignmentId = const Value.absent(),
    this.mapboxPackId = const Value.absent(),
    this.regionBoundsGeojson = const Value.absent(),
    this.downloadedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineTilePacksCompanion.insert({
    required String id,
    required String assignmentId,
    this.mapboxPackId = const Value.absent(),
    required String regionBoundsGeojson,
    this.downloadedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        assignmentId = Value(assignmentId),
        regionBoundsGeojson = Value(regionBoundsGeojson);
  static Insertable<OfflineTilePack> custom({
    Expression<String>? id,
    Expression<String>? assignmentId,
    Expression<String>? mapboxPackId,
    Expression<String>? regionBoundsGeojson,
    Expression<int>? downloadedBytes,
    Expression<int>? totalBytes,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (mapboxPackId != null) 'mapbox_pack_id': mapboxPackId,
      if (regionBoundsGeojson != null)
        'region_bounds_geojson': regionBoundsGeojson,
      if (downloadedBytes != null) 'downloaded_bytes': downloadedBytes,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineTilePacksCompanion copyWith(
      {Value<String>? id,
      Value<String>? assignmentId,
      Value<String?>? mapboxPackId,
      Value<String>? regionBoundsGeojson,
      Value<int>? downloadedBytes,
      Value<int>? totalBytes,
      Value<String>? status,
      Value<int>? rowid}) {
    return OfflineTilePacksCompanion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      mapboxPackId: mapboxPackId ?? this.mapboxPackId,
      regionBoundsGeojson: regionBoundsGeojson ?? this.regionBoundsGeojson,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (mapboxPackId.present) {
      map['mapbox_pack_id'] = Variable<String>(mapboxPackId.value);
    }
    if (regionBoundsGeojson.present) {
      map['region_bounds_geojson'] =
          Variable<String>(regionBoundsGeojson.value);
    }
    if (downloadedBytes.present) {
      map['downloaded_bytes'] = Variable<int>(downloadedBytes.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineTilePacksCompanion(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('mapboxPackId: $mapboxPackId, ')
          ..write('regionBoundsGeojson: $regionBoundsGeojson, ')
          ..write('downloadedBytes: $downloadedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DriveUploadJobsTable extends DriveUploadJobs
    with TableInfo<$DriveUploadJobsTable, DriveUploadJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DriveUploadJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _assignmentIdMeta =
      const VerificationMeta('assignmentId');
  @override
  late final GeneratedColumn<String> assignmentId = GeneratedColumn<String>(
      'assignment_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileTypeMeta =
      const VerificationMeta('fileType');
  @override
  late final GeneratedColumn<String> fileType = GeneratedColumn<String>(
      'file_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileSizeBytesMeta =
      const VerificationMeta('fileSizeBytes');
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
      'file_size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _capturedAtMeta =
      const VerificationMeta('capturedAt');
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
      'captured_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  static const VerificationMeta _resumableUriMeta =
      const VerificationMeta('resumableUri');
  @override
  late final GeneratedColumn<String> resumableUri = GeneratedColumn<String>(
      'resumable_uri', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _driveFileIdMeta =
      const VerificationMeta('driveFileId');
  @override
  late final GeneratedColumn<String> driveFileId = GeneratedColumn<String>(
      'drive_file_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _failureReasonMeta =
      const VerificationMeta('failureReason');
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
      'failure_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nextRetryAtMeta =
      const VerificationMeta('nextRetryAt');
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
      'next_retry_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        assignmentId,
        filePath,
        fileType,
        fileName,
        fileSizeBytes,
        capturedAt,
        status,
        resumableUri,
        driveFileId,
        retryCount,
        failureReason,
        nextRetryAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drive_upload_jobs';
  @override
  VerificationContext validateIntegrity(Insertable<DriveUploadJob> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('assignment_id')) {
      context.handle(
          _assignmentIdMeta,
          assignmentId.isAcceptableOrUnknown(
              data['assignment_id']!, _assignmentIdMeta));
    } else if (isInserting) {
      context.missing(_assignmentIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('file_type')) {
      context.handle(_fileTypeMeta,
          fileType.isAcceptableOrUnknown(data['file_type']!, _fileTypeMeta));
    } else if (isInserting) {
      context.missing(_fileTypeMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
          _fileSizeBytesMeta,
          fileSizeBytes.isAcceptableOrUnknown(
              data['file_size_bytes']!, _fileSizeBytesMeta));
    } else if (isInserting) {
      context.missing(_fileSizeBytesMeta);
    }
    if (data.containsKey('captured_at')) {
      context.handle(
          _capturedAtMeta,
          capturedAt.isAcceptableOrUnknown(
              data['captured_at']!, _capturedAtMeta));
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('resumable_uri')) {
      context.handle(
          _resumableUriMeta,
          resumableUri.isAcceptableOrUnknown(
              data['resumable_uri']!, _resumableUriMeta));
    }
    if (data.containsKey('drive_file_id')) {
      context.handle(
          _driveFileIdMeta,
          driveFileId.isAcceptableOrUnknown(
              data['drive_file_id']!, _driveFileIdMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
          _failureReasonMeta,
          failureReason.isAcceptableOrUnknown(
              data['failure_reason']!, _failureReasonMeta));
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
          _nextRetryAtMeta,
          nextRetryAt.isAcceptableOrUnknown(
              data['next_retry_at']!, _nextRetryAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DriveUploadJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DriveUploadJob(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      assignmentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}assignment_id'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      fileType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_type'])!,
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name'])!,
      fileSizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size_bytes'])!,
      capturedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}captured_at'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      resumableUri: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}resumable_uri']),
      driveFileId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}drive_file_id']),
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      failureReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}failure_reason']),
      nextRetryAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}next_retry_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $DriveUploadJobsTable createAlias(String alias) {
    return $DriveUploadJobsTable(attachedDatabase, alias);
  }
}

class DriveUploadJob extends DataClass implements Insertable<DriveUploadJob> {
  final String id;
  final String assignmentId;
  final String filePath;
  final String fileType;
  final String fileName;
  final int fileSizeBytes;
  final DateTime capturedAt;
  final String status;
  final String? resumableUri;
  final String? driveFileId;
  final int retryCount;
  final String? failureReason;
  final DateTime? nextRetryAt;
  final DateTime createdAt;
  const DriveUploadJob(
      {required this.id,
      required this.assignmentId,
      required this.filePath,
      required this.fileType,
      required this.fileName,
      required this.fileSizeBytes,
      required this.capturedAt,
      required this.status,
      this.resumableUri,
      this.driveFileId,
      required this.retryCount,
      this.failureReason,
      this.nextRetryAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['assignment_id'] = Variable<String>(assignmentId);
    map['file_path'] = Variable<String>(filePath);
    map['file_type'] = Variable<String>(fileType);
    map['file_name'] = Variable<String>(fileName);
    map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || resumableUri != null) {
      map['resumable_uri'] = Variable<String>(resumableUri);
    }
    if (!nullToAbsent || driveFileId != null) {
      map['drive_file_id'] = Variable<String>(driveFileId);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DriveUploadJobsCompanion toCompanion(bool nullToAbsent) {
    return DriveUploadJobsCompanion(
      id: Value(id),
      assignmentId: Value(assignmentId),
      filePath: Value(filePath),
      fileType: Value(fileType),
      fileName: Value(fileName),
      fileSizeBytes: Value(fileSizeBytes),
      capturedAt: Value(capturedAt),
      status: Value(status),
      resumableUri: resumableUri == null && nullToAbsent
          ? const Value.absent()
          : Value(resumableUri),
      driveFileId: driveFileId == null && nullToAbsent
          ? const Value.absent()
          : Value(driveFileId),
      retryCount: Value(retryCount),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      createdAt: Value(createdAt),
    );
  }

  factory DriveUploadJob.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DriveUploadJob(
      id: serializer.fromJson<String>(json['id']),
      assignmentId: serializer.fromJson<String>(json['assignmentId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      fileType: serializer.fromJson<String>(json['fileType']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileSizeBytes: serializer.fromJson<int>(json['fileSizeBytes']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      status: serializer.fromJson<String>(json['status']),
      resumableUri: serializer.fromJson<String?>(json['resumableUri']),
      driveFileId: serializer.fromJson<String?>(json['driveFileId']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'assignmentId': serializer.toJson<String>(assignmentId),
      'filePath': serializer.toJson<String>(filePath),
      'fileType': serializer.toJson<String>(fileType),
      'fileName': serializer.toJson<String>(fileName),
      'fileSizeBytes': serializer.toJson<int>(fileSizeBytes),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'status': serializer.toJson<String>(status),
      'resumableUri': serializer.toJson<String?>(resumableUri),
      'driveFileId': serializer.toJson<String?>(driveFileId),
      'retryCount': serializer.toJson<int>(retryCount),
      'failureReason': serializer.toJson<String?>(failureReason),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DriveUploadJob copyWith(
          {String? id,
          String? assignmentId,
          String? filePath,
          String? fileType,
          String? fileName,
          int? fileSizeBytes,
          DateTime? capturedAt,
          String? status,
          Value<String?> resumableUri = const Value.absent(),
          Value<String?> driveFileId = const Value.absent(),
          int? retryCount,
          Value<String?> failureReason = const Value.absent(),
          Value<DateTime?> nextRetryAt = const Value.absent(),
          DateTime? createdAt}) =>
      DriveUploadJob(
        id: id ?? this.id,
        assignmentId: assignmentId ?? this.assignmentId,
        filePath: filePath ?? this.filePath,
        fileType: fileType ?? this.fileType,
        fileName: fileName ?? this.fileName,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
        capturedAt: capturedAt ?? this.capturedAt,
        status: status ?? this.status,
        resumableUri:
            resumableUri.present ? resumableUri.value : this.resumableUri,
        driveFileId: driveFileId.present ? driveFileId.value : this.driveFileId,
        retryCount: retryCount ?? this.retryCount,
        failureReason:
            failureReason.present ? failureReason.value : this.failureReason,
        nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
        createdAt: createdAt ?? this.createdAt,
      );
  DriveUploadJob copyWithCompanion(DriveUploadJobsCompanion data) {
    return DriveUploadJob(
      id: data.id.present ? data.id.value : this.id,
      assignmentId: data.assignmentId.present
          ? data.assignmentId.value
          : this.assignmentId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileType: data.fileType.present ? data.fileType.value : this.fileType,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      capturedAt:
          data.capturedAt.present ? data.capturedAt.value : this.capturedAt,
      status: data.status.present ? data.status.value : this.status,
      resumableUri: data.resumableUri.present
          ? data.resumableUri.value
          : this.resumableUri,
      driveFileId:
          data.driveFileId.present ? data.driveFileId.value : this.driveFileId,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      nextRetryAt:
          data.nextRetryAt.present ? data.nextRetryAt.value : this.nextRetryAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DriveUploadJob(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('filePath: $filePath, ')
          ..write('fileType: $fileType, ')
          ..write('fileName: $fileName, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('status: $status, ')
          ..write('resumableUri: $resumableUri, ')
          ..write('driveFileId: $driveFileId, ')
          ..write('retryCount: $retryCount, ')
          ..write('failureReason: $failureReason, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      assignmentId,
      filePath,
      fileType,
      fileName,
      fileSizeBytes,
      capturedAt,
      status,
      resumableUri,
      driveFileId,
      retryCount,
      failureReason,
      nextRetryAt,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DriveUploadJob &&
          other.id == this.id &&
          other.assignmentId == this.assignmentId &&
          other.filePath == this.filePath &&
          other.fileType == this.fileType &&
          other.fileName == this.fileName &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.capturedAt == this.capturedAt &&
          other.status == this.status &&
          other.resumableUri == this.resumableUri &&
          other.driveFileId == this.driveFileId &&
          other.retryCount == this.retryCount &&
          other.failureReason == this.failureReason &&
          other.nextRetryAt == this.nextRetryAt &&
          other.createdAt == this.createdAt);
}

class DriveUploadJobsCompanion extends UpdateCompanion<DriveUploadJob> {
  final Value<String> id;
  final Value<String> assignmentId;
  final Value<String> filePath;
  final Value<String> fileType;
  final Value<String> fileName;
  final Value<int> fileSizeBytes;
  final Value<DateTime> capturedAt;
  final Value<String> status;
  final Value<String?> resumableUri;
  final Value<String?> driveFileId;
  final Value<int> retryCount;
  final Value<String?> failureReason;
  final Value<DateTime?> nextRetryAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DriveUploadJobsCompanion({
    this.id = const Value.absent(),
    this.assignmentId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileType = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.resumableUri = const Value.absent(),
    this.driveFileId = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DriveUploadJobsCompanion.insert({
    required String id,
    required String assignmentId,
    required String filePath,
    required String fileType,
    required String fileName,
    required int fileSizeBytes,
    required DateTime capturedAt,
    this.status = const Value.absent(),
    this.resumableUri = const Value.absent(),
    this.driveFileId = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        assignmentId = Value(assignmentId),
        filePath = Value(filePath),
        fileType = Value(fileType),
        fileName = Value(fileName),
        fileSizeBytes = Value(fileSizeBytes),
        capturedAt = Value(capturedAt),
        createdAt = Value(createdAt);
  static Insertable<DriveUploadJob> custom({
    Expression<String>? id,
    Expression<String>? assignmentId,
    Expression<String>? filePath,
    Expression<String>? fileType,
    Expression<String>? fileName,
    Expression<int>? fileSizeBytes,
    Expression<DateTime>? capturedAt,
    Expression<String>? status,
    Expression<String>? resumableUri,
    Expression<String>? driveFileId,
    Expression<int>? retryCount,
    Expression<String>? failureReason,
    Expression<DateTime>? nextRetryAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      if (filePath != null) 'file_path': filePath,
      if (fileType != null) 'file_type': fileType,
      if (fileName != null) 'file_name': fileName,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (status != null) 'status': status,
      if (resumableUri != null) 'resumable_uri': resumableUri,
      if (driveFileId != null) 'drive_file_id': driveFileId,
      if (retryCount != null) 'retry_count': retryCount,
      if (failureReason != null) 'failure_reason': failureReason,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DriveUploadJobsCompanion copyWith(
      {Value<String>? id,
      Value<String>? assignmentId,
      Value<String>? filePath,
      Value<String>? fileType,
      Value<String>? fileName,
      Value<int>? fileSizeBytes,
      Value<DateTime>? capturedAt,
      Value<String>? status,
      Value<String?>? resumableUri,
      Value<String?>? driveFileId,
      Value<int>? retryCount,
      Value<String?>? failureReason,
      Value<DateTime?>? nextRetryAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return DriveUploadJobsCompanion(
      id: id ?? this.id,
      assignmentId: assignmentId ?? this.assignmentId,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      fileName: fileName ?? this.fileName,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      capturedAt: capturedAt ?? this.capturedAt,
      status: status ?? this.status,
      resumableUri: resumableUri ?? this.resumableUri,
      driveFileId: driveFileId ?? this.driveFileId,
      retryCount: retryCount ?? this.retryCount,
      failureReason: failureReason ?? this.failureReason,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (assignmentId.present) {
      map['assignment_id'] = Variable<String>(assignmentId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileType.present) {
      map['file_type'] = Variable<String>(fileType.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (resumableUri.present) {
      map['resumable_uri'] = Variable<String>(resumableUri.value);
    }
    if (driveFileId.present) {
      map['drive_file_id'] = Variable<String>(driveFileId.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DriveUploadJobsCompanion(')
          ..write('id: $id, ')
          ..write('assignmentId: $assignmentId, ')
          ..write('filePath: $filePath, ')
          ..write('fileType: $fileType, ')
          ..write('fileName: $fileName, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('status: $status, ')
          ..write('resumableUri: $resumableUri, ')
          ..write('driveFileId: $driveFileId, ')
          ..write('retryCount: $retryCount, ')
          ..write('failureReason: $failureReason, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EnumeratorsTable enumerators = $EnumeratorsTable(this);
  late final $AssignmentsTable assignments = $AssignmentsTable(this);
  late final $FeaturesTable features = $FeaturesTable(this);
  late final $FeatureGeometryRevisionsTable featureGeometryRevisions =
      $FeatureGeometryRevisionsTable(this);
  late final $SubmissionsTable submissions = $SubmissionsTable(this);
  late final $BuildingAttributesTable buildingAttributes =
      $BuildingAttributesTable(this);
  late final $RoadAttributesTable roadAttributes = $RoadAttributesTable(this);
  late final $HouseholdSurveysTable householdSurveys =
      $HouseholdSurveysTable(this);
  late final $PhotosTable photos = $PhotosTable(this);
  late final $Ra9514TypesTable ra9514Types = $Ra9514TypesTable(this);
  late final $SyncJobsTable syncJobs = $SyncJobsTable(this);
  late final $OfflineTilePacksTable offlineTilePacks =
      $OfflineTilePacksTable(this);
  late final $DriveUploadJobsTable driveUploadJobs =
      $DriveUploadJobsTable(this);
  late final Index featuresAssignmentIdIdx = Index('features_assignment_id_idx',
      'CREATE INDEX features_assignment_id_idx ON features (assignment_id)');
  late final Index fgrFeatureIdIdx = Index('fgr_feature_id_idx',
      'CREATE INDEX fgr_feature_id_idx ON feature_geometry_revisions (feature_id)');
  late final Index fgrSyncStatusIdx = Index('fgr_sync_status_idx',
      'CREATE INDEX fgr_sync_status_idx ON feature_geometry_revisions (sync_status)');
  late final Index submissionsFeatureIdIdx = Index('submissions_feature_id_idx',
      'CREATE INDEX submissions_feature_id_idx ON submissions (feature_id)');
  late final Index buildingAttrsRa9514TypeIdx = Index(
      'building_attrs_ra9514_type_idx',
      'CREATE INDEX building_attrs_ra9514_type_idx ON building_attributes (ra_9514_type)');
  late final Index photosSubmissionIdIdx = Index('photos_submission_id_idx',
      'CREATE INDEX photos_submission_id_idx ON photos (submission_id)');
  late final Index syncJobsStatusRetryIdx = Index('sync_jobs_status_retry_idx',
      'CREATE INDEX sync_jobs_status_retry_idx ON sync_jobs (status, next_retry_at)');
  late final Index driveUploadJobsStatusIdx = Index(
      'drive_upload_jobs_status_idx',
      'CREATE INDEX drive_upload_jobs_status_idx ON drive_upload_jobs (status, next_retry_at)');
  late final Index driveUploadJobsAssignmentIdx = Index(
      'drive_upload_jobs_assignment_idx',
      'CREATE INDEX drive_upload_jobs_assignment_idx ON drive_upload_jobs (assignment_id)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        enumerators,
        assignments,
        features,
        featureGeometryRevisions,
        submissions,
        buildingAttributes,
        roadAttributes,
        householdSurveys,
        photos,
        ra9514Types,
        syncJobs,
        offlineTilePacks,
        driveUploadJobs,
        featuresAssignmentIdIdx,
        fgrFeatureIdIdx,
        fgrSyncStatusIdx,
        submissionsFeatureIdIdx,
        buildingAttrsRa9514TypeIdx,
        photosSubmissionIdIdx,
        syncJobsStatusRetryIdx,
        driveUploadJobsStatusIdx,
        driveUploadJobsAssignmentIdx
      ];
}

typedef $$EnumeratorsTableCreateCompanionBuilder = EnumeratorsCompanion
    Function({
  required String id,
  required String username,
  required String displayName,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$EnumeratorsTableUpdateCompanionBuilder = EnumeratorsCompanion
    Function({
  Value<String> id,
  Value<String> username,
  Value<String> displayName,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$EnumeratorsTableFilterComposer
    extends Composer<_$AppDatabase, $EnumeratorsTable> {
  $$EnumeratorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$EnumeratorsTableOrderingComposer
    extends Composer<_$AppDatabase, $EnumeratorsTable> {
  $$EnumeratorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$EnumeratorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EnumeratorsTable> {
  $$EnumeratorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$EnumeratorsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $EnumeratorsTable,
    Enumerator,
    $$EnumeratorsTableFilterComposer,
    $$EnumeratorsTableOrderingComposer,
    $$EnumeratorsTableAnnotationComposer,
    $$EnumeratorsTableCreateCompanionBuilder,
    $$EnumeratorsTableUpdateCompanionBuilder,
    (Enumerator, BaseReferences<_$AppDatabase, $EnumeratorsTable, Enumerator>),
    Enumerator,
    PrefetchHooks Function()> {
  $$EnumeratorsTableTableManager(_$AppDatabase db, $EnumeratorsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EnumeratorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EnumeratorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EnumeratorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> username = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              EnumeratorsCompanion(
            id: id,
            username: username,
            displayName: displayName,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String username,
            required String displayName,
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              EnumeratorsCompanion.insert(
            id: id,
            username: username,
            displayName: displayName,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EnumeratorsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $EnumeratorsTable,
    Enumerator,
    $$EnumeratorsTableFilterComposer,
    $$EnumeratorsTableOrderingComposer,
    $$EnumeratorsTableAnnotationComposer,
    $$EnumeratorsTableCreateCompanionBuilder,
    $$EnumeratorsTableUpdateCompanionBuilder,
    (Enumerator, BaseReferences<_$AppDatabase, $EnumeratorsTable, Enumerator>),
    Enumerator,
    PrefetchHooks Function()>;
typedef $$AssignmentsTableCreateCompanionBuilder = AssignmentsCompanion
    Function({
  required String id,
  required String enumeratorId,
  required String campaignId,
  required String boundaryPolygonGeojson,
  Value<DateTime?> downloadedAt,
  Value<DateTime?> submittedAt,
  Value<String> status,
  Value<bool> closedRemotely,
  required DateTime createdAt,
  Value<String?> driveModifiedTime,
  Value<String?> driveFolderId,
  Value<String?> driveFolderPath,
  Value<String?> driveFolderUrl,
  Value<DateTime?> driveUploadConfirmedAt,
  Value<int> rowid,
});
typedef $$AssignmentsTableUpdateCompanionBuilder = AssignmentsCompanion
    Function({
  Value<String> id,
  Value<String> enumeratorId,
  Value<String> campaignId,
  Value<String> boundaryPolygonGeojson,
  Value<DateTime?> downloadedAt,
  Value<DateTime?> submittedAt,
  Value<String> status,
  Value<bool> closedRemotely,
  Value<DateTime> createdAt,
  Value<String?> driveModifiedTime,
  Value<String?> driveFolderId,
  Value<String?> driveFolderPath,
  Value<String?> driveFolderUrl,
  Value<DateTime?> driveUploadConfirmedAt,
  Value<int> rowid,
});

class $$AssignmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AssignmentsTable> {
  $$AssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get enumeratorId => $composableBuilder(
      column: $table.enumeratorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get campaignId => $composableBuilder(
      column: $table.campaignId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get boundaryPolygonGeojson => $composableBuilder(
      column: $table.boundaryPolygonGeojson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get downloadedAt => $composableBuilder(
      column: $table.downloadedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get submittedAt => $composableBuilder(
      column: $table.submittedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get closedRemotely => $composableBuilder(
      column: $table.closedRemotely,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driveModifiedTime => $composableBuilder(
      column: $table.driveModifiedTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driveFolderId => $composableBuilder(
      column: $table.driveFolderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driveFolderPath => $composableBuilder(
      column: $table.driveFolderPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driveFolderUrl => $composableBuilder(
      column: $table.driveFolderUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get driveUploadConfirmedAt => $composableBuilder(
      column: $table.driveUploadConfirmedAt,
      builder: (column) => ColumnFilters(column));
}

class $$AssignmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssignmentsTable> {
  $$AssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get enumeratorId => $composableBuilder(
      column: $table.enumeratorId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get campaignId => $composableBuilder(
      column: $table.campaignId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get boundaryPolygonGeojson => $composableBuilder(
      column: $table.boundaryPolygonGeojson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get downloadedAt => $composableBuilder(
      column: $table.downloadedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get submittedAt => $composableBuilder(
      column: $table.submittedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get closedRemotely => $composableBuilder(
      column: $table.closedRemotely,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driveModifiedTime => $composableBuilder(
      column: $table.driveModifiedTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driveFolderId => $composableBuilder(
      column: $table.driveFolderId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driveFolderPath => $composableBuilder(
      column: $table.driveFolderPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driveFolderUrl => $composableBuilder(
      column: $table.driveFolderUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get driveUploadConfirmedAt => $composableBuilder(
      column: $table.driveUploadConfirmedAt,
      builder: (column) => ColumnOrderings(column));
}

class $$AssignmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssignmentsTable> {
  $$AssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get enumeratorId => $composableBuilder(
      column: $table.enumeratorId, builder: (column) => column);

  GeneratedColumn<String> get campaignId => $composableBuilder(
      column: $table.campaignId, builder: (column) => column);

  GeneratedColumn<String> get boundaryPolygonGeojson => $composableBuilder(
      column: $table.boundaryPolygonGeojson, builder: (column) => column);

  GeneratedColumn<DateTime> get downloadedAt => $composableBuilder(
      column: $table.downloadedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get submittedAt => $composableBuilder(
      column: $table.submittedAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get closedRemotely => $composableBuilder(
      column: $table.closedRemotely, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get driveModifiedTime => $composableBuilder(
      column: $table.driveModifiedTime, builder: (column) => column);

  GeneratedColumn<String> get driveFolderId => $composableBuilder(
      column: $table.driveFolderId, builder: (column) => column);

  GeneratedColumn<String> get driveFolderPath => $composableBuilder(
      column: $table.driveFolderPath, builder: (column) => column);

  GeneratedColumn<String> get driveFolderUrl => $composableBuilder(
      column: $table.driveFolderUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get driveUploadConfirmedAt => $composableBuilder(
      column: $table.driveUploadConfirmedAt, builder: (column) => column);
}

class $$AssignmentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AssignmentsTable,
    Assignment,
    $$AssignmentsTableFilterComposer,
    $$AssignmentsTableOrderingComposer,
    $$AssignmentsTableAnnotationComposer,
    $$AssignmentsTableCreateCompanionBuilder,
    $$AssignmentsTableUpdateCompanionBuilder,
    (Assignment, BaseReferences<_$AppDatabase, $AssignmentsTable, Assignment>),
    Assignment,
    PrefetchHooks Function()> {
  $$AssignmentsTableTableManager(_$AppDatabase db, $AssignmentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssignmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssignmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssignmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> enumeratorId = const Value.absent(),
            Value<String> campaignId = const Value.absent(),
            Value<String> boundaryPolygonGeojson = const Value.absent(),
            Value<DateTime?> downloadedAt = const Value.absent(),
            Value<DateTime?> submittedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> closedRemotely = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> driveModifiedTime = const Value.absent(),
            Value<String?> driveFolderId = const Value.absent(),
            Value<String?> driveFolderPath = const Value.absent(),
            Value<String?> driveFolderUrl = const Value.absent(),
            Value<DateTime?> driveUploadConfirmedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AssignmentsCompanion(
            id: id,
            enumeratorId: enumeratorId,
            campaignId: campaignId,
            boundaryPolygonGeojson: boundaryPolygonGeojson,
            downloadedAt: downloadedAt,
            submittedAt: submittedAt,
            status: status,
            closedRemotely: closedRemotely,
            createdAt: createdAt,
            driveModifiedTime: driveModifiedTime,
            driveFolderId: driveFolderId,
            driveFolderPath: driveFolderPath,
            driveFolderUrl: driveFolderUrl,
            driveUploadConfirmedAt: driveUploadConfirmedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String enumeratorId,
            required String campaignId,
            required String boundaryPolygonGeojson,
            Value<DateTime?> downloadedAt = const Value.absent(),
            Value<DateTime?> submittedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<bool> closedRemotely = const Value.absent(),
            required DateTime createdAt,
            Value<String?> driveModifiedTime = const Value.absent(),
            Value<String?> driveFolderId = const Value.absent(),
            Value<String?> driveFolderPath = const Value.absent(),
            Value<String?> driveFolderUrl = const Value.absent(),
            Value<DateTime?> driveUploadConfirmedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AssignmentsCompanion.insert(
            id: id,
            enumeratorId: enumeratorId,
            campaignId: campaignId,
            boundaryPolygonGeojson: boundaryPolygonGeojson,
            downloadedAt: downloadedAt,
            submittedAt: submittedAt,
            status: status,
            closedRemotely: closedRemotely,
            createdAt: createdAt,
            driveModifiedTime: driveModifiedTime,
            driveFolderId: driveFolderId,
            driveFolderPath: driveFolderPath,
            driveFolderUrl: driveFolderUrl,
            driveUploadConfirmedAt: driveUploadConfirmedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AssignmentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AssignmentsTable,
    Assignment,
    $$AssignmentsTableFilterComposer,
    $$AssignmentsTableOrderingComposer,
    $$AssignmentsTableAnnotationComposer,
    $$AssignmentsTableCreateCompanionBuilder,
    $$AssignmentsTableUpdateCompanionBuilder,
    (Assignment, BaseReferences<_$AppDatabase, $AssignmentsTable, Assignment>),
    Assignment,
    PrefetchHooks Function()>;
typedef $$FeaturesTableCreateCompanionBuilder = FeaturesCompanion Function({
  required String id,
  required String assignmentId,
  required String featureType,
  required String geometryGeojson,
  Value<bool> isNew,
  Value<String> status,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$FeaturesTableUpdateCompanionBuilder = FeaturesCompanion Function({
  Value<String> id,
  Value<String> assignmentId,
  Value<String> featureType,
  Value<String> geometryGeojson,
  Value<bool> isNew,
  Value<String> status,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$FeaturesTableFilterComposer
    extends Composer<_$AppDatabase, $FeaturesTable> {
  $$FeaturesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get featureType => $composableBuilder(
      column: $table.featureType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get geometryGeojson => $composableBuilder(
      column: $table.geometryGeojson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isNew => $composableBuilder(
      column: $table.isNew, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$FeaturesTableOrderingComposer
    extends Composer<_$AppDatabase, $FeaturesTable> {
  $$FeaturesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get featureType => $composableBuilder(
      column: $table.featureType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get geometryGeojson => $composableBuilder(
      column: $table.geometryGeojson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isNew => $composableBuilder(
      column: $table.isNew, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$FeaturesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeaturesTable> {
  $$FeaturesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId, builder: (column) => column);

  GeneratedColumn<String> get featureType => $composableBuilder(
      column: $table.featureType, builder: (column) => column);

  GeneratedColumn<String> get geometryGeojson => $composableBuilder(
      column: $table.geometryGeojson, builder: (column) => column);

  GeneratedColumn<bool> get isNew =>
      $composableBuilder(column: $table.isNew, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$FeaturesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FeaturesTable,
    Feature,
    $$FeaturesTableFilterComposer,
    $$FeaturesTableOrderingComposer,
    $$FeaturesTableAnnotationComposer,
    $$FeaturesTableCreateCompanionBuilder,
    $$FeaturesTableUpdateCompanionBuilder,
    (Feature, BaseReferences<_$AppDatabase, $FeaturesTable, Feature>),
    Feature,
    PrefetchHooks Function()> {
  $$FeaturesTableTableManager(_$AppDatabase db, $FeaturesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeaturesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FeaturesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeaturesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> assignmentId = const Value.absent(),
            Value<String> featureType = const Value.absent(),
            Value<String> geometryGeojson = const Value.absent(),
            Value<bool> isNew = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FeaturesCompanion(
            id: id,
            assignmentId: assignmentId,
            featureType: featureType,
            geometryGeojson: geometryGeojson,
            isNew: isNew,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String assignmentId,
            required String featureType,
            required String geometryGeojson,
            Value<bool> isNew = const Value.absent(),
            Value<String> status = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FeaturesCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            featureType: featureType,
            geometryGeojson: geometryGeojson,
            isNew: isNew,
            status: status,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FeaturesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FeaturesTable,
    Feature,
    $$FeaturesTableFilterComposer,
    $$FeaturesTableOrderingComposer,
    $$FeaturesTableAnnotationComposer,
    $$FeaturesTableCreateCompanionBuilder,
    $$FeaturesTableUpdateCompanionBuilder,
    (Feature, BaseReferences<_$AppDatabase, $FeaturesTable, Feature>),
    Feature,
    PrefetchHooks Function()>;
typedef $$FeatureGeometryRevisionsTableCreateCompanionBuilder
    = FeatureGeometryRevisionsCompanion Function({
  required String id,
  required String featureId,
  required String prevGeojson,
  required String newGeojson,
  required String editedBy,
  required DateTime editedAt,
  Value<String?> overrideReason,
  Value<String> syncStatus,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$FeatureGeometryRevisionsTableUpdateCompanionBuilder
    = FeatureGeometryRevisionsCompanion Function({
  Value<String> id,
  Value<String> featureId,
  Value<String> prevGeojson,
  Value<String> newGeojson,
  Value<String> editedBy,
  Value<DateTime> editedAt,
  Value<String?> overrideReason,
  Value<String> syncStatus,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$FeatureGeometryRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $FeatureGeometryRevisionsTable> {
  $$FeatureGeometryRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get featureId => $composableBuilder(
      column: $table.featureId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prevGeojson => $composableBuilder(
      column: $table.prevGeojson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get newGeojson => $composableBuilder(
      column: $table.newGeojson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get editedBy => $composableBuilder(
      column: $table.editedBy, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get editedAt => $composableBuilder(
      column: $table.editedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get overrideReason => $composableBuilder(
      column: $table.overrideReason,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$FeatureGeometryRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FeatureGeometryRevisionsTable> {
  $$FeatureGeometryRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get featureId => $composableBuilder(
      column: $table.featureId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prevGeojson => $composableBuilder(
      column: $table.prevGeojson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get newGeojson => $composableBuilder(
      column: $table.newGeojson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get editedBy => $composableBuilder(
      column: $table.editedBy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get editedAt => $composableBuilder(
      column: $table.editedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get overrideReason => $composableBuilder(
      column: $table.overrideReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$FeatureGeometryRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeatureGeometryRevisionsTable> {
  $$FeatureGeometryRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get featureId =>
      $composableBuilder(column: $table.featureId, builder: (column) => column);

  GeneratedColumn<String> get prevGeojson => $composableBuilder(
      column: $table.prevGeojson, builder: (column) => column);

  GeneratedColumn<String> get newGeojson => $composableBuilder(
      column: $table.newGeojson, builder: (column) => column);

  GeneratedColumn<String> get editedBy =>
      $composableBuilder(column: $table.editedBy, builder: (column) => column);

  GeneratedColumn<DateTime> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);

  GeneratedColumn<String> get overrideReason => $composableBuilder(
      column: $table.overrideReason, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$FeatureGeometryRevisionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FeatureGeometryRevisionsTable,
    FeatureGeometryRevision,
    $$FeatureGeometryRevisionsTableFilterComposer,
    $$FeatureGeometryRevisionsTableOrderingComposer,
    $$FeatureGeometryRevisionsTableAnnotationComposer,
    $$FeatureGeometryRevisionsTableCreateCompanionBuilder,
    $$FeatureGeometryRevisionsTableUpdateCompanionBuilder,
    (
      FeatureGeometryRevision,
      BaseReferences<_$AppDatabase, $FeatureGeometryRevisionsTable,
          FeatureGeometryRevision>
    ),
    FeatureGeometryRevision,
    PrefetchHooks Function()> {
  $$FeatureGeometryRevisionsTableTableManager(
      _$AppDatabase db, $FeatureGeometryRevisionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeatureGeometryRevisionsTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$FeatureGeometryRevisionsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FeatureGeometryRevisionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> featureId = const Value.absent(),
            Value<String> prevGeojson = const Value.absent(),
            Value<String> newGeojson = const Value.absent(),
            Value<String> editedBy = const Value.absent(),
            Value<DateTime> editedAt = const Value.absent(),
            Value<String?> overrideReason = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FeatureGeometryRevisionsCompanion(
            id: id,
            featureId: featureId,
            prevGeojson: prevGeojson,
            newGeojson: newGeojson,
            editedBy: editedBy,
            editedAt: editedAt,
            overrideReason: overrideReason,
            syncStatus: syncStatus,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String featureId,
            required String prevGeojson,
            required String newGeojson,
            required String editedBy,
            required DateTime editedAt,
            Value<String?> overrideReason = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FeatureGeometryRevisionsCompanion.insert(
            id: id,
            featureId: featureId,
            prevGeojson: prevGeojson,
            newGeojson: newGeojson,
            editedBy: editedBy,
            editedAt: editedAt,
            overrideReason: overrideReason,
            syncStatus: syncStatus,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FeatureGeometryRevisionsTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $FeatureGeometryRevisionsTable,
        FeatureGeometryRevision,
        $$FeatureGeometryRevisionsTableFilterComposer,
        $$FeatureGeometryRevisionsTableOrderingComposer,
        $$FeatureGeometryRevisionsTableAnnotationComposer,
        $$FeatureGeometryRevisionsTableCreateCompanionBuilder,
        $$FeatureGeometryRevisionsTableUpdateCompanionBuilder,
        (
          FeatureGeometryRevision,
          BaseReferences<_$AppDatabase, $FeatureGeometryRevisionsTable,
              FeatureGeometryRevision>
        ),
        FeatureGeometryRevision,
        PrefetchHooks Function()>;
typedef $$SubmissionsTableCreateCompanionBuilder = SubmissionsCompanion
    Function({
  required String id,
  required String featureId,
  Value<String?> submittedBy,
  Value<bool> doesNotExist,
  Value<String?> remarks,
  Value<String> syncStatus,
  Value<String?> overrideReason,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$SubmissionsTableUpdateCompanionBuilder = SubmissionsCompanion
    Function({
  Value<String> id,
  Value<String> featureId,
  Value<String?> submittedBy,
  Value<bool> doesNotExist,
  Value<String?> remarks,
  Value<String> syncStatus,
  Value<String?> overrideReason,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$SubmissionsTableFilterComposer
    extends Composer<_$AppDatabase, $SubmissionsTable> {
  $$SubmissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get featureId => $composableBuilder(
      column: $table.featureId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get submittedBy => $composableBuilder(
      column: $table.submittedBy, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get doesNotExist => $composableBuilder(
      column: $table.doesNotExist, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get remarks => $composableBuilder(
      column: $table.remarks, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get overrideReason => $composableBuilder(
      column: $table.overrideReason,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$SubmissionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SubmissionsTable> {
  $$SubmissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get featureId => $composableBuilder(
      column: $table.featureId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get submittedBy => $composableBuilder(
      column: $table.submittedBy, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get doesNotExist => $composableBuilder(
      column: $table.doesNotExist,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get remarks => $composableBuilder(
      column: $table.remarks, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get overrideReason => $composableBuilder(
      column: $table.overrideReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SubmissionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubmissionsTable> {
  $$SubmissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get featureId =>
      $composableBuilder(column: $table.featureId, builder: (column) => column);

  GeneratedColumn<String> get submittedBy => $composableBuilder(
      column: $table.submittedBy, builder: (column) => column);

  GeneratedColumn<bool> get doesNotExist => $composableBuilder(
      column: $table.doesNotExist, builder: (column) => column);

  GeneratedColumn<String> get remarks =>
      $composableBuilder(column: $table.remarks, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
      column: $table.syncStatus, builder: (column) => column);

  GeneratedColumn<String> get overrideReason => $composableBuilder(
      column: $table.overrideReason, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SubmissionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SubmissionsTable,
    Submission,
    $$SubmissionsTableFilterComposer,
    $$SubmissionsTableOrderingComposer,
    $$SubmissionsTableAnnotationComposer,
    $$SubmissionsTableCreateCompanionBuilder,
    $$SubmissionsTableUpdateCompanionBuilder,
    (Submission, BaseReferences<_$AppDatabase, $SubmissionsTable, Submission>),
    Submission,
    PrefetchHooks Function()> {
  $$SubmissionsTableTableManager(_$AppDatabase db, $SubmissionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubmissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubmissionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubmissionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> featureId = const Value.absent(),
            Value<String?> submittedBy = const Value.absent(),
            Value<bool> doesNotExist = const Value.absent(),
            Value<String?> remarks = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<String?> overrideReason = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SubmissionsCompanion(
            id: id,
            featureId: featureId,
            submittedBy: submittedBy,
            doesNotExist: doesNotExist,
            remarks: remarks,
            syncStatus: syncStatus,
            overrideReason: overrideReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String featureId,
            Value<String?> submittedBy = const Value.absent(),
            Value<bool> doesNotExist = const Value.absent(),
            Value<String?> remarks = const Value.absent(),
            Value<String> syncStatus = const Value.absent(),
            Value<String?> overrideReason = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SubmissionsCompanion.insert(
            id: id,
            featureId: featureId,
            submittedBy: submittedBy,
            doesNotExist: doesNotExist,
            remarks: remarks,
            syncStatus: syncStatus,
            overrideReason: overrideReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SubmissionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SubmissionsTable,
    Submission,
    $$SubmissionsTableFilterComposer,
    $$SubmissionsTableOrderingComposer,
    $$SubmissionsTableAnnotationComposer,
    $$SubmissionsTableCreateCompanionBuilder,
    $$SubmissionsTableUpdateCompanionBuilder,
    (Submission, BaseReferences<_$AppDatabase, $SubmissionsTable, Submission>),
    Submission,
    PrefetchHooks Function()>;
typedef $$BuildingAttributesTableCreateCompanionBuilder
    = BuildingAttributesCompanion Function({
  required String submissionId,
  Value<String?> cbmsId,
  Value<String?> buildingName,
  Value<String?> ra9514Type,
  Value<int?> storeys,
  Value<String?> material,
  Value<bool> costIsExact,
  Value<double?> costAmount,
  Value<String?> costEstimateRange,
  Value<String> fireFightingFacilitiesJson,
  Value<String> fireLoadJson,
  Value<int> rowid,
});
typedef $$BuildingAttributesTableUpdateCompanionBuilder
    = BuildingAttributesCompanion Function({
  Value<String> submissionId,
  Value<String?> cbmsId,
  Value<String?> buildingName,
  Value<String?> ra9514Type,
  Value<int?> storeys,
  Value<String?> material,
  Value<bool> costIsExact,
  Value<double?> costAmount,
  Value<String?> costEstimateRange,
  Value<String> fireFightingFacilitiesJson,
  Value<String> fireLoadJson,
  Value<int> rowid,
});

class $$BuildingAttributesTableFilterComposer
    extends Composer<_$AppDatabase, $BuildingAttributesTable> {
  $$BuildingAttributesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cbmsId => $composableBuilder(
      column: $table.cbmsId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get buildingName => $composableBuilder(
      column: $table.buildingName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ra9514Type => $composableBuilder(
      column: $table.ra9514Type, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get storeys => $composableBuilder(
      column: $table.storeys, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get material => $composableBuilder(
      column: $table.material, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get costIsExact => $composableBuilder(
      column: $table.costIsExact, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get costAmount => $composableBuilder(
      column: $table.costAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get costEstimateRange => $composableBuilder(
      column: $table.costEstimateRange,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fireFightingFacilitiesJson => $composableBuilder(
      column: $table.fireFightingFacilitiesJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fireLoadJson => $composableBuilder(
      column: $table.fireLoadJson, builder: (column) => ColumnFilters(column));
}

class $$BuildingAttributesTableOrderingComposer
    extends Composer<_$AppDatabase, $BuildingAttributesTable> {
  $$BuildingAttributesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get submissionId => $composableBuilder(
      column: $table.submissionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cbmsId => $composableBuilder(
      column: $table.cbmsId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get buildingName => $composableBuilder(
      column: $table.buildingName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ra9514Type => $composableBuilder(
      column: $table.ra9514Type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get storeys => $composableBuilder(
      column: $table.storeys, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get material => $composableBuilder(
      column: $table.material, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get costIsExact => $composableBuilder(
      column: $table.costIsExact, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get costAmount => $composableBuilder(
      column: $table.costAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get costEstimateRange => $composableBuilder(
      column: $table.costEstimateRange,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fireFightingFacilitiesJson => $composableBuilder(
      column: $table.fireFightingFacilitiesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fireLoadJson => $composableBuilder(
      column: $table.fireLoadJson,
      builder: (column) => ColumnOrderings(column));
}

class $$BuildingAttributesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BuildingAttributesTable> {
  $$BuildingAttributesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => column);

  GeneratedColumn<String> get cbmsId =>
      $composableBuilder(column: $table.cbmsId, builder: (column) => column);

  GeneratedColumn<String> get buildingName => $composableBuilder(
      column: $table.buildingName, builder: (column) => column);

  GeneratedColumn<String> get ra9514Type => $composableBuilder(
      column: $table.ra9514Type, builder: (column) => column);

  GeneratedColumn<int> get storeys =>
      $composableBuilder(column: $table.storeys, builder: (column) => column);

  GeneratedColumn<String> get material =>
      $composableBuilder(column: $table.material, builder: (column) => column);

  GeneratedColumn<bool> get costIsExact => $composableBuilder(
      column: $table.costIsExact, builder: (column) => column);

  GeneratedColumn<double> get costAmount => $composableBuilder(
      column: $table.costAmount, builder: (column) => column);

  GeneratedColumn<String> get costEstimateRange => $composableBuilder(
      column: $table.costEstimateRange, builder: (column) => column);

  GeneratedColumn<String> get fireFightingFacilitiesJson => $composableBuilder(
      column: $table.fireFightingFacilitiesJson, builder: (column) => column);

  GeneratedColumn<String> get fireLoadJson => $composableBuilder(
      column: $table.fireLoadJson, builder: (column) => column);
}

class $$BuildingAttributesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BuildingAttributesTable,
    BuildingAttribute,
    $$BuildingAttributesTableFilterComposer,
    $$BuildingAttributesTableOrderingComposer,
    $$BuildingAttributesTableAnnotationComposer,
    $$BuildingAttributesTableCreateCompanionBuilder,
    $$BuildingAttributesTableUpdateCompanionBuilder,
    (
      BuildingAttribute,
      BaseReferences<_$AppDatabase, $BuildingAttributesTable, BuildingAttribute>
    ),
    BuildingAttribute,
    PrefetchHooks Function()> {
  $$BuildingAttributesTableTableManager(
      _$AppDatabase db, $BuildingAttributesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BuildingAttributesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BuildingAttributesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BuildingAttributesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> submissionId = const Value.absent(),
            Value<String?> cbmsId = const Value.absent(),
            Value<String?> buildingName = const Value.absent(),
            Value<String?> ra9514Type = const Value.absent(),
            Value<int?> storeys = const Value.absent(),
            Value<String?> material = const Value.absent(),
            Value<bool> costIsExact = const Value.absent(),
            Value<double?> costAmount = const Value.absent(),
            Value<String?> costEstimateRange = const Value.absent(),
            Value<String> fireFightingFacilitiesJson = const Value.absent(),
            Value<String> fireLoadJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BuildingAttributesCompanion(
            submissionId: submissionId,
            cbmsId: cbmsId,
            buildingName: buildingName,
            ra9514Type: ra9514Type,
            storeys: storeys,
            material: material,
            costIsExact: costIsExact,
            costAmount: costAmount,
            costEstimateRange: costEstimateRange,
            fireFightingFacilitiesJson: fireFightingFacilitiesJson,
            fireLoadJson: fireLoadJson,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String submissionId,
            Value<String?> cbmsId = const Value.absent(),
            Value<String?> buildingName = const Value.absent(),
            Value<String?> ra9514Type = const Value.absent(),
            Value<int?> storeys = const Value.absent(),
            Value<String?> material = const Value.absent(),
            Value<bool> costIsExact = const Value.absent(),
            Value<double?> costAmount = const Value.absent(),
            Value<String?> costEstimateRange = const Value.absent(),
            Value<String> fireFightingFacilitiesJson = const Value.absent(),
            Value<String> fireLoadJson = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              BuildingAttributesCompanion.insert(
            submissionId: submissionId,
            cbmsId: cbmsId,
            buildingName: buildingName,
            ra9514Type: ra9514Type,
            storeys: storeys,
            material: material,
            costIsExact: costIsExact,
            costAmount: costAmount,
            costEstimateRange: costEstimateRange,
            fireFightingFacilitiesJson: fireFightingFacilitiesJson,
            fireLoadJson: fireLoadJson,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BuildingAttributesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BuildingAttributesTable,
    BuildingAttribute,
    $$BuildingAttributesTableFilterComposer,
    $$BuildingAttributesTableOrderingComposer,
    $$BuildingAttributesTableAnnotationComposer,
    $$BuildingAttributesTableCreateCompanionBuilder,
    $$BuildingAttributesTableUpdateCompanionBuilder,
    (
      BuildingAttribute,
      BaseReferences<_$AppDatabase, $BuildingAttributesTable, BuildingAttribute>
    ),
    BuildingAttribute,
    PrefetchHooks Function()>;
typedef $$RoadAttributesTableCreateCompanionBuilder = RoadAttributesCompanion
    Function({
  required String submissionId,
  Value<bool> isBridge,
  Value<String?> roadName,
  Value<double?> widthMeters,
  Value<String> roadFeaturesJson,
  Value<String?> othersDescription,
  Value<int> rowid,
});
typedef $$RoadAttributesTableUpdateCompanionBuilder = RoadAttributesCompanion
    Function({
  Value<String> submissionId,
  Value<bool> isBridge,
  Value<String?> roadName,
  Value<double?> widthMeters,
  Value<String> roadFeaturesJson,
  Value<String?> othersDescription,
  Value<int> rowid,
});

class $$RoadAttributesTableFilterComposer
    extends Composer<_$AppDatabase, $RoadAttributesTable> {
  $$RoadAttributesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBridge => $composableBuilder(
      column: $table.isBridge, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get roadName => $composableBuilder(
      column: $table.roadName, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get widthMeters => $composableBuilder(
      column: $table.widthMeters, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get roadFeaturesJson => $composableBuilder(
      column: $table.roadFeaturesJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get othersDescription => $composableBuilder(
      column: $table.othersDescription,
      builder: (column) => ColumnFilters(column));
}

class $$RoadAttributesTableOrderingComposer
    extends Composer<_$AppDatabase, $RoadAttributesTable> {
  $$RoadAttributesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get submissionId => $composableBuilder(
      column: $table.submissionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBridge => $composableBuilder(
      column: $table.isBridge, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get roadName => $composableBuilder(
      column: $table.roadName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get widthMeters => $composableBuilder(
      column: $table.widthMeters, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get roadFeaturesJson => $composableBuilder(
      column: $table.roadFeaturesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get othersDescription => $composableBuilder(
      column: $table.othersDescription,
      builder: (column) => ColumnOrderings(column));
}

class $$RoadAttributesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoadAttributesTable> {
  $$RoadAttributesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => column);

  GeneratedColumn<bool> get isBridge =>
      $composableBuilder(column: $table.isBridge, builder: (column) => column);

  GeneratedColumn<String> get roadName =>
      $composableBuilder(column: $table.roadName, builder: (column) => column);

  GeneratedColumn<double> get widthMeters => $composableBuilder(
      column: $table.widthMeters, builder: (column) => column);

  GeneratedColumn<String> get roadFeaturesJson => $composableBuilder(
      column: $table.roadFeaturesJson, builder: (column) => column);

  GeneratedColumn<String> get othersDescription => $composableBuilder(
      column: $table.othersDescription, builder: (column) => column);
}

class $$RoadAttributesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RoadAttributesTable,
    RoadAttribute,
    $$RoadAttributesTableFilterComposer,
    $$RoadAttributesTableOrderingComposer,
    $$RoadAttributesTableAnnotationComposer,
    $$RoadAttributesTableCreateCompanionBuilder,
    $$RoadAttributesTableUpdateCompanionBuilder,
    (
      RoadAttribute,
      BaseReferences<_$AppDatabase, $RoadAttributesTable, RoadAttribute>
    ),
    RoadAttribute,
    PrefetchHooks Function()> {
  $$RoadAttributesTableTableManager(
      _$AppDatabase db, $RoadAttributesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoadAttributesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoadAttributesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoadAttributesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> submissionId = const Value.absent(),
            Value<bool> isBridge = const Value.absent(),
            Value<String?> roadName = const Value.absent(),
            Value<double?> widthMeters = const Value.absent(),
            Value<String> roadFeaturesJson = const Value.absent(),
            Value<String?> othersDescription = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RoadAttributesCompanion(
            submissionId: submissionId,
            isBridge: isBridge,
            roadName: roadName,
            widthMeters: widthMeters,
            roadFeaturesJson: roadFeaturesJson,
            othersDescription: othersDescription,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String submissionId,
            Value<bool> isBridge = const Value.absent(),
            Value<String?> roadName = const Value.absent(),
            Value<double?> widthMeters = const Value.absent(),
            Value<String> roadFeaturesJson = const Value.absent(),
            Value<String?> othersDescription = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RoadAttributesCompanion.insert(
            submissionId: submissionId,
            isBridge: isBridge,
            roadName: roadName,
            widthMeters: widthMeters,
            roadFeaturesJson: roadFeaturesJson,
            othersDescription: othersDescription,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$RoadAttributesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RoadAttributesTable,
    RoadAttribute,
    $$RoadAttributesTableFilterComposer,
    $$RoadAttributesTableOrderingComposer,
    $$RoadAttributesTableAnnotationComposer,
    $$RoadAttributesTableCreateCompanionBuilder,
    $$RoadAttributesTableUpdateCompanionBuilder,
    (
      RoadAttribute,
      BaseReferences<_$AppDatabase, $RoadAttributesTable, RoadAttribute>
    ),
    RoadAttribute,
    PrefetchHooks Function()>;
typedef $$HouseholdSurveysTableCreateCompanionBuilder
    = HouseholdSurveysCompanion Function({
  required String submissionId,
  Value<String> constructionDetailsJson,
  Value<String> kaayusanJson,
  Value<String> koneksyongElektrikalJson,
  Value<String> kusinaJson,
  Value<String> daananOLabasanJson,
  Value<String?> lebelNgKahinaan,
  Value<String?> safetySuggestions,
  Value<bool> homeownerAcknowledged,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});
typedef $$HouseholdSurveysTableUpdateCompanionBuilder
    = HouseholdSurveysCompanion Function({
  Value<String> submissionId,
  Value<String> constructionDetailsJson,
  Value<String> kaayusanJson,
  Value<String> koneksyongElektrikalJson,
  Value<String> kusinaJson,
  Value<String> daananOLabasanJson,
  Value<String?> lebelNgKahinaan,
  Value<String?> safetySuggestions,
  Value<bool> homeownerAcknowledged,
  Value<DateTime?> completedAt,
  Value<int> rowid,
});

class $$HouseholdSurveysTableFilterComposer
    extends Composer<_$AppDatabase, $HouseholdSurveysTable> {
  $$HouseholdSurveysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get constructionDetailsJson => $composableBuilder(
      column: $table.constructionDetailsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kaayusanJson => $composableBuilder(
      column: $table.kaayusanJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get koneksyongElektrikalJson => $composableBuilder(
      column: $table.koneksyongElektrikalJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get kusinaJson => $composableBuilder(
      column: $table.kusinaJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get daananOLabasanJson => $composableBuilder(
      column: $table.daananOLabasanJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lebelNgKahinaan => $composableBuilder(
      column: $table.lebelNgKahinaan,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get safetySuggestions => $composableBuilder(
      column: $table.safetySuggestions,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get homeownerAcknowledged => $composableBuilder(
      column: $table.homeownerAcknowledged,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));
}

class $$HouseholdSurveysTableOrderingComposer
    extends Composer<_$AppDatabase, $HouseholdSurveysTable> {
  $$HouseholdSurveysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get submissionId => $composableBuilder(
      column: $table.submissionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get constructionDetailsJson => $composableBuilder(
      column: $table.constructionDetailsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kaayusanJson => $composableBuilder(
      column: $table.kaayusanJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get koneksyongElektrikalJson => $composableBuilder(
      column: $table.koneksyongElektrikalJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get kusinaJson => $composableBuilder(
      column: $table.kusinaJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get daananOLabasanJson => $composableBuilder(
      column: $table.daananOLabasanJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lebelNgKahinaan => $composableBuilder(
      column: $table.lebelNgKahinaan,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get safetySuggestions => $composableBuilder(
      column: $table.safetySuggestions,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get homeownerAcknowledged => $composableBuilder(
      column: $table.homeownerAcknowledged,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));
}

class $$HouseholdSurveysTableAnnotationComposer
    extends Composer<_$AppDatabase, $HouseholdSurveysTable> {
  $$HouseholdSurveysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => column);

  GeneratedColumn<String> get constructionDetailsJson => $composableBuilder(
      column: $table.constructionDetailsJson, builder: (column) => column);

  GeneratedColumn<String> get kaayusanJson => $composableBuilder(
      column: $table.kaayusanJson, builder: (column) => column);

  GeneratedColumn<String> get koneksyongElektrikalJson => $composableBuilder(
      column: $table.koneksyongElektrikalJson, builder: (column) => column);

  GeneratedColumn<String> get kusinaJson => $composableBuilder(
      column: $table.kusinaJson, builder: (column) => column);

  GeneratedColumn<String> get daananOLabasanJson => $composableBuilder(
      column: $table.daananOLabasanJson, builder: (column) => column);

  GeneratedColumn<String> get lebelNgKahinaan => $composableBuilder(
      column: $table.lebelNgKahinaan, builder: (column) => column);

  GeneratedColumn<String> get safetySuggestions => $composableBuilder(
      column: $table.safetySuggestions, builder: (column) => column);

  GeneratedColumn<bool> get homeownerAcknowledged => $composableBuilder(
      column: $table.homeownerAcknowledged, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);
}

class $$HouseholdSurveysTableTableManager extends RootTableManager<
    _$AppDatabase,
    $HouseholdSurveysTable,
    HouseholdSurvey,
    $$HouseholdSurveysTableFilterComposer,
    $$HouseholdSurveysTableOrderingComposer,
    $$HouseholdSurveysTableAnnotationComposer,
    $$HouseholdSurveysTableCreateCompanionBuilder,
    $$HouseholdSurveysTableUpdateCompanionBuilder,
    (
      HouseholdSurvey,
      BaseReferences<_$AppDatabase, $HouseholdSurveysTable, HouseholdSurvey>
    ),
    HouseholdSurvey,
    PrefetchHooks Function()> {
  $$HouseholdSurveysTableTableManager(
      _$AppDatabase db, $HouseholdSurveysTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HouseholdSurveysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HouseholdSurveysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HouseholdSurveysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> submissionId = const Value.absent(),
            Value<String> constructionDetailsJson = const Value.absent(),
            Value<String> kaayusanJson = const Value.absent(),
            Value<String> koneksyongElektrikalJson = const Value.absent(),
            Value<String> kusinaJson = const Value.absent(),
            Value<String> daananOLabasanJson = const Value.absent(),
            Value<String?> lebelNgKahinaan = const Value.absent(),
            Value<String?> safetySuggestions = const Value.absent(),
            Value<bool> homeownerAcknowledged = const Value.absent(),
            Value<DateTime?> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HouseholdSurveysCompanion(
            submissionId: submissionId,
            constructionDetailsJson: constructionDetailsJson,
            kaayusanJson: kaayusanJson,
            koneksyongElektrikalJson: koneksyongElektrikalJson,
            kusinaJson: kusinaJson,
            daananOLabasanJson: daananOLabasanJson,
            lebelNgKahinaan: lebelNgKahinaan,
            safetySuggestions: safetySuggestions,
            homeownerAcknowledged: homeownerAcknowledged,
            completedAt: completedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String submissionId,
            Value<String> constructionDetailsJson = const Value.absent(),
            Value<String> kaayusanJson = const Value.absent(),
            Value<String> koneksyongElektrikalJson = const Value.absent(),
            Value<String> kusinaJson = const Value.absent(),
            Value<String> daananOLabasanJson = const Value.absent(),
            Value<String?> lebelNgKahinaan = const Value.absent(),
            Value<String?> safetySuggestions = const Value.absent(),
            Value<bool> homeownerAcknowledged = const Value.absent(),
            Value<DateTime?> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HouseholdSurveysCompanion.insert(
            submissionId: submissionId,
            constructionDetailsJson: constructionDetailsJson,
            kaayusanJson: kaayusanJson,
            koneksyongElektrikalJson: koneksyongElektrikalJson,
            kusinaJson: kusinaJson,
            daananOLabasanJson: daananOLabasanJson,
            lebelNgKahinaan: lebelNgKahinaan,
            safetySuggestions: safetySuggestions,
            homeownerAcknowledged: homeownerAcknowledged,
            completedAt: completedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HouseholdSurveysTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $HouseholdSurveysTable,
    HouseholdSurvey,
    $$HouseholdSurveysTableFilterComposer,
    $$HouseholdSurveysTableOrderingComposer,
    $$HouseholdSurveysTableAnnotationComposer,
    $$HouseholdSurveysTableCreateCompanionBuilder,
    $$HouseholdSurveysTableUpdateCompanionBuilder,
    (
      HouseholdSurvey,
      BaseReferences<_$AppDatabase, $HouseholdSurveysTable, HouseholdSurvey>
    ),
    HouseholdSurvey,
    PrefetchHooks Function()>;
typedef $$PhotosTableCreateCompanionBuilder = PhotosCompanion Function({
  required String id,
  required String submissionId,
  required String localPath,
  Value<String?> storagePath,
  required DateTime capturedAt,
  Value<double?> gpsLat,
  Value<double?> gpsLng,
  Value<String> uploadStatus,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$PhotosTableUpdateCompanionBuilder = PhotosCompanion Function({
  Value<String> id,
  Value<String> submissionId,
  Value<String> localPath,
  Value<String?> storagePath,
  Value<DateTime> capturedAt,
  Value<double?> gpsLat,
  Value<double?> gpsLng,
  Value<String> uploadStatus,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$PhotosTableFilterComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get storagePath => $composableBuilder(
      column: $table.storagePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get gpsLat => $composableBuilder(
      column: $table.gpsLat, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get gpsLng => $composableBuilder(
      column: $table.gpsLng, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uploadStatus => $composableBuilder(
      column: $table.uploadStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$PhotosTableOrderingComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get submissionId => $composableBuilder(
      column: $table.submissionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get storagePath => $composableBuilder(
      column: $table.storagePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get gpsLat => $composableBuilder(
      column: $table.gpsLat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get gpsLng => $composableBuilder(
      column: $table.gpsLng, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uploadStatus => $composableBuilder(
      column: $table.uploadStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$PhotosTableAnnotationComposer
    extends Composer<_$AppDatabase, $PhotosTable> {
  $$PhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get submissionId => $composableBuilder(
      column: $table.submissionId, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get storagePath => $composableBuilder(
      column: $table.storagePath, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => column);

  GeneratedColumn<double> get gpsLat =>
      $composableBuilder(column: $table.gpsLat, builder: (column) => column);

  GeneratedColumn<double> get gpsLng =>
      $composableBuilder(column: $table.gpsLng, builder: (column) => column);

  GeneratedColumn<String> get uploadStatus => $composableBuilder(
      column: $table.uploadStatus, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$PhotosTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PhotosTable,
    Photo,
    $$PhotosTableFilterComposer,
    $$PhotosTableOrderingComposer,
    $$PhotosTableAnnotationComposer,
    $$PhotosTableCreateCompanionBuilder,
    $$PhotosTableUpdateCompanionBuilder,
    (Photo, BaseReferences<_$AppDatabase, $PhotosTable, Photo>),
    Photo,
    PrefetchHooks Function()> {
  $$PhotosTableTableManager(_$AppDatabase db, $PhotosTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> submissionId = const Value.absent(),
            Value<String> localPath = const Value.absent(),
            Value<String?> storagePath = const Value.absent(),
            Value<DateTime> capturedAt = const Value.absent(),
            Value<double?> gpsLat = const Value.absent(),
            Value<double?> gpsLng = const Value.absent(),
            Value<String> uploadStatus = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PhotosCompanion(
            id: id,
            submissionId: submissionId,
            localPath: localPath,
            storagePath: storagePath,
            capturedAt: capturedAt,
            gpsLat: gpsLat,
            gpsLng: gpsLng,
            uploadStatus: uploadStatus,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String submissionId,
            required String localPath,
            Value<String?> storagePath = const Value.absent(),
            required DateTime capturedAt,
            Value<double?> gpsLat = const Value.absent(),
            Value<double?> gpsLng = const Value.absent(),
            Value<String> uploadStatus = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PhotosCompanion.insert(
            id: id,
            submissionId: submissionId,
            localPath: localPath,
            storagePath: storagePath,
            capturedAt: capturedAt,
            gpsLat: gpsLat,
            gpsLng: gpsLng,
            uploadStatus: uploadStatus,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PhotosTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PhotosTable,
    Photo,
    $$PhotosTableFilterComposer,
    $$PhotosTableOrderingComposer,
    $$PhotosTableAnnotationComposer,
    $$PhotosTableCreateCompanionBuilder,
    $$PhotosTableUpdateCompanionBuilder,
    (Photo, BaseReferences<_$AppDatabase, $PhotosTable, Photo>),
    Photo,
    PrefetchHooks Function()>;
typedef $$Ra9514TypesTableCreateCompanionBuilder = Ra9514TypesCompanion
    Function({
  required String code,
  required String labelEn,
  required String labelTl,
  Value<int> sortOrder,
  Value<int> rowid,
});
typedef $$Ra9514TypesTableUpdateCompanionBuilder = Ra9514TypesCompanion
    Function({
  Value<String> code,
  Value<String> labelEn,
  Value<String> labelTl,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$Ra9514TypesTableFilterComposer
    extends Composer<_$AppDatabase, $Ra9514TypesTable> {
  $$Ra9514TypesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get labelEn => $composableBuilder(
      column: $table.labelEn, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get labelTl => $composableBuilder(
      column: $table.labelTl, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));
}

class $$Ra9514TypesTableOrderingComposer
    extends Composer<_$AppDatabase, $Ra9514TypesTable> {
  $$Ra9514TypesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
      column: $table.code, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get labelEn => $composableBuilder(
      column: $table.labelEn, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get labelTl => $composableBuilder(
      column: $table.labelTl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));
}

class $$Ra9514TypesTableAnnotationComposer
    extends Composer<_$AppDatabase, $Ra9514TypesTable> {
  $$Ra9514TypesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get labelEn =>
      $composableBuilder(column: $table.labelEn, builder: (column) => column);

  GeneratedColumn<String> get labelTl =>
      $composableBuilder(column: $table.labelTl, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$Ra9514TypesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $Ra9514TypesTable,
    Ra9514Type,
    $$Ra9514TypesTableFilterComposer,
    $$Ra9514TypesTableOrderingComposer,
    $$Ra9514TypesTableAnnotationComposer,
    $$Ra9514TypesTableCreateCompanionBuilder,
    $$Ra9514TypesTableUpdateCompanionBuilder,
    (Ra9514Type, BaseReferences<_$AppDatabase, $Ra9514TypesTable, Ra9514Type>),
    Ra9514Type,
    PrefetchHooks Function()> {
  $$Ra9514TypesTableTableManager(_$AppDatabase db, $Ra9514TypesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Ra9514TypesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Ra9514TypesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Ra9514TypesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> code = const Value.absent(),
            Value<String> labelEn = const Value.absent(),
            Value<String> labelTl = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              Ra9514TypesCompanion(
            code: code,
            labelEn: labelEn,
            labelTl: labelTl,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String code,
            required String labelEn,
            required String labelTl,
            Value<int> sortOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              Ra9514TypesCompanion.insert(
            code: code,
            labelEn: labelEn,
            labelTl: labelTl,
            sortOrder: sortOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$Ra9514TypesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $Ra9514TypesTable,
    Ra9514Type,
    $$Ra9514TypesTableFilterComposer,
    $$Ra9514TypesTableOrderingComposer,
    $$Ra9514TypesTableAnnotationComposer,
    $$Ra9514TypesTableCreateCompanionBuilder,
    $$Ra9514TypesTableUpdateCompanionBuilder,
    (Ra9514Type, BaseReferences<_$AppDatabase, $Ra9514TypesTable, Ra9514Type>),
    Ra9514Type,
    PrefetchHooks Function()>;
typedef $$SyncJobsTableCreateCompanionBuilder = SyncJobsCompanion Function({
  required String id,
  required String entityType,
  required String entityId,
  Value<String> status,
  Value<String?> blocksOnSubmissionId,
  Value<int> attempts,
  Value<String?> lastError,
  Value<DateTime?> nextRetryAt,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$SyncJobsTableUpdateCompanionBuilder = SyncJobsCompanion Function({
  Value<String> id,
  Value<String> entityType,
  Value<String> entityId,
  Value<String> status,
  Value<String?> blocksOnSubmissionId,
  Value<int> attempts,
  Value<String?> lastError,
  Value<DateTime?> nextRetryAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$SyncJobsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncJobsTable> {
  $$SyncJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get blocksOnSubmissionId => $composableBuilder(
      column: $table.blocksOnSubmissionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$SyncJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncJobsTable> {
  $$SyncJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entityId => $composableBuilder(
      column: $table.entityId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get blocksOnSubmissionId => $composableBuilder(
      column: $table.blocksOnSubmissionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncJobsTable> {
  $$SyncJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
      column: $table.entityType, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get blocksOnSubmissionId => $composableBuilder(
      column: $table.blocksOnSubmissionId, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncJobsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncJobsTable,
    SyncJob,
    $$SyncJobsTableFilterComposer,
    $$SyncJobsTableOrderingComposer,
    $$SyncJobsTableAnnotationComposer,
    $$SyncJobsTableCreateCompanionBuilder,
    $$SyncJobsTableUpdateCompanionBuilder,
    (SyncJob, BaseReferences<_$AppDatabase, $SyncJobsTable, SyncJob>),
    SyncJob,
    PrefetchHooks Function()> {
  $$SyncJobsTableTableManager(_$AppDatabase db, $SyncJobsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> entityType = const Value.absent(),
            Value<String> entityId = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> blocksOnSubmissionId = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncJobsCompanion(
            id: id,
            entityType: entityType,
            entityId: entityId,
            status: status,
            blocksOnSubmissionId: blocksOnSubmissionId,
            attempts: attempts,
            lastError: lastError,
            nextRetryAt: nextRetryAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String entityType,
            required String entityId,
            Value<String> status = const Value.absent(),
            Value<String?> blocksOnSubmissionId = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncJobsCompanion.insert(
            id: id,
            entityType: entityType,
            entityId: entityId,
            status: status,
            blocksOnSubmissionId: blocksOnSubmissionId,
            attempts: attempts,
            lastError: lastError,
            nextRetryAt: nextRetryAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncJobsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncJobsTable,
    SyncJob,
    $$SyncJobsTableFilterComposer,
    $$SyncJobsTableOrderingComposer,
    $$SyncJobsTableAnnotationComposer,
    $$SyncJobsTableCreateCompanionBuilder,
    $$SyncJobsTableUpdateCompanionBuilder,
    (SyncJob, BaseReferences<_$AppDatabase, $SyncJobsTable, SyncJob>),
    SyncJob,
    PrefetchHooks Function()>;
typedef $$OfflineTilePacksTableCreateCompanionBuilder
    = OfflineTilePacksCompanion Function({
  required String id,
  required String assignmentId,
  Value<String?> mapboxPackId,
  required String regionBoundsGeojson,
  Value<int> downloadedBytes,
  Value<int> totalBytes,
  Value<String> status,
  Value<int> rowid,
});
typedef $$OfflineTilePacksTableUpdateCompanionBuilder
    = OfflineTilePacksCompanion Function({
  Value<String> id,
  Value<String> assignmentId,
  Value<String?> mapboxPackId,
  Value<String> regionBoundsGeojson,
  Value<int> downloadedBytes,
  Value<int> totalBytes,
  Value<String> status,
  Value<int> rowid,
});

class $$OfflineTilePacksTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineTilePacksTable> {
  $$OfflineTilePacksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mapboxPackId => $composableBuilder(
      column: $table.mapboxPackId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get regionBoundsGeojson => $composableBuilder(
      column: $table.regionBoundsGeojson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get downloadedBytes => $composableBuilder(
      column: $table.downloadedBytes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalBytes => $composableBuilder(
      column: $table.totalBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));
}

class $$OfflineTilePacksTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineTilePacksTable> {
  $$OfflineTilePacksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mapboxPackId => $composableBuilder(
      column: $table.mapboxPackId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get regionBoundsGeojson => $composableBuilder(
      column: $table.regionBoundsGeojson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get downloadedBytes => $composableBuilder(
      column: $table.downloadedBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalBytes => $composableBuilder(
      column: $table.totalBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$OfflineTilePacksTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineTilePacksTable> {
  $$OfflineTilePacksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId, builder: (column) => column);

  GeneratedColumn<String> get mapboxPackId => $composableBuilder(
      column: $table.mapboxPackId, builder: (column) => column);

  GeneratedColumn<String> get regionBoundsGeojson => $composableBuilder(
      column: $table.regionBoundsGeojson, builder: (column) => column);

  GeneratedColumn<int> get downloadedBytes => $composableBuilder(
      column: $table.downloadedBytes, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
      column: $table.totalBytes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$OfflineTilePacksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OfflineTilePacksTable,
    OfflineTilePack,
    $$OfflineTilePacksTableFilterComposer,
    $$OfflineTilePacksTableOrderingComposer,
    $$OfflineTilePacksTableAnnotationComposer,
    $$OfflineTilePacksTableCreateCompanionBuilder,
    $$OfflineTilePacksTableUpdateCompanionBuilder,
    (
      OfflineTilePack,
      BaseReferences<_$AppDatabase, $OfflineTilePacksTable, OfflineTilePack>
    ),
    OfflineTilePack,
    PrefetchHooks Function()> {
  $$OfflineTilePacksTableTableManager(
      _$AppDatabase db, $OfflineTilePacksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineTilePacksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineTilePacksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineTilePacksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> assignmentId = const Value.absent(),
            Value<String?> mapboxPackId = const Value.absent(),
            Value<String> regionBoundsGeojson = const Value.absent(),
            Value<int> downloadedBytes = const Value.absent(),
            Value<int> totalBytes = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OfflineTilePacksCompanion(
            id: id,
            assignmentId: assignmentId,
            mapboxPackId: mapboxPackId,
            regionBoundsGeojson: regionBoundsGeojson,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            status: status,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String assignmentId,
            Value<String?> mapboxPackId = const Value.absent(),
            required String regionBoundsGeojson,
            Value<int> downloadedBytes = const Value.absent(),
            Value<int> totalBytes = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OfflineTilePacksCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            mapboxPackId: mapboxPackId,
            regionBoundsGeojson: regionBoundsGeojson,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            status: status,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OfflineTilePacksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OfflineTilePacksTable,
    OfflineTilePack,
    $$OfflineTilePacksTableFilterComposer,
    $$OfflineTilePacksTableOrderingComposer,
    $$OfflineTilePacksTableAnnotationComposer,
    $$OfflineTilePacksTableCreateCompanionBuilder,
    $$OfflineTilePacksTableUpdateCompanionBuilder,
    (
      OfflineTilePack,
      BaseReferences<_$AppDatabase, $OfflineTilePacksTable, OfflineTilePack>
    ),
    OfflineTilePack,
    PrefetchHooks Function()>;
typedef $$DriveUploadJobsTableCreateCompanionBuilder = DriveUploadJobsCompanion
    Function({
  required String id,
  required String assignmentId,
  required String filePath,
  required String fileType,
  required String fileName,
  required int fileSizeBytes,
  required DateTime capturedAt,
  Value<String> status,
  Value<String?> resumableUri,
  Value<String?> driveFileId,
  Value<int> retryCount,
  Value<String?> failureReason,
  Value<DateTime?> nextRetryAt,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$DriveUploadJobsTableUpdateCompanionBuilder = DriveUploadJobsCompanion
    Function({
  Value<String> id,
  Value<String> assignmentId,
  Value<String> filePath,
  Value<String> fileType,
  Value<String> fileName,
  Value<int> fileSizeBytes,
  Value<DateTime> capturedAt,
  Value<String> status,
  Value<String?> resumableUri,
  Value<String?> driveFileId,
  Value<int> retryCount,
  Value<String?> failureReason,
  Value<DateTime?> nextRetryAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$DriveUploadJobsTableFilterComposer
    extends Composer<_$AppDatabase, $DriveUploadJobsTable> {
  $$DriveUploadJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileType => $composableBuilder(
      column: $table.fileType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resumableUri => $composableBuilder(
      column: $table.resumableUri, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get driveFileId => $composableBuilder(
      column: $table.driveFileId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get failureReason => $composableBuilder(
      column: $table.failureReason, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$DriveUploadJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $DriveUploadJobsTable> {
  $$DriveUploadJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileType => $composableBuilder(
      column: $table.fileType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resumableUri => $composableBuilder(
      column: $table.resumableUri,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get driveFileId => $composableBuilder(
      column: $table.driveFileId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get failureReason => $composableBuilder(
      column: $table.failureReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$DriveUploadJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DriveUploadJobsTable> {
  $$DriveUploadJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get assignmentId => $composableBuilder(
      column: $table.assignmentId, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get fileType =>
      $composableBuilder(column: $table.fileType, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
      column: $table.fileSizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get resumableUri => $composableBuilder(
      column: $table.resumableUri, builder: (column) => column);

  GeneratedColumn<String> get driveFileId => $composableBuilder(
      column: $table.driveFileId, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
      column: $table.failureReason, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DriveUploadJobsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DriveUploadJobsTable,
    DriveUploadJob,
    $$DriveUploadJobsTableFilterComposer,
    $$DriveUploadJobsTableOrderingComposer,
    $$DriveUploadJobsTableAnnotationComposer,
    $$DriveUploadJobsTableCreateCompanionBuilder,
    $$DriveUploadJobsTableUpdateCompanionBuilder,
    (
      DriveUploadJob,
      BaseReferences<_$AppDatabase, $DriveUploadJobsTable, DriveUploadJob>
    ),
    DriveUploadJob,
    PrefetchHooks Function()> {
  $$DriveUploadJobsTableTableManager(
      _$AppDatabase db, $DriveUploadJobsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DriveUploadJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DriveUploadJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DriveUploadJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> assignmentId = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String> fileType = const Value.absent(),
            Value<String> fileName = const Value.absent(),
            Value<int> fileSizeBytes = const Value.absent(),
            Value<DateTime> capturedAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> resumableUri = const Value.absent(),
            Value<String?> driveFileId = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> failureReason = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DriveUploadJobsCompanion(
            id: id,
            assignmentId: assignmentId,
            filePath: filePath,
            fileType: fileType,
            fileName: fileName,
            fileSizeBytes: fileSizeBytes,
            capturedAt: capturedAt,
            status: status,
            resumableUri: resumableUri,
            driveFileId: driveFileId,
            retryCount: retryCount,
            failureReason: failureReason,
            nextRetryAt: nextRetryAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String assignmentId,
            required String filePath,
            required String fileType,
            required String fileName,
            required int fileSizeBytes,
            required DateTime capturedAt,
            Value<String> status = const Value.absent(),
            Value<String?> resumableUri = const Value.absent(),
            Value<String?> driveFileId = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> failureReason = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              DriveUploadJobsCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            filePath: filePath,
            fileType: fileType,
            fileName: fileName,
            fileSizeBytes: fileSizeBytes,
            capturedAt: capturedAt,
            status: status,
            resumableUri: resumableUri,
            driveFileId: driveFileId,
            retryCount: retryCount,
            failureReason: failureReason,
            nextRetryAt: nextRetryAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DriveUploadJobsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DriveUploadJobsTable,
    DriveUploadJob,
    $$DriveUploadJobsTableFilterComposer,
    $$DriveUploadJobsTableOrderingComposer,
    $$DriveUploadJobsTableAnnotationComposer,
    $$DriveUploadJobsTableCreateCompanionBuilder,
    $$DriveUploadJobsTableUpdateCompanionBuilder,
    (
      DriveUploadJob,
      BaseReferences<_$AppDatabase, $DriveUploadJobsTable, DriveUploadJob>
    ),
    DriveUploadJob,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EnumeratorsTableTableManager get enumerators =>
      $$EnumeratorsTableTableManager(_db, _db.enumerators);
  $$AssignmentsTableTableManager get assignments =>
      $$AssignmentsTableTableManager(_db, _db.assignments);
  $$FeaturesTableTableManager get features =>
      $$FeaturesTableTableManager(_db, _db.features);
  $$FeatureGeometryRevisionsTableTableManager get featureGeometryRevisions =>
      $$FeatureGeometryRevisionsTableTableManager(
          _db, _db.featureGeometryRevisions);
  $$SubmissionsTableTableManager get submissions =>
      $$SubmissionsTableTableManager(_db, _db.submissions);
  $$BuildingAttributesTableTableManager get buildingAttributes =>
      $$BuildingAttributesTableTableManager(_db, _db.buildingAttributes);
  $$RoadAttributesTableTableManager get roadAttributes =>
      $$RoadAttributesTableTableManager(_db, _db.roadAttributes);
  $$HouseholdSurveysTableTableManager get householdSurveys =>
      $$HouseholdSurveysTableTableManager(_db, _db.householdSurveys);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db, _db.photos);
  $$Ra9514TypesTableTableManager get ra9514Types =>
      $$Ra9514TypesTableTableManager(_db, _db.ra9514Types);
  $$SyncJobsTableTableManager get syncJobs =>
      $$SyncJobsTableTableManager(_db, _db.syncJobs);
  $$OfflineTilePacksTableTableManager get offlineTilePacks =>
      $$OfflineTilePacksTableTableManager(_db, _db.offlineTilePacks);
  $$DriveUploadJobsTableTableManager get driveUploadJobs =>
      $$DriveUploadJobsTableTableManager(_db, _db.driveUploadJobs);
}
