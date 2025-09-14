import 'dart:async';
import 'dart:collection';

import 'package:files/backend/database/model.dart';
import 'package:files/backend/entity_info.dart';
import 'package:files/backend/fs.dart' as fs;
import 'package:files/backend/utils.dart';
import 'package:flutter/foundation.dart';

enum SortType { name, modified, type, size }

class CancelableFsFetch {
  final fs.File source;
  final ValueChanged<List<EntityInfo>?> onFetched;
  final VoidCallback? onCancel;
  final ValueChanged<double?>? onProgressChange;
  final bool ascending;
  final SortType sortType;
  final bool showHidden;

  CancelableFsFetch({
    required this.source,
    required this.onFetched,
    this.onCancel,
    this.onProgressChange,
    this.ascending = false,
    this.sortType = SortType.name,
    this.showHidden = false,
  });

  final fs.Cancellable cancellable = fs.Cancellable();

  bool get cancelled => cancellable.isCancelled;

  Future<void> startFetch() async {
    if (cancelled) throw CancelledException();

    final enumeratorOp = source.getEnumerator();
    final enumerator = await enumeratorOp.result;

    onProgressChange?.call(0.0);

    final directories = SplayTreeSet<EntityInfo>(
      (a, b) => _sort(a, b, isDirectory: true)!,
    );
    final files = SplayTreeSet<EntityInfo>(
      (a, b) => _sort(a, b, isDirectory: false)!,
    );

    while (true) {
      final enumerateOp = enumerator.enumerate(cancellable: cancellable);
      final fileList = await enumerateOp.result;

      if (fileList == null) break;

      for (final info in fileList.iterable()) {
        if (!showHidden && info.isHidden()) continue;
        final file = enumerator.getFile(info);
        if (file == null) continue;

        final stat = EntityStat.fromFileInfo(file.path, info);

        switch (stat.type) {
          case EntityType.file:
            files.add(EntityInfo(file, stat, stat.type));
          case EntityType.directory:
            directories.add(EntityInfo(file, stat, stat.type));
          default:
            break;
        }
      }
      fileList.destroy();
    }

    if (!cancelled) onFetched.call([...directories, ...files]);
  }

  int? _sort(EntityInfo a, EntityInfo b, {bool isDirectory = false}) {
    EntityInfo item1 = a;
    EntityInfo item2 = b;

    if (!ascending) {
      item2 = a;
      item1 = b;
    }

    switch (sortType.index) {
      case 0:
        return Utils.getEntityName(
          item1.path.toLowerCase(),
        ).compareTo(Utils.getEntityName(item2.path.toLowerCase()));
      case 1:
        return item1.stat.modified.compareTo(item2.stat.modified);
      case 2:
        return 0;
      case 3:
        if (isDirectory) {
          return 0;
        } else {
          return item1.stat.size.compareTo(item2.stat.size);
        }
    }

    return null;
  }

  void cancel() async {
    if (cancellable.isCancelled) return;

    cancellable.cancel();
  }
}

class CancelledException implements Exception {
  @override
  String toString() {
    return "CancelledException: The fetch was cancelled and can't be restored, please create a new instance for fetching.";
  }
}
