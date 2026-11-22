import '../../core/constants/jm_constants.dart';
import '../models/jm_category.dart';
import '../models/jm_search_page.dart';
import '../sources/jm_api_client.dart';

/// 分类 / 排序 / 列表分页。
class CatalogRepository {
  CatalogRepository(this._api);

  final JmApi _api;

  Future<List<JmCategory>> categories() async {
    final list = await _api.fetchCategories();
    if (list.isNotEmpty) return list;
    return JmCategoryFallback.items
        .map((item) => JmCategory(id: item.id, name: item.name, slug: item.slug))
        .toList(growable: false);
  }

  /// [categorySlug] 为分类 slug（`doujin` / `single`…），空串 = 不过滤。
  Future<JmSearchPage> page({
    required int page,
    String categorySlug = '',
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) =>
      _api.fetchFilter(page: page, categorySlug: categorySlug, order: order);
}
