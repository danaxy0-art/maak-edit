import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/tokens.dart';
import '../../backend/services/health_library_service.dart';

/// Reader-facing Health Library. Article management and comments belong to Admin.
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
  String? _illnessId;
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _illnesses = [];
  bool _filtersExpanded = false;
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
      final types = await HealthLibraryService.getIllnessTypes();
      final articles = await HealthLibraryService.getArticles(
        search: '',
        illnessTypeId: _illnessId,
        collection: _collection.name,
        sort: _sort.name,
      );
      if (!mounted || request != _requestVersion) return;
      setState(() {
        _illnesses = types;
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
  // on every keystroke; changing collection, sort or illness refreshes data.
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
      _illnessId = null;
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
                    TextField(
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
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _tab(_Collection.all, 'All articles', Icons.menu_book_outlined),
                        _tab(_Collection.liked, 'Liked articles', Icons.favorite_border),
                        _tab(_Collection.saved, 'Saved articles', Icons.bookmark_border),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      expanded: _filtersExpanded,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.tune, color: MaakColors.ink, size: 19),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('Filter & sort', style: MaakText.section)),
                              if (_sort != _ArticleSort.newest || _illnessId != null)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Tooltip(
                                    message: 'Filters are active',
                                    child: Icon(Icons.filter_alt, size: 18, color: MaakColors.ink),
                                  ),
                                ),
                              Icon(_filtersExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                            ],
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: _filtersExpanded
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _search.text.isEmpty &&
                                            _sort == _ArticleSort.newest &&
                                            _illnessId == null
                                        ? null
                                        : _clear,
                                    child: const Text('Clear filters'),
                                  ),
                                ),
                    LayoutBuilder(builder: (context, constraints) {
                      final sort = _picker(
                        'Sort by',
                        DropdownButton<_ArticleSort>(
                          value: _sort,
                          isExpanded: true,
                          dropdownColor: MaakColors.surface,
                          menuMaxHeight: 300,
                          borderRadius: BorderRadius.circular(14),
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: _ArticleSort.newest, child: Text('Newest first')),
                            DropdownMenuItem(value: _ArticleSort.popular, child: Text('Most popular')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _sort = value);
                            _load();
                          },
                        ),
                      );
                      final illness = _picker(
                        'Health Condition',
                        DropdownButton<String?>(
                          value: _illnessId,
                          isExpanded: true,
                          dropdownColor: MaakColors.surface,
                          menuMaxHeight: 300,
                          borderRadius: BorderRadius.circular(14),
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All conditions'),
                            ),
                            ..._illnesses.map((type) => DropdownMenuItem<String?>(
                                  value: type['id'] as String,
                                  child: Text(
                                    (type['name'] ?? '').toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                          ],
                          onChanged: (value) {
                            setState(() => _illnessId = value);
                            _load();
                          },
                        ),
                      );
                      if (constraints.maxWidth < 420) {
                        return Column(children: [
                          sort,
                          const SizedBox(height: 10),
                          illness,
                        ]);
                      }
                      return Row(children: [
                        Expanded(child: sort),
                        const SizedBox(width: 12),
                        Expanded(child: illness),
                      ]);
                    }),
                              ],
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _collection == _Collection.all
                          ? 'Explore articles'
                          : _collection == _Collection.liked
                              ? 'Liked articles'
                              : 'Saved articles',
                      style: MaakText.section,
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
                        _search.text.trim().isNotEmpty || _illnessId != null
                            ? 'No matching articles'
                            : _collection == _Collection.liked
                                ? 'No liked articles yet'
                                : _collection == _Collection.saved
                                    ? 'No saved articles yet'
                                    : 'Articles are coming soon',
                        _search.text.trim().isNotEmpty || _illnessId != null
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

  Widget _tab(_Collection value, String label, IconData icon) {
    final selected = _collection == value;
    return ChoiceChip(
      showCheckmark: false,
      avatar: Icon(icon, size: 18,
          color: selected ? Colors.white : MaakColors.ink),
      label: Text(label),
      selected: selected,
      selectedColor: MaakColors.button,
      backgroundColor: MaakColors.surface,
      labelStyle: TextStyle(
        color: selected ? Colors.white : MaakColors.ink,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      side: const BorderSide(color: MaakColors.border),
      onSelected: (_) {
        setState(() => _collection = value);
        _load();
      },
    );
  }

  Widget _picker(String label, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: MaakColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MaakColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: MaakColors.muted)),
          child,
        ]),
      );

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
    final condition = article['illness_types'];
    final conditionName = condition is Map
        ? (condition['name'] ?? '').toString()
        : '';
    final count = (article['like_count'] as num?)?.toInt() ?? 0;
    final busy = _busy.contains(id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: MaakColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: MaakColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (conditionName.isNotEmpty) ...[
            Text(conditionName, style: const TextStyle(
              color: MaakColors.coralDeep, fontWeight: FontWeight.w600)),
            const SizedBox(height: 7),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _ArticleDetailsPage(articleId: id),
              ));
              if (mounted) _load();
            },
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          ),
          const Divider(height: 24),
          Row(children: [
            IconButton(
              tooltip: liked ? 'Unlike article' : 'Like article',
              onPressed: busy ? null : () => _toggle(article, like: true),
              icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                  color: MaakColors.coralDeep),
            ),
            Text('$count', style: const TextStyle(color: MaakColors.muted)),
            const SizedBox(width: 8),
            IconButton(
              tooltip: saved ? 'Remove saved article' : 'Save article',
              onPressed: busy ? null : () => _toggle(article, like: false),
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border,
                  color: MaakColors.coralDeep),
            ),
            const Spacer(),
          ]),
        ]),
      ),
    );
  }
}

/// Full article content stays inside Ma'ak; source is displayed for attribution.
class _ArticleDetailsPage extends StatefulWidget {
  const _ArticleDetailsPage({required this.articleId});
  final String articleId;

  @override
  State<_ArticleDetailsPage> createState() => _ArticleDetailsPageState();
}

class _ArticleDetailsPageState extends State<_ArticleDetailsPage> {
  Map<String, dynamic>? _article;
  bool _openingSource = false;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this article.';
      });
    }
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
    final condition = article?['illness_types'];
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
                    : ListView(
                        padding: const EdgeInsets.all(20),
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
                          const SizedBox(height: 20),
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
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}
