/* BrightnessTile (the light dragger, a signature control): apple/Sources/HassDesign/BrightnessTile.swift; direction-g.md Controls. Tap toggles the light; press and drag sideways sets
 * brightness: the bright band follows the finger, a dark capsule bubble ("30%", white text in both appearances like the system volume HUD) floats beside it, a haptic tick every 10%,
 * and the tile lifts while dragging. A room's lights stack as full-width slabs that work the same way. The band is the lit tile's cream gradient from the leading edge over `#EADBC4`;
 * 0% is the off face. The band width is progress, kept on `quick` (0.2 s) so a dragged value never lags the finger (motion-system departures).
 * props: {title, percent, symbol?, dragging?:boolean, unavailable?, tint?:cssColor (a coloured bulb tints the band, never past dark-ink contrast)}
 */
(function () {
  var h = Mock.h;
  Mock.register('BrightnessTile', function (p) {
    var pct = p.percent || 0;
    var tile = Mock.tile({ title: p.title, subtitle: p.unavailable ? 'Unavailable' : (pct > 0 ? 'On at ' + pct + '%' : 'Off'), symbol: p.symbol || 'lightbulb', family: 'lights', isActive: pct > 0 && !p.unavailable, isUnavailable: p.unavailable, progress: pct > 0 ? pct / 100 : undefined, progressTint: p.tint });
    tile.dataset.anim = 'brightness';
    if (p.dragging) {
      tile.style.transform = 'scale(1.03)'; tile.style.boxShadow = '0 10px 24px rgba(0,0,0,.4)';
      var bubble = h('span.ui-bubble', { 'aria-hidden': 'true', style: { position: 'absolute', top: '-8px', zIndex: 5, left: 'calc(' + pct + '% - 24px)', background: 'rgba(20,20,22,.92)', color: '#fff', font: '600 13px var(--font)', padding: '4px 10px', borderRadius: '99px', fontVariantNumeric: 'tabular-nums' } }, pct + '%');
      tile.style.overflow = 'visible'; tile.appendChild(bubble);
    }
    tile.setAttribute('role', 'slider'); tile.setAttribute('aria-valuenow', pct); tile.setAttribute('aria-valuemin', 0); tile.setAttribute('aria-valuemax', 100);
    return tile;
  }, { source: 'apple/Sources/HassDesign/BrightnessTile.swift', props: '{title, percent, symbol, dragging, unavailable, tint}',
    variants: [{ id: '70', label: '70%', props: { title: 'Table Light', percent: 70 } }, { id: '30', label: '30%', props: { title: 'Floor Lamp', percent: 30 } }, { id: 'bulb', label: 'Coloured bulb tints the band', props: { title: 'Accent Strip', percent: 60, tint: '#FF5E8A' } }],
    states: [{ id: 'off', label: 'Off (0%)', props: { title: 'Table Light', percent: 0 } }, { id: 'drag', label: 'Dragging (bubble, lifted)', props: { title: 'Table Light', percent: 40, dragging: true } }, { id: 'unavailable', label: 'Unavailable', props: { title: 'Back Deck Light', percent: 0, unavailable: true } }] });
})();
