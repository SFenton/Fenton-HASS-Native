/* ThermostatDial (a signature control): main's ThermostatDial exactly. apple/Sources/HassDesign/ThermostatDial/ThermostatDial.swift, ThermostatDialGeometry.swift. A 22 pt (24/320 of the
 * side) round-capped 270-degree track opening at the bottom (min at 7:30, max at 4:30, clockwise); the heat arc is orange `#CD5401` from the minimum to the heat setpoint, the cool arc
 * teal `#2C8E98` from the cool setpoint to the maximum; white knobs at the setpoints (64 pt hit target); a dark dot for the current temperature; the middle reads the mode ("Heating"),
 * a Thin numeral with a raised °F, and the range line. The bed and humidifier dials reuse its geometry.
 * props: {value:71 (current), heat?:68, cool?:74, min?:50, max?:90, mode?:'Heating'|'Cooling'|'Idle'|'Off', range?:string, size?:280}
 */
(function () {
  var h = Mock.h;
  function pt(cx, cy, r, deg) { var a = deg * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; }
  function arc(cx, cy, r, d0, d1) { var a = pt(cx, cy, r, d0), b = pt(cx, cy, r, d1); return 'M' + a[0].toFixed(2) + ' ' + a[1].toFixed(2) + ' A' + r + ' ' + r + ' 0 ' + (d1 - d0 > 180 ? 1 : 0) + ' 1 ' + b[0].toFixed(2) + ' ' + b[1].toFixed(2); }
  Mock.register('ThermostatDial', function (p) {
    var min = p.min == null ? 50 : p.min, max = p.max == null ? 90 : p.max, size = p.size || 280;
    function deg(v) { return 135 + Math.min(Math.max((v - min) / (max - min), 0), 1) * 270; }
    var cx = 160, cy = 160, r = 145, lw = 24, svg = '<svg viewBox="0 0 320 320" aria-hidden="true">';
    svg += '<path d="' + arc(cx, cy, r, 135, 405) + '" fill="none" stroke="var(--fill-tertiary)" stroke-width="' + lw + '" stroke-linecap="round" style="stroke:color-mix(in srgb, var(--ink) 16%, transparent)"/>';
    if (p.heat != null) svg += '<path d="' + arc(cx, cy, r, 135, Math.max(deg(p.heat), 136)) + '" fill="none" stroke="var(--dial-heat)" stroke-width="' + lw + '" stroke-linecap="round"/>';
    if (p.cool != null) svg += '<path d="' + arc(cx, cy, r, Math.min(deg(p.cool), 404), 405) + '" fill="none" stroke="var(--dial-cool)" stroke-width="' + lw + '" stroke-linecap="round"/>';
    [p.heat, p.cool].forEach(function (v) { if (v == null) return; var k = pt(cx, cy, r, deg(v)); svg += '<circle cx="' + k[0] + '" cy="' + k[1] + '" r="15" fill="#fff" stroke="rgba(0,0,0,.2)" stroke-width="1"/>'; });
    if (p.value != null) { var d = pt(cx, cy, r, deg(p.value)); svg += '<circle cx="' + d[0] + '" cy="' + d[1] + '" r="9" fill="#141414" stroke="rgba(255,255,255,.92)" stroke-width="3"/>'; }
    svg += '</svg>';
    var mode = p.mode || 'Idle';
    return h('div.ui-dial', { role: 'slider', 'aria-label': 'Thermostat', 'aria-valuetext': mode + ', ' + p.value + ' degrees' + (p.range ? ', ' + p.range : ''), style: { width: size + 'px', height: size + 'px', '--d': size + 'px' } },
      h('div', { html: svg, style: { position: 'absolute', inset: 0 } }), h('div.mid', h('span.mode', mode), h('span.big', String(p.value), h('sup', '°F')), p.range ? h('span.range', p.range) : null));
  }, { source: 'apple/Sources/HassDesign/ThermostatDial/ThermostatDial.swift', props: '{value, heat, cool, min, max, mode, range, size}',
    variants: [{ id: 'heat', label: 'Heating to 68', props: { value: 66, heat: 68, mode: 'Heating', range: 'Range 66–74°F', size: 240 } }, { id: 'both', label: 'Heat and cool setpoints', props: { value: 71, heat: 68, cool: 74, mode: 'Idle', range: 'Range 68–74°F', size: 240 } }, { id: 'cool', label: 'Cooling to 72', props: { value: 75, cool: 72, mode: 'Cooling', range: 'Range 72–80°F', size: 240 } }] });
})();
