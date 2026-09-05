import 'package:flutter/material.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/screens/theme_define.dart';

class CodeBodyView extends StatelessWidget {
  const CodeBodyView({super.key, required this.text, required this.dark});

  final String? text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final kind = bodyKind(text);
    if (kind == HttpBodyKind.empty) {
      return Text(
        '<无内容>',
        style: TextStyle(
          color: ThemeDefine.kColorText,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final source = text!;
    if (kind == HttpBodyKind.json) {
      return SelectableText.rich(
        TextSpan(
          style: _mono(dark ? Colors.white : ThemeDefine.kColorTitle),
          children: highlightJson(source, dark: dark),
        ),
      );
    }
    return SelectableText(source, style: _mono(dark ? const Color(0xFFE8E6E3) : ThemeDefine.kColorTitle));
  }
}

TextStyle _mono(Color color) => TextStyle(
      color: color,
      fontSize: 12.5,
      height: 1.55,
      fontFamily: 'monospace',
    );

List<InlineSpan> highlightJson(String source, {required bool dark}) {
  final base = dark ? const Color(0xFFE8E6E3) : ThemeDefine.kColorTitle;
  final keyColor = dark ? const Color(0xFFFF9B8A) : const Color(0xFFC54638);
  const stringColor = Color(0xFF21A366);
  const numberColor = Color(0xFFED8A19);
  const keywordColor = Color(0xFF8257E6);
  final punct = dark ? const Color(0xFF9CA3AF) : ThemeDefine.kColorText;
  final regex = RegExp(
    r'("(?:\\.|[^"\\])*")(\s*:)?|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|\b(true|false|null)\b|([{\[\]},:])',
  );
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in regex.allMatches(source)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: source.substring(offset, match.start), style: TextStyle(color: base)));
    }
    final quoted = match.group(1);
    final colon = match.group(2);
    if (quoted != null) {
      if (colon != null) {
        spans.add(TextSpan(text: quoted, style: TextStyle(color: keyColor, fontWeight: FontWeight.w700)));
        spans.add(TextSpan(text: colon, style: TextStyle(color: punct)));
      } else {
        spans.add(TextSpan(text: quoted, style: const TextStyle(color: stringColor)));
      }
    } else if (match.group(3) != null) {
      spans.add(TextSpan(text: match.group(0), style: const TextStyle(color: numberColor)));
    } else if (match.group(4) != null) {
      spans.add(TextSpan(text: match.group(0), style: const TextStyle(color: keywordColor, fontWeight: FontWeight.w700)));
    } else {
      spans.add(TextSpan(text: match.group(0), style: TextStyle(color: punct)));
    }
    offset = match.end;
  }
  if (offset < source.length) {
    spans.add(TextSpan(text: source.substring(offset), style: TextStyle(color: base)));
  }
  return spans;
}
