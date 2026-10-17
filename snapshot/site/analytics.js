/*
 * fastwork.com — Google Tag Manager bootstrap + dataLayer events (FC-775).
 *
 * Hand-written for the Pages repo; it is NOT produced by the fastwork-web
 * landing sync, so keep the <script src="/analytics.js"> tag and the
 * <noscript> iframe in each locale's index.html when re-syncing.
 *
 * Events pushed, in the shape the ticket specifies:
 *   set_user      { lang }                                  on load + language option click
 *   page_view     (no payload)                              once on load, right after set_user
 *   view_section  { page_path, page_title }                 section scrolled into view (once each)
 *   click_item    { page_path, page_title, name }           get-started buttons (hero, all-header, profile)
 *   show_tab      { page_path, page_title, tab_name }       profile feed tabs (post / services / reviews / about)
 *
 * Sections on this build: hero, profile (people), profile-showcase_{profession},
 * pain-point, commission, feature, coming-soon. The ticket's instant-profile
 * section does not exist on the page, so that event is not sent.
 *
 * coming-soon is not a section in the document: it is the header pill morphing
 * into the closing panel (countdown + "Join waitlist") after the last section,
 * so it is detected from the header's `is-expanded` class, not by scrolling.
 */
(function (w, d) {
  'use strict';

  var GTM_ID = 'GTM-M8BMQ3VJ';
  var PAGE_PATH = 'start-selling';

  /* ---- URL hygiene -------------------------------------------------------- */
  // Probes and shared links arrive with junk query strings (?x=1, ?igshid=…),
  // and GA4 files every distinct URL under its own page location. Keep only
  // the campaign and click-id parameters the ad tags read, and rewrite the
  // URL before the container loads and takes its first look at it. Nothing
  // on the page reads the query string, so dropping the rest changes nothing
  // the visitor can see. Unknown *paths* are handled by 404.html instead.
  var KEEP_PARAM = /^(?:utm_[a-z]+|gclid|gbraid|wbraid|dclid|fbclid|ttclid|msclkid|twclid|li_fat_id)$/i;

  function tidyUrl() {
    var loc = w.location;
    if (!loc.search || !w.URLSearchParams || !w.history || !w.history.replaceState) return;
    var kept = new URLSearchParams();
    new URLSearchParams(loc.search).forEach(function (value, key) {
      if (KEEP_PARAM.test(key)) kept.append(key, value);
    });
    var search = kept.toString();
    var next = loc.pathname + (search ? '?' + search : '') + loc.hash;
    if (next === loc.pathname + loc.search + loc.hash) return;
    try {
      w.history.replaceState(w.history.state, '', next);
    } catch (e) {
      /* a hardened browser may refuse; the original URL is still tracked */
    }
  }
  tidyUrl();

  /* ---- GTM container (snippet from the ticket, id inlined) ---------------- */
  w.dataLayer = w.dataLayer || [];
  w.dataLayer.push({ 'gtm.start': new Date().getTime(), event: 'gtm.js' });
  var first = d.getElementsByTagName('script')[0];
  var gtm = d.createElement('script');
  gtm.async = true;
  gtm.src = 'https://www.googletagmanager.com/gtm.js?id=' + GTM_ID;
  first.parentNode.insertBefore(gtm, first);

  /* ---- helpers ------------------------------------------------------------ */
  function push(event, payload) {
    w.dataLayer.push(payload === undefined ? { event: event } : { event: event, payload: payload });
  }

  function pageLang() {
    return (d.documentElement.getAttribute('lang') || 'en').toLowerCase();
  }

  function showcaseTitle(profession) {
    return 'profile-showcase_' + profession;
  }

  // Profession currently selected in the profile showcase (SSR stamps
  // data-active; after hydration the selected tab carries aria-selected).
  function activeProfession() {
    var tab = d.querySelector('[data-profession-tab][aria-selected="true"]');
    if (tab) return tab.getAttribute('data-profession-tab');
    var host = d.querySelector('#profile-showcase [data-active], [data-active]');
    return host ? host.getAttribute('data-active') : null;
  }

  var viewed = {};
  function viewSection(title) {
    if (!title || viewed[title]) return;
    viewed[title] = true;
    push('view_section', { page_path: PAGE_PATH, page_title: title });
  }

  /* ---- set_user, then page_view, on load ---------------------------------- */
  push('set_user', { lang: pageLang() });
  push('page_view');

  /* ---- clicks (capture phase so a navigation in the app handler cannot
          swallow the event; the language switch reloads the page) ----------- */
  var GET_STARTED_TITLE = { header: 'all-header', hero: 'hero', people: 'profile' };

  /* ---- footer "Privacy Policy" link ---------------------------------------
     The landing bundle renders the header's footer panel at runtime with a
     placeholder href="#people" on the privacy link. The page itself is owned
     by the sync, so the correction lives here: rewrite the href as soon as the
     link exists, and again on click in case it was re-rendered in between. */
  var PRIVACY_LINK = '[data-selenium="start-selling.header.link.privacy"]';
  var PRIVACY_URL = '/privacy';

  function fixPrivacyLinks(root) {
    var links = root && root.querySelectorAll ? root.querySelectorAll(PRIVACY_LINK) : [];
    for (var i = 0; i < links.length; i++) {
      if (links[i].getAttribute('href') !== PRIVACY_URL) links[i].setAttribute('href', PRIVACY_URL);
    }
  }

  if ('MutationObserver' in w) {
    new MutationObserver(function (records) {
      for (var i = 0; i < records.length; i++) {
        var added = records[i].addedNodes;
        for (var j = 0; j < added.length; j++) fixPrivacyLinks(added[j]);
      }
    }).observe(d.documentElement, { childList: true, subtree: true });
  }

  d.addEventListener('click', function (e) {
    var el = e.target && e.target.closest ? e.target.closest('[data-selenium]') : null;
    if (!el) return;
    var id = el.getAttribute('data-selenium') || '';
    var m;

    // Footer privacy link: make sure the href is right before the browser follows it.
    if (id === 'start-selling.header.link.privacy') {
      el.setAttribute('href', PRIVACY_URL);
      return;
    }

    // Language switcher option → set_user { lang }
    if ((m = /^start-selling\.header\.option\.language\.([a-z-]+)$/i.exec(id))) {
      push('set_user', { lang: m[1].toLowerCase() });
      return;
    }

    // "Join waitlist" / get-started buttons → click_item
    if ((m = /^start-selling\.(header|hero|people)\.button\.get-started$/.exec(id))) {
      push('click_item', {
        page_path: PAGE_PATH,
        page_title: GET_STARTED_TITLE[m[1]],
        name: 'button_get-started'
      });
      return;
    }

    // Profession tab in the showcase → view_section profile-showcase_{category}
    if ((m = /^start-selling\.profile-showcase\.button\.profession\.([a-z0-9-]+)$/.exec(id))) {
      viewSection(showcaseTitle(m[1]));
      return;
    }

    // Feed tab (posts / services / reviews / about) → show_tab
    if ((m = /^start-selling\.profile-showcase\.button\.feed-tab\.([a-z0-9-]+)_([a-z]+)$/.exec(id))) {
      var tab = m[2] === 'posts' ? 'post' : m[2];
      push('show_tab', {
        page_path: PAGE_PATH,
        page_title: showcaseTitle(m[1]),
        tab_name: tab
      });
      return;
    }
  }, true);

  /* ---- section views ------------------------------------------------------ */
  // selector → page_title. null = profile showcase, resolved at view time.
  var SECTIONS = [
    ['section.hero-track', 'hero'],
    ['#people', 'profile'],
    ['#profile-showcase', null],
    ['section.pain', 'pain-point'],
    ['section.commission', 'commission'],
    ['#platform', 'feature']
  ];

  function observeSections() {
    if (!('IntersectionObserver' in w)) return;
    var titles = new Map();
    // Shrink the root to the middle 20% of the viewport so a section counts
    // as viewed once it crosses the centre, regardless of its own height.
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var title = titles.get(entry.target);
        if (title === null) title = showcaseTitle(activeProfession() || 'unknown');
        viewSection(title);
        io.unobserve(entry.target);
      });
    }, { rootMargin: '-40% 0px -40% 0px', threshold: 0 });

    SECTIONS.forEach(function (pair) {
      var el = d.querySelector(pair[0]);
      if (!el) return;
      titles.set(el, pair[1]);
      io.observe(el);
    });
  }

  /* ---- closing panel → view_section coming-soon --------------------------- */
  // The landing bundle adds `is-expanded` to the header once the morph into the
  // closing panel has (nearly) finished, which is the moment the countdown and
  // the final "Join waitlist" are actually on screen.
  var COMING_SOON_CLASS = 'is-expanded';

  function observeComingSoon() {
    var nav = d.querySelector('.start-selling-top-nav');
    if (!nav || !('MutationObserver' in w)) return;
    var check = function () {
      if (nav.classList.contains(COMING_SOON_CLASS)) viewSection('coming-soon');
    };
    new MutationObserver(check).observe(nav, { attributes: true, attributeFilter: ['class'] });
    check();
  }

  function onReady() {
    observeSections();
    observeComingSoon();
  }

  if (d.readyState === 'loading') {
    d.addEventListener('DOMContentLoaded', onReady);
  } else {
    onReady();
  }
})(window, document);
