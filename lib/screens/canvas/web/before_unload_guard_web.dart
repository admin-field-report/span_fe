import 'dart:html' as html;

typedef ShouldWarnCallback = bool Function();

/// Wires the real browser `beforeunload` event so refreshing/closing the tab
/// shows the browser's own native confirmation when there's unsaved work.
///
/// This must use `dart:html` directly rather than `universal_html` — the
/// latter's browser implementation of `onBeforeUnload` is unimplemented and
/// never fires, so it silently does nothing on a real page refresh.
class BeforeUnloadGuard {
  void Function(html.Event)? _listener;

  void install(ShouldWarnCallback shouldWarn) {
    _listener = (html.Event event) {
      if (shouldWarn()) {
        event.preventDefault();
        (event as html.BeforeUnloadEvent).returnValue = '';
      }
    };
    html.window.addEventListener('beforeunload', _listener);
  }

  void dispose() {
    final listener = _listener;
    if (listener != null) {
      html.window.removeEventListener('beforeunload', listener);
      _listener = null;
    }
  }
}
