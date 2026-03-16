class CommunitySnapshot {
  const CommunitySnapshot({
    required this.generatedAt,
    required this.repositoryUrl,
    required this.owner,
    required this.ranking,
    required this.latestContributors,
  });

  factory CommunitySnapshot.fromJson(Map<String, dynamic> json) {
    final repository = (json['repository'] as Map<String, dynamic>?) ?? const {};
    return CommunitySnapshot(
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      repositoryUrl: repository['url'] as String? ?? '',
      owner: CommunityContributor.fromJson(
        (json['owner'] as Map<String, dynamic>?) ?? const {},
      ),
      ranking: ((json['ranking'] as List<dynamic>?) ?? const [])
          .map(
            (item) =>
                CommunityContributor.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
      latestContributors: ((json['latestContributors'] as List<dynamic>?) ??
              const [])
          .map(
            (item) =>
                CommunityContributor.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final DateTime? generatedAt;
  final String repositoryUrl;
  final CommunityContributor owner;
  final List<CommunityContributor> ranking;
  final List<CommunityContributor> latestContributors;
}

class CommunityContributor {
  const CommunityContributor({
    required this.rank,
    required this.login,
    required this.name,
    required this.avatarUrl,
    required this.profileUrl,
    required this.role,
    required this.summaryEn,
    required this.summaryEs,
    required this.commits,
    required this.mergedPrs,
    required this.changedLines,
    required this.score,
    required this.lastContributionAt,
    required this.isOwner,
  });

  factory CommunityContributor.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    String summaryEn = '';
    String summaryEs = '';
    if (summary is Map<String, dynamic>) {
      summaryEn = summary['en'] as String? ?? '';
      summaryEs = summary['es'] as String? ?? '';
    } else if (summary is String) {
      summaryEn = summary;
      summaryEs = summary;
    }

    return CommunityContributor(
      rank: _asInt(json['rank']),
      login: json['login'] as String? ?? '',
      name: json['name'] as String? ?? json['login'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      profileUrl: json['profileUrl'] as String? ?? '',
      role: json['role'] as String? ?? 'Contributor',
      summaryEn: summaryEn,
      summaryEs: summaryEs,
      commits: _asInt(json['commits']),
      mergedPrs: _asInt(json['mergedPrs']),
      changedLines: _asInt(json['changedLines']),
      score: _asInt(json['score']),
      lastContributionAt: DateTime.tryParse(
        json['lastContributionAt'] as String? ?? '',
      ),
      isOwner: json['isOwner'] as bool? ?? false,
    );
  }

  final int rank;
  final String login;
  final String name;
  final String avatarUrl;
  final String profileUrl;
  final String role;
  final String summaryEn;
  final String summaryEs;
  final int commits;
  final int mergedPrs;
  final int changedLines;
  final int score;
  final DateTime? lastContributionAt;
  final bool isOwner;

  String displaySummary(bool isSpanish) => isSpanish ? summaryEs : summaryEn;

  String get displayName => name.trim().isEmpty ? login : name;

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse('$value') ?? 0;
    }
}
