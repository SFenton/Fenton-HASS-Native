/* NavigationGlass: the glass header circles. apple/Sources/HassDesign/NavigationGlass.swift (the `navigationGlass(in:)` material) and
 * apple/Sources/HassUI/App/Shell/ShellHeader.swift (Quick Links, Profile, Open Navigation, Back).
 *
 * Registers: NavigationGlass, QuickLinksButton, ProfileButton, HamburgerButton, BackButton, CloseButton, RailGroup.
 * Rules (direction-g.md Navigation): Quick Links is a plain 44 pt glass circle; Profile with a known name is a 44 pt monogram disc that
 * IS the whole button (no glass ring), with the attention badge on its top-trailing edge ("9+" past nine); the two sit 12 pt apart on
 * iPhone and iPad. In the Duo's vertical rail they share ONE glass group with the person symbol (owner 2026-10-20). Liquid Glass only on
 * the navigation layer: never on tiles or cards.
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  function circle(symbol, label, o) {
    o = o || {};
    return h('button.ui-circle.ui-glass' + (o.cls ? '.' + o.cls : ''), { type: 'button', 'aria-label': label, title: label, html: I(symbol, { fill: o.fill }) });
  }
  function badgeText(n) { return n > 9 ? '9+' : String(n); }

  /** A glass circle with one symbol. props: {symbol, label, fill?} */
  Mock.register('NavigationGlass', function (p) { return circle(p.symbol || 'square.grid.2x2', p.label || 'Button', p); }, {
    source: 'apple/Sources/HassDesign/NavigationGlass.swift', doc: 'Liquid Glass circle for navigation controls (thin material before iOS 26).',
    variants: [
      { id: 'quick-links', label: 'Quick Links', props: { symbol: 'square.grid.2x2', label: 'Quick Links' } },
      { id: 'back', label: 'Back', props: { symbol: 'chevron.left', label: 'Back' } },
      { id: 'close', label: 'Close', props: { symbol: 'xmark', label: 'Close' } },
      { id: 'menu', label: 'Open Navigation', props: { symbol: 'line.3.horizontal', label: 'Open Navigation' } },
    ] });

  /** Quick Links: opens the Quick Links sheet. identifier quickLinks.open. props: none */
  Mock.register('QuickLinksButton', function () { return circle('square.grid.2x2', 'Quick Links'); }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift' });
  /** Open Navigation (hamburger), nav.open; leading on iPhone and iPad, in the rail on the unfolded Duo. props: {inRail?} */
  Mock.register('HamburgerButton', function (p) { var b = circle('line.3.horizontal', 'Open Navigation'); b.title = 'Open Navigation'; return b; }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift' });
  /** Back on a pushed page. props: {label?} */
  Mock.register('BackButton', function (p) { return circle('chevron.left', (p && p.label) || 'Back'); }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift' });
  /** Close (circle x) as used in the header of a pushed full-screen page. For sheets use SheetCloseItem. */
  Mock.register('CloseButton', function () { return circle('xmark', 'Close'); }, { source: 'apple/Sources/HassDesign/HassModal.swift' });

  /**
   * Profile (nav.profile). props: {name?:string (initials are taken from it; omit for the person-symbol-on-glass form shown before the name is known),
   * badge?:number, offline?:boolean, fill?:cssColor (the monogram fill, default #0066CC: 5.6:1 under white)}
   */
  Mock.register('ProfileButton', function (p) {
    p = p || {};
    var name = p.name === undefined ? 'Stephen Fenton' : p.name, label = 'Profile' + (name ? ', ' + name : '') + (p.badge ? ', ' + p.badge + ' items need attention' : '');
    var b;
    if (name) {
      var initials = name.split(/\s+/).map(function (w) { return w[0]; }).join('').slice(0, 2).toUpperCase();
      b = h('button.ui-monogram', { type: 'button', 'aria-label': label, title: label, style: p.fill ? { background: p.fill } : null }, initials);
    } else b = circle('person', label);
    if (p.badge) { b.style.position = 'relative'; b.appendChild(h('span.ui-badge', { 'aria-hidden': 'true' }, badgeText(p.badge))); }
    if (p.offline) { b.style.position = 'relative'; b.appendChild(h('span.ui-badge.status', { 'aria-hidden': 'true', html: I('icloud.slash') })); }
    return b;
  }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeader.swift', props: '{name?, badge?, offline?, fill?}',
    variants: [{ id: 'monogram', label: 'Monogram', props: { name: 'Stephen Fenton' } }, { id: 'badge', label: 'Badge 3', props: { badge: 3 } }, { id: 'badge9', label: 'Badge 12 (9+)', props: { badge: 12 } },
      { id: 'noname', label: 'No name yet', props: { name: '' } }],
    states: [{ id: 'live', label: 'Live', props: {} }, { id: 'offline', label: 'Offline (cloud badge)', props: { offline: true } }] });

  /** The Duo rail's single glass group: Quick Links and the person symbol, no spacer. props: {badge?} */
  Mock.register('RailGroup', function (p) {
    p = p || {};
    var prof = h('button', { type: 'button', 'aria-label': 'Profile', title: 'Profile', html: I('person.crop.circle.fill') });
    prof.style.position = 'relative';
    if (p.badge) prof.appendChild(h('span.ui-badge', { style: { top: '4px', right: '2px' }, 'aria-hidden': 'true' }, badgeText(p.badge)));
    return h('div.ui-railblob.ui-glass', h('button', { type: 'button', 'aria-label': 'Quick Links', title: 'Quick Links', html: I('square.grid.2x2') }), prof);
  }, { source: 'apple/Sources/HassUI/App/Shell/ShellHeaderGrouping.swift', doc: 'ShellHeaderGrouping.oneGroup' });
})();
