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
        .map((item) => JmCategory(id: item.id, name: item.name))
        .toList(growable: false);
  }

  Future<JmSearchPage> page({
    required int page,
    String category = '0',
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) =>
      _api.fetchFilter(page: page, category: category, order: order);
}
