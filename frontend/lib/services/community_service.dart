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

class DoctorItem {
  const DoctorItem({
    required this.id,
    required this.fullName,
    required this.designation,
    required this.experienceYears,
    required this.specialist,
    required this.contactNumber,
  });

  final int id;
  final String fullName;
  final String designation;
  final int experienceYears;
  final String specialist;
  final String contactNumber;
}

class TrustedContactItem {
  const TrustedContactItem({
    required this.id,
    required this.name,
    required this.relationship,
    required this.contactNumber,
  });

  final int id;
  final String name;
  final String relationship;
  final String contactNumber;
}

class DoctorChatMessageItem {
  const DoctorChatMessageItem({
    required this.id,
    required this.sender,
    required this.message,
    required this.createdAt,
  });

  final int id;
  final String sender;
  final String message;
  final DateTime createdAt;
}

class DoctorInboxItem {
  const DoctorInboxItem({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.lastMessage,
    required this.lastSender,
    required this.lastTime,
  });

  final int userId;
  final String userName;
  final String userEmail;
  final String lastMessage;
  final String lastSender;
  final DateTime lastTime;
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

  Future<List<DoctorItem>> fetchDoctors() async {
    final headers = await _headers();
    if (headers == null) return const [];
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/emergency/doctors/'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => DoctorItem(
            id: (it['id'] as num?)?.toInt() ?? 0,
            fullName: (it['full_name'] ?? '').toString(),
            designation: (it['designation'] ?? '').toString(),
            experienceYears: (it['experience_years'] as num?)?.toInt() ?? 0,
            specialist: (it['specialist'] ?? '').toString(),
            contactNumber: (it['contact_number'] ?? '').toString(),
          ),
        )
        .toList();
  }

  Future<List<TrustedContactItem>> fetchTrustedContacts() async {
    final headers = await _headers();
    if (headers == null) return const [];
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/emergency/trusted-contacts/'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => TrustedContactItem(
            id: (it['id'] as num?)?.toInt() ?? 0,
            name: (it['name'] ?? '').toString(),
            relationship: (it['relationship'] ?? '').toString(),
            contactNumber: (it['contact_number'] ?? '').toString(),
          ),
        )
        .toList();
  }

  Future<bool> createTrustedContact({
    required String name,
    required String relationship,
    required String contactNumber,
  }) async {
    final headers = await _headers();
    if (headers == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/emergency/trusted-contacts/'),
      headers: headers,
      body: jsonEncode({
        'name': name.trim(),
        'relationship': relationship.trim(),
        'contact_number': contactNumber.trim(),
      }),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<List<DoctorChatMessageItem>> fetchDoctorChat(int doctorId) async {
    final headers = await _headers();
    if (headers == null) return const [];
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/emergency/doctors/$doctorId/chat/'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => DoctorChatMessageItem(
            id: (it['id'] as num?)?.toInt() ?? 0,
            sender: (it['sender'] ?? 'user').toString(),
            message: (it['message'] ?? '').toString(),
            createdAt: DateTime.tryParse((it['created_at'] ?? '').toString()) ?? DateTime.now(),
          ),
        )
        .toList();
  }

  Future<bool> sendDoctorChatMessage({
    required int doctorId,
    required String message,
  }) async {
    final headers = await _headers();
    if (headers == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/emergency/doctors/$doctorId/chat/'),
      headers: headers,
      body: jsonEncode({'message': message.trim()}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<List<DoctorInboxItem>> fetchDoctorInbox() async {
    final headers = await _headers();
    if (headers == null) return const [];
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/doctor/inbox/'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => DoctorInboxItem(
            userId: (it['user_id'] as num?)?.toInt() ?? 0,
            userName: (it['user_name'] ?? 'User').toString(),
            userEmail: (it['user_email'] ?? '').toString(),
            lastMessage: (it['last_message'] ?? '').toString(),
            lastSender: (it['last_sender'] ?? '').toString(),
            lastTime: DateTime.tryParse((it['last_time'] ?? '').toString()) ?? DateTime.now(),
          ),
        )
        .toList();
  }

  Future<List<DoctorChatMessageItem>> fetchDoctorThreadMessages(int userId) async {
    final headers = await _headers();
    if (headers == null) return const [];
    final res = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/doctor/inbox/$userId/messages/'),
      headers: headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as List<dynamic>).cast<Map<String, dynamic>>();
    return list
        .map(
          (it) => DoctorChatMessageItem(
            id: (it['id'] as num?)?.toInt() ?? 0,
            sender: (it['sender'] ?? 'user').toString(),
            message: (it['message'] ?? '').toString(),
            createdAt: DateTime.tryParse((it['created_at'] ?? '').toString()) ?? DateTime.now(),
          ),
        )
        .toList();
  }

  Future<bool> sendDoctorReply({
    required int userId,
    required String message,
  }) async {
    final headers = await _headers();
    if (headers == null) return false;
    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/auth/doctor/inbox/$userId/messages/'),
      headers: headers,
      body: jsonEncode({'message': message.trim()}),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
