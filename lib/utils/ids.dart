import 'dart:math';

final _random = Random.secure();

/// Short unique id created on the phone (wallets, custom categories), so
/// other records can refer to it before it reaches the database.
String newId([String prefix = '']) {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final noise = List.generate(6, (_) => _random.nextInt(36).toRadixString(36)).join();
  return '$prefix$time$noise';
}
