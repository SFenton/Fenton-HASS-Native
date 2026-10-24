/* TileGrid (DynamicGridLayout): the responsive tile grid. apple/Sources/HassDesign/DynamicGridLayout.swift; patterns/dynamic-grid.md.
 *
 * Column count = floor((width + spacing) / (minCellWidth + spacing)) clamped to 1...maxColumns; leftover width is shared by every track; an incomplete
 * last row aligns leading (never stretches a lone item); minCellWidth scales with Dynamic Type (AX5 gives one column); equalRowHeights makes every row
 * the tallest tile's height. The browser's `repeat(auto-fill, minmax())` gives exactly these rules. **Hinge-aware even columns:** with a hinge set
 * (the unfolded Duo, any pose) the count rounds DOWN to an even number, never below two (5 becomes 4, 3 becomes 2; a single track stays single), so no
 * track pair straddles the fold: measured after layout, because only the grid knows its own width.
 * Four is a FLOOR on iPad, never a cap: tile grids pass max 6 unless a design reason bounds them (Chores quick links stop at 4).
 * props: {items:Array<Node|GlassTile props>, min?:150 (pt, scaled), max?:6, gap?:12, equal?:boolean (default true), span?:{index:2}, ctx?}
 * Section-header helper: pass a PageSectionHeader node with class `gridheader` to take a whole row.
 */
(function () {
  var h = Mock.h;
  function TileGrid(p) {
    var g = h('div.ui-grid' + (p.equal === false ? '' : '.eq'), { style: { '--min': (p.min || 150) + 'px', '--max': p.max || 6, '--gap': (p.gap == null ? 12 : p.gap) + 'px' } });
    (p.items || []).forEach(function (it, i) { var n = it && it.nodeType ? it : Mock.components.GlassTile(it); if (p.span && p.span[i] === 2) n.classList.add('span2'); g.appendChild(n); });
    var min = p.min || 150, gap = p.gap == null ? 12 : p.gap, max = p.max || 6;
    if (window.ResizeObserver) {
      var ro = new ResizeObserver(function () {
        var screen = g.closest('.screen');
        var w = g.clientWidth, sc = parseFloat(screen ? getComputedStyle(screen).getPropertyValue('--sc') : 1) || 1;
        if (!w) return;
        var n = Math.max(1, Math.min(max, Math.floor((w + gap) / (min * sc + gap))));
        g.dataset.cols = n;
        if (screen && screen.dataset.hinge && n >= 2 && n % 2) { n -= 1; g.dataset.even = 'true'; }   // DynamicGridMetrics.evenRounded
        if (screen && screen.dataset.hinge) g.style.gridTemplateColumns = 'repeat(' + n + ',minmax(0,1fr))';
        g.dataset.cols = n;
      });
      ro.observe(g);
    }
    return g;
  }
  var sample = ['Kitchen', 'Office', 'Gym', 'Guest Room', 'Hallway', 'Garage', 'Back Deck'].map(function (n) { return { title: n + ' Light', subtitle: 'Off', symbol: 'lightbulb', family: 'lights' }; });
  function demo(n, p) { return { items: sample.slice(0, n), min: p.min, max: p.max }; }
  Mock.register('TileGrid', TileGrid, { source: 'apple/Sources/HassDesign/DynamicGridLayout.swift', props: '{items, min, max, gap, equal, span}',
    variants: [{ id: 'default', label: 'min 150, max 6', props: Object.assign(demo(7, {}), {}) }, { id: 'max2', label: 'max 2 (room page sections)', props: demo(4, { max: 2, min: 150 }) }, { id: 'wide', label: 'min 240 (wide cards)', props: demo(4, { min: 240, max: 3 }) }],
    states: [{ id: 'default', label: 'Fills to the width; columns follow Dynamic Type and the hinge', props: demo(7, {}) }] });
  Mock.components.DynamicGrid = TileGrid;
})();
