import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/app_strings.dart';
import 'community_models.dart';
import 'community_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final CommunityService _service = CommunityService();
  late Future<CommunitySnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.load();
  }

  Future<void> _refresh() async {
    final next = _service.load(forceRefresh: true);
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _openProfile(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Scaffold(
      appBar: AppBar(title: Text(strings.community)),
      body: FutureBuilder<CommunitySnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strings.communityLoadFailed,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _refresh,
                      child: Text(strings.tryAgain),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final topContributors = data.ranking
              .where((item) => !item.isOwner)
              .take(12)
              .toList(growable: false);
          final latestContributors = data.latestContributors
              .take(50)
              .toList(growable: false);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _HeroCard(
                  contributor: data.owner,
                  lastUpdatedLabel: _lastUpdatedLabel(context, data.generatedAt),
                  onTapProfile: () => _openProfile(data.owner.profileUrl),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: strings.topContributors,
                  subtitle: strings.topContributorsBody,
                  child: Column(
                    children: topContributors
                        .map(
                          (contributor) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ContributorRow(
                              contributor: contributor,
                              onTap: () => _openProfile(contributor.profileUrl),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: strings.latestContributors,
                  subtitle: strings.latestContributorsBody,
                  child: Column(
                    children: latestContributors
                        .map(
                          (contributor) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ContributorRow(
                              contributor: contributor,
                              dense: true,
                              onTap: () => _openProfile(contributor.profileUrl),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 14),
                _SectionCard(
                  title: strings.thankYouContributorsTitle,
                  subtitle: '',
                  child: Text(
                    strings.thankYouContributorsBody,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _lastUpdatedLabel(BuildContext context, DateTime? generatedAt) {
    final strings = context.strings;
    if (generatedAt == null) {
      return strings.updatedWeekly;
    }

    final locale = Localizations.localeOf(context).languageCode;
    final formatted = DateFormat.yMMMd(locale).add_Hm().format(generatedAt.toLocal());
    return strings.updatedAt(formatted);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.contributor,
    required this.lastUpdatedLabel,
    required this.onTapProfile,
  });

  final CommunityContributor contributor;
  final String lastUpdatedLabel;
  final VoidCallback onTapProfile;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        gradient: const LinearGradient(
          colors: [Color(0xFF111C11), Color(0xFF07151C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(url: contributor.avatarUrl, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contributor.displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${contributor.login}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onTapProfile,
                child: Text(strings.profileLink),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            contributor.displaySummary(strings.isSpanish),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatBadge(
                label: strings.communityRole,
                value: contributor.role,
              ),
              _StatBadge(
                label: strings.communityScore,
                value: contributor.score.toString(),
              ),
              _StatBadge(
                label: strings.weeklySync,
                value: lastUpdatedLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _ContributorRow extends StatelessWidget {
  const _ContributorRow({
    required this.contributor,
    required this.onTap,
    this.dense = false,
  });

  final CommunityContributor contributor;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: EdgeInsets.all(dense ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              _RankBadge(rank: contributor.rank),
              const SizedBox(width: 12),
              _Avatar(url: contributor.avatarUrl, radius: dense ? 18 : 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contributor.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${contributor.login}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    strings.contributorStats(
                      prs: contributor.mergedPrs,
                      commits: contributor.commits,
                    ),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.communityScoreValue(contributor.score),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB8FF8C),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$rank',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.radius});

  final String url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        child: Icon(Icons.person_rounded, size: radius),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      backgroundImage: NetworkImage(url),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.64),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
