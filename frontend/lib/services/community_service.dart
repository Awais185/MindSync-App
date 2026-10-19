import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class CommunityPostItem {
  const CommunityPostItem({
    required this.id,
    required this.content,
    required this.category,
    required this.userName,
    required this.createdAt,
    required this.likesCount,
    required this.commentsCount,
    required this.likedByMe,
  });

  final int id;
  final String content;
  final String category;
  final String userName;
  final DateTime createdAt;
  final int likesCount;
  final int commentsCount;
  final bool likedByMe;
}

class CommunityCommentItem {
  const CommunityCommentItem({
    required this.id,
    required this.content,
    required this.userName,
    required this.createdAt,
  });

  final int id;
  final String content;
  final String userName;
  final DateTime createdAt;
}

class CommunityService {
  Future<Map<String, String>?> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth.accessToken');
    if (token == null || token.isEmpty) return null;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<CommunityPostItem>> fetchPosts(String category) async {
    final headers = await _headers();
    if (headers == null) return const [];
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/auth/community/posts/?category=${Uri.encodeQueryComponent(category)}',
    );
    final res = await http.get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => CommunityPostItem(
            id: (it['id'] as num?)?.toInt() ?? 0,
            content: (it['content'] ?? '').toString(),
            category: (it['category'] ?? 'other').toString(),
            userName: (it['user_name'] ?? 'User').toString(),
            createdAt: DateTime.tryParse((it['created_at'] ?? '').toString()) ?? DateTime.now(),
            likesCount: (it['likes_count'] as num?)?.toInt() ?? 0,
            commentsCount: (it['comments_count'] as num?)?.toInt() ?? 0,
            likedByMe: (it['liked_by_me'] as bool?) ?? false,
          ),
        )
        .toList();
  }

  Future<bool> createPost({
    required String content,
    required String category,
  }) async {
    final headers = await _headers();
    if (headers == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/community/posts/'),
      headers: headers,
      body: jsonEncode({'content': content.trim(), 'category': category}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> toggleLike(int postId) async {
    final headers = await _headers();
    if (headers == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/community/posts/$postId/like/'),
      headers: headers,
      body: jsonEncode({}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<List<CommunityCommentItem>> fetchComments(int postId) async {
    final headers = await _headers();
    if (headers == null) return const [];
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/community/posts/$postId/comments/'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => CommunityCommentItem(
            id: (it['id'] as num?)?.toInt() ?? 0,
            content: (it['content'] ?? '').toString(),
            userName: (it['user_name'] ?? 'User').toString(),
            createdAt: DateTime.tryParse((it['created_at'] ?? '').toString()) ?? DateTime.now(),
          ),
        )
        .toList();
  }

  Future<bool> addComment({
    required int postId,
    required String content,
  }) async {
    final headers = await _headers();
    if (headers == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/community/posts/$postId/comments/'),
      headers: headers,
      body: jsonEncode({'content': content.trim()}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
