import 'package:flutter/material.dart';

import '../booth_controller.dart';
import '../services/share_service.dart';
import '../theme/tb_theme.dart';
import '../widgets/tb_ui.dart';

class GifPreviewScreen extends StatelessWidget {
  final BoothController controller;
  final ShareService shareService;
  const GifPreviewScreen({
    super.key,
    required this.controller,
    this.shareService = const ShareService(),
  });

  Future<void> _share(BuildContext context) async {
    final bytes = controller.gifBytes;
    if (bytes == null) return;
    final box = context.findRenderObject() as RenderBox?;
    await shareService.shareBytes(
      bytes: bytes,
      filename: 'terabooth-${controller.sessionId ?? 'guest'}.gif',
      mimeType: 'image/gif',
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TbBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(TbSpace.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to result',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    const TbWordmark(compact: true),
                    const SizedBox(width: 16),
                    Text(
                      'Animated GIF',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    const TbPill(
                      label: 'Guest share',
                      color: TbColors.gold,
                      icon: Icons.gif_box_outlined,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: TbSpace.lg),
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        final bytes = controller.gifBytes;
                        if (bytes != null) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(TbRadius.lg),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(TbRadius.lg),
                              child: Image.memory(
                                bytes,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                          );
                        }
                        if (controller.gifError != null) {
                          return TbEmptyState(
                            icon: Icons.gif_box_outlined,
                            title: 'GIF unavailable',
                            message: controller.gifError!,
                          );
                        }
                        return const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Preparing the animated GIF…'),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: TbSpace.lg),
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => SizedBox(
                    width: 360,
                    child: TbPrimaryButton(
                      label: 'AirDrop GIF',
                      icon: Icons.ios_share_rounded,
                      expanded: true,
                      onPressed: controller.gifBytes == null
                          ? null
                          : () => _share(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
