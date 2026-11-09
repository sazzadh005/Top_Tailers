import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase/aamarpay_gateway.dart';
import '../data/supabase/cloudinary_uploader.dart';
import '../data/supabase/supabase_repositories.dart';
import 'app_services.dart';

/// The real backend: Supabase (Postgres + Auth + Edge Functions) with
/// AamarPay for online payments and Cloudinary for images.
AppServices buildSupabaseServices(SupabaseClient client) {
  return AppServices(
    auth: SupabaseAuthRepository(client),
    catalog: SupabaseCatalogRepository(client),
    discounts: SupabaseDiscountRepository(client),
    vouchers: SupabaseVoucherRepository(client),
    orders: SupabaseOrderRepository(client),
    notifications: SupabaseNotificationRepository(client),
    payments: AamarPayGateway(client),
    feedback: SupabaseFeedbackRepository(client),
    requests: SupabaseRequestRepository(client),
    wishlist: SupabaseWishlistRepository(client),
    images: CloudinaryUploader(client),
  );
}
