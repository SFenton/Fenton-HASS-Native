/* Device table and the per-render context (`ctx`) every builder receives.
 *
 * Sizes are WINDOW sizes in points; CSS pixels equal points, and the stage scales with `zoom`, never the frame.
 *   iphone                  402 x 874   iPhone 17 Pro (project simulator; portrait only, owner 2026-10-10)
 *   ipad-portrait           834 x 1194  iPad Pro 11; ipad-landscape 1194 x 834
 *   duo-unfolded-landscape  951 x 669   measured on the Duo simulator: hinge band 455.3 to 495.7 pt (split-view.md, duo.md)
 *   duo-unfolded-portrait   669 x 951   the same panel rotated; the hinge band is horizontal at y 455.3 to 495.7 (symmetry: not
 *                                       measured, "unfolded portrait was not run", duo.md)
 *   duo-folded              466 x 678   the OUTER display, portrait. The project docs only say "iPhone-like"; FestivalNativeApps measured
 *                                       the folded portrait window at 466 x 678 (design/apple/duo.md, "Folded portrait") and S+H
 *                                       shares the hardware, so that is used here. Compact width, tabs in the trailing vertical bar.
 * The system's trailing vertical bar covers about 83 pt (ipados.md, duo.md): the page content ends at window width - 83.
 * Everything geometric (split, even columns, chip gap) is derived from `hinge` and `rail`, never from the device name
 * (AGENTS.md: "The rule is geometric (SplitPolicy), never a device-name check").
 */
(function () {
  var HINGE = { at: 455.3, size: 40.4 };
  /** Mock.devices[key]: static facts about a window. */
  Mock.devices = {
    'iphone': { key: 'iphone', label: 'iPhone 17 Pro (402 × 874)', short: 'iPhone', w: 402, h: 874, r: 55, bezel: 9, family: 'phone', regular: false, safeTop: 54, safeBottom: 34,
      barTop: 54, island: true, rail: 0, menu: true, tabs: 'floating', titleInHeader: false, sheetTop: 60, hinge: null },
    'duo-folded': { key: 'duo-folded', label: 'iPhone Duo, folded (466 × 678)', short: 'Duo folded', w: 466, h: 678, r: 30, bezel: 10, family: 'duo', regular: false, safeTop: 36, safeBottom: 20,
      barTop: 40, punch: true, rail: 83, menu: false, tabs: 'rail', titleInHeader: true, sheetTop: 44, hinge: null },
    'duo-unfolded-portrait': { key: 'duo-unfolded-portrait', label: 'iPhone Duo, unfolded portrait (669 × 951)', short: 'Duo unfolded portrait', w: 669, h: 951, r: 24, bezel: 10, family: 'duo', regular: true,
      safeTop: 24, safeBottom: 20, barTop: 30, rail: 83, menu: true, menuInRail: true, tabs: 'flyout', titleInHeader: false, sheetTop: 28, hinge: { axis: 'h', at: HINGE.at, size: HINGE.size } },
    'duo-unfolded-landscape': { key: 'duo-unfolded-landscape', label: 'iPhone Duo, unfolded landscape (951 × 669)', short: 'Duo unfolded landscape', w: 951, h: 669, r: 24, bezel: 10, family: 'duo', regular: true,
      safeTop: 24, safeBottom: 20, barTop: 30, rail: 83, menu: true, menuInRail: true, tabs: 'flyout', titleInHeader: false, sheetTop: 28, hinge: { axis: 'v', at: HINGE.at, size: HINGE.size } },
    'ipad-portrait': { key: 'ipad-portrait', label: 'iPad Pro 11, portrait (834 × 1194)', short: 'iPad portrait', w: 834, h: 1194, r: 20, bezel: 14, family: 'ipad', regular: true, safeTop: 24, safeBottom: 20,
      barTop: 30, rail: 0, menu: true, tabs: 'flyout', titleInHeader: false, sheetTop: 28, hinge: null },
    'ipad-landscape': { key: 'ipad-landscape', label: 'iPad Pro 11, landscape (1194 × 834)', short: 'iPad landscape', w: 1194, h: 834, r: 20, bezel: 14, family: 'ipad', regular: true, safeTop: 24, safeBottom: 20,
      barTop: 30, rail: 0, menu: true, tabs: 'flyout', titleInHeader: false, sheetTop: 28, hinge: null },
  };
  Mock.deviceKeys = Object.keys(Mock.devices);

  /** Text sizes (HIG Dynamic Type): Large (default), xxxLarge, AX5. */
  Mock.textSizes = { 'default': { label: 'Large (default)', cls: '' }, 'xxxl': { label: 'xxxLarge', cls: 'ts-xxxl' }, 'ax5': { label: 'Accessibility 5', cls: 'ts-ax5' } };

  /**
   * Build the context a state's render(ctx) receives.
   * @param {string} key device key
   * @param {{appearance?:'dark'|'light', ts?:'default'|'xxxl'|'ax5', reduceMotion?:boolean, reduceTransparency?:boolean}} [o]
   * @returns {object} ctx with: key, w, h (window), contentW (window minus the vertical bar), contentH, regular (size class), compact,
   *   rail (bar width or 0), hinge ({x,w} in window x, or null; axis 'v' only splits), canSplit (SplitPolicy: regular width, wider than
   *   tall, each half >= 360), splitGeometry ({leading, band, trailing} widths) or null, isPhone/isDuo/isIPad, folded, family,
   *   appearance ('dark'|'light': what sheets use), ts, scale (the Dynamic Type metric scale), reduceMotion, reduceTransparency.
   */
  Mock.ctx = function (key, o) {
    o = o || {};
    var d = Mock.devices[key] || Mock.devices.iphone;
    var ctx = Object.assign({}, d);
    ctx.device = d;
    ctx.appearance = o.appearance || 'dark';
    ctx.ts = o.ts || 'default';
    ctx.scale = { 'default': 1, xxxl: 1.353, ax5: 3.118 }[ctx.ts];
    ctx.axSize = ctx.ts === 'ax5';
    ctx.reduceMotion = !!o.reduceMotion;
    ctx.reduceTransparency = !!o.reduceTransparency;
    ctx.compact = !d.regular;
    ctx.contentW = d.w - d.rail;
    ctx.contentH = d.h;
    ctx.isPhone = d.family === 'phone'; ctx.isDuo = d.family === 'duo'; ctx.isIPad = d.family === 'ipad';
    ctx.folded = key === 'duo-folded';
    ctx.hinge = d.hinge && d.hinge.axis === 'v' ? { x: d.hinge.at, w: d.hinge.size } : null;   // the vertical hinge splits columns
    ctx.hingeAny = d.hinge || null;
    ctx.canSplit = d.regular && d.w > d.h;   // SplitPolicy: regular width, wider than tall (portrait never splits)
    // SplitPolicy.geometry: the band is the hinge when it crosses the container, else 1 pt at the midpoint; each pane >= 360 pt.
    ctx.splitGeometry = null;
    if (ctx.canSplit) {
      var band = ctx.hinge ? ctx.hinge.w : 1, lead = ctx.hinge ? ctx.hinge.x : Math.floor((ctx.contentW - 1) / 2);
      var trail = ctx.contentW - lead - band;
      if (lead >= 360 && trail >= 360) ctx.splitGeometry = { leading: lead, band: band, trailing: trail };
      else ctx.canSplit = false;
    }
    return ctx;
  };
})();
