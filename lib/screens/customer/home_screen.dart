import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/theme.dart';
import '../../models/catalog_query.dart';
import '../../models/product.dart';
import '../../models/voucher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/product_widgets.dart';

/// Home: search entry, promo banners, categories, offers and product shelves.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenShop});

  /// Switches the shell to the Shop tab.
  final VoidCallback onOpenShop;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _pageController = PageController(viewportFraction: 0.92);
  int _bannerIndex = 0;

  @override
  void dispose() {
    _search.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _submitSearch(String text) {
    final catalog = context.read<CatalogProvider>();
    catalog.showSearch(text.trim());
    _search.clear();
    widget.onOpenShop();
  }

  void _openCategory(String? category) {
    context.read<CatalogProvider>().showCategory(category);
    widget.onOpenShop();
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showAppSnack(context, 'Code $code copied. Paste it in your cart or checkout.');
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final user = context.watch<AuthProvider>().user;
    final home = catalog.home;
    final firstName = (user?.name ?? '').split(' ').first;

    if (catalog.homeState == LoadState.error && home.banners.isEmpty) {
      return ErrorState(
        message: 'We could not load the shop right now.',
        onRetry: () => context.read<CatalogProvider>().loadHome(),
      );
    }

    final loading = catalog.homeState != LoadState.ready && home.banners.isEmpty;
    final featuredIds = home.featured.map((p) => p.id).toSet();
    final popular = home.popular.where((p) => !featuredIds.contains(p.id)).toList();
    final recent = catalog.recentlyViewed;

    return RefreshIndicator(
      onRefresh: () => context.read<CatalogProvider>().loadHome(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName.isEmpty ? 'Welcome' : 'Hello, $firstName',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  AppStrings.tagline,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _submitSearch,
                  decoration: const InputDecoration(
                    hintText: 'Search fabrics, shirts, services...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),
          if (loading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SkeletonBox(height: 150, radius: 20),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SkeletonBox(height: 90),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SkeletonBox(height: 240),
            ),
          ] else ...[
            if (home.banners.isNotEmpty) ...[
              SizedBox(
                height: 152,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: home.banners.length,
                  onPageChanged: (i) => setState(() => _bannerIndex = i),
                  itemBuilder: (context, index) {
                    final banner = home.banners[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _BannerCard(
                        banner: banner,
                        onTap: () {
                          if (banner.category != null) {
                            _openCategory(banner.category);
                          } else if (banner.voucherCode != null) {
                            _copyCode(banner.voucherCode!);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < home.banners.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 6,
                      width: i == _bannerIndex ? 20 : 6,
                      decoration: BoxDecoration(
                        color: i == _bannerIndex ? AppColors.burgundy : AppColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ],
            const SectionHeader(title: 'Categories'),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: kCategories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final c = kCategories[index];
                  return _CategoryTile(category: c, onTap: () => _openCategory(c));
                },
              ),
            ),
            if (home.offers.isNotEmpty) ...[
              const SectionHeader(title: 'Offers (demonstration vouchers)'),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: home.offers.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _OfferCard(
                    voucher: home.offers[index],
                    onCopy: () => _copyCode(home.offers[index].code),
                  ),
                ),
              ),
            ],
            if (home.featured.isNotEmpty) ...[
              SectionHeader(
                title: 'Featured fabrics',
                actionLabel: 'See all',
                onAction: () => _openCategory('Fabrics'),
              ),
              ProductCarousel(products: home.featured),
            ],
            if (home.services.isNotEmpty) ...[
              SectionHeader(
                title: 'Tailoring services',
                actionLabel: 'See all',
                onAction: () => _openCategory('Tailoring'),
              ),
              ProductCarousel(products: home.services),
            ],
            if (home.discounted.isNotEmpty) ...[
              const SectionHeader(title: 'Discounted products'),
              ProductCarousel(products: home.discounted),
            ],
            if (popular.isNotEmpty) ...[
              const SectionHeader(title: 'Popular right now'),
              ProductCarousel(products: popular),
            ],
            if (recent.isNotEmpty) ...[
              const SectionHeader(title: 'Recently viewed'),
              ProductCarousel(products: recent),
            ],
          ],
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner, required this.onTap});

  final PromoBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(banner.colorArgb);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -24,
              bottom: -24,
              child: Icon(
                Icons.content_cut,
                size: 140,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    banner.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      banner.voucherCode != null ? 'Copy code' : 'Shop now',
                      style: const TextStyle(
                        color: AppColors.burgundyDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final String category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 84,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: categoryColor(category),
                shape: BoxShape.circle,
              ),
              child: Icon(categoryIcon(category), color: AppColors.burgundy),
            ),
            const SizedBox(height: 6),
            Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.voucher, required this.onCopy});

  final Voucher voucher;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onCopy,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.local_offer, color: AppColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Code ${voucher.code}  |  tap to copy',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.burgundy),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
