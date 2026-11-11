import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:eye_protocol/eye_protocol.dart';

/// What the simulator pretends to be.
enum SimProfile { eyeSensor, eyeBeacon, iBeacon }

extension SimProfileLabel on SimProfile {
  String get label => switch (this) {
        SimProfile.eyeSensor => 'EYE SENSOR',
        SimProfile.eyeBeacon => 'EYE BEACON',
        SimProfile.iBeacon => 'iBeacon',
      };

  /// A name like the real devices' (`MP1_…` sensors, `ID1_…` beacons, BTSMP1 / BTSID1 pages).
  String get defaultName => switch (this) {
        SimProfile.eyeSensor => 'MP1_SIM001',
        SimProfile.eyeBeacon => 'ID1_SIM0001',
        SimProfile.iBeacon => '',
      };
}

/// How an EYE SENSOR packs its packets — the device's *Protocol type* (BTSMP1 page): sensor data
/// alone in the advertisement, or a beacon frame in the advertisement and the sensor data in the
/// scan response.
enum SensorPacket { sensorOnly, eddystoneAndSensor, iBeaconAndSensor }

extension SensorPacketLabel on SensorPacket {
  String get label => switch (this) {
        SensorPacket.sensorOnly => 'EYE Sensors',
        SensorPacket.eddystoneAndSensor => 'Eddystone + EYE Sensors',
        SensorPacket.iBeaconAndSensor => 'iBeacon + EYE Sensors',
      };
}

/// The beacon frame an EYE BEACON advertises.
enum BeaconFrame { eddystone, iBeacon }

/// Android's transmit power steps (AdvertisingSetParameters), dBm.
enum SimTxPower { ultraLow, low, medium, high }

extension SimTxPowerDbm on SimTxPower {
  int get dbm => switch (this) {
        SimTxPower.ultraLow => -21,
        SimTxPower.low => -15,
        SimTxPower.medium => -7,
        SimTxPower.high => 1,
      };

  String get label => switch (this) {
        SimTxPower.ultraLow => 'Ultra low',
        SimTxPower.low => 'Low',
        SimTxPower.medium => 'Medium',
        SimTxPower.high => 'High',
      };
}

/// Advertising intervals offered, ms. Real EYE devices default to 5 s (BTSMP1) and 1 s (BTSID1).
const simIntervals = [100, 250, 500, 1000, 2000, 3000, 5000, 10000];

/// How often the values change by themselves, seconds; 0 = with every advertisement, -1 = never.
const simChangeChoices = [0, 1, 5, 10, 30, 60, -1];

/// Everything the user sets for a simulation. Kept on this device between runs.
class SimSettings {
  SimSettings({
    this.profile = SimProfile.eyeSensor,
    String? name,
    this.intervalMs = 2000,
    this.txPower = SimTxPower.medium,
    this.changeEverySec = 0,
    this.sensorPacket = SensorPacket.sensorOnly,
    this.beaconFrame = BeaconFrame.eddystone,
    this.sendTemperature = true,
    this.temperatureC = 22.5,
    this.autoTemperature = true,
    this.sendHumidity = true,
    this.humidity = 45,
    this.autoHumidity = true,
    this.sendMagnet = true,
    this.magnetDetected = false,
    this.autoMagnet = true,
    this.sendMovement = true,
    this.moving = false,
    this.movementCount = 0,
    this.autoMovement = true,
    this.countPackets = false,
    this.sendAngles = true,
    this.pitch = 0,
    this.roll = 0,
    this.autoAngles = true,
    this.sendBattery = true,
    this.batteryMv = 3030,
    this.autoBattery = true,
    this.lowBattery = false,
    this.namespaceHex = 'B1E5B1E5B1E5B1E5B1E5',
    String? instanceHex,
    this.eddystoneTx0m = -4,
    this.iBeaconUuidHex = 'B1E5A11C0B1E4F00A000000000000001',
    this.major = 1,
    this.minor = 1,
    this.measuredPower = -59,
    this.simTag = true,
    String? simIdHex,
  })  : name = name ?? profile.defaultName,
        instanceHex = instanceHex ?? _randomHex(6),
        simIdHex = simIdHex ?? _randomHex(4);

  SimProfile profile;
  String name;
  int intervalMs;
  SimTxPower txPower;
  int changeEverySec;
  SensorPacket sensorPacket;
  BeaconFrame beaconFrame;

  bool sendTemperature;
  double temperatureC;
  bool autoTemperature;
  bool sendHumidity;
  int humidity;
  bool autoHumidity;
  bool sendMagnet;
  bool magnetDetected;
  bool autoMagnet;
  bool sendMovement;
  bool moving;
  int movementCount;
  bool autoMovement;

  /// The movement count becomes a packet counter (+1 with each change), so a receiver can count
  /// exactly which updates it missed.
  bool countPackets;
  bool sendAngles;
  int pitch;
  int roll;
  bool autoAngles;
  bool sendBattery;
  int batteryMv;
  bool autoBattery;
  bool lowBattery;

  String namespaceHex;
  String instanceHex;
  int eddystoneTx0m;
  String iBeaconUuidHex;
  int major;
  int minor;
  int measuredPower;

  /// Adds the BluePulse simulator tag ([simulatorCompanyId]) wherever a packet has room, so a
  /// BluePulse receiver keeps this as one device although the address changes with every burst.
  bool simTag;

  /// This install's simulated sensor's ID (4 bytes, hex), made once: what the tag carries when the
  /// packets have no beacon frame.
  String simIdHex;

  static String _randomHex(int bytes) {
    final r = Random();
    return [for (var i = 0; i < bytes; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join().toUpperCase();
  }

  /// How often values change, given the interval; null = never.
  Duration? get changeEvery => switch (changeEverySec) {
        < 0 => null,
        0 => Duration(milliseconds: intervalMs),
        final s => Duration(seconds: s),
      };

  Map<String, Object?> toJson() => {
        'profile': profile.name,
        'name': name,
        'intervalMs': intervalMs,
        'txPower': txPower.name,
        'changeEverySec': changeEverySec,
        'sensorPacket': sensorPacket.name,
        'beaconFrame': beaconFrame.name,
        'sendTemperature': sendTemperature,
        'temperatureC': temperatureC,
        'autoTemperature': autoTemperature,
        'sendHumidity': sendHumidity,
        'humidity': humidity,
        'autoHumidity': autoHumidity,
        'sendMagnet': sendMagnet,
        'magnetDetected': magnetDetected,
        'autoMagnet': autoMagnet,
        'sendMovement': sendMovement,
        'moving': moving,
        'movementCount': movementCount,
        'autoMovement': autoMovement,
        'countPackets': countPackets,
        'sendAngles': sendAngles,
        'pitch': pitch,
        'roll': roll,
        'autoAngles': autoAngles,
        'sendBattery': sendBattery,
        'batteryMv': batteryMv,
        'autoBattery': autoBattery,
        'lowBattery': lowBattery,
        'namespaceHex': namespaceHex,
        'instanceHex': instanceHex,
        'eddystoneTx0m': eddystoneTx0m,
        'iBeaconUuidHex': iBeaconUuidHex,
        'major': major,
        'minor': minor,
        'measuredPower': measuredPower,
        'simTag': simTag,
        'simIdHex': simIdHex,
      };

  /// Unknown or damaged values fall back to their defaults.
  factory SimSettings.fromJson(Map<String, Object?> j) {
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    E pickEnum<E extends Enum>(String k, List<E> values, E fallback) =>
        values.where((v) => v.name == j[k]).firstOrNull ?? fallback;
    final d = SimSettings();
    final profile = pickEnum('profile', SimProfile.values, d.profile);
    return SimSettings(
      profile: profile,
      name: pick('name', profile.defaultName),
      intervalMs: pick('intervalMs', d.intervalMs),
      txPower: pickEnum('txPower', SimTxPower.values, d.txPower),
      changeEverySec: pick('changeEverySec', d.changeEverySec),
      sensorPacket: pickEnum('sensorPacket', SensorPacket.values, d.sensorPacket),
      beaconFrame: pickEnum('beaconFrame', BeaconFrame.values, d.beaconFrame),
      sendTemperature: pick('sendTemperature', d.sendTemperature),
      temperatureC: (j['temperatureC'] as num?)?.toDouble() ?? d.temperatureC,
      autoTemperature: pick('autoTemperature', d.autoTemperature),
      sendHumidity: pick('sendHumidity', d.sendHumidity),
      humidity: pick('humidity', d.humidity),
      autoHumidity: pick('autoHumidity', d.autoHumidity),
      sendMagnet: pick('sendMagnet', d.sendMagnet),
      magnetDetected: pick('magnetDetected', d.magnetDetected),
      autoMagnet: pick('autoMagnet', d.autoMagnet),
      sendMovement: pick('sendMovement', d.sendMovement),
      moving: pick('moving', d.moving),
      movementCount: pick('movementCount', d.movementCount),
      autoMovement: pick('autoMovement', d.autoMovement),
      countPackets: pick('countPackets', d.countPackets),
      sendAngles: pick('sendAngles', d.sendAngles),
      pitch: pick('pitch', d.pitch),
      roll: pick('roll', d.roll),
      autoAngles: pick('autoAngles', d.autoAngles),
      sendBattery: pick('sendBattery', d.sendBattery),
      batteryMv: pick('batteryMv', d.batteryMv),
      autoBattery: pick('autoBattery', d.autoBattery),
      lowBattery: pick('lowBattery', d.lowBattery),
      namespaceHex: pick('namespaceHex', d.namespaceHex),
      instanceHex: pick('instanceHex', d.instanceHex),
      eddystoneTx0m: pick('eddystoneTx0m', d.eddystoneTx0m),
      iBeaconUuidHex: pick('iBeaconUuidHex', d.iBeaconUuidHex),
      major: pick('major', d.major),
      minor: pick('minor', d.minor),
      measuredPower: pick('measuredPower', d.measuredPower),
      simTag: pick('simTag', d.simTag),
      simIdHex: pick('simIdHex', d.simIdHex),
    );
  }

  SimSettings copy() => SimSettings.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, Object?>);
}

/// The values on air now. They start from the settings and, where *Auto* is on, wander the way a
/// real sensor's do: temperature and humidity drift around the set value, the battery sags very
/// slowly, the device starts and stops moving (each start counts a movement event), angles shake
/// while it moves, a magnet comes and goes.
class SimValues {
  SimValues.from(SimSettings s)
      : temperatureC = s.temperatureC,
        humidity = s.humidity,
        batteryMv = s.batteryMv,
        moving = s.moving,
        movementCount = s.movementCount,
        pitch = s.pitch,
        roll = s.roll,
        magnetDetected = s.magnetDetected;

  double temperatureC;
  int humidity;
  int batteryMv;
  bool moving;
  int movementCount;
  int pitch;
  int roll;
  bool magnetDetected;

  /// Changes made so far (the packet counter's value in *count packets* mode).
  int seq = 0;

  /// One change. Values whose *Auto* is off follow the settings exactly.
  void step(SimSettings s, Random rng) {
    seq++;
    double noise(double sd) => sd * (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) * 2;

    temperatureC = s.autoTemperature
        ? (temperatureC + (s.temperatureC - temperatureC) * 0.1 + noise(0.05)).clamp(-40.0, 125.0)
        : s.temperatureC;
    temperatureC = (temperatureC * 100).round() / 100;

    humidity = s.autoHumidity
        ? (humidity + ((s.humidity - humidity) * 0.15 + noise(0.7)).round()).clamp(0, 100)
        : s.humidity;

    if (s.autoBattery) {
      if (batteryMv > s.batteryMv + 40) batteryMv = s.batteryMv; // the set value was lowered
      if (rng.nextDouble() < 0.02) batteryMv = max(2000, batteryMv - 10);
    } else {
      batteryMv = s.batteryMv;
    }

    if (s.autoMovement) {
      if (moving) {
        if (rng.nextDouble() < 0.25) moving = false;
      } else if (rng.nextDouble() < 0.08) {
        moving = true;
        movementCount = (movementCount + 1) & 0x7FFF;
      }
    } else {
      moving = s.moving;
      movementCount = s.movementCount;
    }
    if (s.countPackets) movementCount = seq & 0x7FFF;

    if (s.autoAngles) {
      final shake = moving ? 12.0 : 0.8;
      pitch = (pitch + (s.pitch - pitch) * 0.2 + noise(shake)).round().clamp(-90, 90);
      roll = (roll + (s.roll - roll) * 0.2 + noise(shake)).round().clamp(-180, 180);
    } else {
      pitch = s.pitch;
      roll = s.roll;
    }

    magnetDetected = s.autoMagnet ? (rng.nextDouble() < 0.03 ? !magnetDetected : magnetDetected) : s.magnetDetected;
  }

  bool lowBattery(SimSettings s) => s.lowBattery || batteryMv <= 2600;
}

/// One simulated transmission: the advertisement and, when the profile has one, the scan response.
class SimPayload {
  const SimPayload(this.adv, this.scanResponse, {this.simulatorId});

  final AdvertisementData adv;
  final AdvertisementData? scanResponse;

  /// The ID the simulator tag carries, when at least one packet has it.
  final int? simulatorId;

  /// Legacy advertising carries at most 31 bytes per packet.
  static const maxBytes = 31;

  int get advBytes => adv.toBytes().length;
  int? get scanResponseBytes => scanResponse?.toBytes().length;

  /// Why it cannot be sent, or null.
  String? get problem {
    if (advBytes > maxBytes) return 'The advertisement is $advBytes bytes; at most $maxBytes fit — shorten the name';
    final sr = scanResponseBytes;
    if (sr != null && sr > maxBytes) return 'The scan response is $sr bytes; at most $maxBytes fit — shorten the name';
    return null;
  }
}

Uint8List _hex(String hex, int bytes) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  final padded = clean.padRight(bytes * 2, '0').substring(0, bytes * 2);
  return parseHex(padded);
}

/// The beacon ID these settings put on air, or null for a sensor without a beacon frame.
BeaconId? simBeaconId(SimSettings s) {
  BeaconId eddystone() => BeaconId.eddystone(_hex(s.namespaceHex, 10), _hex(s.instanceHex, 6));
  BeaconId iBeacon() => BeaconId.iBeacon(_hex(s.iBeaconUuidHex, 16), s.major.clamp(0, 65535), s.minor.clamp(0, 65535));
  return switch (s.profile) {
    SimProfile.eyeSensor => switch (s.sensorPacket) {
        SensorPacket.sensorOnly => null,
        SensorPacket.eddystoneAndSensor => eddystone(),
        SensorPacket.iBeaconAndSensor => iBeacon(),
      },
    SimProfile.eyeBeacon => s.beaconFrame == BeaconFrame.eddystone ? eddystone() : iBeacon(),
    SimProfile.iBeacon => iBeacon(),
  };
}

/// The ID the simulator tag carries. A simulated beacon's follows from its beacon ID, so a receiver
/// can join the beacon frames Windows sends without the tag; a sensor alone has this install's own.
int simulatorIdOf(SimSettings s) {
  final beacon = simBeaconId(s);
  if (beacon != null) return simulatorIdForBeacon(beacon);
  return int.tryParse(s.simIdHex, radix: 16) ?? 0;
}

/// The packets for these settings and values, exactly as they go on air.
///
/// [sendsName] is false on Windows, which does not let apps advertise a name. [reservedBytes] is
/// room kept for what the system adds itself (Windows' Flags), so the tag never overfills a packet.
SimPayload buildPayload(SimSettings s, SimValues v, {bool sendsName = true, int reservedBytes = 0}) {
  final (adv, response) = _packets(s, v, sendsName ? s.name.trim() : '', sendsName);
  if (!s.simTag) return SimPayload(adv, response);
  final id = simulatorIdOf(s);
  final tag = encodeSimulatorTag(id);
  final room = SimPayload.maxBytes - reservedBytes;
  var tagged = false;
  AdvertisementData withTag(AdvertisementData d) {
    if (d.toBytes().length + simulatorTagBytes > room) return d;
    tagged = true;
    return AdvertisementData(
      name: d.name,
      serviceUuids16: d.serviceUuids16,
      serviceData16: d.serviceData16,
      manufacturerData: {...d.manufacturerData, simulatorCompanyId: tag},
    );
  }

  final a = withTag(adv);
  final r = response == null ? null : withTag(response);
  return SimPayload(a, r, simulatorId: tagged ? id : null);
}

(AdvertisementData, AdvertisementData?) _packets(SimSettings s, SimValues v, String typedName, bool sendsName) {
  final name = typedName.isEmpty ? null : typedName;
  AdvertisementData eddystone() => AdvertisementData(
        serviceUuids16: const [eddystoneServiceUuid],
        serviceData16: {
          eddystoneServiceUuid: encodeEddystoneUid(
            namespace: _hex(s.namespaceHex, 10),
            instance: _hex(s.instanceHex, 6),
            txPower0m: s.eddystoneTx0m,
          ),
        },
      );
  AdvertisementData iBeacon() => AdvertisementData(manufacturerData: {
        appleCompanyId: encodeIBeacon(
          uuid: _hex(s.iBeaconUuidHex, 16),
          major: s.major.clamp(0, 65535),
          minor: s.minor.clamp(0, 65535),
          measuredPower: s.measuredPower,
        ),
      });

  switch (s.profile) {
    case SimProfile.eyeSensor:
      final block = encodeTeltonika(
        temperatureC: s.sendTemperature ? v.temperatureC : null,
        humidity: s.sendHumidity ? v.humidity : null,
        magnetPresent: s.sendMagnet,
        magnetDetected: v.magnetDetected,
        moving: s.sendMovement ? v.moving : null,
        movementCount: s.sendMovement ? v.movementCount : null,
        pitch: s.sendAngles ? v.pitch : null,
        roll: s.sendAngles ? v.roll : null,
        lowBattery: v.lowBattery(s),
        batteryMv: s.sendBattery ? v.batteryMv : null,
      );
      final sensor = AdvertisementData(name: name, manufacturerData: {teltonikaCompanyId: block});
      return switch (s.sensorPacket) {
        SensorPacket.sensorOnly => (sensor, null),
        SensorPacket.eddystoneAndSensor => (eddystone(), sensor),
        SensorPacket.iBeaconAndSensor => (iBeacon(), sensor),
      };
    case SimProfile.eyeBeacon:
      final block = encodeTeltonika(lowBattery: v.lowBattery(s), batteryMv: s.sendBattery ? v.batteryMv : null);
      final response = AdvertisementData(name: name, manufacturerData: {teltonikaCompanyId: block});
      return (s.beaconFrame == BeaconFrame.eddystone ? eddystone() : iBeacon(), response);
    case SimProfile.iBeacon:
      // From Windows, which sends no name, the tag goes in a burst of its own between the iBeacon
      // frames: a frame has no room for it, and without it every burst would be a new device.
      if (!sendsName && s.simTag) return (iBeacon(), const AdvertisementData());
      return (iBeacon(), name == null ? null : AdvertisementData(name: name));
  }
}
