/// Decoders for Teltonika EYE devices.
///
/// * BLE advertisements: AD structures, iBeacon, Eddystone, the Teltonika `0x089A` block.
/// * Tracker records: Codec 8 / 8 Extended framing, AVL 385 and AVL 10828 / 10829 / 10831.
///
/// Pure Dart — no Flutter — so the same code runs in the app, in tests and on a CLI.
library;

export 'src/ad_structures.dart';
export 'src/advertisement.dart';
export 'src/avl_beacons.dart';
export 'src/beacon_id.dart';
export 'src/byte_field.dart';
export 'src/byte_reader.dart' show TruncatedException;
export 'src/codec8e.dart';
export 'src/encode.dart';
export 'src/eddystone.dart';
export 'src/eye_config.dart';
export 'src/hex.dart';
export 'src/ibeacon.dart';
export 'src/inspect.dart';
export 'src/simulator_tag.dart';
export 'src/teltonika.dart';
