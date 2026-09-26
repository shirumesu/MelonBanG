enum CacheMethod {
  bt,
  pikpak;

  String get label => this == bt ? 'BT' : 'PikPak';
  CacheMethod get other => this == bt ? pikpak : bt;

  static CacheMethod fromStored(dynamic value) =>
      value == 'pikpak' ? pikpak : bt;
}
