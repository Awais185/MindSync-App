import 'package:flutter/material.dart';

/// Purple header: title + short copy + small “face mesh landmarks” chip only.
class DeepFaceAnalysisIntroCard extends StatelessWidget {
  const DeepFaceAnalysisIntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6F39E8), Color(0xFF4B2AAD)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6F39E8).withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deep Face Analysis',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Stress, anxiety, and depression from facial action units (AUs) '
            'and face mesh landmarks on your recorded clip.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: Color(0xFFE8DDFF),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 18,
                  color: const Color(0xFF7CFFCB),
                ),
                const SizedBox(width: 8),
                Text(
                  'Face mesh landmarks',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sample scan photo (outside the purple card).
class DeepFaceMeshSampleImage extends StatelessWidget {
  const DeepFaceMeshSampleImage({super.key});

  static const String assetPath = 'assets/images/deep_face_mesh_sample.jpg';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (context, error, stack) {
                return Container(
                  color: const Color(0xFFE8EAF3),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF6E7381),
                    size: 40,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sample: tracked face mesh during analysis',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6E7381),
          ),
        ),
      ],
    );
  }
}

/// Record / upload actions (separate from intro card and sample image).
class DeepFaceScanActions extends StatelessWidget {
  const DeepFaceScanActions({
    super.key,
    required this.maxVideoSeconds,
    required this.loading,
    required this.onRecord,
    required this.onUpload,
  });

  final int maxVideoSeconds;
  final bool loading;
  final VoidCallback? onRecord;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ActionTile(
          icon: Icons.videocam_rounded,
          title: 'Record from camera',
          subtitle: 'Front camera · max $maxVideoSeconds seconds',
          onTap: loading ? null : onRecord,
        ),
        const SizedBox(height: 10),
        _ActionTile(
          icon: Icons.upload_file_rounded,
          title: 'Upload video',
          subtitle: 'Choose a clip from gallery or storage',
          onTap: loading ? null : onUpload,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E6EE)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6F39E8)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6E7381),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
