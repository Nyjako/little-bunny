import 'package:flutter/material.dart';

/// A real digits-only PIN keypad (M60), reused across every PIN-entry
/// context -- unlocking, setting a new PIN, confirming it, and re-entering
/// it to disable the lock. Deliberately a controlled widget (no internal
/// state of its own, same shape as this codebase's own [SegmentedButton]
/// usage elsewhere): the caller owns [value] and decides what "entry
/// complete" means (comparing [value.length] to [length] after each
/// [onChanged] call), since each of those four contexts reacts differently
/// once the PIN is fully entered.
class PinEntry extends StatelessWidget {
  final int length;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  const PinEntry({super.key, required this.length, required this.value, required this.onChanged, this.enabled = true});

  void _onDigit(String digit) {
    if (enabled && value.length < length) {
      onChanged(value + digit);
    }
  }

  void _onBackspace() {
    if (enabled && value.isNotEmpty) {
      onChanged(value.substring(0, value.length - 1));
    }
  }

  Widget _dot(BuildContext context, int index) {
    final filled = index < value.length;
    final color = enabled ? Theme.of(context).colorScheme.primary : Theme.of(context).disabledColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? color : null, border: Border.all(color: color, width: 2)),
      ),
    );
  }

  Widget _key(BuildContext context, {String? digit, Widget? icon, Key? key, VoidCallback? onPressed}) {
    return SizedBox(
      key: key,
      width: 72,
      height: 56,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        child: digit != null ? Text(digit, style: Theme.of(context).textTheme.headlineSmall) : icon ?? const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(length, (index) => _dot(context, index))),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((digit) => _key(context, digit: digit, key: ValueKey('pinDigit$digit'), onPressed: () => _onDigit(digit))).toList(),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 72, height: 56),
            _key(context, digit: '0', key: const ValueKey('pinDigit0'), onPressed: () => _onDigit('0')),
            _key(context, icon: const Icon(Icons.backspace_outlined), key: const Key('pinBackspace'), onPressed: _onBackspace),
          ],
        ),
      ],
    );
  }
}
