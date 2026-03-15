import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/bilibili_api.dart';

class CommentPanel extends StatefulWidget {
  final int oid;
  final String title;

  const CommentPanel({
    super.key,
    required this.oid,
    required this.title,
  });

  @override
  State<CommentPanel> createState() => _CommentPanelState();
}

class _CommentPanelState extends State<CommentPanel> {
  List<dynamic> _comments = [];
  int _currentPage = 1;
  bool _isLoading = true;
  bool _hasMore = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadComments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await BilibiliApi.getComments(
      oid: widget.oid,
      pn: _currentPage,
    );

    if (!mounted) return;

    if (result['code'] == 0) {
      final data = result['data'];
      final replies = data['replies'] as List? ?? [];
      final page = data['page'] as Map<String, dynamic>? ?? {};
      final pageCount = page['count'] as int? ?? 0;

      setState(() {
        _comments = replies;
        _hasMore = _comments.length < pageCount;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result['message'] ?? '加载失败';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoading = true);

    final result = await BilibiliApi.getComments(
      oid: widget.oid,
      pn: _currentPage + 1,
    );

    if (!mounted) return;

    if (result['code'] == 0) {
      final replies = result['data']['replies'] as List? ?? [];
      final page = result['data']['page'] as Map<String, dynamic>? ?? {};
      final pageCount = page['count'] as int? ?? 0;

      setState(() {
        _currentPage++;
        _comments.addAll(replies);
        _hasMore = _comments.length < pageCount;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays > 365) {
      return '${diff.inDays ~/ 365}年前';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '评论',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? _buildError()
                : _comments.isEmpty && _isLoading
                    ? _buildLoading()
                    : _buildCommentList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFFfb7299),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _error ?? '加载失败',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadComments,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFfb7299),
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentList() {
    if (_comments.isEmpty) {
      return Center(
        child: Text(
          '暂无评论',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _comments.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _comments.length) {
          return _buildLoadMoreIndicator();
        }
        return _buildCommentItem(_comments[index]);
      },
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFfb7299),
                ),
              )
            : TextButton(
                onPressed: _loadMore,
                child: const Text(
                  '加载更多',
                  style: TextStyle(color: Color(0xFFfb7299)),
                ),
              ),
      ),
    );
  }

  Widget _buildCommentItem(dynamic comment) {
    final member = comment['member'] as Map<String, dynamic>? ?? {};
    final content = comment['content'] as Map<String, dynamic>? ?? {};
    final rcount = comment['rcount'] as int? ?? 0;
    final rcountText = rcount > 0 ? ' $rcount 条回复' : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: member['avatar'] ?? '',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: 40,
                height: 40,
                color: Colors.grey[800],
                child: const Icon(Icons.person, color: Colors.white54),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        member['uname'] ?? '未知用户',
                        style: const TextStyle(
                          color: Color(0xFFfb7299),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(comment['ctime'] as int? ?? 0),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  content['message'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (rcountText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.subdirectory_arrow_right,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '查看$rcountText',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Icon(
                Icons.thumb_up_outlined,
                size: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 2),
              Text(
                '${comment['like'] ?? 0}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
