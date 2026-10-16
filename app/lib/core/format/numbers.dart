/// A price or rate as the app shows it: whole numbers with thousands separators
/// (2,150), anything else with two decimals (336.39).
String amount(double value) {
  if (value == value.roundToDouble()) {
    final digits = value.round().abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+$)'),
      (match) => ',',
    );
    return value < 0 ? '-$grouped' : grouped;
  }
  return value.toStringAsFixed(2);
}
