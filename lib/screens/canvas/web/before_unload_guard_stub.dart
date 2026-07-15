typedef ShouldWarnCallback = bool Function();

/// No-op on non-web platforms — there's no browser "leave page" event to guard.
class BeforeUnloadGuard {
  void install(ShouldWarnCallback shouldWarn) {}

  void dispose() {}
}
