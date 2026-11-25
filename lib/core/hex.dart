/// [bytes] as lowercase hexadecimal, two digits a byte.
String hexEncode(Iterable<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
