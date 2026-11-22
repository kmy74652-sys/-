import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class OfflineAttachmentStore {
  OfflineAttachmentStore._();

  static Future<String> save({
    required String ownerUid,
    required String attachmentId,
    required List<int> bytes,
  }) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/offline-attachments/$ownerUid');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$attachmentId.bin');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List> read(String path) => File(path).readAsBytes();

  static Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
