part of 'admin.dart';

// Health Library management for administrators: add, view, edit and delete
// scientific articles, and moderate their comments.
// Backed by 20261126000000_article_management_comments.sql.

enum _ArticleFilter { all, published, draft }

class ArticlesAdminPage extends StatefulWidget {
  const ArticlesAdminPage({super.key});
  @override
  State<ArticlesAdminPage> createState() => _ArticlesAdminPageState();
}

class _ArticlesAdminPageState extends State<ArticlesAdminPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final _searchController = TextEditingController();
  String _search = '';
  _ArticleFilter _filter = _ArticleFilter.all;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    try {
      return await ArticleAdminService.listArticles().timeout(
        const Duration(seconds: 15),
      );
    } catch (error) {
      debugPrint('Admin articles load failed: ${error.runtimeType}');
      rethrow;
    }
  }

  void _reload() => setState(() => _future = _fetch());

  Future<void> _pullToRefresh() async {
    _reload();
    try {
      await _future;
    } catch (_) {
      // FutureBuilder shows the retryable error state.
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? article]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ArticleEditorPage(article: article)),
    );
    if (saved == true && mounted) {
      _reload();
      showSuccess(context, article == null ? 'Article added.' : 'Article saved.');
    }
  }

  Future<void> _openDetail(Map<String, dynamic> article) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminArticleDetailPage(article: article)),
    );
    if (mounted) _reload();
  }

  Future<void> _delete(Map<String, dynamic> article) async {
    final id = article['id'] as String;
    if (!await _confirmArticleDelete(context, article)) return;
    if (!mounted) return;
    setState(() => _deleting.add(id));
    try {
      await ArticleAdminService.deleteArticle(id);
      if (mounted) {
        _reload();
        showSuccess(context, 'Article deleted.');
      }
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  bool _matches(Map<String, dynamic> row) {
    final inFilter = switch (_filter) {
      _ArticleFilter.all => true,
      _ArticleFilter.published => row['status'] == 'published',
      _ArticleFilter.draft => row['status'] != 'published',
    };
    if (!inFilter) return false;
    if (_search.isEmpty) return true;
    return [row['title'], row['summary'], row['condition_name'], row['source_name']]
        .any((v) => (v ?? '').toString().toLowerCase().contains(_search));
  }

  @override
  Widget build(BuildContext context) => BotanicalScaffold(
    appBar: AppBar(title: const Text('Health Library articles')),
    body: _AdminResponsiveBody(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add and maintain the scientific articles members read in the Health Library.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  maxLength: 100,
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search articles...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  'Add article',
                  icon: Icons.add,
                  onPressed: () => _openEditor(),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.hasError) {
                  return EmptyState(
                    'Could not load articles',
                    friendlyError(s.error!),
                    retry: _reload,
                  );
                }
                final all = s.data ?? const <Map<String, dynamic>>[];
                final rows = all.where(_matches).toList();
                final published = all.where((r) => r['status'] == 'published').length;
                return RefreshIndicator(
                  onRefresh: _pullToRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      _FilterBar<_ArticleFilter>(
                        keyPrefix: 'article_filter',
                        options: {
                          _ArticleFilter.all: 'All (${all.length})',
                          _ArticleFilter.published: 'Published ($published)',
                          _ArticleFilter.draft: 'Drafts (${all.length - published})',
                        },
                        selected: _filter,
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                      const SizedBox(height: 16),
                      if (all.isEmpty)
                        const EmptyState(
                          'No articles yet',
                          'Tap Add article to publish the first one.',
                          icon: Icons.auto_stories_outlined,
                        )
                      else if (rows.isEmpty)
                        const EmptyState(
                          'No matching articles',
                          'Try a different search or filter.',
                        ),
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ArticleAdminCard(
                            article: row,
                            busy: _deleting.contains(row['id']),
                            onOpen: () => _openDetail(row),
                            onEdit: () => _openEditor(row),
                            onDelete: () => _delete(row),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmArticleDelete(
  BuildContext context,
  Map<String, dynamic> article,
) async {
  final comments = (article['comment_count'] as num?)?.toInt() ?? 0;
  final likes = (article['like_count'] as num?)?.toInt() ?? 0;
  final title = (article['title'] ?? '').toString();
  String plural(int n, String word) => n == 1 ? '1 $word' : '$n ${word}s';
  final extras = comments + likes > 0
      ? ', together with its ${plural(comments, 'comment')} and ${plural(likes, 'like')}'
      : '';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      actionsAlignment: MainAxisAlignment.center,
      title: const Text('Delete article?'),
      content: Text(
        '"$title" will be removed from the Health Library$extras. '
        'This cannot be undone.',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _ArticleStatusChip extends StatelessWidget {
  final String? status;
  const _ArticleStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    if (status != 'published') return const RoleChip('Draft', pending: true);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'Published',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
      ),
    );
  }
}

class _ArticleAdminCard extends StatelessWidget {
  final Map<String, dynamic> article;
  final bool busy;
  final VoidCallback onOpen, onEdit, onDelete;
  const _ArticleAdminCard({
    required this.article,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final condition = (article['condition_name'] ?? '').toString();
    final updated = formatDay((article['updated_at'] ?? article['created_at'])?.toString());
    final likes = (article['like_count'] as num?)?.toInt() ?? 0;
    final comments = (article['comment_count'] as num?)?.toInt() ?? 0;
    return SurfaceCard(
      onTap: busy ? null : onOpen,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (article['title'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              _ArticleStatusChip(article['status'] as String?),
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (article['summary'] ?? '').toString(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (condition.isNotEmpty)
                      Text(condition, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    if (updated.isNotEmpty)
                      Text('Updated $updated',
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.favorite_border, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text('$likes', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(width: 10),
                      const Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text('$comments', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit article',
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Delete article',
                onPressed: busy ? null : onDelete,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full article as members see it, plus status details and comment moderation.
class AdminArticleDetailPage extends StatefulWidget {
  final Map<String, dynamic> article;
  const AdminArticleDetailPage({super.key, required this.article});
  @override
  State<AdminArticleDetailPage> createState() => _AdminArticleDetailPageState();
}

class _AdminArticleDetailPageState extends State<AdminArticleDetailPage> {
  late Map<String, dynamic> _article = widget.article;
  bool _busy = false;
  int _commentsVersion = 0;

  String get _id => _article['id'] as String;

  Future<void> _refreshArticle() async {
    try {
      final rows = await ArticleAdminService.listArticles();
      final match = rows.where((r) => r['id'] == _id);
      if (!mounted) return;
      if (match.isEmpty) {
        Navigator.pop(context);
        return;
      }
      setState(() => _article = match.first);
    } catch (error) {
      if (mounted) showAppError(context, error, retry: _refreshArticle);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ArticleEditorPage(article: _article)),
    );
    if (saved == true && mounted) {
      showSuccess(context, 'Article saved.');
      await _refreshArticle();
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == 'draft') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Move to drafts?'),
          content: const Text(
            'Help seekers and volunteers will no longer see this article or its comments. '
            'You can publish it again at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Move to drafts'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ArticleAdminService.setStatus(_id, status);
      if (!mounted) return;
      showSuccess(
        context,
        status == 'published' ? 'Article published.' : 'Article moved to drafts.',
      );
      await _refreshArticle();
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirmArticleDelete(context, _article) || !mounted) return;
    setState(() => _busy = true);
    try {
      await ArticleAdminService.deleteArticle(_id);
      if (!mounted) return;
      showSuccess(context, 'Article deleted.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSource() async {
    final raw = (_article['source_url'] ?? '').toString().trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !ArticleAdminService.isValidUrl(raw)) {
      showAppError(context, ArgumentError('This article has no valid source link.'));
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showAppError(context, ArgumentError('Could not open the source link.'));
      }
    } catch (_) {
      if (mounted) showAppError(context, ArgumentError('Could not open the source link.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;
    final condition = (a['condition_name'] ?? '').toString();
    final published = a['status'] == 'published';
    final sourceName = (a['source_name'] ?? '').toString();
    final image = (a['image_url'] ?? '').toString();
    return BotanicalScaffold(
      appBar: AppBar(
        title: const Text('Article'),
        actions: [
          IconButton(
            tooltip: 'Edit article',
            onPressed: _busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete article',
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
        ],
      ),
      body: _AdminResponsiveBody(
        child: RefreshIndicator(
          onRefresh: () async {
            await _refreshArticle();
            if (mounted) setState(() => _commentsVersion++);
          },
          // A plain scroll view keeps the comment list built and interactive.
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ArticleStatusChip(a['status'] as String?),
                    if (condition.isNotEmpty)
                      Text(condition, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  published
                      ? 'Visible to members since ${formatDay(a['published_at']?.toString())}.'
                      : 'Draft: only administrators can see this article.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                // Publish or unpublish without opening the editor.
                SizedBox(
                  width: double.infinity,
                  child: published
                      ? OutlinedButton.icon(
                          onPressed: _busy ? null : () => _setStatus('draft'),
                          icon: const Icon(Icons.visibility_off_outlined),
                          label: const Text('Move to drafts'),
                        )
                      : FilledButton.icon(
                          onPressed: _busy ? null : () => _setStatus('published'),
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.public),
                          label: const Text('Publish article'),
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  (a['title'] ?? '').toString(),
                  style: const TextStyle(fontFamily: 'DMSans', fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Text(
                  (a['summary'] ?? '').toString(),
                  style: const TextStyle(fontSize: 15, height: 1.6, color: AppColors.textMuted),
                ),
                if (image.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      image,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SelectableText(
                  (a['content'] ?? '').toString(),
                  style: const TextStyle(fontSize: 15, height: 1.7),
                ),
                const SizedBox(height: 20),
                const Divider(),
                Text(
                  sourceName.isEmpty ? 'No source added' : 'Source: $sourceName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if ((a['source_url'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: _openSource,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open original source'),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.favorite_border, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text('${(a['like_count'] as num?)?.toInt() ?? 0} likes',
                        style: const TextStyle(color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                ArticleCommentsSection(
                  key: ValueKey('comments_${_id}_$_commentsVersion'),
                  articleId: _id,
                  moderator: true,
                  onCountChanged: (count) {
                    if (count != (a['comment_count'] as num?)?.toInt()) {
                      setState(() => _article = {..._article, 'comment_count': count});
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Add (article null) or edit an article.
class ArticleEditorPage extends StatefulWidget {
  final Map<String, dynamic>? article;
  const ArticleEditorPage({super.key, this.article});
  @override
  State<ArticleEditorPage> createState() => _ArticleEditorPageState();
}

class _ArticleEditorPageState extends State<ArticleEditorPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _summary, _content, _sourceName, _sourceUrl, _imageUrl;
  String? _conditionId;
  List<Map<String, dynamic>>? _conditions;
  Object? _conditionsError;
  bool _busy = false;
  // Source fields are required only once the admin chooses Publish.
  bool _requireSource = false;
  String? _error;

  bool get _editing => widget.article != null;

  @override
  void initState() {
    super.initState();
    final a = widget.article ?? const <String, dynamic>{};
    String text(String key) => (a[key] ?? '').toString();
    _title = TextEditingController(text: text('title'));
    _summary = TextEditingController(text: text('summary'));
    _content = TextEditingController(text: text('content'));
    _sourceName = TextEditingController(text: text('source_name'));
    _sourceUrl = TextEditingController(text: text('source_url'));
    _imageUrl = TextEditingController(text: text('image_url'));
    _conditionId = a['condition_id'] as String?;
    _loadConditions();
  }

  @override
  void dispose() {
    for (final c in [_title, _summary, _content, _sourceName, _sourceUrl, _imageUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConditions() async {
    setState(() => _conditionsError = null);
    try {
      final conditions = await ArticleAdminService.getConditions();
      if (mounted) setState(() => _conditions = conditions);
    } catch (error) {
      if (mounted) setState(() => _conditionsError = error);
    }
  }

  /// Asks whether to publish now or keep the article as a draft.
  /// The two choices sit side by side at equal width (no stacked buttons);
  /// the close button cancels.
  Future<String?> _chooseStatus() {
    final current = widget.article?['status'] == 'published' ? 'published' : 'draft';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        titlePadding: const EdgeInsetsDirectional.fromSTEB(24, 16, 8, 0),
        title: Row(
          children: [
            Expanded(child: Text(_editing ? 'Save article' : 'Add article')),
            IconButton(
              tooltip: 'Cancel',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_editing ? 'This article is currently ${current == 'published' ? 'published' : 'a draft'}. ' : ''}'
              'Publish it so help seekers and volunteers can read and comment on it, '
              'or save it as a draft that only administrators can see.',
              style: const TextStyle(height: 1.45),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext, 'draft'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Save as draft', maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, 'published'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Publish', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _lengthRule(String? v, String what, int min, int max) {
    final n = (v ?? '').trim().runes.length;
    if (n == 0) return 'Enter $what';
    if (n < min) return 'Use at least $min characters';
    if (n > max) return 'Use at most $max characters';
    return null;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _requireSource = false);
    if (!_form.currentState!.validate()) return;
    final status = await _chooseStatus();
    if (status == null || !mounted) return;
    if (status == 'published') {
      setState(() => _requireSource = true);
      if (!_form.currentState!.validate()) {
        setState(() => _error =
            'Add a source name and link before publishing, or save it as a draft.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ArticleAdminService.saveArticle(
        id: widget.article?['id'] as String?,
        title: _title.text,
        summary: _summary.text,
        content: _content.text,
        conditionId: _conditionId,
        sourceName: _sourceName.text,
        sourceUrl: _sourceUrl.text,
        imageUrl: _imageUrl.text,
        status: status,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Active conditions, plus the article's current one if it was deactivated.
    final conditions = _conditions
        ?.where((c) => c['is_active'] == true || c['id'] == _conditionId)
        .toList();
    final selectedCondition =
        conditions != null && conditions.any((c) => c['id'] == _conditionId)
            ? _conditionId
            : null;
    return PopScope(
      canPop: !_busy,
      child: BotanicalScaffold(
        appBar: AppBar(title: Text(_editing ? 'Edit article' : 'Add article')),
        body: _AdminResponsiveBody(
          child: Form(
            key: _form,
            // Not a lazy ListView: every field must be built so Save
            // validates all of them, including those scrolled out of view.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Title', requiredField: true),
                _AdminTextField(
                  controller: _title,
                  enabled: !_busy,
                  maxLength: ArticleAdminService.titleMax,
                  validator: (v) => _lengthRule(v, 'a title', 3, ArticleAdminService.titleMax),
                ),
                const FieldLabel('Summary', requiredField: true),
                _AdminTextField(
                  controller: _summary,
                  enabled: !_busy,
                  maxLines: 3,
                  maxLength: ArticleAdminService.summaryMax,
                  decoration: const InputDecoration(
                    helperText: 'Shown on the article card in the library.',
                  ),
                  validator: (v) => _lengthRule(v, 'a summary', 10, ArticleAdminService.summaryMax),
                ),
                const FieldLabel('Article content', requiredField: true),
                _AdminTextField(
                  controller: _content,
                  enabled: !_busy,
                  maxLines: 14,
                  maxLength: ArticleAdminService.contentMax,
                  validator: (v) => _lengthRule(v, 'the article content', 20, ArticleAdminService.contentMax),
                ),
                const FieldLabel('Health condition'),
                if (_conditionsError != null)
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Could not load conditions.',
                            style: TextStyle(color: AppColors.error)),
                      ),
                      TextButton(onPressed: _loadConditions, child: const Text('Try again')),
                    ],
                  )
                else if (conditions == null)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String?>(
                    initialValue: selectedCondition,
                    isExpanded: true,
                    decoration: InputDecoration(
                      helperText: conditions.isEmpty
                          ? 'No conditions yet. Add them in Admin > Conditions.'
                          : 'Conditions are managed in Admin > Conditions.',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('General (no specific condition)'),
                      ),
                      for (final c in conditions)
                        DropdownMenuItem<String?>(
                          value: c['id'] as String,
                          child: Text(
                            c['is_active'] == true
                                ? (c['name'] ?? '').toString()
                                : '${c['name'] ?? ''} (inactive)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _conditionId = v),
                  ),
                const FieldLabel('Source name'),
                _AdminTextField(
                  controller: _sourceName,
                  enabled: !_busy,
                  maxLength: ArticleAdminService.sourceNameMax,
                  decoration: const InputDecoration(hintText: 'e.g. World Health Organization'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) {
                      return _requireSource ? 'Add a source before publishing' : null;
                    }
                    return text.runes.length > ArticleAdminService.sourceNameMax
                        ? 'Use at most ${ArticleAdminService.sourceNameMax} characters'
                        : null;
                  },
                ),
                const FieldLabel('Source link'),
                _AdminTextField(
                  controller: _sourceUrl,
                  enabled: !_busy,
                  maxLength: ArticleAdminService.urlMax,
                  decoration: const InputDecoration(hintText: 'https://'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) {
                      return _requireSource ? 'Add a source link before publishing' : null;
                    }
                    return ArticleAdminService.isValidUrl(text)
                        ? null
                        : 'Enter a link that starts with https:// or http://';
                  },
                ),
                const FieldLabel('Image link (optional)'),
                _AdminTextField(
                  controller: _imageUrl,
                  enabled: !_busy,
                  maxLength: ArticleAdminService.urlMax,
                  decoration: const InputDecoration(hintText: 'https://'),
                  validator: (v) {
                    final text = (v ?? '').trim();
                    if (text.isEmpty) return null;
                    return ArticleAdminService.isValidUrl(text, httpsOnly: true)
                        ? null
                        : 'Enter a link that starts with https://';
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  FieldErrorNotice(_error!),
                ],
                const SizedBox(height: 22),
                // Opens the Publish / Save as draft dialog.
                PrimaryButton(
                  _editing ? 'Save changes' : 'Add article',
                  busy: _busy,
                  icon: Icons.check,
                  onPressed: _save,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
