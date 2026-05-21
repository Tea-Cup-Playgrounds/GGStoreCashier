// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_operations_queue.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PendingOperationAdapter extends TypeAdapter<PendingOperation> {
  @override
  final int typeId = 11;

  @override
  PendingOperation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PendingOperation()
      ..id = fields[0] as String
      ..method = fields[1] as String
      ..path = fields[2] as String
      ..body = (fields[3] as Map).cast<dynamic, dynamic>()
      ..createdAt = fields[4] as DateTime
      ..retryCount = fields[5] as int
      ..status = fields[6] as String
      ..description = fields[7] as String;
  }

  @override
  void write(BinaryWriter writer, PendingOperation obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.method)
      ..writeByte(2)
      ..write(obj.path)
      ..writeByte(3)
      ..write(obj.body)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.retryCount)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.description);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingOperationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
