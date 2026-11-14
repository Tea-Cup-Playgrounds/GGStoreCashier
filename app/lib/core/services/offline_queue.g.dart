// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_queue.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OfflineTransactionEntryAdapter
    extends TypeAdapter<OfflineTransactionEntry> {
  @override
  final int typeId = 10;

  @override
  OfflineTransactionEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OfflineTransactionEntry()
      ..uuid = fields[0] as String
      ..payload = (fields[1] as Map).cast<dynamic, dynamic>()
      ..createdAt = fields[2] as DateTime
      ..retryCount = fields[3] as int
      ..status = fields[4] as String
      ..lastError = fields[5] as String?
      ..lastAttemptAt = fields[6] as DateTime?;
  }

  @override
  void write(BinaryWriter writer, OfflineTransactionEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.uuid)
      ..writeByte(1)
      ..write(obj.payload)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.retryCount)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.lastError)
      ..writeByte(6)
      ..write(obj.lastAttemptAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfflineTransactionEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
