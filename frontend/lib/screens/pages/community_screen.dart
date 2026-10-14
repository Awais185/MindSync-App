import 'package:flutter/material.dart';
import '../../services/community_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _service = CommunityService();
  String selectedTag = 'all';
  bool _loading = false;
  List<CommunityPostItem> _posts = const [];

  static const _tagMap = <String, String>{
    'all': 'All Stories',
    'stress': '#Stress',
    'selfcare': '#SelfCare',
    'mindfulness': '#Mindfulness',
    'wellness': '#Wellness',
  };

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    final posts = await _service.fetchPosts(selectedTag);
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            // Header
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Community',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 22),
              ],
            ),
            const SizedBox(height: 24),

            // Hero Section
            const Text(
              'Find your collective breath.',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: Color(0xFF161820),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'A shared space for stories, strategies, and moments of quiet resilience.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF676977),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // Tags Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Tag(
                    text: _tagMap['all']!,
                    isActive: selectedTag == 'all',
                    onTap: () {
                      setState(() => selectedTag = 'all');
                      _loadPosts();
                    },
                  ),
                  const SizedBox(width: 8),
                  _Tag(
                    text: _tagMap['stress']!,
                    isActive: selectedTag == 'stress',
                    onTap: () {
                      setState(() => selectedTag = 'stress');
                      _loadPosts();
                    },
                  ),
                  const SizedBox(width: 8),
                  _Tag(
                    text: _tagMap['selfcare']!,
                    isActive: selectedTag == 'selfcare',
                    onTap: () {
                      setState(() => selectedTag = 'selfcare');
                      _loadPosts();
                    },
                  ),
                  const SizedBox(width: 8),
                  _Tag(
                    text: _tagMap['mindfulness']!,
                    isActive: selectedTag == 'mindfulness',
                    onTap: () {
                      setState(() => selectedTag = 'mindfulness');
                      _loadPosts();
                    },
                  ),
                  const SizedBox(width: 8),
                  _Tag(
                    text: _tagMap['wellness']!,
                    isActive: selectedTag == 'wellness',
                    onTap: () {
                      setState(() => selectedTag = 'wellness');
                      _loadPosts();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No posts yet in this category.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF676977)),
                ),
              )
            else
              ..._posts.map(
                (post) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PostCard(
                    name: post.userName,
                    time: _ago(post.createdAt),
                    title: '#${post.category.toUpperCase()}',
                    body: post.content,
                    tags: '#${post.category.toUpperCase()}',
                    likesCount: post.likesCount,
                    commentsCount: post.commentsCount,
                    likedByMe: post.likedByMe,
                    accentColor: const Color(0xFFC6F2ED),
                    iconColor: const Color(0xFF0E9186),
                    onLikeTap: () async {
                      final ok = await _service.toggleLike(post.id);
                      if (ok) _loadPosts();
                    },
                    onCommentTap: () => _openComments(post.id),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePostDialog(context),
        backgroundColor: const Color(0xFF6F39E8),
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  void _showCreatePostDialog(BuildContext context) {
    final TextEditingController contentController = TextEditingController();
    String selectedTag = 'wellness';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateBottom) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Create New Post',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF161820),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6FA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: contentController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Share your story or strategy...',
                      hintStyle: TextStyle(
                        color: Color(0xFF8F919C),
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Add Tags',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF161820),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTagSelector(
                        'wellness',
                        selectedTag,
                        setStateBottom,
                      ),
                      const SizedBox(width: 8),
                      _buildTagSelector('stress', selectedTag, setStateBottom),
                      const SizedBox(width: 8),
                      _buildTagSelector(
                        'selfcare',
                        selectedTag,
                        setStateBottom,
                      ),
                      const SizedBox(width: 8),
                      _buildTagSelector(
                        'mindfulness',
                        selectedTag,
                        setStateBottom,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFE5E5EA)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Color(0xFF8F919C)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (contentController.text.isNotEmpty) {
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await _service.createPost(
                              content: contentController.text,
                              category: selectedTag,
                            );
                            if (!mounted) return;
                            navigator.pop();
                            if (ok) {
                              await _loadPosts();
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Post shared with community!'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Color(0xFF0E9186),
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6F39E8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Post',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTagSelector(
    String tag,
    String selectedTag,
    StateSetter setStateBottom,
  ) {
    final isSelected = selectedTag == tag;
    final label = _tagMap[tag] ?? tag;
    return GestureDetector(
      onTap: () => setStateBottom(() => selectedTag = tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6F39E8) : const Color(0xFFF0F0F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF6D6F7A),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _ago(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'JUST NOW';
    if (diff.inHours < 1) return '${diff.inMinutes} MIN AGO';
    if (diff.inDays < 1) return '${diff.inHours} HOURS AGO';
    return '${diff.inDays} DAYS AGO';
  }

  Future<void> _openComments(int postId) async {
    final controller = TextEditingController();
    List<CommunityCommentItem> comments = await _service.fetchComments(postId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> refresh() async {
            final next = await _service.fetchComments(postId);
            setSheetState(() => comments = next);
            _loadPosts();
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 14,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Comments',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 220,
                    child: comments.isEmpty
                        ? const Center(
                            child: Text(
                              'No comments yet.',
                              style: TextStyle(color: Color(0xFF7E8090)),
                            ),
                          )
                        : ListView.builder(
                            itemCount: comments.length,
                            itemBuilder: (context, index) {
                              final item = comments[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item.userName),
                                subtitle: Text(item.content),
                              );
                            },
                          ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Write a comment...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) return;
                          final ok = await _service.addComment(
                            postId: postId,
                            content: text,
                          );
                          if (!ok) return;
                          controller.clear();
                          await refresh();
                        },
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.isActive, required this.onTap});

  final String text;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6F39E8) : const Color(0xFFEDEEF4),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF6D6F7A),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.name,
    required this.time,
    required this.title,
    required this.body,
    required this.tags,
    required this.likesCount,
    required this.commentsCount,
    required this.likedByMe,
    required this.accentColor,
    required this.iconColor,
    required this.onLikeTap,
    required this.onCommentTap,
  });

  final String name;
  final String time;
  final String title;
  final String body;
  final String tags;
  final int likesCount;
  final int commentsCount;
  final bool likedByMe;
  final Color accentColor;
  final Color iconColor;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(Icons.person, size: 22, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF161820),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFA1A3AE),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz, size: 20, color: Color(0xFF8E909C)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: Color(0xFF161820),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF5F616F),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tags,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6F39E8),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: onLikeTap,
                child: Icon(
                  likedByMe ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: likedByMe
                      ? const Color(0xFFE11D48)
                      : const Color(0xFF8E909C),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$likesCount',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5F616F)),
              ),
              const SizedBox(width: 20),
              InkWell(
                onTap: onCommentTap,
                child: const Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: Color(0xFF8E909C),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$commentsCount',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5F616F)),
              ),
              const Spacer(),
              const Icon(Icons.share, size: 18, color: Color(0xFF8E909C)),
            ],
          ),
        ],
      ),
    );
  }
}
