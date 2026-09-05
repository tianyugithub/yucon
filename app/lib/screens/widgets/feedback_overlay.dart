import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';

class FeedbackOverlay extends StatelessWidget {
  const FeedbackOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final bottom = 64 + MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        child,
        if (store.feedback.visible)
          Positioned(
            left: 24,
            right: 24,
            bottom: bottom,
            child: GestureDetector(
              onTap: store.dismissFeedback,
              child: Material(
                color: store.feedback.type == FeedbackType.error
                    ? const Color(0xF5BE2630)
                    : store.feedback.type == FeedbackType.warning
                    ? const Color(0xF5BC6C05)
                    : const Color(0xF0191B1E),
                borderRadius: BorderRadius.circular(10),
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Text(
                    store.feedback.message,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
