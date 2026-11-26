import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/tokens.dart';
import '../../backend/services/health_library_service.dart';
import 'article_comments.dart';

/// Reader-facing Health Library. Members can like, save and comment on
/// articles; article management belongs to Admin.
class HealthLibraryPage extends StatefulWidget {
  const HealthLibraryPage({super.key});

  @override
  State<HealthLibraryPage> createState() => _HealthLibraryPageState();
}

enum _Collection { all, liked, saved }
enum _ArticleSort { newest, popular }

class _HealthLibraryPageState extends State<HealthLibraryPage> {
  final _search = TextEditingController();
  _Collection _collection = _Collection.all;
  _ArticleSort _sort = _ArticleSort.newest;
  String? _conditionId;
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _conditions = [];
  bool _loading = true;
  String? _error;
  int _requestVersion = 0;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conditions = await HealthLibraryService.getConditions();
      final articles = await HealthLibraryService.getArticles(
        search: '',
        conditionId: _conditionId,
        collection: _collection.name,
        sort: _sort.name,
      );
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _conditions = conditions;
        _articles = articles;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _error = 'Unable to load articles. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  // Search operates locally on the last loaded collection to avoid a request
  // on every keystroke; changing collection, sort or condition refreshes data.
  List<Map<String, dynamic>> get _visible {
    final term = _search.text.trim().toLowerCase();
    if (term.isEmpty) return _articles;
    return _articles.where((a) {
      final title = (a['title'] ?? '').toString().toLowerCase();
      final summary = (a['summary'] ?? '').toString().toLowerCase();
      return title.contains(term) || summary.contains(term);
    }).toList();
  }

  void _clear() {
    _search.clear();
    setState(() {
      _sort = _ArticleSort.newest;
      _conditionId = null;
    });
    _load();
  }

  // Update the visible article immediately; persist the change without
  // re-fetching the entire library. Roll back if Supabase rejects the update.
  Future<void> _toggle(Map<String, dynamic> article, {required bool like}) async {
    final id = article['id'] as String;
    if (_busy.contains(id)) return;

    final field = like ? 'is_liked' : 'is_saved';
    final oldValue = article[field] == true;
    final oldCount = (article['like_count'] as num?)?.toInt() ?? 0;
    final newValue = !oldValue;
    final newCount = like
        ? (oldCount + (newValue ? 1 : -1)).clamp(0, 1 << 30).toInt()
        : oldCount;

    // Keep a copy for safe rollback, including in Liked/Saved collections.
    final previous = _articles.map((a) => Map<String, dynamic>.from(a)).toList();
    setState(() {
      _busy.add(id);
      _articles = _articles.map((a) {
        if (a['id'] != id) return a;
        return Map<String, dynamic>.from(a)
          ..[field] = newValue
          ..['like_count'] = newCount;
      }).where((a) {
        if (like && _collection == _Collection.liked) return a['is_liked'] == true;
        if (!like && _collection == _Collection.saved) return a['is_saved'] == true;
        return true;
      }).toList();
      if (like && _sort == _ArticleSort.popular) {
        _articles.sort((a, b) =>
            ((b['like_count'] as num?)?.toInt() ?? 0)
                .compareTo((a['like_count'] as num?)?.toInt() ?? 0));
      }
    });

    try {
      if (like) {
        await HealthLibraryService.setLiked(id, liked: newValue);
      } else {
        await HealthLibraryService.setSaved(id, saved: newValue);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _articles = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(like
              ? 'Could not update your like. Please try again.'
              : 'Could not update saved articles. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final articles = _visible;
    return Scaffold(
      backgroundColor: MaakColors.canvasMid,
      appBar: AppBar(
        backgroundColor: MaakColors.canvasTop,
        surfaceTintColor: Colors.transparent,
        title: const Text('Health Library', style: MaakText.pageTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh articles',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: MaakGradients.canvas),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _welcomeCard(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _searchField()),
                        const SizedBox(width: 10),
                        _filterMenu(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              _collection == _Collection.all
                                  ? 'Explore articles'
                                  : _collection == _Collection.liked
                                      ? 'Liked articles'
                                      : 'Saved articles',
                              style: MaakText.section,
                            ),
                          ),
                        ),
                        _myArticlesMenu(),
                      ],
                    ),
                    if (_collection != _Collection.all)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: () => _setCollection(_Collection.all),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Back to all articles'),
                          style: TextButton.styleFrom(
                            foregroundColor: MaakColors.ink,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 44),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _messageCard(
                        Icons.wifi_off_outlined,
                        'Could not load Health Library',
                        _error!,
                        action: TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      )
                    else if (articles.isEmpty)
                      _messageCard(
                        _collection == _Collection.liked
                            ? Icons.favorite_border
                            : _collection == _Collection.saved
                                ? Icons.bookmark_border
                                : Icons.auto_stories_outlined,
                        _search.text.trim().isNotEmpty || _conditionId != null
                            ? 'No matching articles'
                            : _collection == _Collection.liked
                                ? 'No liked articles yet'
                                : _collection == _Collection.saved
                                    ? 'No saved articles yet'
                                    : 'Articles are coming soon',
                        _search.text.trim().isNotEmpty || _conditionId != null
                            ? 'Try a different search or clear your filters.'
                            : _collection == _Collection.liked
                                ? 'Articles you like will appear here.'
                                : _collection == _Collection.saved
                                    ? 'Articles you save for later will appear here.'
                                    : 'Published articles will appear here when they are added.',
                      )
                    else
                      ...articles.map(_articleCard),
                    const SizedBox(height: 22),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: MaakColors.muted, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Health information is educational and does not replace professional medical advice.',
                            style: TextStyle(color: MaakColors.muted, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomeCard() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: MaakGradients.orb,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('YOUR SPACE TO LEARN',
                  style: TextStyle(color: MaakColors.ink, fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
              SizedBox(height: 7),
              Text('Explore. Learn. Feel supported.',
                  style: TextStyle(color: MaakColors.ink, fontSize: 20,
                      fontWeight: FontWeight.w700, height: 1.2)),
              SizedBox(height: 6),
              Text('Helpful health knowledge, all in one place.',
                  style: TextStyle(color: MaakColors.onHero, height: 1.4)),
            ],
          )),
          SizedBox(width: 10),
          Icon(Icons.auto_stories_outlined, size: 38, color: MaakColors.ink),
        ]),
      );

  void _setCollection(_Collection value) {
    if (_collection == value) return;
    setState(() => _collection = value);
    _load();
  }

  bool get _filtersActive => _sort != _ArticleSort.newest || _conditionId != null;

  Widget _searchField() => TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search articles or topics',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(_search.clear),
                  icon: const Icon(Icons.close),
                ),
          filled: true,
          fillColor: MaakColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: MaakColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: MaakColors.border),
          ),
        ),
      );

  static const _menuStyle = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(MaakColors.surface),
    surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
    maximumSize: WidgetStatePropertyAll(Size(320, 440)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    )),
  );

  Widget _menuHeader(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: MaakColors.muted, letterSpacing: 0.4)),
      );

  Widget _choice(String label, {required bool selected, required VoidCallback onPressed,
          IconData? icon}) =>
      MenuItemButton(
        leadingIcon: Icon(selected ? Icons.check : (icon ?? Icons.circle_outlined),
            size: 18, color: selected ? MaakColors.coralDeep : MaakColors.muted),
        onPressed: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Text(label, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        ),
      );

  /// "Filter & sort" beside the search bar; opens as a dropdown menu.
  Widget _filterMenu() => MenuAnchor(
        style: _menuStyle,
        alignmentOffset: const Offset(0, 6),
        menuChildren: [
          _menuHeader('SORT BY'),
          _choice('Newest first', selected: _sort == _ArticleSort.newest,
              icon: Icons.schedule, onPressed: () {
            setState(() => _sort = _ArticleSort.newest);
            _load();
          }),
          _choice('Most popular', selected: _sort == _ArticleSort.popular,
              icon: Icons.trending_up, onPressed: () {
            setState(() => _sort = _ArticleSort.popular);
            _load();
          }),
          const Divider(height: 12),
          _menuHeader('HEALTH CONDITION'),
          _choice('All conditions', selected: _conditionId == null, onPressed: () {
            setState(() => _conditionId = null);
            _load();
          }),
          for (final condition in _conditions)
            _choice((condition['name'] ?? '').toString(),
                selected: _conditionId == condition['id'], onPressed: () {
              setState(() => _conditionId = condition['id'] as String);
              _load();
            }),
          if (_filtersActive) ...[
            const Divider(height: 12),
            MenuItemButton(
              leadingIcon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              onPressed: _clear,
              child: const Text('Clear filters'),
            ),
          ],
        ],
        builder: (context, controller, _) => Tooltip(
          message: _filtersActive ? 'Filter & sort (active)' : 'Filter & sort',
          child: Semantics(
            button: true,
            expanded: controller.isOpen,
            label: 'Filter and sort',
            child: Material(
              color: _filtersActive ? MaakColors.button : MaakColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: MaakColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => controller.isOpen ? controller.close() : controller.open(),
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 20,
                            color: _filtersActive ? Colors.white : MaakColors.ink),
                        // Label hidden on narrow phones to keep the search wide.
                        if (MediaQuery.sizeOf(context).width >= 400) ...[
                          const SizedBox(width: 6),
                          Text('Filter & sort',
                              style: TextStyle(fontWeight: FontWeight.w600,
                                  color: _filtersActive ? Colors.white : MaakColors.ink)),
                        ],
                        Icon(controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                            color: _filtersActive ? Colors.white : MaakColors.ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// "My articles": switch to the member's saved or liked articles.
  Widget _myArticlesMenu() {
    final active = _collection != _Collection.all;
    return MenuAnchor(
      style: _menuStyle,
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        _choice('Saved articles', selected: _collection == _Collection.saved,
            icon: Icons.bookmark_border,
            onPressed: () => _setCollection(_Collection.saved)),
        _choice('Liked articles', selected: _collection == _Collection.liked,
            icon: Icons.favorite_border,
            onPressed: () => _setCollection(_Collection.liked)),
        if (active) ...[
          const Divider(height: 12),
          _choice('All articles', selected: false, icon: Icons.menu_book_outlined,
              onPressed: () => _setCollection(_Collection.all)),
        ],
      ],
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(
          foregroundColor: active ? Colors.white : MaakColors.ink,
          backgroundColor: active ? MaakColors.button : MaakColors.surface,
          side: const BorderSide(color: MaakColors.border),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        icon: Icon(
          _collection == _Collection.saved
              ? Icons.bookmark
              : _collection == _Collection.liked
                  ? Icons.favorite
                  : Icons.person_outline,
          size: 18,
        ),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('My articles', style: TextStyle(fontWeight: FontWeight.w600)),
          Icon(controller.isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 20),
        ]),
      ),
    );
  }

  Widget _messageCard(IconData icon, String title, String message, {Widget? action}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        decoration: BoxDecoration(
          color: MaakColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MaakColors.border),
          boxShadow: MaakShadows.card,
        ),
        child: Column(children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: MaakColors.blush,
            child: Icon(icon, color: MaakColors.coralDeep, size: 29),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, color: MaakColors.ink,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center,
              style: const TextStyle(color: MaakColors.muted, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ]),
      );

  Widget _articleCard(Map<String, dynamic> article) {
    final id = article['id'] as String;
    final liked = article['is_liked'] == true;
    final saved = article['is_saved'] == true;
    final condition = article['condition'];
    final conditionName = condition is Map
        ? (condition['name'] ?? '').toString()
        : '';
    final count = (article['like_count'] as num?)?.toInt() ?? 0;
    final comments = (article['comment_count'] as num?)?.toInt() ?? 0;
    final busy = _busy.contains(id);
    final image = (article['image_url'] ?? '').toString();
    Future<void> open({bool comments = false}) async {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ArticleDetailsPage(articleId: id, scrollToComments: comments),
      ));
      if (mounted) _load();
    }
    // The whole card opens the article; the like, save and comment buttons
    // keep their own actions.
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: MaakColors.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: MaakColors.border),
      ),
      child: InkWell(
        onTap: open,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (image.isNotEmpty) ArticleImage(url: image, height: 160),
        Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (conditionName.isNotEmpty) ...[
            Text(conditionName, style: const TextStyle(
              color: MaakColors.coralDeep, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
          ],
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((article['title'] ?? '').toString(),
                  style: const TextStyle(color: MaakColors.ink,
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text((article['summary'] ?? '').toString(),
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaakColors.muted, height: 1.5)),
              const SizedBox(height: 8),
              const Text('Read article  ›',
                  style: TextStyle(color: MaakColors.coralDeep,
                      fontWeight: FontWeight.w600)),
          ]),
          const Divider(height: 24),
          Row(children: [
            IconButton(
              tooltip: liked ? 'Unlike article' : 'Like article',
              onPressed: busy ? null : () => _toggle(article, like: true),
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                  color: MaakColors.coralDeep),
            ),
            Text('$count', style: const TextStyle(color: MaakColors.muted)),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'View comments',
              onPressed: () => open(comments: true),
              icon: const Icon(Icons.chat_bubble_outline,
                  color: MaakColors.coralDeep),
            ),
            Text('$comments', style: const TextStyle(color: MaakColors.muted)),
            const Spacer(),
            // Save sits on the right, apart from like and comment.
            IconButton(
              tooltip: saved ? 'Remove saved article' : 'Save article',
              onPressed: busy ? null : () => _toggle(article, like: false),
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border,
                  color: MaakColors.coralDeep),
            ),
          ]),
        ]),
        ),
        ]),
      ),
    );
  }
}

/// Full article content stays inside Ma'ak; source is displayed for attribution.
/// Opened from the library list, and from an 'article_reply' notification
/// (with [scrollToComments], so the member lands on the conversation).
class ArticleDetailsPage extends StatefulWidget {
  const ArticleDetailsPage({
    super.key,
    required this.articleId,
    this.scrollToComments = false,
  });
  final String articleId;
  final bool scrollToComments;

  @override
  State<ArticleDetailsPage> createState() => _ArticleDetailsPageState();
}

class _ArticleDetailsPageState extends State<ArticleDetailsPage> {
  final _commentsKey = GlobalKey();
  Map<String, dynamic>? _article;
  bool _openingSource = false;
  bool _liked = false;
  bool _saved = false;
  int _likeCount = 0;
  int? _commentCount;
  // Null until the like/save state has loaded.
  bool? _stateReady;
  bool _stateBusy = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final article = await HealthLibraryService.getArticle(widget.articleId);
      if (!mounted) return;
      setState(() {
        _article = article;
        _loading = false;
      });
      if (widget.scrollToComments && article != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToComments());
      }
      if (article != null) _loadState();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this article.';
      });
    }
  }

  void _scrollToComments() {
    final target = _commentsKey.currentContext;
    if (target != null && target.mounted) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  // Like/save state is loaded separately so the article shows even if it fails.
  Future<void> _loadState() async {
    try {
      final state = await HealthLibraryService.getArticleState(widget.articleId);
      if (!mounted) return;
      setState(() {
        _liked = state['is_liked'] == true;
        _saved = state['is_saved'] == true;
        _likeCount = (state['like_count'] as num?)?.toInt() ?? 0;
        _stateReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _stateReady = false);
    }
  }

  // Updates at once; rolls back if the database rejects the change.
  Future<void> _toggle({required bool like}) async {
    if (_stateBusy || _stateReady != true) return;
    final wasLiked = _liked, wasSaved = _saved, oldCount = _likeCount;
    setState(() {
      _stateBusy = true;
      if (like) {
        _liked = !_liked;
        _likeCount = (_likeCount + (_liked ? 1 : -1)).clamp(0, 1 << 30).toInt();
      } else {
        _saved = !_saved;
      }
    });
    try {
      if (like) {
        await HealthLibraryService.setLiked(widget.articleId, liked: _liked);
      } else {
        await HealthLibraryService.setSaved(widget.articleId, saved: _saved);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _saved = wasSaved;
        _likeCount = oldCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(like
            ? 'Could not update your like. Please try again.'
            : 'Could not update saved articles. Please try again.'),
      ));
    } finally {
      if (mounted) setState(() => _stateBusy = false);
    }
  }

  /// Like and comment on the left, save on the right (as on the cards).
  Widget _actions() {
    final enabled = _stateReady == true && !_stateBusy;
    return Row(children: [
      IconButton(
        tooltip: _liked ? 'Unlike article' : 'Like article',
        onPressed: enabled ? () => _toggle(like: true) : null,
        icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
            color: MaakColors.coralDeep),
      ),
      Text('$_likeCount', style: const TextStyle(color: MaakColors.muted)),
      const SizedBox(width: 12),
      IconButton(
        tooltip: 'Go to comments',
        onPressed: _scrollToComments,
        icon: const Icon(Icons.chat_bubble_outline, color: MaakColors.coralDeep),
      ),
      Text(_commentCount == null ? '' : '$_commentCount',
          style: const TextStyle(color: MaakColors.muted)),
      const Spacer(),
      IconButton(
        tooltip: _saved ? 'Remove saved article' : 'Save article',
        onPressed: enabled ? () => _toggle(like: false) : null,
        icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border,
            color: MaakColors.coralDeep),
      ),
    ]);
  }

  Future<void> _openSource() async {
    final raw = (_article?['source_url'] ?? '').toString().trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This article has no valid source link.')),
      );
      return;
    }
    if (_openingSource) return;
    setState(() => _openingSource = true);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the source link.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the source link.')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingSource = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final article = _article;
    final condition = article?['condition'];
    final conditionName = condition is Map
        ? (condition['name'] ?? '').toString()
        : '';
    return Scaffold(
      backgroundColor: MaakColors.canvasMid,
      appBar: AppBar(
        title: const Text('Article details'),
        backgroundColor: MaakColors.canvasTop,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: MaakGradients.canvas),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null || article == null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error ?? 'This article is no longer available.'),
                      ))
                    // Not a lazy ListView: the comments section must exist
                    // so a notification can scroll straight to it.
                    : SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 20),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // The article keeps page margins; the comment box
                          // below runs edge to edge.
                          Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                          if (conditionName.isNotEmpty)
                            Text(conditionName, style: const TextStyle(
                                color: MaakColors.coralDeep,
                                fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Text((article['title'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w700,
                                color: MaakColors.ink,
                              )),
                          const SizedBox(height: 14),
                          Text((article['summary'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 16, height: 1.6,
                                color: MaakColors.muted,
                              )),
                          if ((article['image_url'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 18),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: ArticleImage(
                                url: article['image_url'].toString(),
                                height: 220,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _actions(),
                          const Divider(height: 16),
                          const SizedBox(height: 8),
                          SelectableText((article['content'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 16, height: 1.75,
                                color: MaakColors.ink,
                              )),
                          const SizedBox(height: 24),
                          const Divider(),
                          Text('Source: ${(article['source_name'] ?? '').toString()}',
                              style: const TextStyle(
                                color: MaakColors.ink,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _openingSource ? null : _openSource,
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(_openingSource
                                  ? 'Opening source...'
                                  : 'Open original source'),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Health information is educational and does not replace professional medical advice.',
                            style: TextStyle(color: MaakColors.muted),
                          ),
                          const SizedBox(height: 28),
                          const Divider(),
                          const SizedBox(height: 12),
                          ],
                          ),
                          ),
                          ArticleCommentsSection(
                            key: _commentsKey,
                            articleId: widget.articleId,
                            onCountChanged: (count) {
                              if (count != _commentCount) {
                                setState(() => _commentCount = count);
                              }
                            },
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
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

/// An article's photo (image_url). Shows a soft placeholder while loading and
/// nothing at all if the link is not https or the image cannot be loaded.
class ArticleImage extends StatelessWidget {
  const ArticleImage({super.key, required this.url, required this.height});
  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      image: true,
      label: 'Article photo',
      child: Image.network(
        uri.toString(),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                height: height,
                color: MaakColors.blush,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}
