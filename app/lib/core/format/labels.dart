/// Short names for Ceylon Petroleum Corporation's products, as the gazettes and
/// CEYPETCO name them ("Lanka Petrol 92 Octane" reads "Petrol 92"), checked in
/// this order.
const _fuels = [
  ('petrol 92', 'Petrol 92'),
  ('petrol 95', 'Petrol 95'),
  ('super diesel', 'Super Diesel'),
  ('auto diesel', 'Diesel'),
  ('industrial kerosene', 'Industrial kerosene'),
  ('kerosene', 'Kerosene'),
];

/// A key number's label, shortened where a long official name has a common one.
String shortLabel(String label) {
  final lower = label.toLowerCase();
  for (final (key, name) in _fuels) {
    if (lower.contains(key)) {
      return name;
    }
  }
  return label.startsWith('Lanka ') ? label.substring('Lanka '.length) : label;
}
