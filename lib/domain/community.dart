import 'catalog.dart';

/// A post on a subject's community tab.
class CommunityEntry {
  const CommunityEntry({
    required this.id,
    required this.userId,
    required this.author,
    this.avatarUrl,
    this.score = 0,
    this.status,
    this.replies = 0,
    this.title,
    this.text = '',
    this.time,
  });
  final int id;
  final String userId, author;
  final String? avatarUrl, title;
  final int score, replies;
  final CollectionStatus? status;
  final String text;

  /// Unix seconds.
  final int? time;
}

/// A post in a discussion topic, with the replies nested under it.
class TopicPost {
  const TopicPost({
    required this.id,
    required this.author,
    this.avatarUrl,
    this.time,
    this.content = '',
    this.replies = const [],
  });
  final int id;
  final String author;
  final String? avatarUrl;

  /// Unix seconds.
  final int? time;

  /// Bangumi BBCode.
  final String content;
  final List<TopicPost> replies;
}

class CommunityPage {
  const CommunityPage({required this.entries, required this.total});
  final List<CommunityEntry> entries;
  final int total;
}

/// A subject's community posts and related subjects, as the signed-in
/// account sees them.
abstract interface class SubjectCommunitySource {
  /// The account whose view is shown; changes on sign-in and sign-out.
  String get userId;
  AccountProfile? get profile;

  /// One page of `comments`, `reviews` or `topics`.
  Future<CommunityPage> page(
    int subjectId,
    String segment, {
    int offset = 0,
    bool refresh = false,
  });

  /// A discussion topic: its opening post, then the replies.
  Future<List<TopicPost>> topic(int topicId);

  /// The full BBCode of a review, whose listing holds only its start.
  Future<String> blog(int entryId);

  /// An episode's comments, oldest first, each with its replies.
  Future<List<TopicPost>> episodeComments(
    int episodeId, {
    bool refresh = false,
  });
  Future<List<Subject>> relations(int subjectId, {bool refresh = false});
}
