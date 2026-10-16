// The HUD dotsync shows on a Mac after a sync pulls commits or fails: a
// card at the bottom of the screen with a status icon, a title, a detail line
// and a system sound. Run by /usr/bin/osascript, so it needs nothing installed.
//
//   osascript -l JavaScript dotsync-hud.js <ok|warn|fail> <title> [detail] [seconds]
ObjC.import('AppKit');

function run(argv) {
  const kind = argv[0] || 'ok';
  const title = argv[1] || 'dotfiles synced and reloaded';
  const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '\u2026' : s);
  const detail = clip(argv[2] || '', 72);
  const seconds = parseFloat(argv[3] || '5');

  const look = {
    ok:   { symbol: 'checkmark.circle.fill', color: $.NSColor.systemGreenColor, sound: 'Glass' },
    warn: { symbol: 'exclamationmark.circle.fill', color: $.NSColor.systemOrangeColor, sound: 'Purr' },
    fail: { symbol: 'xmark.circle.fill', color: $.NSColor.systemRedColor, sound: 'Basso' },
  }[kind] || { symbol: 'info.circle.fill', color: $.NSColor.systemBlueColor, sound: 'Tink' };

  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  const label = (text, font, color) => {
    const l = $.NSTextField.labelWithString(text);
    l.font = font;
    l.textColor = color;
    l.sizeToFit;
    return l;
  };
  const top = label(title, $.NSFont.systemFontOfSizeWeight(14, $.NSFontWeightSemibold), $.NSColor.labelColor);
  const sub = detail ? label(detail, $.NSFont.systemFontOfSizeWeight(12, $.NSFontWeightRegular), $.NSColor.secondaryLabelColor) : null;

  const iconSize = 22, gap = 10, padX = 16, padY = 10, lineGap = 1;
  const textW = Math.ceil(Math.max(top.frame.size.width, sub ? sub.frame.size.width : 0));
  const textH = Math.ceil(top.frame.size.height + (sub ? lineGap + sub.frame.size.height : 0));
  const w = padX + iconSize + gap + textW + padX + 4;
  const h = Math.max(textH, iconSize) + padY * 2;

  const screen = $.NSScreen.mainScreen.visibleFrame;
  const x = screen.origin.x + (screen.size.width - w) / 2;
  const y = screen.origin.y + screen.size.height * 0.12;

  const panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(x, y, w, h),
    $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
    $.NSBackingStoreBuffered, false);
  panel.level = $.NSStatusWindowLevel;
  panel.opaque = false;
  panel.backgroundColor = $.NSColor.clearColor;
  panel.hasShadow = true;
  panel.ignoresMouseEvents = true;
  panel.collectionBehavior = $.NSWindowCollectionBehaviorCanJoinAllSpaces | $.NSWindowCollectionBehaviorStationary;

  const blur = $.NSVisualEffectView.alloc.initWithFrame($.NSMakeRect(0, 0, w, h));
  blur.material = $.NSVisualEffectMaterialHUDWindow;
  blur.blendingMode = $.NSVisualEffectBlendingModeBehindWindow;
  blur.state = $.NSVisualEffectStateActive;
  blur.wantsLayer = true;
  blur.layer.cornerRadius = 14;
  blur.layer.masksToBounds = true;
  // A hairline in the status color, so the state reads at a glance.
  blur.layer.borderWidth = 1;
  blur.layer.borderColor = look.color.colorWithAlphaComponent(0.55).CGColor;

  const config = $.NSImageSymbolConfiguration.configurationWithPointSizeWeight(iconSize, $.NSFontWeightSemibold);
  const image = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(look.symbol, 'status').imageWithSymbolConfiguration(config);
  const icon = $.NSImageView.imageViewWithImage(image);
  icon.contentTintColor = look.color;
  icon.frame = $.NSMakeRect(padX, Math.round((h - iconSize) / 2), iconSize, iconSize);
  blur.addSubview(icon);

  const tx = padX + iconSize + gap;
  let ty = Math.round((h - textH) / 2);
  if (sub) {
    sub.frame = $.NSMakeRect(tx, ty, Math.ceil(sub.frame.size.width), sub.frame.size.height);
    blur.addSubview(sub);
    ty += sub.frame.size.height + lineGap;
  }
  top.frame = $.NSMakeRect(tx, ty, Math.ceil(top.frame.size.width), top.frame.size.height);
  blur.addSubview(top);

  panel.contentView = blur;
  panel.alphaValue = 0;
  panel.orderFrontRegardless;

  const step = (from, to, ms) => {
    const n = 12;
    for (let i = 1; i <= n; i++) {
      panel.alphaValue = from + (to - from) * (i / n);
      $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(ms / 1000 / n));
    }
  };
  $.NSSound.soundNamed(look.sound).play;
  step(0, 1, 150);
  $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(seconds));
  step(1, 0, 250);
}
