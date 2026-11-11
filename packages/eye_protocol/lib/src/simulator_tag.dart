import 'dart:typed_data';

import 'beacon_id.dart';

/// The BluePulse simulator tag: a small manufacturer-data block that marks a packet as sent by the
/// BluePulse simulator and carries the simulated device's ID. A receiver keeps every packet with
/// the same ID as one device, although the sender's address changes — Windows takes a new random
/// address for every burst, Android every few minutes, and neither tells the app which.
///
/// Company ID `0xFFFF` is the one the Bluetooth SIG keeps for tests: no product carries it. The
/// block is `B` `P` and the 4-byte ID, big-endian.
const simulatorCompanyId = 0xFFFF;

const _magic = [0x42, 0x50]; // "BP"

/// What the tag adds to a packet: length, AD type, company ID, `BP`, the ID.
const simulatorTagBytes = 10;

/// The block after the company ID.
Uint8List encodeSimulatorTag(int id) =>
    Uint8List.fromList([..._magic, (id >> 24) & 0xFF, (id >> 16) & 0xFF, (id >> 8) & 0xFF, id & 0xFF]);

/// The simulator ID in a `0xFFFF` block, or null when the block is not BluePulse's.
int? decodeSimulatorTag(Uint8List data) {
  if (data.length < 6 || data[0] != _magic[0] || data[1] != _magic[1]) return null;
  return data[2] * 0x1000000 + (data[3] << 16) + (data[4] << 8) + data[5];
}

/// A simulated beacon's ID follows from its beacon ID. Windows sends a beacon frame in its own
/// burst with no room left for the tag; a receiver that already knows the simulator joins the frame
/// to it by this ID. FNV-1a, 32 bits, in arithmetic that stays exact on the web as well.
int simulatorIdForBeacon(BeaconId id) {
  var h = 0x811C9DC5;
  for (final b in [id.kind.index, ...id.bytes]) {
    h ^= b;
    h = (h * 0x193 + (h % 0x100) * 0x1000000) % 0x100000000; // h × 16777619, modulo 2³²
  }
  return h;
}

/// How a simulated device is listed in place of a MAC: `SIM-1A2B3C4D`.
String simulatorKey(int id) => 'SIM-${id.toRadixString(16).padLeft(8, '0').toUpperCase()}';

bool isSimulatorKey(String key) => key.startsWith('SIM-');
