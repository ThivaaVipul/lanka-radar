/// A price or rate as the app shows it, with thousands separators: whole
/// numbers as they are (2,150), anything else with two decimals (4,748.84).
String amount(double value) {
  final whole = value == value.roundToDouble();
  final text = whole
      ? value.round().abs().toString()
      : value.abs().toStringAsFixed(2);
  final (digits, decimals) = switch (text.split('.')) {
    [final digits, final decimals] => (digits, '.$decimals'),
    _ => (text, ''),
  };
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (match) => ',',
  );
  return '${value < 0 ? '-' : ''}$grouped$decimals';
}
