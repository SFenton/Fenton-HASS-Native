/* SF Symbol look-alikes, keyed by SF Symbol name (the names HassDesign/SymbolMap.swift returns).
 *
 * These are a STAND-IN: simple 24 x 24 outline drawings in the SF Symbols spirit, so a mockup reads like the app without
 * shipping Apple's glyphs (no fonts, no network: AUTHORING.md rule 4). Each entry is outline markup, or [outline, filled] when
 * `symbolVariant(.fill)` has a distinct drawing. Mock.icon('house', {fill:true}) and Mock.icon('house.fill') are the same glyph.
 * A name that is missing draws a dashed circle and is recorded in Mock.missingIcons so the lint banner names it.
 */
(function () {
  var C = 'cx', R = 'r';
  function c(x, y, r) { return '<circle cx="' + x + '" cy="' + y + '" r="' + r + '"/>'; }
  function p(d) { return '<path d="' + d + '"/>'; }
  function rc(x, y, w, h, r) { return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" rx="' + (r || 0) + '"/>'; }
  var cloud = 'M7.5 18.5h9.2a4 4 0 0 0 .6-7.95A5.6 5.6 0 0 0 6.5 12 3.3 3.3 0 0 0 7.5 18.5z';
  var bulb = 'M12 3.2a6 6 0 0 0-3.5 10.9c.6.5 1 1.2 1 2v.2h5v-.2c0-.8.4-1.5 1-2A6 6 0 0 0 12 3.2z';
  var shield = 'M12 3 4.6 5.8v5.7c0 4.3 3 7.8 7.4 9.5 4.4-1.7 7.4-5.2 7.4-9.5V5.8z';
  var person = c(12, 8, 3.8) + p('M4.8 20.2c.3-3.6 3.3-5.9 7.2-5.9s6.9 2.3 7.2 5.9');
  var walk = c(13.5, 4.6, 1.9) + p('M12.2 9.5 9.4 11v3.2M12.2 9.5l3 3.3 2.9.5M12.2 9.5l.9 5.6-3.3 6.2M13.1 15.1l3 2.4.7 3.7');
  var S = {
    'house': [p('M3.4 11.2 12 4l8.6 7.2M5.6 9.7V20h12.8V9.7M10 20v-5.4h4V20'), p('M12 3.1 2.6 11a.8.8 0 0 0 .5 1.4h1.7v7.8a.8.8 0 0 0 .8.8H10v-5.6h4v5.6h4.4a.8.8 0 0 0 .8-.8v-7.8h1.7a.8.8 0 0 0 .5-1.4z')],
    'shield': [p(shield), p(shield)],
    'shield.slash': [p(shield) + p('M4 3.5l16 17'), p(shield) + p('M4 3.5l16 17')],
    'thermometer.medium': [p('M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z') + p('M12 8.5v7.2'), p('M10 14.4V5.2a2 2 0 0 1 4 0v9.2a4 4 0 1 1-4 0z')],
    'checklist': p('M3.8 6.6 5.2 8 8 5.2M3.8 12.6 5.2 14 8 11.2M3.8 18.6 5.2 20 8 17.2M11 7h9.2M11 13h9.2M11 19h9.2'),
    'gearshape': [p('M10.4 3.4h3.2l.5 2.3 1.6.9 2.2-.8 1.6 2.8-1.7 1.6v1.8l1.7 1.6-1.6 2.8-2.2-.8-1.6.9-.5 2.3h-3.2l-.5-2.3-1.6-.9-2.2.8-1.6-2.8 1.7-1.6v-1.8L4.5 8.2l1.6-2.8 2.2.8 1.6-.9z') + c(12, 12, 3)],
    'square.grid.2x2': [rc(4.5, 4.5, 6, 6, 1.6) + rc(13.5, 4.5, 6, 6, 1.6) + rc(4.5, 13.5, 6, 6, 1.6) + rc(13.5, 13.5, 6, 6, 1.6), rc(4, 4, 7, 7, 1.8) + rc(13, 4, 7, 7, 1.8) + rc(4, 13, 7, 7, 1.8) + rc(13, 13, 7, 7, 1.8)],
    'person': [person, c(12, 8, 4.3) + p('M4 21c0-4.2 3.6-6.8 8-6.8s8 2.6 8 6.8z')],
    'person.2': [c(9, 8.5, 3.3) + p('M2.8 19.5c.3-3.2 2.9-5.1 6.2-5.1s5.9 1.9 6.2 5.1M16 5.6a3.3 3.3 0 0 1 0 5.8M17.5 14.6c2 .5 3.5 2 3.7 4.9'), c(9, 8.5, 3.6) + p('M2.4 20c0-3.6 2.8-5.8 6.6-5.8s6.6 2.2 6.6 5.8z') + p('M16 5.2a3.6 3.6 0 0 1 0 6.6M17.6 14.4c2.2.6 3.8 2.3 3.9 5.6h-2.6')],
    'person.crop.circle.fill': [c(12, 12, 9.2) + c(12, 9.6, 3) + p('M6.2 18.2c1-2.3 3.2-3.6 5.8-3.6s4.8 1.3 5.8 3.6'), '<path fill-rule="evenodd" d="M12 2.6a9.4 9.4 0 1 0 0 18.8 9.4 9.4 0 0 0 0-18.8zm0 4.1a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2zM6.8 17.6c.9-1.9 2.9-3 5.2-3s4.3 1.1 5.2 3A7.6 7.6 0 0 1 12 20.2a7.6 7.6 0 0 1-5.2-2.6z"/>'],
    'lightbulb': [p(bulb) + p('M9.8 19.2h4.4M10.6 21.6h2.8'), p(bulb) + p('M9.6 19h4.8v1.4H9.6zM10.6 21.2h2.8v1H10.6z')],
    'lightbulb.2': ['<g transform="translate(-3.200 1.600) scale(.84)">' + p(bulb) + p('M9.800 19.200h4.400M10.600 21.600h2.800') + '</g><g transform="translate(11.400 .6) scale(.56)">' + p(bulb) + p('M9.800 19.200h4.400') + '</g>'],
    'video': [rc(3, 6.5, 12.5, 11, 2.6) + p('M16 10.8 21 8v8l-5-2.8z'), rc(2.6, 6, 13.4, 12, 3) + p('M16.8 10.7 21.6 7.6v8.8l-4.8-3.1z')],
    'video.slash': [rc(3, 6.5, 12.5, 11, 2.6) + p('M16 10.8 21 8v8M3.5 3.5l17 17')],
    'camera': [p('M4 8.2h3l1.4-2h7.2l1.4 2h3V19H4z') + c(12, 13.4, 3.4), p('M4 8.2h3l1.4-2h7.2l1.4 2h3V19H4z')],
    'figure.walk': walk,
    'figure.walk.motion': walk + p('M3.6 8.2h2.4M2.8 11.8h2.6M3.6 15.4h2.4'),
    'figure.walk.departure': walk + p('M18.5 5.5h2.6v13'),
    'door.left.hand.closed': [rc(6.5, 3.5, 11, 17, 1) + c(14.6, 12.4, .5), rc(6.2, 3.2, 11.6, 17.6, 1.2)],
    'door.left.hand.open': [p('M6.5 3.8 15 5.6v12.8l-8.5 1.8z') + p('M15 5.6h2.5v12.8H15') + c(12, 12, .5)],
    'door.garage.closed': [p('M3 20.5V8.8L12 4l9 4.8v11.7M6.5 20.5V12h11v8.5M6.5 14.8h11M6.5 17.6h11')],
    'door.garage.open': [p('M3 20.5V8.8L12 4l9 4.8v11.7M6.5 11.2h11M6.5 20.5V11.2')],
    'lock': [rc(5, 10.5, 14, 10, 2.6) + p('M8 10.5V8a4 4 0 0 1 8 0v2.5'), '<path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><rect x="4.6" y="10.5" width="14.8" height="10.4" rx="2.8"/>'],
    'lock.open': [rc(5, 10.5, 14, 10, 2.6) + p('M8 10.5V8a4 4 0 0 1 7.6-1.7'), '<path d="M8 10.5V8a4 4 0 0 1 7.6-1.7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><rect x="4.6" y="10.5" width="14.8" height="10.4" rx="2.8"/>'],
    'lock.shield': [p(shield) + rc(9, 10.5, 6, 5, 1.2) + p('M10.2 10.5V9a1.8 1.8 0 0 1 3.6 0v1.5')],
    'exclamationmark.triangle': [p('M12 4.4 21.4 20H2.6z') + p('M12 10.2v4.4M12 17.2v.2'), '<path fill-rule="evenodd" d="M13.1 3.9a1.3 1.3 0 0 0-2.2 0L2.2 18.6A1.3 1.3 0 0 0 3.3 20.5h17.4a1.3 1.3 0 0 0 1.1-1.9zM11 9.4h2v5h-2zm0 6.3h2v2h-2z"/>'],
    'moon': [p('M20 14.6A8.4 8.4 0 0 1 9.4 4a8.4 8.4 0 1 0 10.6 10.6z')],
    'moon.zzz': [p('M17 12.600A6.800 6.800 0 0 1 9 5a6.800 6.800 0 1 0 8 7.600zM15 4h4l-4 4h4')],
    'exclamationmark.shield': [p(shield) + p('M12 8.500v4M12 15.300v.2')],
    'moon.stars': [p('M19.4 14.4A7.8 7.8 0 0 1 9.6 4.6a7.8 7.8 0 1 0 9.8 9.8z') + p('M17 3.5v3M15.5 5h3')],
    'wind': [p('M3 9h11.2a2.4 2.4 0 1 0-2.4-2.4M3 13h15.2a2.8 2.8 0 1 1-2.8 2.8M3 17h8')],
    'fan': ['<g>' + [0, 90, 180, 270].map(function (a) { return '<path transform="rotate(' + a + ' 12 12)" d="M12 10.800C10.600 7.800 11.200 4.600 13.600 3.400 15.800 5.200 14.600 8.600 12 10.800z"/>'; }).join('') + c(12, 12, 1.200) + '</g>'],
    'drop': [p('M12 3.6c3.4 4.1 5.6 7 5.6 10.1a5.6 5.6 0 0 1-11.2 0c0-3.1 2.2-6 5.6-10.1z'), p('M12 3.2c3.5 4.2 5.9 7.3 5.9 10.5a5.9 5.9 0 0 1-11.8 0c0-3.2 2.4-6.300 5.9-10.5z')],
    'humidity': [p('M12 3.6c3.4 4.1 5.6 7 5.6 10.1a5.6 5.6 0 0 1-11.2 0c0-3.1 2.2-6 5.6-10.1z') + p('M9.7 15.5l4.6-3.4')],
    'humidifier': [rc(5, 11, 14, 9, 3) + p('M9 7.5c0-1.6 1.2-1.6 1.2-3.1M13.5 7.5c0-1.6 1.2-1.6 1.2-3.1')],
    'flame': [p('M12 3.4c.6 3.2 5.6 5.6 5.6 10.4a5.6 5.6 0 0 1-11.2 0c0-2.2 1-3.4 2-4.5.3 1.2.9 1.9 1.7 2.1C9.4 8.100 10.700 5.400 12 3.400z')],
    'snowflake': [p('M12 3v18M4.2 7.5l15.6 9M19.8 7.500l-15.600 9M9.600 4.800 12 6.800l2.400-2M9.600 19.200 12 17.200l2.400 2')],
    'bolt.fill': ['<path d="M13.300 2.800 5.200 13.200h5.400l-1 8 8.200-10.800h-5.500z"/>'],
    'power': [p('M12 3.400v8.200M7.100 6.800a7.400 7.400 0 1 0 9.800 0')],
    'chevron.right': p('M9.200 5.200 15.800 12l-6.600 6.800'),
    'chevron.left': p('M14.800 5.200 8.200 12l6.600 6.800'),
    'chevron.up': p('M5.200 14.800 12 8.200l6.800 6.600'),
    'chevron.down': p('M5.200 9.200 12 15.800l6.800-6.600'),
    'xmark': p('M6 6l12 12M18 6 6 18'),
    'checkmark': p('M5 12.800 9.800 17.600 19 7'),
    'plus': p('M12 4.800v14.400M4.800 12h14.400'),
    'minus': p('M4.800 12h14.400'),
    'magnifyingglass': c(10.800, 10.800, 6.200) + p('M15.500 15.500 20.400 20.400'),
    'line.3.horizontal': p('M4 7h16M4 12h16M4 17h16'),
    'arrow.up.arrow.down': p('M8 20V5M4.500 8.500 8 5l3.500 3.500M16 4v15M12.500 15.500 16 19l3.500-3.500'),
    'line.3.horizontal.decrease': p('M4 7h16M7 12h10M10 17h4'),
    'tv': [rc(3, 5.500, 18, 12, 2.500) + p('M8.500 20.500h7'), rc(3, 5.200, 18, 12.400, 2.800) + rc(8, 20, 8, 1.200, .6)],
    'hifispeaker': [rc(6, 3.500, 12, 17, 2.800) + c(12, 9, 2.300) + c(12, 15.500, 1.700)],
    'gamecontroller': [rc(2.800, 7, 18.400, 10, 5) + p('M7.500 10v4M5.500 12h4M15.800 11.200v.1M18 13v.1')],
    'pc': [rc(3, 4.500, 18, 11.500, 2) + p('M9 20h6M12 16v4')],
    'display': [rc(3, 4.500, 18, 11.500, 2) + p('M9 20h6M12 16v4')],
    'laptopcomputer': [rc(5, 5.500, 14, 9.500, 1.500) + p('M2.500 18.500h19')],
    'robotic.vacuum': [c(12, 12.500, 8) + c(12, 12.500, 2.300) + p('M12 4.500V3')],
    'sprinkler.and.droplets': [p('M12 20v-7M9 13h6M12 13c0-3-4-3.500-4-7a4 4 0 0 1 8 0c0 3.500-4 4-4 7zM5 18c0 1.100-.8 1.800-.8 2.400a.8.800 0 0 0 1.600 0c0-.6-.8-1.300-.8-2.400zM19 18c0 1.100-.8 1.800-.8 2.400a.8.800 0 0 0 1.600 0c0-.6-.8-1.300-.8-2.400z')],
    'leaf': [p('M5 19c-1-9 4-14 15-14 0 9-4.500 15-13 14zM5 19c3-4 6-6.500 10-8.500')],
    'bed.double': [p('M3 19V6M3 15h18v4M21 15v-3.500a3 3 0 0 0-3-3h-7V15M6.500 12.500h.1')],
    'sofa': [p('M5 11V8.500A2.500 2.500 0 0 1 7.500 6h9A2.500 2.500 0 0 1 19 8.500V11M3 12.500a2 2 0 0 1 4 0V15h10v-2.500a2 2 0 0 1 4 0V18H3zM6 18v2M18 18v2')],
    'fork.knife': [p('M7 3v7.500M4.500 3v5a2.500 2.500 0 0 0 5 0V3M7 11v10M17 21V3c-2.200 1.500-3 4-3 7v3h3')],
    'refrigerator': [rc(5.500, 3, 13, 18, 2.500) + p('M5.500 10.500h13M8.500 6.500v1.500M8.500 13v3')],
    'cabinet': [rc(4.500, 3.500, 15, 17, 1.500) + p('M12 3.500v17M9.500 11v2M14.500 11v2')],
    'dumbbell': [p('M7 8v8M17 8v8M4.500 10v4M19.500 10v4M7 12h10')],
    'shower': [p('M5 9a7 7 0 0 1 14 0zM12 3v-.5M8 13v1.500M12 13v3M16 13v1.500M10 18.500v1.500M14 18.500v1.500')],
    'gauge.with.dots.needle.50percent': [c(12, 13.500, 8.500) + p('M12 13.500V8M6.500 11.200h.1M17.500 11.200h.1')],
    'wifi': [p('M3 9.200a13.500 13.500 0 0 1 18 0M6 12.700a9 9 0 0 1 12 0M9 16.200a4.500 4.500 0 0 1 6 0') + c(12, 19.300, .8)],
    'wifi.slash': [p('M3 9.200a13.500 13.500 0 0 1 8-3.300M6 12.700a9 9 0 0 1 3-1.900M9 16.200a4.500 4.500 0 0 1 3.500-1.100M18.200 11.200M3.500 3.500l17 17') + c(12, 19.300, .8)],
    'icloud.slash': [p(cloud) + p('M4 4l16.500 16.500')],
    'bell': [p('M6 17.500V11a6 6 0 0 1 12 0v6.500l1.500 1.500h-15zM10 21h4')],
    'clock': [c(12, 12, 8.800) + p('M12 7v5.200l3.400 2')],
    'calendar': [rc(3.500, 5, 17, 15.500, 3) + p('M3.500 10h17M8 3v4M16 3v4')],
    'timer': [c(12, 13.500, 7.500) + p('M12 13.500V9.500M9.500 3h5M18.500 6l1-1')],
    'mappin.and.ellipse': [p('M12 21c4.500-4.500 6.500-7.800 6.500-10.800a6.500 6.500 0 0 0-13 0C5.500 13.200 7.500 16.500 12 21z') + c(12, 10, 2.300)],
    'info.circle': [c(12, 12, 8.800) + p('M12 11v5.500M12 7.700v.2'), '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zM11 7.400h2v2h-2zm0 3.600h2v6h-2z"/>'],
    'checkmark.circle': [c(12, 12, 8.800) + p('M8 12.300l2.800 2.800L16.200 9.500'), '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zm4.200 6.600-5.300 6a.8.800 0 0 1-1.200 0l-2.200-2.300 1.100-1.100 1.700 1.700 4.700-5.300z"/>'],
    'exclamationmark.circle': [c(12, 12, 8.800) + p('M12 7.600v5.500M12 16.200v.2'), '<path fill-rule="evenodd" d="M12 2.800a9.200 9.200 0 1 0 0 18.400 9.200 9.200 0 0 0 0-18.400zM11 7h2v6h-2zm0 7.600h2v2h-2z"/>'],
    'questionmark.circle': [c(12, 12, 8.800) + p('M9.500 9.500a2.500 2.500 0 1 1 3.500 2.300c-.7.400-1 .8-1 1.700M12 16.300v.2')],
    'pencil': [p('M4.500 19.500l.8-4 10-10a2.100 2.100 0 0 1 3 3l-10 10zM13.800 7l3.200 3.200')],
    'trash': [p('M4.500 7h15M9.500 7V4.500h5V7M6.500 7l.8 12.500h9.400L17.500 7M10 10.500v6M14 10.500v6')],
    'record.circle': [c(12, 12, 8.800) + '<circle cx="12" cy="12" r="4.400" fill="currentColor" stroke="none"/>'],
    'speaker.wave.2': [p('M4 9.500h3l4.500-3.500v12L7 14.500H4zM15 9a4.200 4.200 0 0 1 0 6M17.500 6.500a8 8 0 0 1 0 11')],
    'speaker.slash': [p('M4 9.500h3l4.500-3.500v12L7 14.500H4zM16 9.500l4.500 5M20.500 9.500 16 14.500')],
    'mic': [rc(9, 3.500, 6, 11, 3) + p('M5.500 11.500a6.500 6.500 0 0 0 13 0M12 18v3')],
    'play.fill': ['<path d="M7.500 4.800v14.400a.8.800 0 0 0 1.200.7l11.800-7.200a.8.8 0 0 0 0-1.400L8.700 4.100a.8.800 0 0 0-1.200.7z"/>'],
    'pause.fill': ['<rect x="6.200" y="4.500" width="4" height="15" rx="1.200"/><rect x="13.800" y="4.500" width="4" height="15" rx="1.200"/>'],
    'stop.fill': ['<rect x="5.500" y="5.500" width="13" height="13" rx="2.500"/>'],
    'sun.max': [c(12, 12, 4.200) + p('M12 2.800v2.500M12 18.700v2.500M2.800 12h2.500M18.700 12h2.500M5.500 5.500l1.800 1.800M16.700 16.700l1.800 1.800M5.500 18.500l1.800-1.800M16.700 7.300l1.800-1.800')],
    'cloud': [p(cloud)],
    'cloud.sun': [p('M8 18.500h9a3.800 3.800 0 0 0 .5-7.500 5.200 5.200 0 0 0-9.600 1.500A3 3 0 0 0 8 18.500zM7.500 5l.8 1.500M3.500 8.500 5 9M12 3.500v1.500')],
    'cloud.rain': [p('M7.500 15h9.200a4 4 0 0 0 .6-7.950A5.600 5.600 0 0 0 6.500 8.500 3.300 3.300 0 0 0 7.500 15zM8 18l-.8 2.500M12 18l-.8 2.500M16 18l-.8 2.500')],
    'cloud.bolt': [p('M7.500 14.500h9.200a4 4 0 0 0 .6-7.950A5.600 5.600 0 0 0 6.500 8 3.300 3.300 0 0 0 7.500 14.500zM12.500 13l-2 3.500h3l-1.500 3.500')],
    'aqi.medium': [p('M3.500 9h10.500a2.500 2.500 0 1 0-2.500-2.500M3.500 13h14.500a2.800 2.800 0 1 1-2.800 2.800M3.500 17h7')],
    'photo': [rc(3.500, 5, 17, 14, 2.500) + c(9, 10, 1.700) + p('M4 17.500l4.500-4.500 3.500 3.500 3-3 5 4.500')],
    'ellipsis': ['<circle cx="5.500" cy="12" r="1.700"/><circle cx="12" cy="12" r="1.700"/><circle cx="18.500" cy="12" r="1.700"/>'],
    'ellipsis.circle': [c(12, 12, 8.800) + '<circle cx="8" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="16" cy="12" r="1" fill="currentColor"/>'],
    'arrow.clockwise': [p('M19.500 12a7.500 7.500 0 1 1-2.400-5.500M19.500 4.500v4.200h-4.200')],
    'arrow.uturn.left.circle': [c(12, 12, 8.800) + p('M9.500 9.500 8 11l1.500 1.500M8 11h5a2.500 2.500 0 0 1 0 5h-1.500')],
    'car.side': [p('M3.500 15v-3l2-4.500a2 2 0 0 1 1.800-1.200h9.400a2 2 0 0 1 1.800 1.200l2 4.500v3zM3.500 15v2.500h3.300V15M17.200 15v2.500h3.300V15M6 11.500h12') + c(7.500, 15, .6)],
    'airplane': [p('M3 13.500 21 6l-4.500 12-3.500-4.500zM13 13.500 21 6')],
    'sparkles': [p('M10 4l1.600 4.400L16 10l-4.400 1.600L10 16l-1.600-4.400L4 10l4.400-1.600zM18 14l.8 2.200L21 17l-2.200.8L18 20l-.8-2.200L15 17l2.200-.8z')],
    'paintpalette': [p('M12 3.500a8.500 8.500 0 1 0 0 17c1.600 0 2-1 1.400-2-.7-1.100.1-2.500 1.500-2.500H17a3.500 3.500 0 0 0 3.500-3.500c0-4.200-3.800-9-8.500-9z') + c(8, 11, .8) + c(11, 7.500, .8) + c(15.500, 8.500, .8)],
    'slider.vertical.3': [p('M6 3.500v17M12 3.500v17M18 3.500v17') + c(6, 14, 2) + c(12, 8, 2) + c(18, 15.500, 2)],
    'cart': [p('M3 4.500h2.500l2.200 10.500h10.500l1.800-7.500H6.200') + c(9, 19.200, 1.200) + c(17, 19.200, 1.200)],
    'cart.badge.plus': [p('M3 4.500h2.500l2.200 10.500h9.500l1-4M6 7.500h8') + c(9, 19.200, 1.200) + c(16, 19.200, 1.200) + p('M18 3v5M15.500 5.500h5')],
    'star': [p('M12 3.800l2.500 5.300 5.800.7-4.300 4 1.100 5.800L12 16.800 6.900 19.600 8 13.800 3.700 9.800l5.800-.7z')],
    'heart': [p('M12 20c-6-4.200-8.500-7.500-8.500-10.500a4.700 4.700 0 0 1 8.500-2.800 4.700 4.700 0 0 1 8.500 2.800C20.500 12.500 18 15.800 12 20z')],
    'location': [p('M20 4 4 11l7 2 2 7z')],
    'bed.double.fill': [p('M3 19V6M3 15h18v4M21 15v-3.500a3 3 0 0 0-3-3h-7V15')],
    'tray': [p('M3.500 13.500 6 5h12l2.500 8.500v5h-17zM3.500 13.500H9a3 3 0 0 0 6 0h5.500')],
    'doc.text': [p('M6 3.500h8l4 4v13H6zM14 3.500v4h4M9 12h6M9 15.500h6')],
    'link': [p('M10 14a4 4 0 0 0 5.600 0l3-3a4 4 0 0 0-5.600-5.600l-1 1M14 10a4 4 0 0 0-5.600 0l-3 3a4 4 0 0 0 5.600 5.600l1-1')],
    'hourglass': [p('M6.500 3.500h11M6.500 20.500h11M7.500 3.500v3.500l4.500 5-4.500 5v3.500M16.500 3.500v3.500L12 12l4.500 5v3.500')],
    'envelope': [rc(3, 5.500, 18, 13, 2.500) + p('M3.500 7.500 12 13.500l8.500-6')],
    'tag': [p('M3.500 12.500V4.500h8l9 9-8 8z') + c(8, 9, 1.300)],
    'rectangle.dashed': ['<rect x="4" y="5" width="16" height="14" rx="2.500" stroke-dasharray="3 3"/>'],
    'square.split.2x2': [rc(4, 4, 16, 16, 3) + p('M12 4v16M4 12h16')],
    'videoprojector': [rc(3, 8, 18, 9, 3) + c(15, 12.500, 2.500) + p('M6 17v2M18 17v2')],
    'guitars': [p('M10 14 19 5M17 3.500l3.500 3.500M8.500 12a4 4 0 1 0 3.500 3.500') + c(8.500, 15.500, 1)],
    'music.note': [p('M9 18V6l10-2v12') + c(6.500, 18, 2.500) + c(16.500, 16, 2.500)],
    'film': [rc(3.500, 4, 17, 16, 2) + p('M3.500 9h17M3.500 15h17M8 4v16M16 4v16')],
    'suitcase': [rc(3.500, 7.500, 17, 12.500, 2.500) + p('M9 7.500V5a1.500 1.500 0 0 1 1.500-1.500h3A1.500 1.500 0 0 1 15 5v2.500M3.500 12.500h17')],
    'testtube.2': [p('M9 3.500h4M10 3.500V16a3 3 0 1 0 6 0V3.500M13 3.500M6 8l-1.500 8.500a3 3 0 0 0 5 2')],
    'paintbrush': [p('M19.500 4.500 11 13M8.500 14a3 3 0 0 0-3 3c0 1.500-.8 2.500-2 3 3.500.8 7-1 7-4.200z')],
    'battery.75percent': [rc(2.500, 7.500, 17, 9, 2.500) + p('M21.500 10.500v3') + '<rect x="4.500" y="9.500" width="9.500" height="5" rx="1" fill="currentColor" stroke="none"/>'],
    'a.circle': [c(12, 12, 8.800) + p('M8.500 16l3.500-8 3.500 8M9.800 13.500h4.400')],
    'number': [p('M9 4 7.500 20M16.500 4 15 20M4.500 9h16M3.500 15h16')],
    'percent': [c(7.500, 7.500, 2.500) + c(16.500, 16.500, 2.500) + p('M18 5.500 6 18.500')],
    'smoke': [p('M3 15h8v4H3zM13 15h3v4h-3zM18 15h3v4h-3zM6 12c0-2 2-2 2-4M12 12c0-2 2-2 2-4')],
    'circle.lefthalf.filled': [c(12, 12, 8.500) + '<path d="M12 3.500a8.500 8.500 0 0 0 0 17z" fill="currentColor" stroke="none"/>'],
    'switch.2': [rc(3.500, 5, 17, 6, 3) + c(17.500, 8, 1.600) + rc(3.500, 13, 17, 6, 3) + c(6.500, 16, 1.600)],
    'person.badge.shield.checkmark': [p(shield) + p('M9 12l2 2 3.500-4')],
    'wrench.and.screwdriver': [p('M14.500 4.500a4 4 0 0 0-3.800 5.300L4 16.500a1.800 1.800 0 0 0 2.500 2.500l6.700-6.700a4 4 0 0 0 5.300-3.800l-2.400 2.400-2.400-.7-.7-2.400z')],
    'questionmark': [p('M9 9a3 3 0 1 1 4.300 2.700c-.9.500-1.300 1.100-1.300 2M12 17.500v.2')],
    'building.2': [rc(4.500, 3.500, 9, 17, 1) + rc(13.500, 9, 6, 11.500, 1) + p('M7.500 7h3M7.500 11h3M7.500 15h3M15.500 13h2M15.500 16.500h2')],
    'photo.on.rectangle': [rc(6, 3.500, 14, 12, 2) + p('M3.500 8v10a2 2 0 0 0 2 2h11') + c(11, 8, 1.400)],
  };
  /** Alias names the app uses for the same glyph. */
  var alias = { 'house.fill': 'house', 'shield.fill': 'shield', 'lightbulb.fill': 'lightbulb', 'lock.fill': 'lock', 'video.fill': 'video', 'camera.fill': 'camera',
    'person.fill': 'person', 'drop.fill': 'drop', 'flame.fill': 'flame', 'moon.fill': 'moon', 'star.fill': 'star', 'heart.fill': 'heart', 'bell.fill': 'bell',
    'checkmark.circle.fill': 'checkmark.circle', 'info.circle.fill': 'info.circle', 'exclamationmark.circle.fill': 'exclamationmark.circle',
    'exclamationmark.triangle.fill': 'exclamationmark.triangle', 'gearshape.fill': 'gearshape', 'thermometer': 'thermometer.medium', 'lock.open.fill': 'lock.open',
    'sun.max.fill': 'sun.max', 'cloud.fill': 'cloud', 'tv.fill': 'tv', 'speaker.wave.2.fill': 'speaker.wave.2', 'mic.fill': 'mic', 'pencil.circle': 'pencil',
    'door.left.hand.closed.fill': 'door.left.hand.closed', 'lightbulb.max': 'lightbulb', 'figure.walk.circle': 'figure.walk', 'shield.lefthalf.filled': 'shield',
    'xmark.circle.fill': 'xmark', 'trash.fill': 'trash', 'refrigerator.fill': 'refrigerator', 'play.rectangle': 'film' };
  /** Symbols that always draw their fill drawing (the app asks for the fill variant). */
  var solid = { 'bolt.fill': 1, 'play.fill': 1, 'pause.fill': 1, 'stop.fill': 1, 'ellipsis': 1 };

  Mock.symbols = S;
  Mock.missingIcons = {};
  /**
   * An inline SVG icon as an HTML string.
   * @param {string} name SF Symbol name (as in HassDesign/SymbolMap.swift)
   * @param {{fill?:boolean, cls?:string, size?:string, label?:string, weight?:number}} [o]
   *   fill: the `.fill` symbol variant (active tiles, selected tabs). label: sets role="img" and aria-label; otherwise aria-hidden.
   */
  Mock.icon = function (name, o) {
    o = o || {};
    var key = alias[name] || name;
    var wantFill = o.fill || /\.fill$/.test(name) || solid[key];
    var base = S[key];
    if (!base && /\.fill$/.test(key)) base = S[key.replace(/\.fill$/, '')];
    if (!base) { Mock.missingIcons[name] = true; return '<svg class="ui-sym" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-dasharray="3 3" aria-hidden="true"><circle cx="12" cy="12" r="8"/></svg>'; }
    var outline = Array.isArray(base) ? base[0] : base;
    var filled = Array.isArray(base) && base[1] ? base[1] : null;
    var a11y = o.label ? ' role="img" aria-label="' + Mock.esc(o.label) + '"' : ' aria-hidden="true"';
    var w = o.weight || 1.8;
    var st = o.size ? ' style="width:' + o.size + ';height:' + o.size + '"' : '';
    var cls = 'ui-sym' + (o.cls ? ' ' + o.cls : '');
    if (wantFill && filled) return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="currentColor" stroke="none"' + a11y + st + '>' + filled + '</svg>';
    if (wantFill && !filled) return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="currentColor" fill-opacity=".92" stroke="currentColor" stroke-width="' + (w + .3) + '" stroke-linecap="round" stroke-linejoin="round"' + a11y + st + '>' + outline + '</svg>';
    return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round"' + a11y + st + '>' + outline + '</svg>';
  };
  /** Same, as a DOM node. */
  Mock.iconEl = function (name, o) { return Mock.html(Mock.icon(name, o)); };
  /** The names this kit can draw (for the README and the lint). */
  Mock.iconNames = function () { return Object.keys(S).concat(Object.keys(alias)).sort(); };
})();
