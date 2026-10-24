/* Local helper for the devices-vacuums batch: the Vacuums page, the vacuum sheet (map, status, Controls / Rooms / Auto-Clean / Dock / Info), the area editor and the
 * cleaning report. Needs ../room-devices/_devices-vacuums.js loaded first (Mock.dv: section, swatches, actionSheet, extra glyphs). Defines Mock.dv.vac.
 * Every builder is a STAND-IN for a SwiftUI view in apple/Sources/HassUI/Features/Vacuums (named in each header). Fixture data follows VacuumGallery.swift.
 * Promote to kit: vac.mapCard (ValetudoMapCanvas + VacuumMapFrame), vac.statusChip (VacuumStatusChip), vac.orderChip / vac.badge (VacuumOrderChip, VacuumOrderBadge),
 * vac.settingRow (VacuumSettingRow), vac.actionButton (VacuumActionButton), vac.section (VacuumSection), vac.actionRow (VacuumActionRow), vac.roomCard.
 */
(function () {
  var h = Mock.h, I = Mock.icon, K = function () { return Mock.components; }, dv = Mock.dv;
  var vac = dv.vac = {};

  (function () {
    function p(d) { return '<path d="' + d + '"/>'; }
    var S = Mock.symbols;
    /* The kit draws robotic.vacuum as two circles with no filled variant, so a selected tab or an active tile fills into a blob: give it a real fill drawing (promote to kit). */
    S['robotic.vacuum'] = ['<circle cx="12" cy="12.5" r="8"/><circle cx="12" cy="12.5" r="2.3"/><path d="M12 4.5V3"/>', '<path fill-rule="evenodd" d="M12 4.5a8 8 0 1 0 0 16 8 8 0 0 0 0-16zM12 10.2a2.3 2.3 0 1 1 0 4.6 2.3 2.3 0 0 1 0-4.6z"/><path d="M11.3 2.6h1.4v2.2h-1.4z"/>'];
    if (!S['chevron.up.chevron.down']) S['chevron.up.chevron.down'] = [p('M7 9.5 12 4.5l5 5M7 14.5l5 5 5-5')];
  })();

  /* ---------------------------------------------------------------- styles */
  var css = [
    '.in-sheet.g-dark { --vc-sel: #fff; --vc-sel-ink: #1C1C1E; --vc-fill: rgba(120,120,128,.32); --vc-active: var(--fam-cleaning-glyph); }',
    '.in-sheet.g-light { --vc-sel: #1C1C1E; --vc-sel-ink: #fff; --vc-fill: rgba(120,120,128,.16); --vc-active: var(--fam-cleaning-glyph-light); }',
    /* sections and cards */
    '.vc-sec { display: flex; flex-direction: column; gap: 8px; min-width: 0; }',
    '.vc-sec > .h { margin: 0; padding: 0 16px; font: 600 var(--fs-sub)/1.25 var(--font); color: var(--ink-sheet-2); }',
    '.vc-desc { margin: 0; padding: 0 16px; font-size: var(--fs-foot); color: var(--ink-sheet-2); overflow-wrap: anywhere; }',
    '.vc-card { background: var(--sheet-cell); border-radius: var(--radius-module); padding: 16px; display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    '.vc-card .hd { display: flex; align-items: center; gap: 8px; font: 600 var(--fs-hd)/1.25 var(--font); color: var(--ink); }',
    '.vc-col { display: flex; flex-direction: column; gap: 24px; min-width: 0; } .vc-gap12 { display: flex; flex-direction: column; gap: 12px; min-width: 0; }',
    '.vc-pad { padding: 0 16px; }',
    /* map card */
    '.vc-mapframe { position: relative; background: #262628; border-radius: var(--radius-module); overflow: hidden; min-width: 0; }',
    '.vc-mapin { padding: 12px; display: flex; justify-content: center; --mh: 300px; } .vc-mapin.big { --mh: 460px; }',
    '.vc-map { position: relative; max-width: 100%; transition: width .28s ease-in-out; } .k-reduce-motion .vc-map { transition: none; }',
    '.vc-map-x { position: relative; max-width: 100%; } .vc-map svg { display: block; width: 100%; height: 100%; }',
    '.vc-map .lb { position: absolute; transform: translate(-50%, -50%); display: flex; flex-direction: column; align-items: center; gap: 3px; pointer-events: none; font: 600 11px/1.15 var(--font); color: rgba(255,255,255,.92); white-space: nowrap; text-align: center; }',
    '.vc-map .lb.sel { color: #1C1C1E; } .vc-map .lb .bd { width: 22px; height: 22px; border-radius: 50%; background: #1C1C1E; color: #fff; display: grid; place-items: center; font: 700 12px/1 var(--font); }',
    '.vc-locate { position: absolute; left: 8px; top: 8px; z-index: 3; color: var(--glass-ink); }',
    '.vc-mapfb { min-height: 220px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; padding: 16px; text-align: center; color: #fff; } .vc-mapfb b { font: 600 var(--fs-hd)/1.2 var(--font); } .vc-mapfb span { font-size: var(--fs-sub); overflow-wrap: anywhere; }',
    '.vc-mapfb .ui-arc, .vc-mapfb .ui-arc svg { color: #fff; }',
    /* chips */
    '.vc-flow { display: flex; flex-wrap: wrap; gap: 8px; }',
    '.vc-chip { display: inline-flex; align-items: center; gap: 6px; min-height: 36px; padding: 8px 12px 8px 10px; border-radius: 999px; background: var(--sheet-cell); color: var(--ink); font: 600 var(--fs-sub)/1.2 var(--font); font-variant-numeric: tabular-nums; }',
    '.vc-chip .ui-sym { color: var(--ct, var(--ink)); transition: color var(--t-state) var(--ease-state); }',
    '.vc-ochip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 10px 3px 3px; border-radius: 999px; background: var(--vc-sel); color: var(--vc-sel-ink); font: 600 var(--fs-sub)/1.2 var(--font); }',
    '.ui-tile .ti, .ui-tile .st, .ui-mrow .ti, .ui-mrow .su { overflow-wrap: anywhere; }',
    '.in-sheet .ui-mrow .ti, .in-sheet .ui-mrow .su, .vc-sec > .h, .vc-card .hd, .vc-room .ti, .vc-sbtn, .vc-tool { overflow-wrap: anywhere; }',
    '.in-sheet .ui-info, .in-sheet .ui-info .h, .in-sheet .ui-info p { overflow-wrap: anywhere; min-width: 0; }',
    '.vc-badge { min-width: calc(24px * var(--sc)); min-height: calc(24px * var(--sc)); padding: 0 3px; box-sizing: border-box; border-radius: 50%; background: var(--vc-sel-ink); color: var(--vc-sel); display: grid; place-items: center; font: 700 var(--fs-foot)/1 var(--font); font-variant-numeric: tabular-nums; }',
    /* rows and settings */
    '.ui-mlist > .vc-set { position: relative; } .ui-mlist > * + .vc-set::before, .ui-mlist > .vc-set + *::before { content: ""; position: absolute; top: 0; left: var(--sep-inset, 56px); right: 0; height: .5px; background: var(--sep); }',
    '.vc-set .ui-seg { margin: 0 16px 12px; } .vc-set .ui-mrow .ac { flex: none; } .vc-seg170 { width: 170px; max-width: 45%; } .vc-seg170 .ui-seg button { min-height: 32px; }',
    '.vc-menu { display: inline-flex; align-items: center; gap: 4px; min-height: 44px; color: var(--ink-action); font-size: var(--fs-body); } .vc-menu.off { color: var(--ink-sheet-2); } .vc-set .vc-menurow { padding: 0 16px 8px; }',
    '.vc-selrow { display: flex; flex-direction: column; gap: 8px; padding: 12px 16px 16px; min-height: 44px; width: 100%; text-align: left; background: none; border: 0; color: inherit; font: inherit; cursor: pointer; }',
    '.vc-selrow .t { display: flex; justify-content: space-between; align-items: center; font: 600 var(--fs-sub)/1.25 var(--font); color: var(--ink-sheet-2); } .vc-selrow .t .ui-sym { font-size: var(--fs-foot); }',
    '.vc-trail { font-size: var(--fs-body); font-variant-numeric: tabular-nums; text-align: right; overflow-wrap: anywhere; }',
    /* buttons */
    '.vc-ab { display: flex; flex-direction: column; gap: 4px; min-width: 0; flex: 1 1 0; } .vc-ab .d { padding: 0 16px; font-size: var(--fs-foot); color: var(--ink-sheet-2); overflow-wrap: anywhere; }',
    '.vc-sbtn { display: flex; align-items: center; justify-content: center; gap: 8px; width: 100%; min-height: 50px; padding: 8px 16px; border: 0; border-radius: 999px; background: var(--vc-fill); color: var(--ink); font: 600 var(--fs-body)/1.25 var(--font); text-align: center; cursor: pointer; }',
    '.vc-sbtn[disabled] { opacity: .45; cursor: default; } .vc-sbtn .ui-sym { flex: none; }',
    '.vc-btnrow { display: flex; gap: 10px; align-items: flex-start; } .ts-ax5 .vc-btnrow { flex-direction: column; align-items: stretch; } .vc-btnrow.stack { flex-direction: column; align-items: stretch; }',
    '.vc-tool { display: flex; align-items: center; justify-content: center; gap: 6px; flex: 1 1 0; min-width: 0; min-height: 44px; padding: 4px 8px; border: 0; border-radius: 999px; background: var(--vc-fill); color: var(--ink); font: 600 var(--fs-sub)/1.2 var(--font); cursor: pointer; transition: background-color var(--t-state) var(--ease-state); }',
    '.vc-tool.on { background: #0071E3; color: #fff; } .vc-tool[disabled] { opacity: .45; } .vc-toolbar { display: flex; gap: 8px; }',
    /* room cards */
    '.vc-rooms { display: grid; gap: 8px; grid-template-columns: repeat(auto-fill, minmax(min(100%, calc(150px * var(--sc))), 1fr)); } .vc-rooms.two { grid-template-columns: repeat(2, minmax(0, 1fr)); } .ts-ax5 .vc-rooms.two { grid-template-columns: 1fr; }',
    '.vc-room { position: relative; display: flex; flex-direction: column; gap: 8px; min-height: 76px; padding: 12px; border: 0; border-radius: var(--radius-tile); background: var(--sheet-cell); color: var(--ink); text-align: left; font: inherit; cursor: pointer; transition: background-color var(--t-state) var(--ease-state), color var(--t-state) var(--ease-state); }',
    '.vc-room .top { display: flex; justify-content: space-between; align-items: flex-start; gap: 4px; } .vc-room .g { font-size: var(--fs-t3); color: var(--ink-sheet-2); transition: color var(--t-state) var(--ease-state); } .vc-room.off .g { opacity: .5; }',
    '.vc-room .ti { font: 600 var(--fs-body)/1.25 var(--font); overflow-wrap: anywhere; } .vc-room.sel { background: var(--vc-sel); color: var(--vc-sel-ink); } .vc-room.sel .g { color: var(--vc-sel-ink); }',
    /* area editor */
    '.vc-edmap { border-radius: var(--radius-tile); overflow: hidden; background: #262628; display: flex; justify-content: center; padding: 12px; --mh: 420px; }',
    '.vc-dim { font: 600 var(--fs-hd)/1.25 var(--font); color: var(--ink); display: block; } .vc-dim + span { font-size: var(--fs-sub); color: var(--ink-sheet-2); display: block; margin-top: 2px; }',
    /* the pushed page */
    '.vc-trailst { color: var(--ink-sheet-2); font-size: var(--fs-sub); text-align: right; overflow-wrap: anywhere; max-width: 45%; }',
    /* Vacuums page */
    '.vc-summary { margin: 0; font: 400 var(--fs-sub)/1.25 var(--font); color: rgba(255,255,255,.85); font-variant-numeric: tabular-nums; }',
    '.vc-pagecol { display: flex; flex-direction: column; gap: 24px; } .vc-pagecol .rob { display: flex; flex-direction: column; gap: 8px; }',
  ].join('\n');
  var st = document.getElementById('vc-style');
  if (!st) { st = document.createElement('style'); st.id = 'vc-style'; document.head.appendChild(st); }
  st.textContent = css;

  /* ---------------------------------------------------------------- fixtures */
  /* Robots (Vacuums.mainFloor, musicRoom, theaterRoom). */
  vac.ROBOTS = {
    main: { title: 'Main Floor', battery: 87, hasAutoClean: true, zones: ['living_room', 'master_bedroom', 'kitchen', 'office', 'hallway', 'guest_room', 'master_bathroom', 'guest_bathroom', 'gym', 'closet', 'dining_room'], selectRooms: true, rot: 180, map: 'main' },
    music: { title: 'Music Room', battery: 100, hasAutoClean: false, zones: ['music_room', 'ds_hallway', 'ds_bathroom'], selectRooms: true, rot: 0, map: 'music' },
    theater: { title: 'Theater Room', battery: 64, hasAutoClean: false, zones: [], selectRooms: false, rot: 0, map: 'theater' },
  };
  var ZONE = {
    living_room: ['Living Room', 'sofa'], master_bedroom: ['Master Bedroom', 'bed.double'], kitchen: ['Kitchen', 'refrigerator'], office: ['Office', 'laptopcomputer'], hallway: ['Hallway', 'cabinet'],
    guest_room: ['Guest Room', 'bed.double'], master_bathroom: ['Master Bathroom', 'shower'], guest_bathroom: ['Guest Bathroom', 'shower'], gym: ['Gym', 'dumbbell'], closet: ['Closet', 'cabinet'],
    dining_room: ['Dining Room', 'fork.knife'], music_room: ['Clean Music Room', 'guitars'], ds_hallway: ['Clean Downstairs Hallway', 'cabinet'], ds_bathroom: ['Clean Downstairs Bathroom', 'shower'],
  };
  vac.zoneTitle = function (id) { return ZONE[id][0]; };
  /* Map rooms (viewBox units): id, name (the map's own name), x, y, w, h. */
  var MAPS = {
    main: { w: 300, h: 360, rooms: [['living_room', 'Living Room', 0, 0, 150, 150], ['dining_room', 'Dining Room', 150, 0, 150, 70], ['kitchen', 'Kitchen', 150, 70, 150, 80], ['hallway', 'Hallway', 0, 150, 300, 30],
      ['master_bedroom', 'Master Bedroom', 0, 180, 110, 180], ['master_bathroom', 'Master Bathroom', 110, 180, 90, 80], ['closet', 'Master Bedroom Closet', 110, 260, 90, 100], ['office', 'Office', 200, 180, 100, 50],
      ['gym', 'Gym', 200, 230, 100, 50], ['guest_room', 'Guest Room', 200, 280, 50, 80], ['guest_bathroom', 'Guest Bathroom', 250, 280, 50, 80]], dock: [14, 12], rot: 180 },
    music: { w: 300, h: 200, rooms: [['music_room', 'Music Room', 0, 0, 190, 200], ['ds_hallway', 'Downstairs Hallway', 190, 0, 110, 110], ['ds_bathroom', 'Downstairs Bathroom', 190, 110, 110, 90]], dock: [14, 100], rot: 0 },
    theater: { w: 300, h: 220, rooms: [['t1', '', 0, 0, 200, 220], ['t2', '', 200, 0, 100, 120], ['t3', '', 200, 120, 100, 100]], dock: [14, 110], rot: 0, noNames: true },
  };
  var RAMP = ['#50565F', '#5A616B', '#454B54', '#565D66', '#4B5159', '#40464E', '#5E656F', '#4D535C', '#575E68', '#474D55'];
  function rot(m, r) { return m.rot === 180 ? [m.w - r[2] - r[4], m.h - r[3] - r[5], r[4], r[5]] : [r[2], r[3], r[4], r[5]]; }
  function mp(m, x, y) { return m.rot === 180 ? [m.w - x, m.h - y] : [x, y]; }

  /**
   * ValetudoMapCanvas on its dark card (direction G: flat neutral rooms; selected rooms white with black numbered badges; skipped rooms hatched).
   * o: {map:'main'|'music'|'theater', selected:[ids in order], skipped:[ids], robot:'dock'|[x,y]|null, reported?, path?:[[x,y]...], area?:{x,y,w,h} (viewBox units, unrotated), handles?, names?:true, scale?:0.85}
   */
  vac.mapCanvas = function (o) {
    var m = MAPS[o.map || 'main'], sc = o.scale || .85, sel = o.selected || [], skipped = o.skipped || [], ratio = m.w / m.h, labels = [];
    var svg = '<svg viewBox="0 0 ' + m.w + ' ' + m.h + '" aria-hidden="true"><defs>';
    skipped.forEach(function (id) { svg += '<clipPath id="vc-clip-' + id + '-' + (vac._n = (vac._n || 0) + 1) + '"></clipPath>'; });
    svg += '<pattern id="vc-hatch" width="7" height="7" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="7" stroke="rgba(20,21,24,.75)" stroke-width="2.4"/></pattern></defs>';
    svg += '<rect width="' + m.w + '" height="' + m.h + '" fill="#262628"/>';
    var rooms = m.rooms.map(function (r, i) { var g = rot(m, r); return { id: r[0], name: r[1], x: g[0], y: g[1], w: g[2], h: g[3], i: i }; });
    rooms.forEach(function (r) { svg += '<rect x="' + (r.x + 1.5) + '" y="' + (r.y + 1.5) + '" width="' + (r.w - 3) + '" height="' + (r.h - 3) + '" fill="' + (sel.indexOf(r.id) >= 0 ? '#EDEFF2' : RAMP[r.i % RAMP.length]) + '"/>'; });
    rooms.forEach(function (r) { if (skipped.indexOf(r.id) >= 0) svg += '<rect x="' + (r.x + 1.5) + '" y="' + (r.y + 1.5) + '" width="' + (r.w - 3) + '" height="' + (r.h - 3) + '" fill="url(#vc-hatch)"/>'; });
    if (o.path) svg += '<polyline fill="none" stroke="rgba(138,144,153,.9)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" points="' + o.path.map(function (p) { var q = mp(m, p[0], p[1]); return q[0] + ',' + q[1]; }).join(' ') + '"/>';
    var d = mp(m, m.dock[0], m.dock[1]); svg += '<rect x="' + (d[0] - 5) + '" y="' + (d[1] - 10) + '" width="10" height="20" rx="3.5" fill="#C9CDD3" stroke="#1E1F22" stroke-width="1.2"/>';
    if (o.area) { var a = o.area; svg += '<rect x="' + a.x + '" y="' + a.y + '" width="' + a.w + '" height="' + a.h + '" fill="rgba(64,156,255,.22)" stroke="#409CFF" stroke-width="2"/>';
      if (o.handles) [[a.x, a.y], [a.x + a.w, a.y], [a.x, a.y + a.h], [a.x + a.w, a.y + a.h]].forEach(function (c) { svg += '<circle cx="' + c[0] + '" cy="' + c[1] + '" r="8" fill="#fff" stroke="#0071E3" stroke-width="2"/>'; }); }
    if (o.robot) { var rp = o.robot === 'dock' ? [d[0] + 18, d[1]] : mp(m, o.robot[0], o.robot[1]); var col = o.reported ? '#8A9099' : '#fff';
      svg += '<circle cx="' + rp[0] + '" cy="' + rp[1] + '" r="15" fill="rgba(255,255,255,.22)"/><circle cx="' + rp[0] + '" cy="' + rp[1] + '" r="9" fill="' + col + '" stroke="#1C1C1E" stroke-width="2.2"/><circle cx="' + rp[0] + '" cy="' + rp[1] + '" r="3" fill="#1C1C1E"/>'; }
    svg += '</svg>';
    if (o.names !== false && !m.noNames) rooms.forEach(function (r) {
      var order = sel.indexOf(r.id) + 1, len = r.name.length;
      var nameFits = r.w * sc >= len * 6.3 + 8 && r.h * sc >= 18, both = order && r.h * sc >= 22 + 3 + 14 + 4;
      var left = (r.x + r.w / 2) / m.w * 100, top = (r.y + r.h / 2) / m.h * 100;
      if (order && nameFits && both) labels.push(h('div.lb.sel', { style: { left: left + '%', top: top + '%' } }, h('span.bd', String(order)), h('span', r.name)));
      else if (order) labels.push(h('div.lb.sel', { style: { left: left + '%', top: top + '%' } }, h('span.bd', String(order))));
      else if (nameFits) labels.push(h('div.lb', { style: { left: left + '%', top: top + '%' } }, h('span', r.name)));
    });
    return h('div.vc-map', { style: { width: 'min(100%, calc(var(--mh, 300px) * ' + ratio.toFixed(3) + '))', aspectRatio: String(ratio) } }, h('div', { html: svg, style: { position: 'absolute', inset: 0 } }), labels);
  };
  /** VacuumMapFrame: the map card with its Locate button, or the loading / unavailable fallback. o: all vac.mapCanvas props plus {big, fallback:'unavailable'|'loading'|'loading-last', locate:true, title} */
  vac.mapCard = function (o) {
    var inner;
    if (o.fallback === 'unavailable') inner = h('div.vc-mapfb', { role: 'group', 'aria-label': 'Map Unavailable' }, h('b', 'Map Unavailable'), h('span', 'Home Assistant cannot currently confirm the vacuum\'s map or position.'));
    else if (o.fallback) inner = h('div.vc-mapfb', { role: 'group', 'aria-label': o.fallback === 'loading' ? 'Loading Current Map' : 'Loading Last Vacuum Map Position' }, K().ArcSpinner({ size: 'page' }), h('span', o.fallback === 'loading' ? 'Loading Current Map…' : 'Loading Last Vacuum Map Position…'));
    else inner = h('div.vc-mapin' + (o.big ? '.big' : ''), { role: 'img', 'aria-label': (o.title || 'Main Floor') + ' Valetudo map' + (o.selected && o.selected.length ? ', selected rooms: ' + o.selected.map(vac.zoneTitle).join(', ') : '') }, vac.mapCanvas(o));
    return h('div.vc-mapframe', inner, o.locate === false ? null : h('button.ui-circle.ui-glass.vc-locate', { type: 'button', 'aria-label': 'Locate', title: 'Locate', html: I('scope', { weight: 2 }) }));
  };

  /* ---------------------------------------------------------------- state and format helpers */
  var VIS = { cleaning: ['sparkles', 'active'], docked: ['checkmark.circle.fill', 'ok'], returning: ['arrow.uturn.left.circle', 'returning'], paused: ['pause.circle', 'warning'], error: ['exclamationmark.circle', 'danger'], idle: ['robotic.vacuum', 'neutral'], unavailable: ['questionmark.circle', 'unavailable'] };
  var TONE = { active: 'var(--vc-active)', ok: 'var(--ink-success)', returning: 'var(--ink-action)', warning: 'var(--ink-warning)', danger: 'var(--ink-danger)', neutral: 'var(--ink-sheet-2)', unavailable: 'var(--ink-sheet-2)' };
  vac.TONE = TONE;
  vac.cap = function (s) { return s.replace(/\b\w/g, function (c) { return c.toUpperCase(); }); };
  function batterySym(b) { return b == null ? 'battery.0percent' : b < 13 ? 'battery.0percent' : b < 38 ? 'battery.25percent' : b < 63 ? 'battery.50percent' : b < 88 ? 'battery.75percent' : 'battery.100percent'; }
  /** A scenario's facts. o: {robot, scenario, selected, area, dock, mop, map} */
  vac.V = function (o) {
    o = o || {}; var R = vac.ROBOTS[o.robot || 'main'];
    var v = Object.assign({ robot: o.robot || 'main', title: R.title, scenario: 'docked', state: 'docked', battery: R.battery, dock: 'idle', dockLabel: 'Idle', mop: true, issue: null, resumable: false, lowBattery: false,
      selected: o.robot === 'music' ? ['music_room'] : (R.selectRooms ? ['kitchen', 'living_room'] : []), area: null, skipped: R.hasAutoClean ? ['guest_room'] : [], map: 'live', report: R.hasAutoClean ? 'typed' : null, notices: [] }, o);
    var sc = v.scenario;
    if (sc === 'cleaning') Object.assign(v, { state: 'cleaning', battery: v.battery > 80 ? 74 : v.battery });
    if (sc === 'dock-prep') Object.assign(v, { state: 'cleaning', dock: 'cleaning', dockLabel: 'Cleaning' });
    if (sc === 'paused') Object.assign(v, { state: 'paused' });
    if (sc === 'returning') Object.assign(v, { state: 'returning' });
    if (sc === 'error') Object.assign(v, { state: 'error', issue: 'Main brush jammed' });
    if (sc === 'stuck') Object.assign(v, { state: 'error', issue: 'Cannot reach target' });
    if (sc === 'resumable') Object.assign(v, { state: 'docked', resumable: true });
    if (sc === 'lowbattery') Object.assign(v, { state: 'error', issue: 'Low battery', lowBattery: true, battery: 12 });
    if (sc === 'unavailable') Object.assign(v, { state: 'unavailable', battery: null, dock: 'unavailable', dockLabel: 'Unavailable', map: o.map || 'reported' });
    v.minimal = !(v.state === 'docked' || v.state === 'idle') || v.resumable || !!v.issue || v.state === 'unavailable';
    v.available = v.state !== 'unavailable';
    return v;
  };
  vac.stateLabel = function (v) { return v.state === 'unavailable' ? 'Unavailable' : vac.cap(v.state); };
  vac.subtitle = function (v) { return vac.stateLabel(v) + (v.battery == null ? '' : ' · ' + v.battery + '%'); };
  /** Tabs in the runtime mode (VacuumRuntime.tabs). */
  vac.tabs = function (v) {
    var R = vac.ROBOTS[v.robot], activeDock = v.dock === 'cleaning' || v.dock === 'drying', t = [{ id: 'controls', title: 'Controls', symbol: 'robotic.vacuum' }];
    if (!v.minimal && R.zones.length) t.push({ id: 'zones', title: 'Rooms', symbol: 'square.split.2x2' });
    if (R.hasAutoClean) t.push({ id: 'autoClean', title: 'Auto-Clean', symbol: 'clock.arrow.circlepath' });
    if (!v.minimal || activeDock) t.push({ id: 'more', title: 'Dock', symbol: 'ev.charger' });
    t.push({ id: 'info', title: 'Info', symbol: 'info.circle' });
    return t;
  };
  vac.tabBar = function (v, sel, ctx) { return K().ModalTabBar({ ctx: ctx, tabs: vac.tabs(v), selected: sel }); };

  /* ---------------------------------------------------------------- small views */
  /** VacuumSection: a 15 pt semibold secondary header over a group, optional footer. */
  vac.section = function (title, kids, footer) { return h('section.vc-sec', { role: 'group', 'aria-label': title }, h('h3.h', { role: 'heading', 'aria-level': '3' }, title), kids, footer ? h('p.vc-desc', footer) : null); };
  vac.desc = function (t) { return h('p.vc-desc', t); };
  vac.card = function (kids) { return h('div.vc-card', kids); };
  vac.badge = function (n) { return h('span.vc-badge', { 'aria-hidden': 'true' }, String(n)); };
  vac.orderChip = function (n, title) { return h('span.vc-ochip', { role: 'img', 'aria-label': n + '. ' + title }, vac.badge(n), title); };
  vac.statusChip = function (o) { return h('span.vc-chip', { role: 'group', 'aria-label': o.label + ': ' + o.value, style: { '--ct': o.tint || 'var(--ink)' } }, h('span', { html: I(o.symbol, { fill: /fill$/.test(o.symbol) }) }), h('span', o.value)); };
  vac.actionButton = function (a) {
    /* a: {title, symbol, tone:'primary'|'neutral'|'warning'|'danger', disabled, detail, showDetail} */
    var b;
    if (a.tone === 'primary') { b = K().PrimaryButton({ title: a.title, symbol: a.symbol, disabled: a.disabled }); }
    else { b = h('button.vc-sbtn', { type: 'button' }, h('span', { html: I(a.symbol), style: { color: a.tone === 'warning' ? 'var(--ink-warning)' : a.tone === 'danger' ? 'var(--ink-danger)' : 'var(--ink)', display: 'inline-flex' } }), a.title); if (a.disabled) b.disabled = true; }
    return h('div.vc-ab', b, a.detail && a.showDetail !== false ? h('div.d', a.detail) : null);
  };
  /** A setting as a ModuleRow (VacuumSettingRow). s: {title, symbol, detail, options:[labels], value} */
  vac.settingRow = function (s, ctx, o) {
    o = o || {}; var ax = ctx && ctx.axSize, n = s.options.length, seg = !ax && n >= 2 && n <= 4, short = s.options.every(function (x) { return x.length <= 3; });
    var row = function (acc) { return K().ModuleRow({ title: s.title, subtitle: s.detail, symbol: s.symbol, accessory: acc }); };
    var menu = h('span.vc-menu' + (s.disabled ? '.off' : ''), { role: 'button', 'aria-haspopup': 'menu', 'aria-label': s.title + ', ' + s.value }, s.value, h('span', { html: I('chevron.up.chevron.down', { weight: 2.2, size: '.8em' }) }));
    var segs = K().SegmentedChoice({ options: s.options, selected: s.value, label: s.title, style: 'segmented', large: true });
    if (seg && short) return h('div.vc-set', row(h('span.vc-seg170', segs)));
    if (seg) return h('div.vc-set', row(), segs);
    if (ax) return h('div.vc-set', row(), h('div.vc-menurow', menu));
    return h('div.vc-set', row(menu));
  };
  /** VacuumActionRow: a dock command with a blue title. a: {title, symbol, detail, tone:'neutral'|'warning'|'danger', disabled} */
  vac.actionRow = function (a) {
    var tint = a.disabled ? 'var(--ink-sheet-2)' : a.tone === 'warning' ? 'var(--ink-warning)' : a.tone === 'danger' ? 'var(--ink-danger)' : 'var(--ink-action)';
    var r = K().ModuleRow({ title: a.title, subtitle: a.detail, symbol: a.symbol, glyph: tint, press: !a.disabled });
    r.querySelector('.ti').style.color = a.disabled ? 'var(--ink-sheet-2)' : 'var(--ink-action)'; r.setAttribute('aria-label', a.title); if (a.disabled) r.setAttribute('aria-disabled', 'true');
    return r;
  };
  vac.roomCard = function (id, o) {
    o = o || {}; var z = ZONE[id], on = o.order != null;
    var b = h('button.vc-room' + (on ? '.sel' : '') + (o.locked ? '.off' : ''), { type: 'button', role: 'switch', 'aria-checked': on ? 'true' : 'false', 'aria-label': on ? z[0] + ', cleaning order ' + o.order : z[0] }, h('span.top', h('span.g', { html: I(z[1]) }), on ? vac.badge(o.order) : null), h('span.ti', z[0]));
    return b;
  };

  /* ---------------------------------------------------------------- the map column: map, status, notices, report */
  vac.statusSummary = function (v) {
    var vis = VIS[v.state] || VIS.idle, tone = vis[1], flow = [];
    flow.push(vac.statusChip({ label: 'Status', value: vac.stateLabel(v), symbol: vis[0], tint: TONE[tone] }));
    flow.push(vac.statusChip({ label: 'Battery', value: v.battery == null ? 'Unknown' : v.battery + '%', symbol: batterySym(v.battery), tint: v.available ? 'var(--ink)' : 'var(--ink-sheet-2)' }));
    var dockTone = !v.available ? 'unavailable' : v.dock === 'cleaning' || v.dock === 'drying' ? 'active' : v.dock === 'emptying' ? 'warning' : 'neutral';
    flow.push(vac.statusChip({ label: 'Dock Status', value: 'Dock ' + v.dockLabel, symbol: dockTone === 'neutral' || dockTone === 'unavailable' ? 'ev.charger' : (v.dock === 'drying' ? 'wind' : 'drop'), tint: dockTone === 'neutral' ? 'var(--ink)' : TONE[dockTone] }));
    var kids = [h('div.vc-flow', flow)];
    if (!v.available && v.map !== 'reported') kids.push(K().InfoBox({ title: 'Unavailable', message: 'Home Assistant does not have a current status for the vacuum.' }));
    if (v.issue) kids.push(K().InlineAlert({ message: 'Current Issue: ' + (v.issue === 'Cannot reach target' ? 'Can\'t reach its room. A door may be closed. Open it, then tap Resume.' : v.issue) }));
    (v.notices || []).forEach(function (n) { kids.push(n); });
    return h('div.vc-gap12', kids);
  };
  /** VacuumCleaningReport: one row that opens the room details (typed), or the protocol notice. */
  vac.reportRow = function (v, kind) {
    if (kind === 'incomplete') return vac.section('Main Floor Cleaning Report', [K().InlineAlert({ message: 'Report Still Being Prepared: Final counts are not available.' })]);
    if (kind === 'malformed') return vac.section('Main Floor Cleaning Report', [K().InlineAlert({ message: 'Report Could Not Be Read: Structured cleaning results are unavailable.' }), h('div.vc-pad', h('button.dv-act', { type: 'button', style: { background: 'none', padding: '8px 0' } }, h('span.tx', h('span.a', { style: { color: 'var(--ink-action)', fontWeight: 400 } }, 'Unstructured Report Details')), h('span.chev', { html: I('chevron.right', { weight: 2.4 }) })))]);
    if (kind === 'incompatible') return vac.section('Main Floor Cleaning Report', [K().InlineAlert({ message: 'Dashboard Update Required: This cleaning report uses an unsupported version.' })]);
    var sub = kind === 'completed' ? '10 Oct 2026 · 4 Rooms Completed' : kind === 'stuck' ? '10 Oct 2026 · 2 Rooms Completed • 1 Error' : '10 Oct 2026 · 2 Rooms Completed • 1 Room Needs Attention';
    var sym = kind === 'completed' ? 'checkmark.circle.fill' : kind === 'stuck' ? 'exclamationmark.circle' : 'pause.circle', glyph = kind === 'completed' ? 'var(--ink-success)' : kind === 'stuck' ? 'var(--ink-danger)' : 'var(--ink-warning)';
    return vac.section('Cleaning Report', [K().ModuleList({ rows: [K().ModuleRow({ title: v.title + ' Cleaning Report (4)', subtitle: sub, symbol: sym, glyph: glyph, chevron: true })] })]);
  };
  vac.mapColumn = function (ctx, v, tab, o) {
    o = o || {};
    var POS = { main: { cleaning: [220, 110], mid: [150, 165], reported: [60, 300] }, music: { cleaning: [90, 100], mid: [150, 100], reported: [100, 100] }, theater: { cleaning: [100, 110], mid: [150, 110], reported: [100, 110] } }[vac.ROBOTS[v.robot].map];
    var reported = v.map === 'reported', st = v.state;
    var robot = reported ? POS.reported : st === 'cleaning' ? POS.cleaning : (st === 'docked' || st === 'idle') ? 'dock' : POS.mid;
    var path = st === 'cleaning' && v.robot === 'main' ? [[40, 50], [110, 80], [170, 40], [240, 90], [220, 110]] : null;
    var fb = v.map === 'none' ? 'unavailable' : v.map === 'loading' ? 'loading' : v.map === 'loading-last' ? 'loading-last' : null;
    var kids = [vac.mapCard({ map: vac.ROBOTS[v.robot].map, selected: tab === 'autoClean' ? [] : v.selected, skipped: tab === 'autoClean' ? v.skipped : [], robot: robot, reported: reported, path: path, big: v.minimal, fallback: fb, title: v.title, area: v.area, locate: v.available })];
    if (reported) kids.push(K().InlineAlert({ message: 'Last Reported Position: This is the last map the vacuum reported before contact was lost. The exact report time is unknown, and the vacuum may have been moved since then.' }));
    kids.push(vac.statusSummary(v));
    if (v.report) kids.push(vac.reportRow(v, v.report));
    return h('div.vc-gap12', kids);
  };

  /* ---------------------------------------------------------------- tabs */
  vac.settings = function (v) {
    return [{ title: 'Mode', symbol: 'robotic.vacuum', detail: 'Choose whether the robot vacuums, mops, or combines both for the next run.', options: ['Vacuum', 'Mop', 'Vacuum And Mop'], value: v.modeValue || 'Vacuum And Mop' },
      { title: 'Fan', symbol: 'fan', detail: 'Adjust suction strength for carpets, hard floors, and quieter cleaning.', options: ['Low', 'Medium', 'High', 'Max', 'Turbo'], value: v.fanValue || 'Medium' },
      { title: 'Water', symbol: 'drop', detail: 'Set mop water flow so floors get the right amount of moisture.', options: ['Low', 'Medium', 'High'], value: v.waterValue || 'Medium' }].filter(function (s) {
      return !(s.title === 'Fan' && v.modeValue === 'Mop') && !(s.title === 'Water' && v.modeValue === 'Vacuum'); });
  };
  vac.passes = function (v) { return { title: 'Cleaning Passes', symbol: 'number', options: ['1x', '2x', '3x'], value: v.passesValue || '1x' }; };
  vac.runtimeCard = function (v, ctx) {
    var vis = VIS[v.state] || VIS.idle, acts = vac.actions(v), ax = ctx && ctx.axSize;
    var disabledDetail = true;
    return h('div.vc-card', { role: 'group' }, h('div.hd', { role: 'heading', 'aria-level': '3' }, h('span', { html: I(vis[0], { fill: /fill$/.test(vis[0]) }), style: { color: TONE[vis[1]], display: 'inline-flex' } }), vac.stateLabel(v)),
      h('div.vc-btnrow' + (ax || acts.length > 2 ? '.stack' : ''), acts.map(function (a) { return vac.actionButton(Object.assign({}, a, { showDetail: a.disabled })); })));
  };
  /** VacuumController.runtimeActions for a scenario. */
  vac.actions = function (v) {
    var s = v.scenario;
    if (s === 'cleaning') return [{ title: 'Pause', symbol: 'pause.fill', tone: 'warning', detail: 'Pause the current cleaning run.' }, { title: 'Stop', symbol: 'stop.fill', tone: 'danger', detail: 'Stop the current cleaning run.' }];
    if (s === 'dock-prep') return [{ title: 'Pause', symbol: 'pause.fill', tone: 'warning', disabled: true, detail: 'Pause becomes available after the robot leaves the dock.' }, { title: 'Cancel Cleaning Session', symbol: 'stop.fill', tone: 'danger', detail: 'Cancel this cleaning session before the robot leaves the dock.' }];
    if (s === 'paused') return [{ title: 'Resume', symbol: 'play.fill', tone: 'primary', detail: 'Continue the paused cleaning run.' }, { title: 'Stop', symbol: 'stop.fill', tone: 'danger', detail: 'Stop the paused cleaning run.' }];
    if (s === 'returning') return [{ title: 'Pause', symbol: 'pause.fill', tone: 'warning', detail: 'Pause the return-to-dock action.' }];
    if (s === 'error' || s === 'stuck') return [{ title: 'Stop', symbol: 'stop.fill', tone: 'danger', detail: 'Stop the current vacuum task.' }, { title: 'Dock', symbol: 'house', tone: 'neutral', detail: 'Send the robot back to the dock.' }];
    if (s === 'resumable') return [{ title: 'Resume', symbol: 'play.fill', tone: 'primary', detail: 'Continue the interrupted cleaning run.' }, { title: 'Cancel', symbol: 'stop.fill', tone: 'danger', detail: 'Cancel the pending cleaning resume.' }];
    return [];
  };
  vac.controls = function (v, ctx, o) {
    o = o || {}; var ax = ctx && ctx.axSize, kids = [], R = vac.ROBOTS[v.robot], hasRooms = R.zones.length > 0, acts = vac.actions(v);
    if (!v.minimal) {
      var areaOn = !!v.area;
      kids.push(K().SegmentedChoice({ options: ['Rooms', 'Area'], selected: areaOn ? 'Area' : 'Rooms', label: 'Cleaning Target', large: true, ctx: ctx }));
      if (areaOn) {
        kids.push(vac.desc('Draw one rectangular cleaning area on the map. The vacuum will use the mode, suction, water, and pass settings shown below.'));
        kids.push(h('div.vc-btnrow' + (ax ? '.stack' : ''), vac.actionButton({ title: 'Edit Area', symbol: 'pencil', tone: 'neutral' }), vac.actionButton({ title: 'Clear Area', symbol: 'trash', tone: 'neutral' })));
        kids.push(h('div.vc-gap12', { style: { gap: '8px' } }, K().ModuleList({ rows: [vac.settingRow(vac.passes(v), ctx)] }), vac.desc('These settings are confirmed in Home Assistant before the area-cleaning command is sent.')));
        kids.push(vac.actionButton({ title: 'Start Area Clean', symbol: 'play.fill', tone: 'primary' }));
      } else {
        var sel = v.selected, rows = [];
        if (hasRooms) rows.push(h('button.vc-selrow', { type: 'button', 'aria-label': sel.length ? 'Selected Rooms' : 'Full Clean', 'aria-description': 'Opens the Rooms section.' },
          h('span.t', h('span', sel.length ? 'Selected Rooms' : 'Full Clean'), h('span', { html: I('chevron.right', { weight: 2.4 }) })),
          sel.length ? h('div.vc-flow', { style: { gap: '6px' } }, sel.map(function (id, i) { return vac.orderChip(i + 1, vac.zoneTitle(id)); })) : K().InlineAlert({ message: 'No rooms are selected, and no areas are drawn. If you begin cleaning, the robot vacuum will attempt to clean every mapped area.' })));
        rows.push(vac.settingRow(vac.passes(v), ctx));
        kids.push(h('div.vc-gap12', { style: { gap: '8px' } }, K().ModuleList({ rows: rows, hasGlyphs: !hasRooms }), hasRooms ? vac.desc('The vacuum cleans the selected rooms in order.') : null));
        kids.push(vac.actionButton({ title: 'Clean', symbol: 'play.fill', tone: 'primary', disabled: !!o.cleanDisabled }));
      }
    }
    if (acts.length && v.minimal) kids.push(vac.runtimeCard(v, ctx));
    if (o.cleanError) kids.push(h('div.vc-pad', K().InlineAlert({ message: o.cleanError, severity: 'error' })));
    if (!acts.length && v.minimal) {
      var raw = v.issue ? (v.issue === 'Cannot reach target' ? 'Can\'t reach its room. A door may be closed. Open it, then tap Resume.' : v.issue) : 'Home Assistant does not have a current status for the vacuum.';
      kids.push(vac.section(vac.stateLabel(v), [h('div.vc-card', { style: { borderRadius: 'var(--radius-module)' } }, h('p', { style: { margin: 0, fontSize: 'var(--fs-body)', color: 'var(--ink)', overflowWrap: 'anywhere' } }, raw))]));
    }
    var stack = h('div.vc-col', { style: { gap: '24px' } }, h('div.vc-gap12', { style: { gap: '16px' } }, kids));
    if (!v.minimal) stack.appendChild(vac.section('Power Settings', [K().ModuleList({ rows: vac.settings(v).map(function (s) { return vac.settingRow(s, ctx); }) })]));
    return stack;
  };
  vac.rooms = function (v, ctx, o) {
    o = o || {}; var R = vac.ROBOTS[v.robot], kids = [];
    if (v.robot === 'main') { kids.push(vac.desc('Select any zones to focus cleaning in those areas. If you press clean and no zones are selected, we will clean all zones on the Main Floor.')); kids.push(vac.desc('Zones are not selectable or changeable while cleaning is ongoing.')); }
    else { kids.push(vac.desc('Select any zones to focus cleaning in those areas. If you press clean and no zones are selected, we will clean all zones in the Music Room.')); kids.push(vac.desc('Zones are not selectable or changeable while cleaning is ongoing.')); }
    kids.push(vac.desc('Rooms are cleaned in the order you select them. The numbered badges show the cleaning sequence.'));
    kids.push(h('div.vc-rooms.two', { role: 'group', 'aria-label': 'Rooms' }, R.zones.map(function (id) { var i = v.selected.indexOf(id); return vac.roomCard(id, { order: i >= 0 ? i + 1 : null, locked: o.locked }); })));
    return h('div.vc-gap12', kids);
  };
  vac.autoClean = function (v) {
    var rows = ['living_room', 'master_bedroom', 'kitchen', 'office', 'hallway', 'guest_room', 'master_bathroom', 'guest_bathroom', 'gym', 'closet', 'dining_room'].map(function (id) {
      var skipped = v.skipped.indexOf(id) >= 0, z = ZONE[id];
      return K().ModuleRow({ title: z[0], subtitle: skipped ? 'Skipped' : null, symbol: z[1], press: true, accessory: h('span', { html: I('checkmark', { weight: 2.4 }), style: { color: 'var(--ink-action)', opacity: skipped ? 1 : 0, display: 'inline-flex' }, 'aria-hidden': 'true' }) });
    });
    return vac.section('Disabled Auto-Clean Rooms', [K().ModuleList({ rows: rows })], 'Checked rooms are skipped when the coordinator starts an automatic away clean. Use this for closed doors, guests, or projects on the floor; manual selected-room cleans still use the Rooms section.');
  };
  vac.dock = function (v, o) {
    o = o || {}; var kids = [], prep = v.dock === 'cleaning' && v.state === 'cleaning', rows = [];
    var fresh = !v.minimal || v.dock === 'cleaning' || v.dock === 'drying';
    if (prep) rows.push(K().ModuleRow({ title: 'Washing Mop Pads', subtitle: 'The dock is washing the mop pads for the current cleaning session. To stop, use Cancel Cleaning Session on the Controls section.', symbol: 'drop', glyph: 'var(--vc-active)' }));
    var dis = !v.mop || o.bridgeMissing || v.state !== 'docked';
    if (!prep) {
      if (v.dock === 'cleaning') rows.push(vac.actionRow({ title: 'Stop Dock Clean', symbol: 'stop.fill', tone: 'warning', detail: 'Finish the dock-cleaning phase and drain the wash tray into the dirty-water tank.' }));
      else if (!v.minimal) rows.push(vac.actionRow({ title: 'Clean Mop Dock', symbol: 'drop', tone: 'neutral', disabled: dis, detail: 'Start the mop-dock cleaning phase. Use Stop Dock Clean when finished so the dock drains the wash tray.' }));
      if (v.dock === 'drying') rows.push(vac.actionRow({ title: 'Stop Mop Drying', symbol: 'stop.fill', tone: 'neutral', detail: 'Stop the current mop-drying cycle.' }));
      else if (!v.minimal) rows.push(vac.actionRow({ title: 'Dry Mops', symbol: 'wind', tone: 'neutral', disabled: dis, detail: 'Start drying the attached mop pads.' }));
    }
    if (!v.minimal) rows.push(vac.actionRow({ title: 'Empty Bin', symbol: 'trash.circle', tone: 'neutral', disabled: v.state !== 'docked', detail: 'Trigger the dock to empty the robot dustbin into its dust bag.' }));
    kids.push(K().ModuleList({ rows: rows }));
    if (!v.mop && !v.minimal) kids.push(h('div.vc-pad', K().InlineAlert({ message: 'Attach the mop pads before cleaning or drying them at the dock.' })));
    if (o.bridgeMissing) kids.push(h('div.vc-pad', K().InlineAlert({ message: 'Dock cleaning and drying controls will be available after Home Assistant restarts.' })));
    return vac.section('Dock Controls', kids);
  };
  vac.info = function (v) {
    function row(title, sym, value, tone) { var c = tone === 'warning' ? 'var(--ink-warning)' : tone === 'danger' ? 'var(--ink-danger)' : 'var(--ink-sheet-2)';
      return K().ModuleRow({ title: title, symbol: sym, glyph: c, accessory: h('span.vc-trail', { style: { color: c } }, value) }); }
    var bin = [row('Dustbag', 'exclamationmark.circle', 'Full', 'warning'), row('Fresh Water', 'drop', 'OK'), row('Waste Water', 'drop.triangle', 'OK'), row('Detergent', 'testtube.2', 'OK')];
    var cons = [row('Main Brush', 'paintbrush', '90h left'), row('Side Brush', 'paintbrush.pointed', '90h left'), row('Main Filter', 'timer', '7h left', 'warning'), row('Sensors', 'wrench.and.screwdriver', 'Due', 'danger'), row('Wheels', 'circle.circle', '90h left')];
    return h('div.vc-col', vac.section('Bin State', [K().ModuleList({ rows: bin })]), vac.section('Consumables', [K().ModuleList({ rows: cons })]));
  };
  vac.tabBody = function (v, tab, ctx, o) {
    o = o || {};
    if (tab === 'zones') return vac.rooms(v, ctx, o);
    if (tab === 'autoClean') return vac.autoClean(v);
    if (tab === 'more') return vac.dock(v, o);
    if (tab === 'info') return vac.info(v);
    return vac.controls(v, ctx, o);
  };

  /* ---------------------------------------------------------------- the pushed pages */
  /** The cleaning report detail. kind: 'interrupted' | 'completed' | 'stuck' | 'unverified' */
  vac.reportDetail = function (kind) {
    var STAT = { completed: ['checkmark.circle.fill', 'var(--ink-success)', 'Completed'], interrupted: ['pause.circle', 'var(--ink-warning)', 'Interrupted'], deferred: ['clock', 'var(--ink-warning)', 'Not Attempted'], failed: ['exclamationmark.circle', 'var(--ink-danger)', 'Failed'], uncertain: ['questionmark.circle', 'var(--ink-warning)', 'Completion Unverified'] };
    var rooms = kind === 'completed' ? [['Kitchen', 'completed', 'Vacuuming and mopping completed for the room.'], ['Office', 'completed', 'Vacuuming and mopping completed for the room.'], ['Living Room', 'completed', 'Vacuuming and mopping completed for the room.'], ['Dining Room', 'completed', 'Vacuuming and mopping completed for the room.']]
      : kind === 'stuck' ? [['Kitchen', 'completed', 'Vacuuming and mopping completed for the room.'], ['Office', 'completed', 'Vacuuming and mopping completed for the room.'], ['Living Room', 'failed', 'The vacuum became stuck while trying to clean the room.'], ['Dining Room', 'deferred', 'The mop dock\'s clean-water tank was empty; refill it.']]
      : kind === 'unverified' ? [['Kitchen', 'completed', 'Vacuuming and mopping completed for the room.'], ['Office', 'uncertain', 'Completion could not be verified from the available vacuum data.'], ['Living Room', 'interrupted', 'Cleaning was interrupted because someone returned home.'], ['Dining Room', 'deferred', 'The mop dock\'s clean-water tank was empty; refill it.']]
      : [['Kitchen', 'completed', 'Vacuuming and mopping completed for the room.'], ['Office', 'completed', 'Vacuuming and mopping completed for the room.'], ['Living Room', 'interrupted', 'Cleaning was interrupted because someone returned home.'], ['Dining Room', 'deferred', 'The mop dock\'s clean-water tank was empty; refill it.']];
    return h('div.dv-col', { style: { maxWidth: '640px' } }, K().ModuleList({ rows: rooms.map(function (r) {
      var s = STAT[r[1]]; return K().ModuleRow({ title: r[0], subtitle: r[2], symbol: s[0], glyph: s[1], accessory: h('span.vc-trailst', s[2]) }); }) }));
  };
  /** The area editor. o: {area:{x,y,w,h}|null, draw:boolean, outside:boolean, unavailable:boolean} */
  vac.areaEditor = function (o) {
    o = o || {}; var a = o.area, tools = [];
    tools.push(h('button.vc-tool' + (o.draw ? '.on' : ''), { type: 'button', 'aria-pressed': o.draw ? 'true' : 'false' }, h('span', { html: I('rectangle.dashed') }), a ? 'Redraw' : 'Draw'));
    tools.push(h('button.vc-tool', { type: 'button' }, h('span', { html: I('arrow.up.left.and.arrow.down.right') }), 'Reset View'));
    var clear = h('button.vc-tool', { type: 'button' }, h('span', { html: I('trash') }), 'Clear'); if (!a) clear.disabled = true; tools.push(clear);
    if (o.unavailable) tools.forEach(function (b) { b.disabled = true; });
    var map = o.unavailable ? K().InlineAlert({ message: 'Map Unavailable: Home Assistant cannot currently confirm the vacuum\'s map or position.' })
      : h('div.vc-gap12', { style: { gap: '8px' } }, h('div.vc-edmap', { role: 'img', 'aria-label': 'Main Floor cleaning area editor', 'aria-description': a ? '3.8 m × 2.6 m' : 'No area selected', style: { overflow: 'hidden' } },
        h('div', { style: o.zoom ? { transform: 'scale(' + o.zoom + ')', transformOrigin: '30% 25%', width: '100%', display: 'flex', justifyContent: 'center' } : { width: '100%', display: 'flex', justifyContent: 'center' } }, vac.mapCanvas({ map: 'main', selected: [], robot: 'dock', area: a, handles: !!a && !o.draw, names: true, scale: .85 }))),
        h('p.dv-foot', { style: { margin: 0 } }, o.draw ? 'Drag on the map to draw the cleaning area.' : a ? 'Drag the area to move it or use any round corner handle to resize it.' : 'Choose Draw, then drag on the map.'));
    var sum = h('div.vc-gap12', h('div', { role: 'group', 'aria-label': a ? '3.8 m × 2.6 m, 9.88 m² selected' : 'No area selected' }, h('span.vc-dim', a ? '3.8 m × 2.6 m' : 'No area selected'), h('span', a ? '9.88 m² selected' : 'Draw a rectangle to continue.')),
      vac.desc('Drag to draw an area, drag inside it to move it, and drag any round corner handle to resize it. Pinch to zoom.'), o.outside ? K().InlineAlert({ message: 'The area must stay inside the rooms shown on the map.' }) : null,
      vac.actionButton({ title: a ? 'Use This Area' : 'Draw an Area to Continue', symbol: 'checkmark', tone: 'primary', disabled: !a || !!o.unavailable }));
    var vo = o.voiceover ? h('div.vc-card', { style: { border: '1px dashed var(--ink-sheet-2)', background: 'transparent' }, role: 'note' }, h('div.hd', 'VoiceOver: custom actions on the map'),
      h('div.vc-flow', ['Move area left', 'Move area right', 'Move area up', 'Move area down', 'Make area larger', 'Make area smaller'].map(function (t) { return h('span.vc-chip', t); })),
      h('p.dv-foot', { style: { margin: 0 } }, 'Annotation, not UI: Draw places a centred area (a drag is not available), then these actions move and resize it.')) : null;
    return h('div.dv-col', { style: { maxWidth: '760px' } }, h('div.vc-gap12', { style: { gap: '16px' } }, h('div.vc-toolbar', tools), map, vo, sum));
  };

  /* ---------------------------------------------------------------- the vacuum sheet and presenters */
  /** A trimmed Vacuums page behind the sheet: Robot Vacuums tiles and the summary. */
  vac.robotTile = function (key, sc) {
    var R = vac.ROBOTS[key], v = vac.V({ robot: key, scenario: sc || 'docked' }), vis = VIS[v.state] || VIS.idle;
    var sym = { cleaning: 'sparkles', docked: 'house', returning: 'arrow.uturn.left.circle', paused: 'pause.circle', error: 'exclamationmark.circle', idle: 'robotic.vacuum', unavailable: 'questionmark.circle' }[v.state];
    var sub = v.state === 'unavailable' ? 'Unavailable' : vac.stateLabel(v) + (v.battery == null ? '' : ' • ' + v.battery + '%') + (v.state === 'error' && v.issue ? ' • ' + vac.cap(v.issue.replace(/ /g, ' ')) : '');
    return K().GlassTile({ title: R.title, subtitle: sub, symbol: sym, family: 'cleaning', isActive: ['cleaning', 'returning', 'paused'].indexOf(v.state) >= 0, isError: v.state === 'error', kind: 'navigate', progress: v.state === 'cleaning' ? v.battery / 100 : undefined });
  };
  vac.summaryLine = function (states) {
    var parts = [], n = function (s) { return states.filter(function (x) { return x === s; }).length; };
    [['cleaning', 'Cleaning'], ['returning', 'Returning'], ['error', 'Needs Attention']].forEach(function (p) { if (n(p[0])) parts.push(n(p[0]) + ' ' + p[1]); });
    if (parts.length) return parts.join(' · ');
    return states.length && states.every(function (s) { return s === 'docked'; }) ? 'All Docked' : null;
  };
  vac.autoCleanList = function (rows) {
    return K().ModuleList({ rows: [['Main Floor', true], ['Music Room', true], ['Theater Room', false]].map(function (r, i) {
      var d = rows && rows[i]; var on = d ? d.on : r[1], unav = d && d.unavailable;
      return K().ModuleRow({ title: r[0], subtitle: unav ? 'Unavailable' : (on ? 'Enabled' : 'Paused'), symbol: 'clock.arrow.circlepath', glyph: 'var(--fam-cleaning-glyph)', glyphOpacity: unav ? .4 : 1, accessory: (function () { var t = K().Toggle({ on: on && !unav, label: r[0] }); if (unav) t.disabled = true; return t; })() }); }) });
  };
  vac.pageBody = function (ctx, o) {
    o = o || {}; var sc = o.scenarios || ['docked', 'docked', 'docked'], keys = ['main', 'music', 'theater'];
    var states = sc.map(function (s) { return vac.V({ robot: 'main', scenario: s }).state; });
    var line = o.summary === undefined ? vac.summaryLine(states) : o.summary;
    var tiles = dv.fitGrid(K().TileGrid({ items: keys.map(function (k, i) { return vac.robotTile(k, sc[i]); }), min: 150, max: 6, equal: true }));
    var robots = h('div.rob', K().PageSectionHeader({ title: 'Robot Vacuums' }), tiles);
    var col1 = h('div.vc-pagecol', { style: { gap: '12px' } }, line ? h('p.vc-summary', line) : null, robots);
    var col2 = h('div.rob', K().PageSectionHeader({ title: 'Auto-Clean' }), vac.autoCleanList(o.autoClean));
    return { col1: col1, col2: col2 };
  };
  vac.pagePresenter = function (ctx, o) {
    var b = vac.pageBody(ctx, o);
    return Mock.page(ctx, { title: 'Vacuums', section: 'home', back: 'Home', badge: 3, choresBadge: 2, connection: (o && o.connection) || 'live', body: [Mock.split(ctx, { leading: [b.col1], trailing: [b.col2] })] });
  };
  vac.content = function (ctx, v, tab, o) {
    o = o || {};
    var mapCol = vac.mapColumn(ctx, v, tab, o), tabCol = h('div.vc-tabcol', { style: { minWidth: 0 } }, vac.tabBody(v, tab, ctx, o));
    if (ctx.canSplit) return h('div.dv-two', { style: { margin: '0 -16px' } }, h('div', mapCol), h('div', tabCol));   // MediaRemoteLayout.usesTwoColumns
    return h('div.dv-col', { style: { maxWidth: '640px' } }, h('div.vc-col', mapCol, tabCol));
  };
  /** The sheet over the Vacuums page. o: {v, tab, detent, connection, alert, scenarios (page tiles)} */
  vac.sheet = function (ctx, o) {
    o = o || {}; var v = o.v || vac.V({}), tab = o.tab || 'controls';
    if (vac.tabs(v).every(function (t) { return t.id !== tab; })) tab = 'controls';
    return Mock.sheet(ctx, { title: v.title + ' Robot Vacuum', subtitle: vac.subtitle(v), detent: o.detent || 'large', size: 'page', trailing: 'close', content: vac.content(ctx, v, tab, o), tabs: vac.tabBar(v, tab, ctx),
      presenter: o.noPresenter ? null : vac.pagePresenter(ctx, { scenarios: o.scenarios || [v.scenario === 'unavailable' ? 'unavailable' : v.scenario, 'docked', 'docked'], connection: o.connection }), alert: o.alert });
  };
  /** Transition helper: push a page onto the sheet (the system push); o: {title, content}. Pops back when o.back. */
  vac.pushDemo = function (stage, o) {
    var body = stage.querySelector('.ui-sheet .ui-modal'); if (!body) return Promise.resolve();
    var host = body.parentNode, ctx = Mock.current;
    var pushed = Mock.sheet(ctx, { title: o.title, detent: 'large', size: 'page', leading: 'back', trailing: 'none', content: o.content }).querySelector('.ui-modal');
    pushed.style.position = 'absolute'; pushed.style.inset = '0'; pushed.style.background = 'var(--sheet-ground)'; host.appendChild(pushed);
    if (!o.back) return Mock.anim.push(body, pushed).then(function () { return Mock.sleep(900); }).then(function () { return Mock.anim.push(pushed, body, { back: true }); }).then(function () { pushed.remove(); body.style.transform = ''; body.style.filter = ''; });
    pushed.style.zIndex = 0; host.insertBefore(pushed, body); body.style.zIndex = 1; body.style.background = 'var(--sheet-ground)';
    return Mock.anim.push(body, pushed, { back: true }).then(function () { return Mock.sleep(500); }).then(function () { pushed.remove(); body.style.transform = ''; body.style.zIndex = ''; });
  };
  /** A pushed page inside the sheet (area editor, report): leading Back, no section bar. */
  vac.pushed = function (ctx, o) {
    return Mock.sheet(ctx, { title: o.title, detent: 'large', size: 'page', leading: 'back', trailing: o.trailing === undefined ? 'none' : o.trailing, content: o.content, presenter: o.noPresenter ? null : vac.pagePresenter(ctx, { scenarios: o.scenarios || ['docked', 'docked', 'docked'], connection: o.connection }), alert: o.alert });
  };
})();
