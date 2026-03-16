import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import '../../../services/bilibili_api.dart';

class CommentPanel extends StatefulWidget {
  final int oid;
  final String title;
  final VoidCallback? onClose;

  const CommentPanel({
    super.key,
    required this.oid,
    required this.title,
    this.onClose,
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
  final FocusNode _focusNode = FocusNode();
  int _focusedIndex = -1;
  int? _expandedCommentIndex;
  List<dynamic> _expandedReplies = [];
  bool _isLoadingReplies = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _totalItems {
    int total = _comments.length;
    if (_expandedCommentIndex != null && _expandedCommentIndex! < _comments.length) {
      total += _expandedReplies.length;
    }
    return total;
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isInReplies = _expandedCommentIndex != null && 
                        _focusedIndex > _comments.length - 1;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _totalItems - 1) {
        _focusedIndex++;
        // 如果展开的评论有回复，自动跳转到回复区域
        if (_expandedCommentIndex != null && _focusedIndex == _comments.length) {
          _focusedIndex = _comments.length;
        }
      } else if (_focusedIndex == _totalItems - 1 && _hasMore && !_isLoading) {
        _loadMore();
      }
      _scrollToFocusedItem();
      return KeyEventResult.handled;
    }
    
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        _focusedIndex--;
        // 如果退出回复区域，关闭展开
        if (_expandedCommentIndex != null && _focusedIndex < _comments.length) {
          setState(() {
            _expandedCommentIndex = null;
            _expandedReplies = [];
          });
        }
      }
      _scrollToFocusedItem();
      return KeyEventResult.handled;
    }
    
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_focusedIndex < _comments.length) {
        final comment = _comments[_focusedIndex];
        final rcount = comment['rcount'] as int? ?? 0;
        if (rcount > 0) {
          if (_expandedCommentIndex == _focusedIndex) {
            setState(() {
              _expandedCommentIndex = null;
              _expandedReplies = [];
            });
          } else {
            _showReplies(comment, _focusedIndex);
          }
        }
      }
      return KeyEventResult.handled;
    }
    
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_expandedCommentIndex != null) {
        setState(() {
          _expandedCommentIndex = null;
          _expandedReplies = [];
          _focusedIndex = _expandedCommentIndex!;
        });
      } else {
        widget.onClose?.call();
      }
      return KeyEventResult.handled;
    }
    
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      widget.onClose?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showReplies(dynamic comment, int commentIndex) async {
    setState(() {
      _expandedCommentIndex = commentIndex;
      _expandedReplies = [];
      _isLoadingReplies = true;
      _focusedIndex = _comments.length;
    });

    final rpid = comment['rpid'];
    final oid = widget.oid;

    try {
      final url =
          'https://api.bilibili.com/x/v2/reply/reply?oid=$oid&type=1&root=$rpid&pn=1&ps=10';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['code'] == 0 && json['data'] != null) {
          final replies = json['data']['replies'] as List? ?? [];
          if (mounted) {
            setState(() {
              _expandedReplies = replies;
              _isLoadingReplies = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingReplies = false;
        });
      }
    }
  }

  void _scrollToFocusedItem() {
    if (_focusedIndex < 0) return;
    
    final commentHeight = 140.0;
    final replyHeight = 70.0;
    
    double targetOffset = 0;
    if (_focusedIndex < _comments.length) {
      targetOffset = _focusedIndex * commentHeight - 200;
      if (_expandedCommentIndex != null && _expandedCommentIndex! < _focusedIndex) {
        targetOffset += _expandedReplies.length * replyHeight;
      }
    } else if (_expandedCommentIndex != null) {
      final replyIndex = _focusedIndex - _comments.length;
      targetOffset = _comments.length * commentHeight + replyIndex * replyHeight - 200;
      if (_expandedCommentIndex! < _comments.length) {
        targetOffset += _expandedReplies.length * replyHeight;
      }
    }
    
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        targetOffset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
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
      final replies = result['data'] as List? ?? [];
      final page = result['page'] as Map<String, dynamic>? ?? {};
      final pageCount = page['count'] as int? ?? replies.length;

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
      final replies = result['data'] as List? ?? [];
      final page = result['page'] as Map<String, dynamic>? ?? {};
      final pageCount = page['count'] as int? ?? replies.length;

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
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Container(
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
                      _expandedCommentIndex != null ? '回复' : '评论',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_expandedCommentIndex != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _expandedCommentIndex = null;
                          _expandedReplies = [];
                          _focusedIndex = _expandedCommentIndex!;
                        });
                      },
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
      itemBuilder: (context, index) {
        if (index < _comments.length) {
          final comment = _comments[index];
          final isExpanded = _expandedCommentIndex == index;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCommentItem(comment, index),
              if (isExpanded) _buildExpandedReplies(),
            ],
          );
        } else if (index == _comments.length && _hasMore) {
          return _buildLoadMoreIndicator();
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildExpandedReplies() {
    if (_isLoadingReplies) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFfb7299),
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 32, right: 16, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: const Color(0xFFfb7299).withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._expandedReplies.map((reply) => _buildReplyItem(reply)),
          if (_expandedCommentIndex != null) 
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '按确认键收起',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(dynamic reply) {
    final replyMember = reply['member'] as Map<String, dynamic>? ?? {};
    final replyContent = reply['content'] as Map<String, dynamic>? ?? {};
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: replyMember['avatar'] ?? '',
              width: 24,
              height: 24,
              errorWidget: (_, __, ___) => Container(
                width: 24,
                height: 24,
                color: Colors.grey[800],
                child: const Icon(Icons.person, color: Colors.white54, size: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  replyMember['uname'] ?? '',
                  style: const TextStyle(
                    color: Color(0xFFfb7299),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyContent['message'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildCommentItem(dynamic comment, int index) {
    final member = comment['member'] as Map<String, dynamic>? ?? {};
    final content = comment['content'] as Map<String, dynamic>? ?? {};
    final rcount = comment['rcount'] as int? ?? 0;
    final isFocused = _focusedIndex == index;
    final isExpanded = _expandedCommentIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _focusedIndex = index;
        });
        if (rcount > 0) {
          if (_expandedCommentIndex == index) {
            setState(() {
              _expandedCommentIndex = null;
              _expandedReplies = [];
            });
          } else {
            _showReplies(comment, index);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isFocused 
              ? const Color(0xFFfb7299).withValues(alpha: 0.3)
              : const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(8),
          border: isFocused 
              ? Border.all(color: const Color(0xFFfb7299), width: 2)
              : isExpanded
                  ? Border.all(color: const Color(0xFFfb7299).withValues(alpha: 0.5), width: 1)
                  : null,
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
                if (rcount > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.subdirectory_arrow_right,
                        size: 14,
                        color: isFocused || isExpanded
                            ? const Color(0xFFfb7299)
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isExpanded 
                            ? '收起回复' 
                            : '查看 $rcount 条回复',
                        style: TextStyle(
                          color: isFocused 
                              ? const Color(0xFFfb7299)
                              : Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                          fontWeight: isFocused ? FontWeight.bold : FontWeight.normal,
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
