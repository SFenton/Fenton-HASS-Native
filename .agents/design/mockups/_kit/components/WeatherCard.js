/* WeatherCard, WeatherCardHeader, WeatherGlyph: the Home weather summary card. apple/Sources/HassUI/Features/Home/Weather/WeatherCardContent.swift (+ WeatherSummaryCard, WeatherGlyph).
 * IN FLIGHT: the header layout is option D, decided 2026-10-22 (design/weather-card-header.md, proposals/weather-card-header): the glyph over the condition over H/L on the LEFT, the
 * Thin numeral with the chevron centred on it on the RIGHT. The numeral never truncates; the condition never wraps below accessibility sizes: a label too long for its column scrolls like a
 * ticker (30 pt/s, 1.5 s holds, soft fade at both edges, three passes then it rests; pauses on scroll, off screen and while the scene is inactive; an exception to motion.md 9.6 and 9.10).
 * Reduce Motion: no ticker, the condition wraps. Accessibility sizes stack: glyph, numeral and chevron on the top row, the condition under it at full width (wraps), H/L under that. "Was" (main):
 * the numeral could truncate to "4…" beside a long condition because layoutPriority sat inside the Button. The card is about 19 pt taller at the default size.
 * Card: a 26 pt thin module with the header, a daily briefing, a hairline, then the hourly row (Now, 11 AM, ...). Always dark styling (it sits on the wallpaper).
 * WeatherCardHeader props: {condition, temp, hi, lo, glyph?:'partly-cloudy'|'sunny'|'cloudy'|'rain'|'storm'|'snow'|'clear-night', ctx?}
 * WeatherCard props: header props + {brief?, hours?:[{t,glyph,temp}], pending?:boolean (first sign-in placeholders)}
 */
(function () {
  var h = Mock.h;
  var G = {
    'partly-cloudy': '<g stroke="#FFD93D" stroke-width="4.5" stroke-linecap="round"><path d="M40 6v6M55 13l-4 4M60 28h-6M24 13l4 4M55 43l-4-4"/></g><circle cx="40" cy="28" r="12" fill="#FFD93D"/><path d="M18 54h24a10 10 0 0 0 1.4-19.9A14 14 0 0 0 16.6 37 8.5 8.5 0 0 0 18 54z" fill="#fff"/>',
    'sunny': '<g stroke="#FFD93D" stroke-width="5" stroke-linecap="round" transform="translate(9.500 3.700) scale(.82)"><path d="M32 4v8M32 52v8M4 32h8M52 32h8M12 12l6 6M46 46l6 6M12 52l6-6M46 18l6-6"/></g><circle cx="36" cy="30" r="11" fill="#FFD93D"/>',
    'cloudy': '<path d="M16 48h30a11 11 0 0 0 1.500-21.900A16 16 0 0 0 16 29 9.500 9.500 0 0 0 16 48z" fill="#E4E8EE"/><path d="M12 42h22a9 9 0 0 0 1.200-17.900A13 13 0 0 0 12 26a8 8 0 0 0 0 16z" fill="#fff" transform="translate(10 4)"/>',
    'rain': '<path d="M18 40h26a10 10 0 0 0 1.400-19.900A14 14 0 0 0 16.600 23 8.500 8.500 0 0 0 18 40z" fill="#DDE3EA"/><g stroke="#5AB2FF" stroke-width="4" stroke-linecap="round"><path d="M22 46l-3 7M32 46l-3 7M42 46l-3 7"/></g>',
    'storm': '<path d="M18 38h26a10 10 0 0 0 1.400-19.900A14 14 0 0 0 16.600 21 8.500 8.500 0 0 0 18 38z" fill="#9AA5B5"/><path d="M33 38l-7 10h6l-3 8 10-12h-6l3-6z" fill="#FFD93D"/>',
    'snow': '<path d="M18 40h26a10 10 0 0 0 1.400-19.900A14 14 0 0 0 16.600 23 8.500 8.500 0 0 0 18 40z" fill="#E4E8EE"/><g fill="#fff"><circle cx="22" cy="48" r="2.600"/><circle cx="32" cy="52" r="2.600"/><circle cx="42" cy="48" r="2.600"/></g>',
    'clear-night': '<path d="M44 40A18 18 0 0 1 28 10a18 18 0 1 0 16 30z" fill="#E9E4FF"/><g fill="#fff"><circle cx="46" cy="14" r="1.800"/><circle cx="52" cy="26" r="1.300"/></g>',
  };
  /** Weather condition glyph (multicolour like Apple Weather): props {kind, size?} */
  function Glyph(p) { return Mock.html('<svg class="gl" viewBox="9.5 3.7 52.8 50.3" aria-hidden="true" style="' + (p.size ? 'width:' + p.size + 'px;height:' + p.size + 'px' : '') + '">' + (G[p.kind || 'partly-cloudy']) + '</svg>'); }
  Mock.register('WeatherGlyph', function (p) { return Glyph(p || {}); }, { source: 'apple/Sources/HassUI/Features/Home/Weather/WeatherGlyph.swift', props: '{kind, size}', variants: Object.keys(G).map(function (k) { return { id: k, label: k, props: { kind: k, size: 40 } }; }) });

  var CHEV = Mock.icon('chevron.right', { weight: 2.4 });
  function Header(p) {
    var ctx = p.ctx || Mock.current || {}, ax = !!ctx.axSize;
    var g = Glyph({ kind: p.glyph });
    if (p.pending) {
      return h('div.ui-wxhdr', { 'aria-label': 'Weather, Loading' }, h('div.lc', g, h('span.ui-pending', { style: { position: 'relative', top: 0, width: '110px' } }), h('span.ui-pending', { style: { position: 'relative', top: 0, width: '80px' } })), h('div.temp', h('span.ui-pending', { style: { position: 'relative', top: 0, width: '84px', height: '48px', borderRadius: '12px' } })));
    }
    var num = h('span.num', { 'aria-label': p.temp + ' degrees' }, p.temp + '°'), chev = h('span.chev', { html: CHEV, 'aria-hidden': 'true' });
    var hl = h('span.hl', 'H:' + p.hi + '°  L:' + p.lo + '°');
    var el;
    if (ax) {
      el = h('div.ui-wxhdr.stack', { role: 'button', tabindex: 0, 'aria-label': p.condition + ', ' + p.temp + ' degrees' }, h('div.r1', g, h('span.sp'), h('span.temp', num, chev)), h('span.lab.wrap', p.condition), hl);
    } else {
      var tick = h('div.ui-tick', h('span.tk.lab', p.condition));
      el = h('div.ui-wxhdr', { role: 'button', tabindex: 0, 'aria-label': p.condition + ', ' + p.temp + ' degrees' }, h('div.lc', g, tick, hl), h('div.temp', num, chev));
      Mock.whenAttached(el, function () {
        var tk = tick.firstElementChild, over = tk.offsetWidth - (tick.clientWidth - 16);
        if (over > 1 && Mock.settings.reduceMotion) { tick.classList.remove('over'); tk.classList.remove('lab'); tk.classList.add('lab', 'wrap'); tk.style.whiteSpace = 'normal'; tick.style.overflow = 'visible'; tick.style.width = 'auto'; tick.style.marginLeft = 0; tick.style.paddingLeft = 0; }
        else Mock.anim.ticker(tick);
      });
      el.dataset.anim = 'weather-header';
    }
    return el;
  }
  Mock.register('WeatherCardHeader', Header, { source: 'apple/Sources/HassUI/Features/Home/Weather/WeatherCardContent.swift (option D, in flight)', props: '{condition, temp, hi, lo, glyph, ctx}',
    variants: [{ id: 'short', label: 'Partly Cloudy', props: { condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 } }, { id: 'long', label: 'Long label: ticker', props: { condition: 'Heavy Thunderstorm With Hail', temp: 48, hi: 58, lo: 38, glyph: 'storm' } }, { id: 'unavailable', label: 'Weather Unavailable', props: { condition: 'Weather Unavailable', temp: 48, hi: 58, lo: 38 } }] });

  function WeatherCard(p) {
    var hours = p.hours || [{ t: 'Now', g: 'partly-cloudy', d: '48°' }, { t: '11 AM', g: 'sunny', d: '52°' }, { t: '12 PM', g: 'sunny', d: '55°' }, { t: '1 PM', g: 'partly-cloudy', d: '57°' }, { t: '2 PM', g: 'cloudy', d: '58°' }, { t: '3 PM', g: 'cloudy', d: '58°' }];
    return h('section.ui-weather', { role: 'region', 'aria-label': 'Weather' }, Header(p), h('hr'), (p.pending ? h('div', { style: { display: 'flex', flexDirection: 'column', gap: '8px', padding: '4px 0' }, 'aria-hidden': 'true' }, h('span.ui-pending', { style: { position: 'relative', top: 0, width: '100%', height: '12px' } }), h('span.ui-pending', { style: { position: 'relative', top: 0, width: '70%', height: '12px' } })) : h('p.brief', p.brief || 'The day opens with full sun, shifts to a mix of sun and clouds, and settles into overcast skies.')), h('hr'),
      h('div.ui-hours', hours.map(function (x) {
        if (p.pending) return h('div.hr', h('span.ht', x.t), h('span.ui-pending', { style: { position: 'relative', top: 0, width: '22px', height: '22px', borderRadius: '50%' } }), h('span.ui-pending', { style: { position: 'relative', top: 0, width: '26px', height: '10px' } }));
        return h('div.hr', h('span.ht', x.t), Glyph({ kind: x.g || x.glyph }), h('span.hd', x.d || x.temp));
      })));
  }
  Mock.register('WeatherCard', WeatherCard, { source: 'apple/Sources/HassUI/Features/Home/Weather/WeatherSummaryCard.swift', props: 'WeatherCardHeader props + {brief, hours}',
    variants: [{ id: 'default', label: 'Default', props: { condition: 'Partly Cloudy', temp: 48, hi: 58, lo: 38 } }, { id: 'long', label: 'Long condition (ticker)', props: { condition: 'Heavy Thunderstorm With Hail', temp: 48, hi: 58, lo: 38, glyph: 'storm' } }],
    states: [{ id: 'pending', label: 'First sign-in: placeholders pulse', props: { pending: true } }] });
})();
