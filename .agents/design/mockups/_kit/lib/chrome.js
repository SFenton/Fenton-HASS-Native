/* Shell chrome per device: Mock.frame (device + status bar), Mock.page (a tab root or pushed page), Mock.sheet (a presented modal),
 * Mock.split (the on-demand split on the hinge or the midpoint).
 *
 * What the chrome is, per device (direction-g.md Navigation; design/apple/{iphone,ipados,duo,split-view}.md):
 *   iphone                  hamburger leading (owner 2026-10-20), Quick Links circle + Profile monogram trailing 12 pt apart, large title
 *                           below the bar, glass floating tab bar (5 tabs, Settings last).
 *   duo-folded              no hamburger; tabs and one glass group (Quick Links + Profile as the person symbol, no spacer) in the trailing
 *                           vertical rail; the title shares the header row (inlineLarge) because nothing else leads.
 *   duo-unfolded-*          flyout style; Open Navigation moves into the trailing rail with the one glass group; title below the bar.
 *   ipad-*                  flyout style; hamburger leading; Quick Links and Profile circles trailing; title below the bar; no tab bar.
 * Quick Links and Profile are on every page, root or pushed. A pushed page swaps the hamburger for a glass Back circle.
 */
(function () {
  var h = Mock.h;
  var C = function () { return Mock.components; };

  var STATUS_R = '<svg viewBox="0 0 72 13" aria-hidden="true"><g fill="currentColor"><rect x="0" y="8" width="3" height="5" rx=".8"/><rect x="5" y="5.5" width="3" height="7.5" rx=".8"/><rect x="10" y="3" width="3" height="10" rx=".8"/><rect x="15" y="0" width="3" height="13" rx=".8"/></g>' +
    '<path fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" d="M24 5.2a8 8 0 0 1 12 0M26.4 8a4.6 4.6 0 0 1 7.2 0"/><circle cx="30" cy="11.3" r="1.2" fill="currentColor"/>' +
    '<rect x="42" y=".7" width="25" height="11.6" rx="3.4" fill="none" stroke="currentColor" stroke-opacity=".45"/><rect x="43.7" y="2.4" width="19" height="8.2" rx="2" fill="currentColor"/><rect x="68.6" y="4.4" width="1.8" height="4.2" rx=".9" fill="currentColor" fill-opacity=".5"/></svg>';

  /**
   * Wrap a screen body in a device: bezel, true-size .screen, status bar, Dynamic Island, home indicator, hinge band.
   * @param {object} ctx from Mock.ctx
   * @param {Node|Node[]|string} content what render() returned (a Mock.page / Mock.sheet node or your own)
   * @returns {HTMLElement} .k-device
   */
  Mock.frame = function (ctx, content, o) {
    o = o || {};
    var d = ctx.device, ts = Mock.textSizes[ctx.ts] || Mock.textSizes['default'];
    var screen = h('div.screen.ui-root.g-dark' + (ts.cls ? '.' + ts.cls : '') + (ctx.reduceMotion ? '.k-reduce-motion' : '') + (ctx.reduceTransparency ? '.k-reduce-transparency' : ''),
      { dataset: { device: ctx.key }, style: { '--w': d.w + 'px', '--h': d.h + 'px', '--r': d.r + 'px', '--safe-top': d.safeTop + 'px', '--safe-bottom': d.safeBottom + 'px' } });
    if (d.hinge) screen.dataset.hinge = d.hinge.axis;
    if (typeof content === 'string') content = Mock.html(content);
    Mock.append(screen, content);
    var first = content && content.nodeType ? content : (Array.isArray(content) ? content[0] : null);
    var indicator = first && first.dataset && first.dataset.indicator === 'dark';
    var statusDark = first && first.dataset && first.dataset.statusInk === 'dark';
    if (indicator) screen.style.setProperty('--indicator', 'rgba(0,0,0,.85)');
    var phone = d.family === 'phone';
    var time = phone || ctx.folded ? '9:41' : '9:41 Fri Oct 23';
    screen.appendChild(h('div.k-status' + (statusDark ? '.dark-ink' : ''), { 'aria-hidden': 'true' }, h('span.l', time), h('span.r', { html: STATUS_R })));
    if (d.island) screen.appendChild(h('div.k-island', { 'aria-hidden': 'true' }));
    if (d.punch) screen.appendChild(h('div.k-punch', { 'aria-hidden': 'true' }));
    if (d.hinge) {
      var v = d.hinge.axis === 'v';
      var hv = h('div.k-hinge.' + (v ? 'v' : 'h'), { 'aria-hidden': 'true', title: 'Hinge band ' + d.hinge.at + ' to ' + (d.hinge.at + d.hinge.size).toFixed(1) + ' pt (nothing interactive here)' });
      if (v) { hv.style.left = d.hinge.at + 'px'; hv.style.width = d.hinge.size + 'px'; } else { hv.style.top = d.hinge.at + 'px'; hv.style.height = d.hinge.size + 'px'; }
      screen.appendChild(hv);
    }
    screen.appendChild(h('div.k-home', { 'aria-hidden': 'true' }));
    var dev = h('div.k-device', { dataset: { device: ctx.key } }, h('div.k-bezel', { style: { '--r': d.r + 'px', '--bz': d.bezel + 'px' } }, screen));
    return dev;
  };

  /**
   * A page (tab root or pushed): wallpaper, scrolling body with large title, header buttons, tab bar or rail or flyout.
   * @param {object} ctx
   * @param {{title:string, subtitle?:string, section?:string, back?:string|boolean, body?:Node|Node[], connection?:'live'|'offline'|'reconnecting'|'reconnecting-chip',
   *   badge?:number, choresBadge?:number, flyoutOpen?:boolean, floating?:Node, scrollTop?:number, noTabs?:boolean, profileName?:string, bottomPad?:number}} o
   *   section: which tab/flyout row is selected ('home'|'security'|'climate'|'chores'|'settings'); back: pushed page (label for VoiceOver);
   *   connection: 'reconnecting' draws the in-flight arc left of Quick Links; 'reconnecting-chip' draws today's orange chip (the "was");
   *   badge: Profile attention count; choresBadge: overdue chores on the Chores tab/row; floating: a FloatingActionBar node.
   */
  Mock.page = function (ctx, o) {
    o = o || {};
    var K = C(), d = ctx.device, barBottom = d.barTop + 44;
    var page = h('div.ui-page', { style: { '--bar-top': d.barTop + 'px', '--bar-bottom': barBottom + 'px', '--rail-w': d.rail + 'px', '--safe-top': d.safeTop + 'px' } });
    page.appendChild(h('div.ui-wall'));
    var lead = o.back ? K.BackButton({ label: typeof o.back === 'string' ? o.back : 'Back' }) : (d.menu && !d.menuInRail ? K.HamburgerButton() : null);
    var bar = h('div.ui-bar', lead);
    if (d.titleInHeader && !o.back) bar.appendChild(h('h1.ui-t-large', { style: { marginLeft: lead ? 0 : 4, whiteSpace: 'nowrap' } }, o.title));
    else if (d.titleInHeader && o.back) bar.appendChild(h('h1.ui-t-large', { style: { whiteSpace: 'nowrap' } }, o.title));
    bar.appendChild(h('div.sp'));
    if (o.connection === 'reconnecting') bar.appendChild(K.ReconnectingArc({ on: true }));
    if (!d.rail) {
      bar.appendChild(K.QuickLinksButton());
      bar.appendChild(K.ProfileButton({ badge: o.badge, offline: o.connection === 'offline', name: o.profileName }));
    }
    page.appendChild(bar);

    var scroll = h('div.ui-scroll');
    var bottom = (d.tabs === 'floating' ? 110 : 24) + (o.floating ? 64 : 0) + (o.bottomPad || 0);
    scroll.style.setProperty('--bottom-pad', bottom + 'px');
    if (!d.titleInHeader) scroll.appendChild(h('div.ui-title-wrap', h('h1.ui-t-large', o.title), o.subtitle ? h('p.sub', o.subtitle) : null));
    else scroll.appendChild(h('div', { style: { height: '4px' } }));
    var body = h('div.ui-body', o.body);
    scroll.appendChild(body);
    scroll.addEventListener('scroll', function () { scroll.style.setProperty('--ramp', Math.min(40, scroll.scrollTop) + 'px'); });
    page.appendChild(scroll);
    if (o.scrollTop) requestAnimationFrame(function () { scroll.scrollTop = o.scrollTop; });

    if (o.connection === 'offline' || o.connection === 'reconnecting-chip') {
      page.appendChild(h('div', { style: { position: 'absolute', left: 0, right: d.rail + 'px', top: (barBottom + 4) + 'px', zIndex: 15, pointerEvents: 'none' } }, K.OfflineChip({ variant: o.connection === 'offline' ? 'offline' : 'reconnecting' })));
    }
    if (o.floating) {
      var bot = d.tabs === 'floating' ? 22 + 62 + 6 : Math.max(12, d.safeBottom - 8);
      page.appendChild(h('div.ui-actions-slot', { style: { bottom: bot + 'px' } }, o.floating));
    }
    if (d.tabs === 'floating' && !o.noTabs) page.appendChild(K.TabBar({ selected: o.section || 'home', badges: { chores: o.choresBadge } }));
    if (d.rail) {
      var rail = h('div.ui-rail');
      if (d.menuInRail && d.menu) rail.appendChild(K.HamburgerButton({ inRail: true }));
      rail.appendChild(K.RailGroup({ badge: o.badge }));
      rail.appendChild(h('div.grow'));
      if (d.tabs === 'rail' && !o.noTabs) rail.appendChild(K.TabBar({ selected: o.section || 'home', orientation: 'vertical', badges: { chores: o.choresBadge } }));
      page.appendChild(rail);
    }
    if (o.flyoutOpen) page.appendChild(K.NavigationFlyout({ selected: o.section || 'home', badges: { chores: o.choresBadge } }));
    return page;
  };

  /**
   * Two columns on the on-demand split (SplitPolicy.geometry): leading ends at the hinge (Duo) or the midpoint (iPad landscape), the band
   * between them stays empty. Returns the single stacked column when the window may not split (portrait, compact, a pane under 360 pt).
   * @param {object} ctx
   * @param {{leading:Node[], trailing:Node[], forceSplit?:boolean}} o  leading/trailing: the panes' children (a .ui-bleed child ignores pane padding)
   */
  Mock.split = function (ctx, o) {
    var g = ctx.splitGeometry;
    if (!g) {
      var col = h('div.ui-split', { style: { flexDirection: 'column', gap: '24px', alignItems: 'stretch' } });
      [].concat(o.leading || [], o.trailing || []).forEach(function (n) { col.appendChild(h('div', { class: n.classList && n.classList.contains('ui-bleed') ? 'ui-bleed' : '', style: n.classList && n.classList.contains('ui-bleed') ? {} : { margin: '0 16px' } }, n)); });
      col.classList.add('ui-bleed'); col.style.margin = '0';
      return col;
    }
    var s = h('div.ui-split.ui-bleed', { style: { margin: 0 } },
      h('div.pane', { style: { width: g.leading + 'px' } }, o.leading),
      h('div.band', { style: { width: g.band + 'px', alignSelf: 'stretch' }, 'aria-hidden': 'true' }),
      h('div.pane', { style: { width: g.trailing + 'px' } }, o.trailing));
    return s;
  };

  /**
   * Demo of a sheet presenting over the stage's current page and dismissing again (for the Transitions list). The page becomes the presenter,
   * the system sheet slides up (presenter scales back and dims), holds, then slides down. Reduce Motion cross-fades (Mock.anim.sheet).
   * @param {HTMLElement} stage the .screen from play(stage); @param {object} sheetOpts as Mock.sheet; @param {{hold?:number}} [o]
   */
  Mock.presentDemo = function (stage, sheetOpts, o) {
    var ctx = Mock.current, page = stage.querySelector('.ui-page');
    if (!page || !ctx) return Promise.resolve();
    var parent = page.parentNode, next = page.nextSibling;
    var host = Mock.sheet(ctx, Object.assign({}, sheetOpts, { presenter: page }));
    parent.insertBefore(host, next);
    return Mock.anim.sheet(host, 'in').then(function () { return Mock.sleep((o && o.hold) || 900); }).then(function () { return Mock.anim.sheet(host, 'out'); }).then(function () {
      page.style.transform = ''; parent.insertBefore(page, host); host.remove();
    });
  };

  /**
   * A presented modal over an optional presenter page.
   * @param {object} ctx
   * @param {{title:string, subtitle?:string, detent?:'medium'|'large'|'fitted', size?:'page'|'form', leading?:'none'|'back'|'cancel'|Node,
   *   trailing?:'close'|'confirm'|'none'|Node, confirm?:{enabled?:boolean, busy?:boolean, title?:string}, content:Node|Node[], tabs?:Node,
   *   appearance?:'system'|'dark', presenter?:Node, alert?:Node, grabber?:boolean}} o
   *   detent: compact width opens at medium (about half the window), large (below the status bar) or fitted (content plus safe areas, capped at
   *   large; hassSheet's default). Regular width ignores detents except `large`: iPad and the unfolded Duo present a centred form (540 pt)
   *   or page (704 pt) sheet, fitted to the content (iOS 18 and later). appearance 'dark' = always dark (Weather, camera viewer, Login,
   *   Location permission); otherwise the sheet follows ctx.appearance (the Appearance control). The presenter scales back and dims (compact).
   */
  Mock.sheet = function (ctx, o) {
    var K = C(), d = ctx.device;
    var dark = o.appearance === 'dark' || ctx.appearance === 'dark';
    var detent = o.detent || 'fitted';
    var compact = ctx.compact;
    var host = h('div.ui-host' + (compact ? '' : '.regular'), { dataset: { indicator: !dark && compact ? 'dark' : 'light' }, style: { display: 'flex', justifyContent: 'center', alignItems: compact ? 'flex-end' : 'center' } });
    if (o.presenter) {
      var pres = h('div.ui-presenter', o.presenter);
      if (compact) { pres.style.transform = 'translateY(10px) scale(.92)'; pres.style.borderRadius = '38px'; }
      host.appendChild(pres);
    }
    host.appendChild(h('div.ui-dim'));
    var panel = h('div.ui-sheet.in-sheet.' + (dark ? 'g-dark' : 'g-light'), { role: 'dialog', aria: { modal: 'true', label: o.title }, dataset: { detent: detent, size: o.size || 'form' } });
    panel.style.position = 'relative';
    var top = d.sheetTop;
    if (compact) {
      panel.style.width = '100%'; panel.style.borderRadius = '38px 38px 0 0'; panel.style.paddingBottom = d.safeBottom + 'px';
      if (detent === 'medium') panel.style.height = '50%';
      else if (detent === 'large') panel.style.height = 'calc(100% - ' + top + 'px)';
      else panel.style.maxHeight = 'calc(100% - ' + top + 'px)';
    } else {
      var width = Math.min(o.size === 'page' ? 704 : 540, d.w - 64);
      panel.style.width = width + 'px'; panel.style.borderRadius = '28px'; panel.style.boxShadow = '0 20px 60px rgba(0,0,0,.45)';
      var maxH = d.h - 2 * top;
      if (detent === 'large') panel.style.height = Math.min(maxH, o.size === 'page' ? maxH : 620) + 'px'; else panel.style.maxHeight = maxH + 'px';
      panel.style.paddingBottom = '8px';
    }
    if (o.grabber !== false && compact) panel.appendChild(h('div.grab'));
    panel.appendChild(K.HassModal({ title: o.title, subtitle: o.subtitle, leading: o.leading, trailing: o.trailing, confirm: o.confirm, content: o.content, tabs: o.tabs, fitted: detent === 'fitted' }));
    host.appendChild(panel);
    if (o.alert) host.appendChild(h('div.ui-alert-scrim.' + (ctx.appearance === 'dark' ? 'g-dark' : 'g-light'), o.alert));
    return host;
  };
})();
