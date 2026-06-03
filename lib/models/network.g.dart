// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class NetworkAdapter extends TypeAdapter<Network> {
  @override
  final int typeId = 20;

  @override
  Network read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Network(
      id: fields[0] as String,
      name: fields[1] as String,
      rpcUrl: fields[2] as String,
      prefix: fields[3] as String,
      builtin: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Network obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.rpcUrl)
      ..writeByte(3)
      ..write(obj.prefix)
      ..writeByte(4)
      ..write(obj.builtin);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
