/// The canonical overdrag resistance formula (rubber-banding):
/// f(x) = x*d*c / (d + c*x). Monotonic, asymptotically approaches d,
/// resistance is felt from the very first pixel (slope c at zero).
/// c = 0.55 is the classic iOS coefficient.
double morphRubberband(
  double x, {
  required double dimension,
  double coefficient = 0.55,
}) {
  if (x <= 0) {
    return 0;
  }
  return x * dimension * coefficient / (dimension + coefficient * x);
}
