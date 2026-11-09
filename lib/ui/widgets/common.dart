import 'package:flutter/material.dart';

import '../theme.dart';

/// Help that appears only after the pointer has rested 5 s — invisible to everyone else.
class HoldTip extends StatelessWidget {
  const HoldTip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => message.isEmpty
      ? child
      : Tooltip(message: message, waitDuration: const Duration(seconds: 5), child: child);
}

enum Tone { neutral, accent, ok, warn, bad, muted }

Color toneColor(BuildContext context, Tone tone) {
  final t = context.tokens;
  final light = Theme.of(context).brightness == Brightness.light;
  // On white, the shared ok / warn / bad hues are too pale for text; darken them to pass AA.
  Color text(Color c, double by) => light ? Color.lerp(c, const Color(0xFF000000), by)! : c;
  return switch (tone) {
    Tone.neutral => t.dim,
    Tone.accent => t.accent,
    Tone.ok => text(t.ok, 0.42),
    Tone.warn => text(t.warn, 0.45),
    Tone.bad => text(t.bad, 0.2),
    Tone.muted => t.muted,
  };
}

/// A small rounded state label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.neutral, this.small = false});

  final String text;
  final Tone tone;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = toneColor(context, tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        border: Border.all(color: c.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: small ? 10.5 : 11.5,
          fontWeight: FontWeight.w600,
          color: c,
          height: 1.3,
        ),
      ),
    );
  }
}

/// Top-bar status chip: dot + short text; a click goes where it is fixed.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.text, required this.tone, this.detail, this.onTap, this.glow = false});

  final String text;
  final Tone tone;
  final String? detail;
  final VoidCallback? onTap;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = toneColor(context, tone);
    final chip = Material(
      color: t.panel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide(color: t.frame)),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                boxShadow: glow ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)] : null,
              ),
            ),
            const SizedBox(width: 7),
            Text(text, style: TextStyle(fontSize: 12.5, color: t.text)),
          ]),
        ),
      ),
    );
    return detail == null ? chip : Tooltip(message: detail!, child: chip);
  }
}

/// A panel with a title row (title, count, actions on the right) over a rule.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    this.title,
    this.count,
    this.tip = '',
    this.actions = const [],
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.expand = false,
  });

  final String? title;
  final String? count;
  final String tip;
  final List<Widget> actions;
  final Widget child;
  final EdgeInsets padding;

  /// Fill the height given (for a card holding a scrolling grid).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final body = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
              child: LayoutBuilder(builder: (context, box) {
                final heading = Row(children: [
                  Flexible(
                    child: HoldTip(
                      message: tip,
                      child: Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text),
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(count!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: t.muted, fontFeatures: tabular)),
                    ),
                  ],
                ]);
                if (actions.isEmpty) return heading;
                // Narrow: the actions move under the title instead of squeezing it.
                if (box.maxWidth < 520) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    heading,
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ]);
                }
                return Row(children: [
                  Expanded(child: heading),
                  ...actions.expand((a) => [const SizedBox(width: 8), a]),
                ]);
              }),
            ),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

/// Outlined tile over a soft gradient of its colour: label, big value, optional data sub-line.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.secondary,
    this.sub,
    this.tone = Tone.neutral,
    this.tip = '',
    this.onTap,
  });

  final String label;
  final String value;

  /// Smaller figure beside the value (a count beside a share).
  final String? secondary;
  final String? sub;
  final Tone tone;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = tone == Tone.neutral ? Color.lerp(t.text, t.panel, 0.4)! : toneColor(context, tone);
    final border = tone == Tone.neutral ? c : c;
    return HoldTip(
      message: tip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border.withValues(alpha: tone == Tone.neutral ? 0.45 : 0.75)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.panel, Color.alphaBlend(c.withValues(alpha: 0.08), t.panel)],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: labelStyle(context), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: tone == Tone.neutral ? t.text : c,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
                if (secondary != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(secondary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: t.dim, fontFeatures: tabular)),
                  ),
                ],
              ]),
              if (sub != null) ...[
                const SizedBox(height: 3),
                Text(sub!, style: TextStyle(fontSize: 12, color: t.dim), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A row of tiles that wraps to fit.
class TileRow extends StatelessWidget {
  const TileRow({super.key, required this.tiles, this.minWidth = 140});

  final List<Widget> tiles;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final perRow = (c.maxWidth / minWidth).floor().clamp(1, tiles.length);
        final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final tile in tiles) SizedBox(width: w, child: tile)],
        );
      });
}

/// One short line saying why something is empty, with the action that fixes it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.icon, this.action, this.actionLabel, this.secondary});

  final String text;
  final IconData? icon;
  final VoidCallback? action;
  final String? actionLabel;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 30, color: t.muted), const SizedBox(height: 10)],
          Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: t.dim)),
          if (action != null || secondary != null) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              if (action != null) FilledButton(onPressed: action, child: Text(actionLabel ?? 'Retry')),
              ?secondary,
            ]),
          ],
        ]),
      ),
    );
  }
}

/// A one-line notice: ok, warn (advisory) or error.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.tone = Tone.warn, this.action});

  final String text;
  final Tone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = toneColor(context, tone);
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.10), t.panel),
        border: Border.all(color: c.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Icon(
          switch (tone) {
            Tone.bad => Icons.error_outline,
            Tone.ok => Icons.check_circle_outline,
            _ => Icons.info_outline,
          },
          size: 17,
          color: c,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: t.text))),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ]),
    );
  }
}

/// A labelled slider with its value on the right.
class SliderField extends StatelessWidget {
  const SliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
    this.tip = '',
    this.width = 280,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final String tip;
  final double width;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: HoldTip(
              message: tip,
              child: Text(label.toUpperCase(),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle(context)),
            ),
          ),
          const SizedBox(width: 8),
          Text(display, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text, fontFeatures: tabular)),
        ]),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions ?? (max - min).round(),
          onChanged: onChanged,
        ),
      ]),
    );
  }
}

/// The house confirm dialog: a title, one sentence, Cancel focused, the action in red.
Future<bool> confirmDestructive(BuildContext context, {required String title, required String sentence, required String action}) async {
  final t = context.tokens;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: t.frame)),
      title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.text)),
      content: Text(sentence, style: TextStyle(fontSize: 13.5, color: t.dim)),
      actions: [
        OutlinedButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.bad, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Label above a value, for detail headers.
class Fact extends StatelessWidget {
  const Fact(this.label, this.value, {super.key, this.mono = false, this.tip = ''});

  final String label;
  final String value;
  final bool mono;
  final String tip;

  @override
  Widget build(BuildContext context) => HoldTip(
        message: tip,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: labelStyle(context)),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: mono
                ? monoStyle(context, size: 13)
                : TextStyle(fontSize: 13.5, color: context.tokens.text, fontWeight: FontWeight.w600, fontFeatures: tabular),
          ),
        ]),
      );
}
