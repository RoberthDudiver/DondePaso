enum FootprintTransportMode {
  unknown,
  walking,
  vehicle;

  String get storageValue => switch (this) {
    FootprintTransportMode.unknown => 'unknown',
    FootprintTransportMode.walking => 'walking',
    FootprintTransportMode.vehicle => 'vehicle',
  };

  static FootprintTransportMode fromStorage(String? value) {
    return switch (value) {
      'walking' => FootprintTransportMode.walking,
      'vehicle' => FootprintTransportMode.vehicle,
      _ => FootprintTransportMode.unknown,
    };
  }
}

FootprintTransportMode detectTransportMode({
  required double speedMetersPerSecond,
  required bool walkingHint,
}) {
  if (walkingHint && speedMetersPerSecond <= 3.2) {
    return FootprintTransportMode.walking;
  }
  if (speedMetersPerSecond >= 5.5) {
    return FootprintTransportMode.vehicle;
  }
  if (walkingHint || speedMetersPerSecond <= 2.2) {
    return FootprintTransportMode.walking;
  }
  return FootprintTransportMode.unknown;
}
