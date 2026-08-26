/// Lightweight in-memory flag set by main() when a non-remembered session
/// is wiped on cold start.  The login page reads this once and shows the
/// "Sesimu sudah habis" modal, then clears the flag.
class SessionExpiredNotifier {
  SessionExpiredNotifier._();

  static bool _wasExpired = false;

  /// Called by main() after wiping a non-remembered session that had a token.
  static void markExpired() => _wasExpired = true;

  /// Returns true once — consuming the flag so the modal only shows once.
  static bool consumeExpired() {
    final v = _wasExpired;
    _wasExpired = false;
    return v;
  }
}
