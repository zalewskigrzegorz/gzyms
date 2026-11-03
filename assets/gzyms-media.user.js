// ==UserScript==
// @name        Gzyms media
// @namespace   dev.gzyms
// @version     0.2.0
// @description Tells Gzyms (127.0.0.1:47100) what video and audio this tab plays, and takes its play, pause, next, previous and go-to.
// @match       *://*/*
// @downloadURL http://127.0.0.1:47100/gzyms-media.user.js
// @updateURL   http://127.0.0.1:47100/gzyms-media.user.js
// @grant       GM_xmlhttpRequest
// @grant       GM_notification
// @connect     127.0.0.1
// @run-at      document-start
// @inject-into page
// @noframes
// ==/UserScript==

// shortcut: @noframes skips players embedded in iframes; drop it when a site needs one.
(() => {
  const page = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
  const id = Math.random().toString(36).slice(2);
  const handlers = {};
  let note = '';
  let had = false;

  // The page's own next/previous handlers, kept so "next" can do what the site's media keys would.
  const ms = page.navigator.mediaSession;
  if (ms) {
    const orig = ms.setActionHandler.bind(ms);
    const wrap = (action, h) => { handlers[action] = h; return orig(action, h); };
    ms.setActionHandler = typeof exportFunction === 'function' ? exportFunction(wrap, page) : wrap;
  }

  const media = () => [...document.querySelectorAll('video, audio')].filter((e) => e.currentSrc || e.srcObject);

  function run({ i, cmd }) {
    const e = media()[i];
    if (cmd === 'focus') {
      // Gecko ignores window.focus() from a page; Tampermonkey's highlight-only notification activates the tab instead.
      const how = typeof GM_notification === 'function' ? 'highlight' : 'window.focus';
      if (how === 'highlight') GM_notification({ highlight: true });
      else window.focus();
      setTimeout(() => { note = `focus (${how}): ${document.hasFocus() ? 'ok' : 'blocked'}`; }, 500);
      return;
    }
    if (!e) { note = `${cmd}: no media #${i}`; return; }
    if (cmd === 'play' || (cmd === 'toggle' && e.paused)) {
      e.play().then(() => { note = ''; }, (err) => { note = `play: ${err.name}`; });
    } else if (cmd === 'pause' || cmd === 'toggle') {
      e.pause();
    } else if (cmd === 'next') {
      if (handlers.nexttrack) handlers.nexttrack({ action: 'nexttrack' });
      else if (document.querySelector('.ytp-next-button')) document.querySelector('.ytp-next-button').click();
      else note = 'next: the site has no next';
    } else if (cmd === 'previous') {
      // Like a player's back button: to the start, or the site's previous when already there.
      if (e.currentTime > 3 || !handlers.previoustrack) e.currentTime = 0;
      else handlers.previoustrack({ action: 'previoustrack' });
    }
  }

  function report() {
    const list = media().map((e, i) => ({
      i, kind: e.tagName.toLowerCase(), playing: !e.paused && !e.ended,
      title: (ms && ms.metadata && ms.metadata.title) || document.title,
    }));
    // A tab without media stays silent; one last report when its media goes, so Gzyms drops it.
    if (!list.length && !had) return;
    had = list.length > 0;
    GM_xmlhttpRequest({
      method: 'POST',
      url: 'http://127.0.0.1:47100/report',
      // The custom header makes a page's own fetch() need a CORS preflight, which Gzyms never answers.
      headers: { 'Content-Type': 'application/json', 'X-Gzyms': '1' },
      data: JSON.stringify({ id, url: location.href, title: document.title, note, media: list }),
      timeout: 2000,
      onload: (r) => { try { JSON.parse(r.responseText).commands.forEach(run); } catch (_) { /* Gzyms not running */ } },
    });
  }

  setInterval(report, 1000);
})();
