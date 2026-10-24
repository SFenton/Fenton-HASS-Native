/* Alert: the iOS 26 alert, for destructive or hard-to-undo actions (direction-g.md Sheets: Alerts): Disarm the Security System, Turn Off Vacation Mode, Sign Out. The destructive button is red
 * (#FF6961 on dark, #C21717 on light); Cancel always stays (also on iPad, where an action sheet would be a popover). Two buttons sit side by side; three or more (or long titles) stack.
 * Pass the node as Mock.sheet's `alert` option (it draws the scrim) or place it in a `.ui-alert-scrim`. props: {title, message?, buttons:[{title, role?:'destructive'|'cancel'}], stacked?}
 */
(function () {
  var h = Mock.h;
  Mock.register('Alert', function (p) {
    var bs = p.buttons || [{ title: 'OK' }];
    return h('div.ui-alert' + (p.stacked || bs.length > 2 ? '.stacked' : ''), { role: 'alertdialog', 'aria-label': p.title, 'aria-modal': 'true' }, h('div.bd', h('div.ti', p.title), p.message ? h('div.ms', p.message) : null),
      h('div.btns', bs.map(function (b) { return h('button' + (b.role === 'destructive' ? '.destructive' : ''), { type: 'button', style: b.role === 'cancel' ? { fontWeight: 600 } : null }, b.title); })));
  }, { source: 'apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift', props: '{title, message, buttons, stacked}',
    variants: [{ id: 'destructive', label: 'Destructive + Cancel', props: { title: 'Disarm the Security System?', message: 'Doors and motion stop triggering the alarm.', buttons: [{ title: 'Cancel', role: 'cancel' }, { title: 'Disarm', role: 'destructive' }] } }] });
})();
