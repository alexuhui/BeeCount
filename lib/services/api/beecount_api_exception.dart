class BeeCountApiException implements Exception {
  BeeCountApiException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  bool get isAuth => statusCode == 401 || statusCode == 403;

  @override
  String toString() => 'BeeCountApiException($statusCode): $message';
}

class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;
}
