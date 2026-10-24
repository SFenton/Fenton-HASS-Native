/* ReconnectingArc and OfflineChip.
 *
 * IN FLIGHT (branch claude/reconnecting-spinner, proposals/reconnecting-spinner): the "Reconnecting…" chip under the header is replaced by a
 * 20 pt white arc to the LEFT of Quick Links, 12 pt from it (the same gap as Quick Links to Profile). It fades in over 0.35 s once the connection
 * has been down 2 s and fades out over 0.35 s when live; no text; labelled "Reconnecting to Home Assistant"; not a control. On the Duo rail it stays
 * in the page header, trailing, and never joins the rail. Today (main): apple/Sources/HassUI/App/Shell/ReconnectingChip.swift draws an orange
 * breathing dot and the word "Reconnecting…" under the header (variant 'reconnecting' of OfflineChip = the "was").
 * OfflineChip variant 'offline' is unchanged: "Offline. Showing last known values." (no network means nothing is retrying, so no arc).
 */
(function () {
  var h = Mock.h, I = Mock.icon;
  /** props: {on?:boolean (visible), hidden?:boolean} */
  Mock.register('ReconnectingArc', function (p) {
    p = p || {};
    var s = h('span.ui-slot' + (p.on !== false ? '.on' : ''), { role: 'img', 'aria-label': 'Reconnecting to Home Assistant', dataset: { anim: 'reconnecting-arc' } }, Mock.components.ArcSpinner({ size: 'compact', label: 'Reconnecting to Home Assistant', color: '#fff' }));
    s.firstChild.setAttribute('aria-hidden', 'true'); s.firstChild.removeAttribute('role');
    if (p.hidden) s.hidden = true;
    return s;
  }, { source: 'apple/Sources/HassUI/App/Shell/ReconnectingArc.swift (in flight, claude/reconnecting-spinner)', props: '{on, hidden}',
    states: [{ id: 'visible', label: 'Visible (down 2 s+)', props: { on: true } }, { id: 'hidden', label: 'Hidden (live)', props: { on: false } }] });
  /** props: {variant:'offline'|'reconnecting', text?:string} */
  Mock.register('OfflineChip', function (p) {
    p = p || {};
    var rec = p.variant === 'reconnecting';
    var chip = h('div.ui-conn', { role: 'status' }, rec ? h('i') : h('span', { html: I('icloud.slash') }), p.text || (rec ? 'Reconnecting…' : 'Offline. Showing last known values.'));
    return h('div.ui-conn-row', chip);
  }, { source: 'apple/Sources/HassUI/App/Shell/ReconnectingChip.swift', props: '{variant, text}',
    states: [{ id: 'offline', label: 'Offline', props: { variant: 'offline' } }, { id: 'was', label: 'Reconnecting chip (the "was", removed by the arc)', props: { variant: 'reconnecting' } }] });
})();
