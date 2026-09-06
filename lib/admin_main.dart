// ============================================================================
// AUTOSERVICE — ADMIN APP
// Alohida ilova: admin servis egalarining arizalarini ko'rib chiqadi,
// tasdiqlaydi, rad etadi (sababi bilan) yoki ma'lumotlarini tahrirlaydi.
// Bir xil "liquid glass" dizayn tizimidan foydalanadi (asosiy ilova bilan
// vizual uzviylik uchun), lekin mustaqil, alohida ishga tushadigan ilova.
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: kIsWeb ? DefaultFirebaseOptions.web : null,
  );
  await PushNotificationService.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const AdminApp());
}

// ============================================================================
// THEME — same palette as the client app, so the two feel like one product.
// ============================================================================
class AppColors {
  static const Color primary = Color(0xFF3A7BFF);
  static const Color primaryDark = Color(0xFF2E63D8);
  static const Color primaryLight = Color(0xFF6CA8FF);
  static const Color primaryPale = Color(0xFFD7E6FF);
  static const List<Color> primaryGradient = [primary, primaryLight];

  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color chipBg = Color(0xFFF1F3F8);

  static const Color textPrimary = Color(0xFF1B1D23);
  static const Color textSecondary = Color(0xFF6B7080);
  static const Color textMuted = Color(0xFFA7ACBA);
  static const Color border = Color(0xFFE6E9F2);

  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color error = Color(0xFFFF3B30);

  static const Color glassBorder = Color(0x66FFFFFF);
}

// ============================================================================
// Xizmat turlari ro'yxati (/api/admin/service-types) tezkor ochilishi uchun
// rasmni o'zida saqlamaydi - faqat `has_image` belgisini beradi. Shu widget
// ro'yxat allaqachon ko'rinib turgan holda, har bir qator uchun rasmni fonda
// alohida-alohida so'raydi (AdminApi.getServiceTypeImage orqali) va tayyor
// bo'lgach ustiga chizadi. Rasm hali kelmagan yoki umuman bo'lmasa ham,
// qator/ro'yxat ko'rinishda qoladi - faqat ikonka ko'rsatiladi.
// Rasmlar bittadan, navbat bilan yuklanadi (1-chisi tugagach 2-chisi
// boshlanadi) - hammasi bab-baravar emas. Bir marta yuklangan rasm shu
// yerda (xotirada) saqlanadi - ekrandan chiqib qayta kirilsa ham, qayta
// so'ralmaydi, darhol ko'rsatiladi.
class _ServiceTypeImageCache {
  static final Map<int, String?> _cache = {};
  static Future<void> _queue = Future.value();

  static bool has(int id) => _cache.containsKey(id);
  static String? get(int id) => _cache[id];

  static Future<String?> load(int id, Future<String?> Function() fetcher) {
    if (_cache.containsKey(id)) return Future.value(_cache[id]);
    final completer = Completer<String?>();
    _queue = _queue.then((_) async {
      if (_cache.containsKey(id)) {
        completer.complete(_cache[id]);
        return;
      }
      String? url;
      try {
        url = await fetcher();
      } catch (_) {
        url = null;
      }
      _cache[id] = url;
      completer.complete(url);
    });
    return completer.future;
  }
}

class AdminLazyTypeImage extends StatefulWidget {
  final Map<String, dynamic> item;
  final IconData fallbackIcon;
  final double size;
  final double iconSize;
  final double borderRadius;

  const AdminLazyTypeImage({
    super.key,
    required this.item,
    required this.fallbackIcon,
    this.size = 42,
    this.iconSize = 20,
    this.borderRadius = 12,
  });

  @override
  State<AdminLazyTypeImage> createState() => _AdminLazyTypeImageState();
}

class _AdminLazyTypeImageState extends State<AdminLazyTypeImage> {
  String? _imageUrl;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.item['image_url'] as String?;
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant AdminLazyTypeImage old) {
    super.didUpdateWidget(old);
    final directUrl = widget.item['image_url'] as String?;
    if (old.item['id'] != widget.item['id'] ||
        directUrl != old.item['image_url']) {
      _imageUrl = directUrl;
      _fetching = false;
    }
    _maybeLoad();
  }

  void _maybeLoad() {
    if (_imageUrl != null || _fetching) return;
    if (widget.item['has_image'] != true) return;
    final rawId = widget.item['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    if (id == null) return;
    if (_ServiceTypeImageCache.has(id)) {
      // Avval yuklangan - qayta so'ralmaydi, darhol ko'rsatiladi.
      _imageUrl = _ServiceTypeImageCache.get(id);
      return;
    }
    _fetching = true;
    _ServiceTypeImageCache.load(id, () => AdminApi.getServiceTypeImage(id))
        .then((url) {
      if (!mounted) return;
      setState(() {
        _imageUrl = url;
        _fetching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageUrl != null && _imageUrl!.startsWith('data:');
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.primaryPale.withOpacity(0.55),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        image: hasImage
            ? DecorationImage(
                image: MemoryImage(base64Decode(_imageUrl!.split(',').last)),
                fit: BoxFit.cover)
            : null,
      ),
      child: hasImage
          ? null
          : Icon(widget.fallbackIcon,
              color: AppColors.primary, size: widget.iconSize),
    );
  }
}

class LiquidGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final double tintOpacity;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;
  final Color tintColor;

  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 22,
    this.blur = 22,
    this.tintOpacity = 0.78,
    this.padding,
    this.shadow,
    this.tintColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final glassContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor.withOpacity(tintOpacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.glassBorder, width: 1),
      ),
      child: child,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ??
            [
              BoxShadow(
                color: AppColors.textPrimary.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: kIsWeb
            ? glassContent
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: glassContent,
              ),
      ),
    );
  }
}

class GlassGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final List<Color>? colors;

  const GlassGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 54,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    // True frosted Liquid Glass surface — blue text/icons on top of the glass,
    // no solid color fill.
    final contentColor = AppColors.primary.withOpacity(disabled ? 0.4 : 1.0);
    final radius = height / 2;
    final glassBackground = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(disabled ? 0.34 : 0.68),
            Colors.white.withOpacity(disabled ? 0.14 : 0.34),
          ],
        ),
        border: Border.all(
            color: Colors.white.withOpacity(disabled ? 0.3 : 0.85), width: 1.1),
        boxShadow: disabled
            ? []
            : [
                BoxShadow(
                    color: AppColors.textPrimary.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8))
              ],
      ),
    );

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned.fill(
              child: kIsWeb
                  ? glassBackground
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: glassBackground,
                    ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: disabled ? null : onPressed,
                  splashColor: AppColors.primary.withOpacity(0.14),
                  highlightColor: AppColors.primary.withOpacity(0.08),
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: contentColor),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(icon, color: contentColor, size: 20),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: contentColor,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Icon-only action button (used for Tasdiqlash / Rad etish / Tahrirlash controls,
// which should show only an icon — no text label).
class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final List<Color>? colors;
  final bool outlined;
  final String? tooltip;

  const _IconActionButton({
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.colors,
    this.outlined = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final grad = colors ?? [AppColors.primary, AppColors.primary];

    final child = SizedBox(
      height: 52,
      child: isLoading
          ? const Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white),
              ),
            )
          : Center(
              child: Icon(icon,
                  color: outlined ? AppColors.primary : Colors.white,
                  size: 22)),
    );

    final button = outlined
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: disabled ? null : onPressed,
                child: child,
              ),
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: disabled
                    ? grad.map((c) => c.withOpacity(0.35)).toList()
                    : grad,
              ),
              boxShadow: disabled
                  ? []
                  : [
                      BoxShadow(
                          color: grad.first.withOpacity(0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6))
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: disabled ? null : onPressed,
                child: child,
              ),
            ),
          );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

Widget statusBadge(String status) {
  Color c;
  String label;
  switch (status) {
    case 'approved':
      c = AppColors.success;
      label = 'Tasdiqlangan';
      break;
    case 'rejected':
      c = AppColors.error;
      label = 'Rad etilgan';
      break;
    default:
      c = AppColors.warning;
      label = 'Kutilmoqda';
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
  );
}

// ============================================================================
// API SERVICE — talks to the same backend as the client app's admin routes.
// ============================================================================
class AdminApi {
  static const String baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://1-production-9aab.up.railway.app');

  static Future<Map<String, dynamic>> login(
      String phone, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['role'] != 'admin') {
          return {'success': false, 'message': 'Bu hisob admin emas'};
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_token', data['token']);
        await prefs.setString('admin_name', data['name'] ?? '');
        await prefs.setString('admin_phone', data['phone'] ?? '');
        await prefs.setInt('admin_id', data['user_id'] as int);
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'message':
            jsonDecode(res.body)['detail'] ?? 'Login yoki parol noto\'g\'ri'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  // Kirish parolini o'zgartirish (joriy parol tasdiqlanadi, keyin yangisi saqlanadi).
  static Future<Map<String, dynamic>> changePassword(
      int userId, String oldPassword, String newPassword) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );
      if (res.statusCode == 200) {
        return {'success': true};
      }
      String message = 'Parol o\'zgartirilmadi';
      try {
        message = jsonDecode(res.body)['detail'] ?? message;
      } catch (_) {}
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>?> dashboard() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/dashboard'));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  static Future<List<dynamic>> services(
      {String? status, String? providerType}) async {
    try {
      final params = <String, String>{
        if (status != null) 'status': status,
        if (providerType != null) 'provider_type': providerType,
      };
      final uri = Uri.parse('$baseUrl/api/admin/services').replace(
        queryParameters: params.isEmpty ? null : params,
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  // ---- Evakuator / benzin dastavka uchun global narxlar ----
  static Future<Map<String, dynamic>?> getPricing() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/pricing'));
      if (res.statusCode == 200)
        return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<bool> updatePricing({
    double? evacuatorPrice,
    double? fuelDeliveryFee,
    double? fuelPricePerLiter,
    double? fuelPriceAi92,
    double? fuelPriceAi95,
    double? fuelPriceAi98,
    double? fuelPriceAi100,
    double? fuelPriceHyperfuel,
    String? electricDeliveryPhone,
    String? carwashCallPhone,
    String? evacuatorImage,
    String? fuelImage,
    String? carwashLocationsImage,
    String? gasstationLocationsImage,
    String? electricDeliveryImage,
    String? carwashCallImage,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/pricing'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (evacuatorPrice != null) 'evacuator_price': evacuatorPrice,
          if (fuelDeliveryFee != null) 'fuel_delivery_fee': fuelDeliveryFee,
          if (fuelPricePerLiter != null)
            'fuel_price_per_liter': fuelPricePerLiter,
          if (fuelPriceAi92 != null) 'fuel_price_ai92': fuelPriceAi92,
          if (fuelPriceAi95 != null) 'fuel_price_ai95': fuelPriceAi95,
          if (fuelPriceAi98 != null) 'fuel_price_ai98': fuelPriceAi98,
          if (fuelPriceAi100 != null) 'fuel_price_ai100': fuelPriceAi100,
          if (fuelPriceHyperfuel != null)
            'fuel_price_hyperfuel': fuelPriceHyperfuel,
          if (electricDeliveryPhone != null)
            'electric_delivery_phone': electricDeliveryPhone,
          if (carwashCallPhone != null)
            'carwash_call_phone': carwashCallPhone,
          if (evacuatorImage != null) 'evacuator_image': evacuatorImage,
          if (fuelImage != null) 'fuel_image': fuelImage,
          if (carwashLocationsImage != null)
            'carwash_locations_image': carwashLocationsImage,
          if (gasstationLocationsImage != null)
            'gasstation_locations_image': gasstationLocationsImage,
          if (electricDeliveryImage != null)
            'electric_delivery_image': electricDeliveryImage,
          if (carwashCallImage != null)
            'carwash_call_image': carwashCallImage,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Moyka/zapravka manzillari (faqat joylashuv) ----
  // locationType: "carwash" (moyka) yoki "gasstation" (zapravka).
  static Future<List<dynamic>> listLocations(String locationType) async {
    try {
      final res = await http.get(Uri.parse(
          '$baseUrl/api/admin/locations?location_type=$locationType'));
      if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  static Future<bool> createLocation({
    required String locationType,
    required String name,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/admin/locations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'location_type': locationType,
          'name': name,
          if (address != null) 'address': address,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateLocation(
    int id, {
    String? name,
    String? address,
    double? latitude,
    double? longitude,
    bool? isActive,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/locations/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (name != null) 'name': name,
          if (address != null) 'address': address,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (isActive != null) 'is_active': isActive,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteLocation(int id) async {
    try {
      final res =
          await http.delete(Uri.parse('$baseUrl/api/admin/locations/$id'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> verifyService(int id) async {
    try {
      final res =
          await http.put(Uri.parse('$baseUrl/api/admin/services/$id/verify'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> rejectService(int id, String reason) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/services/$id/reject'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> editService(int id, Map<String, dynamic> fields) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/services/$id/edit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(fields),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> toggleBlockService(int id) async {
    try {
      final res =
          await http.put(Uri.parse('$baseUrl/api/admin/services/$id/block'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Xizmatlarni tasdiqlash (services_offered) ----
  static Future<List<dynamic>> pendingOfferedServices() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/admin/services-offered/pending'));
      if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  static Future<bool> approveOfferedService(int id) async {
    try {
      final res = await http
          .put(Uri.parse('$baseUrl/api/admin/services-offered/$id/approve'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> rejectOfferedService(int id, String reason) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/services-offered/$id/reject'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reason': reason}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Admin xohlagan servisga (serviceId bo'yicha) to'g'ridan-to'g'ri xizmat qo'shadi.
  static Future<bool> addOfferedServiceDirect(
      int serviceId, String name, double? price) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/admin/services/$serviceId/services-offered'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'category': name, 'price': price, 'is_active': true}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Xizmat turlari katalogi (ServiceType) ----
  // Nomi va narxini FAQAT admin belgilaydi; servis egalari faqat shu katalogdan
  // tanlaydi, foydalanuvchilar esa shu turlar bo'yicha qidiradi.
  static Future<List<dynamic>> listServiceTypes() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/service-types'));
      if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  // Xizmat turi rasmini alohida-alohida (lazy) yuklab olish uchun. Ro'yxat
  // (/api/admin/service-types) tezkor ochilishi uchun rasmni o'zida
  // saqlamaydi - faqat `has_image` belgisini beradi, rasm shu orqali
  // fonda so'raladi.
  static Future<String?> getServiceTypeImage(int id) async {
    try {
      final res =
          await http.get(Uri.parse('$baseUrl/api/service-types/$id/image'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['image_url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> createServiceType(
      String name, double? priceSedan, double? priceCrossover, String icon,
      {String? imageUrl}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/admin/service-types'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'price_sedan': priceSedan,
          'price_crossover': priceCrossover,
          'icon': icon,
          if (imageUrl != null) 'image_url': imageUrl,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> updateServiceType(int id,
      {String? name,
      double? priceSedan,
      double? priceCrossover,
      String? icon,
      String? imageUrl,
      bool? removeImage,
      bool? isActive}) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/service-types/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (name != null) 'name': name,
          if (priceSedan != null) 'price_sedan': priceSedan,
          if (priceCrossover != null) 'price_crossover': priceCrossover,
          if (icon != null) 'icon': icon,
          if (imageUrl != null) 'image_url': imageUrl,
          if (removeImage != null) 'remove_image': removeImage,
          if (isActive != null) 'is_active': isActive,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteServiceType(int id) async {
    try {
      final res =
          await http.delete(Uri.parse('$baseUrl/api/admin/service-types/$id'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Foydalanuvchilar (dashboard "Jami foydalanuvchi" kartasi uchun) ----
  static Future<List<dynamic>> users() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/users'));
      if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> userDetail(int id) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/users/$id'));
      if (res.statusCode == 200)
        return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<bool> toggleBlockUser(int id) async {
    try {
      final res =
          await http.put(Uri.parse('$baseUrl/api/admin/users/$id/block'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Buyurtmalar (dashboard "Faol buyurtmalar" / "Bugungi buyurtmalar" kartalari uchun) ----
  static Future<List<dynamic>> orders({String? scope, String? status}) async {
    try {
      final params = <String, String>{
        if (scope != null) 'scope': scope,
        if (status != null) 'status': status,
      };
      final uri = Uri.parse('$baseUrl/api/admin/orders').replace(
        queryParameters: params.isEmpty ? null : params,
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) return jsonDecode(res.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> orderDetail(int id) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/orders/$id'));
      if (res.statusCode == 200)
        return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<bool> editOrder(int id,
      {String? status, double? price, String? description}) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/api/admin/orders/$id/edit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (status != null) 'status': status,
          if (price != null) 'price': price,
          if (description != null) 'description': description,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteOrder(int id) async {
    try {
      final res = await http.delete(Uri.parse('$baseUrl/api/admin/orders/$id'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> deleteService(int id) async {
    try {
      final res =
          await http.delete(Uri.parse('$baseUrl/api/admin/services/$id'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- Xarita: barcha servislar, faol buyurtmalar, faol ustalar ----
  static Future<Map<String, dynamic>?> mapData() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/map'));
      if (res.statusCode == 200)
        return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  // ---- Statistika: kunlik/haftalik/oylik, eng mashhur xizmat, eng faol servis ----
  static Future<Map<String, dynamic>?> statistics() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/admin/statistics'));
      if (res.statusCode == 200)
        return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }
}

// ============================================================================
// PUSH BILDIRISHNOMALAR (Firebase Cloud Messaging - Android)
// ============================================================================
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Fon rejimida FCM tizim darajasida bildirishnomani o'zi ko'rsatadi.
}

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _androidChannelId = 'autoservis_default';

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);
    const channel = AndroidNotificationChannel(
      _androidChannelId,
      'Asosiy bildirishnomalar',
      description: 'Yangi ariza va boshqa xabarlar',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final title =
          notification?.title ?? message.data['title'] ?? 'Yangi xabar';
      final body = notification?.body ?? message.data['body'] ?? '';
      if (title.isEmpty && body.isEmpty) return;
      _localNotifications.show(
        message.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            'Asosiy bildirishnomalar',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  static Future<void> registerToken(int userId) async {
    if (userId <= 0) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _sendTokenToBackend(userId, token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _sendTokenToBackend(userId, newToken);
      });
    } catch (_) {}
  }

  static Future<void> _sendTokenToBackend(int userId, String token) async {
    try {
      await http.post(
        Uri.parse('${AdminApi.baseUrl}/api/register-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'token': token}),
      );
    } catch (_) {}
  }
}

// ============================================================================
// APP ROOT
// ============================================================================
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoFix admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        fontFamily: 'SF Pro Display',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.6)),
          hintStyle: const TextStyle(color: AppColors.textMuted),
        ),
      ),
      home: const AdminAuthWrapper(),
    );
  }
}

class AdminAuthWrapper extends StatefulWidget {
  const AdminAuthWrapper({super.key});
  @override
  State<AdminAuthWrapper> createState() => _AdminAuthWrapperState();
}

class _AdminAuthWrapperState extends State<AdminAuthWrapper> {
  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getString('admin_token') != null;
    setState(() {
      _loggedIn = loggedIn;
      _checking = false;
    });
    if (loggedIn) {
      final adminId = prefs.getInt('admin_id') ?? 0;
      PushNotificationService.registerToken(adminId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn ? const AdminHomeScreen() : const AdminLoginScreen();
  }
}

// ============================================================================
// LOGIN
// ============================================================================
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  bool _obscure = true;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final result = await AdminApi.login(
        _phoneController.text.trim(), _passwordController.text);
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      final adminId = result['data']?['user_id'] as int? ?? 0;
      PushNotificationService.registerToken(adminId);
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
          (r) => false);
    } else {
      setState(() => _error = result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryDark, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(26)),
                      child: const Icon(Icons.admin_panel_settings_rounded,
                          color: Colors.white, size: 48),
                    ),
                    const SizedBox(height: 22),
                    const Text('Admin panel',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 6),
                    const Text('AutoService boshqaruv tizimi',
                        style:
                            TextStyle(fontSize: 14.5, color: Colors.white70)),
                    const SizedBox(height: 34),
                    LiquidGlass(
                      radius: 22,
                      padding: const EdgeInsets.all(20),
                      tintOpacity: 0.9,
                      child: Column(
                        children: [
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                hintText: '+998 90 123 45 67',
                                prefixIcon: Icon(Icons.phone_outlined)),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscure,
                            keyboardType: TextInputType.visiblePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            onSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              hintText: 'Parol',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textMuted),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.error,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                          const SizedBox(height: 18),
                          GlassGradientButton(
                              label: 'Kirish',
                              isLoading: _isLoading,
                              onPressed: _login),
                        ],
                      ),
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
}

// ============================================================================
// HOME — bottom nav: Dashboard / Arizalar (services)
// ============================================================================
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Kamroq ishlatiladigan bo'limlar ("Xizmat turlari", "Tasdiqlash",
    // "Xarita") pastki menyudan olib tashlangan va "Umumiy" sahifasiga
    // tezkor-havola kartochka sifatida ko'chirilgan — pastki menyuda
    // faqat eng ko'p ishlatiladigan 3 ta bo'lim qoladi.
    final pages = [
      const AdminDashboardTab(),
      const AdminServicesTab(),
      const AdminStatisticsTab(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primaryPale,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon:
                  Icon(Icons.dashboard_rounded, color: AppColors.primary),
              label: 'Umumiy'),
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon:
                  Icon(Icons.storefront_rounded, color: AppColors.primary),
              label: 'Arizalar'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon:
                  Icon(Icons.bar_chart_rounded, color: AppColors.primary),
              label: 'Statistika'),
        ],
      ),
    );
  }
}

// ============================================================================
// Pastki menyudan "Umumiy"ga ko'chirilgan bo'limlar uchun umumiy wrapper.
// Har bir bo'lim (Xizmat turlari, Tasdiqlash, Xarita) o'z ichida sarlavhaga
// ega, shuning uchun bu yerda faqat orqaga qaytish tugmasi qo'shiladi.
// ============================================================================
class _AdminSectionScreen extends StatelessWidget {
  final Widget child;
  const _AdminSectionScreen({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
                child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 20, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context)),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DASHBOARD TAB
// ============================================================================
class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key});
  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.dashboard();
    if (!mounted) return;
    setState(() {
      _stats = data;
      _loading = false;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
        (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Boshqaruv paneli',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminChangePasswordScreen())),
                  icon: const Icon(Icons.lock_outline,
                      color: AppColors.textSecondary)),
              IconButton(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()))
          else if (_stats == null)
            const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                    child: Text('Ma\'lumot yuklanmadi',
                        style: TextStyle(color: AppColors.textMuted))))
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.35,
              children: [
                _statCard(
                  'Jami foydalanuvchi',
                  '${_stats!['total_users'] ?? 0}',
                  Icons.people_alt_rounded,
                  AppColors.primary,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminUsersListScreen())),
                ),
                _statCard(
                  'Jami servislar',
                  '${_stats!['total_services'] ?? 0}',
                  Icons.storefront_rounded,
                  AppColors.success,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AdminAllServicesScreen())),
                ),
                _statCard(
                  'Faol buyurtmalar',
                  '${_stats!['active_orders'] ?? 0}',
                  Icons.local_shipping_rounded,
                  AppColors.warning,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminOrdersListScreen(
                            scope: 'active', title: 'Faol buyurtmalar')),
                  ),
                ),
                _statCard(
                  'Bugungi buyurtmalar',
                  '${_stats!['today_orders'] ?? 0}',
                  Icons.today_rounded,
                  AppColors.primaryDark,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminOrdersListScreen(
                            scope: 'today', title: 'Bugungi buyurtmalar')),
                  ),
                ),
                _statCard(
                  'Yakunlangan buyurtmalar',
                  '${_stats!['completed_orders'] ?? 0}',
                  Icons.check_circle_rounded,
                  AppColors.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AdminOrdersListScreen(
                            status: 'completed',
                            title: 'Yakunlangan buyurtmalar')),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          _navCard(
            icon: Icons.receipt_long_rounded,
            color: AppColors.primary,
            title: 'Barcha buyurtmalar',
            subtitle: 'To\'liq ro\'yxatni ko\'rish va boshqarish',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminOrdersListScreen(
                        title: 'Barcha buyurtmalar'))),
          ),
          const SizedBox(height: 12),
          // Evakuator va benzin dastavka - global narxlarni shu yerdan
          // boshqarish uchun alohida joy (avtoservislardan farqli o'laroq,
          // bularning narxi har bir provayderda emas, butun tizim uchun
          // bitta bo'ladi).
          _navCard(
            icon: Icons.payments_rounded,
            color: AppColors.warning,
            title: 'Evakuator / Benzin dastavka narxlari',
            subtitle: 'Global narxlarni shu yerdan belgilang',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminPricingScreen())),
          ),
          const SizedBox(height: 12),
          _navCard(
            icon: Icons.local_car_wash_rounded,
            color: AppColors.primaryLight,
            title: 'Moyka manzillari',
            subtitle: 'Foydalanuvchilar uchun moyka joylashuvlari',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const _AdminSectionScreen(
                        child: AdminLocationsTab(
                            locationType: 'carwash',
                            title: 'Moyka manzillari')))),
          ),
          const SizedBox(height: 12),
          _navCard(
            icon: Icons.ev_station_rounded,
            color: AppColors.success,
            title: 'Zapravka manzillari',
            subtitle: 'Foydalanuvchilar uchun zapravka joylashuvlari',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const _AdminSectionScreen(
                        child: AdminLocationsTab(
                            locationType: 'gasstation',
                            title: 'Zapravka manzillari')))),
          ),
          const SizedBox(height: 20),
          const Text('Boshqarish',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          // Quyidagi 3 ta bo'lim ilgari pastki menyuda alohida tab edi;
          // kamdan-kam ishlatilgani uchun bu yerga tezkor-havola sifatida
          // ko'chirildi va pastki menyu 6 tadan 3 taga tushirildi.
          _navCard(
            icon: Icons.category_rounded,
            color: AppColors.primaryDark,
            title: 'Xizmat turlari',
            subtitle: 'Katalogdagi xizmat turlari va narxlar',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const _AdminSectionScreen(
                        child: AdminServiceTypesTab()))),
          ),
          const SizedBox(height: 12),
          _navCard(
            icon: Icons.build_rounded,
            color: AppColors.success,
            title: 'Tasdiqlash',
            subtitle: 'Servis egalari qo\'shgan yangi xizmatlar',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const _AdminSectionScreen(
                        child: AdminOfferedServicesTab()))),
          ),
          const SizedBox(height: 12),
          _navCard(
            icon: Icons.map_rounded,
            color: AppColors.error,
            title: 'Xarita',
            subtitle: 'Servislar, buyurtmalar va ustalarni xaritada ko\'rish',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const _AdminSectionScreen(child: AdminMapTab()))),
          ),
        ],
      ),
    );
  }

  Widget _navCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: 20,
        tintOpacity: 0.9,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        radius: 20,
        tintOpacity: 0.9,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
                maxLines: 2),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ADMIN — PAROLNI O'ZGARTIRISH
// ============================================================================
class AdminChangePasswordScreen extends StatefulWidget {
  const AdminChangePasswordScreen({super.key});
  @override
  State<AdminChangePasswordScreen> createState() =>
      _AdminChangePasswordScreenState();
}

class _AdminChangePasswordScreenState extends State<AdminChangePasswordScreen> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _error;
  int? _adminId;

  @override
  void initState() {
    super.initState();
    _loadAdminId();
  }

  Future<void> _loadAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _adminId = prefs.getInt('admin_id'));
  }

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final oldPass = _oldController.text;
    final newPass = _newController.text;
    final confirmPass = _confirmController.text;

    if (_adminId == null) {
      setState(() => _error = 'Admin aniqlanmadi, qayta kiring');
      return;
    }
    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      setState(() => _error = 'Barcha maydonlarni to\'ldiring');
      return;
    }
    if (newPass.length < 6) {
      setState(() =>
          _error = 'Yangi parol kamida 6 ta belgidan iborat bo\'lishi kerak');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _error = 'Yangi parollar mos kelmadi');
      return;
    }

    setState(() => _isSaving = true);
    final result = await AdminApi.changePassword(_adminId!, oldPass, newPass);
    setState(() => _isSaving = false);
    if (!mounted) return;

    if (!result['success']) {
      setState(() => _error = result['message'] ?? 'Parol o\'zgartirilmadi');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Parol muvaffaqiyatli o\'zgartirildi'),
          backgroundColor: AppColors.success),
    );
    Navigator.pop(context);
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: TextInputType.visiblePassword,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: '••••••',
            prefixIcon:
                const Icon(Icons.lock_outline, color: AppColors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textMuted),
              onPressed: onToggle,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Parolni o\'zgartirish',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _passwordField(
                    label: 'Joriy parol',
                    controller: _oldController,
                    obscure: _obscureOld,
                    onToggle: () => setState(() => _obscureOld = !_obscureOld),
                  ),
                  _passwordField(
                    label: 'Yangi parol',
                    controller: _newController,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  _passwordField(
                    label: 'Yangi parolni tasdiqlang',
                    controller: _confirmController,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13.5)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GlassGradientButton(
                  label: 'Saqlash', isLoading: _isSaving, onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PRICING SCREEN — evakuator va benzin dastavka uchun global narxlar
// ============================================================================
// Auto_service uchun narxlar servis egasi tomonidan (ServiceType katalogi
// orqali) belgilanadi, lekin evakuator va benzin dastavka - alohida
// provayder turlari bo'lib, ularning narxi HAR BIR provayderda emas, balki
// butun tizim uchun bitta bo'lishi kerak. Shuning uchun bu alohida ekran:
// admin bu yerda ikkita narxni belgilaydi:
//  - Evakuator: chaqiruv uchun yagona narx (so'm).
//  - Benzin dastavka: yetkazib berish narxi (so'm) + har bir litr narxi
//    (so'm/litr). Foydalanuvchi ilovasida yakuniy narx shu ikkitasidan
//    avtomatik hisoblanadi: yetkazib berish narxi + (litr soni * 1 litr narxi).
class AdminPricingScreen extends StatefulWidget {
  const AdminPricingScreen({super.key});
  @override
  State<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends State<AdminPricingScreen> {
  final _evacuatorCtrl = TextEditingController();
  final _deliveryFeeCtrl = TextEditingController();
  final _perLiterCtrl = TextEditingController();
  final _ai92Ctrl = TextEditingController();
  final _ai95Ctrl = TextEditingController();
  final _ai98Ctrl = TextEditingController();
  final _ai100Ctrl = TextEditingController();
  final _hyperfuelCtrl = TextEditingController();
  final _electricPhoneCtrl = TextEditingController();
  final _carwashPhoneCtrl = TextEditingController();
  String? _evacuatorImage;
  String? _fuelImage;
  String? _carwashLocationsImage;
  String? _gasstationLocationsImage;
  String? _electricDeliveryImage;
  String? _carwashCallImage;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _evacuatorCtrl.dispose();
    _deliveryFeeCtrl.dispose();
    _perLiterCtrl.dispose();
    _ai92Ctrl.dispose();
    _ai95Ctrl.dispose();
    _ai98Ctrl.dispose();
    _ai100Ctrl.dispose();
    _hyperfuelCtrl.dispose();
    _electricPhoneCtrl.dispose();
    _carwashPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.getPricing();
    if (!mounted) return;
    setState(() {
      if (data != null) {
        _evacuatorCtrl.text = _fmt(data['evacuator_price']);
        _deliveryFeeCtrl.text = _fmt(data['fuel_delivery_fee']);
        _perLiterCtrl.text = _fmt(data['fuel_price_per_liter']);
        _ai92Ctrl.text = _fmt(data['fuel_price_ai92']);
        _ai95Ctrl.text = _fmt(data['fuel_price_ai95']);
        _ai98Ctrl.text = _fmt(data['fuel_price_ai98']);
        _ai100Ctrl.text = _fmt(data['fuel_price_ai100']);
        _hyperfuelCtrl.text = _fmt(data['fuel_price_hyperfuel']);
        _electricPhoneCtrl.text = data['electric_delivery_phone']?.toString() ?? '';
        _carwashPhoneCtrl.text = data['carwash_call_phone']?.toString() ?? '';
        _evacuatorImage = data['evacuator_image']?.toString();
        _fuelImage = data['fuel_image']?.toString();
        _carwashLocationsImage = data['carwash_locations_image']?.toString();
        _gasstationLocationsImage =
            data['gasstation_locations_image']?.toString();
        _electricDeliveryImage = data['electric_delivery_image']?.toString();
        _carwashCallImage = data['carwash_call_image']?.toString();
      }
      _loading = false;
    });
  }

  String _fmt(dynamic v) {
    if (v == null) return '';
    final n = (v as num);
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await AdminApi.updatePricing(
      evacuatorPrice:
          double.tryParse(_evacuatorCtrl.text.trim().replaceAll(' ', '')),
      fuelDeliveryFee:
          double.tryParse(_deliveryFeeCtrl.text.trim().replaceAll(' ', '')),
      fuelPricePerLiter:
          double.tryParse(_perLiterCtrl.text.trim().replaceAll(' ', '')),
      fuelPriceAi92:
          double.tryParse(_ai92Ctrl.text.trim().replaceAll(' ', '')),
      fuelPriceAi95:
          double.tryParse(_ai95Ctrl.text.trim().replaceAll(' ', '')),
      fuelPriceAi98:
          double.tryParse(_ai98Ctrl.text.trim().replaceAll(' ', '')),
      fuelPriceAi100:
          double.tryParse(_ai100Ctrl.text.trim().replaceAll(' ', '')),
      fuelPriceHyperfuel:
          double.tryParse(_hyperfuelCtrl.text.trim().replaceAll(' ', '')),
      electricDeliveryPhone: _electricPhoneCtrl.text.trim(),
      carwashCallPhone: _carwashPhoneCtrl.text.trim(),
      evacuatorImage: _evacuatorImage ?? '',
      fuelImage: _fuelImage ?? '',
      carwashLocationsImage: _carwashLocationsImage ?? '',
      gasstationLocationsImage: _gasstationLocationsImage ?? '',
      electricDeliveryImage: _electricDeliveryImage ?? '',
      carwashCallImage: _carwashCallImage ?? '',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Narxlar saqlandi' : 'Saqlashda xatolik yuz berdi'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Evakuator / Benzin narxlari',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 17)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _sectionCard(
                  title: 'Evakuator',
                  icon: Icons.local_shipping_rounded,
                  children: [
                    _fieldLabel('Chaqiruv narxi (so\'m)'),
                    _numberField(_evacuatorCtrl, hint: 'Masalan: 150000'),
                    const SizedBox(height: 16),
                    AdminImagePickerField(
                      imageBase64: _evacuatorImage,
                      fallbackIcon: Icons.local_shipping_rounded,
                      label: 'Bandning rasmi',
                      onChanged: (v) => setState(
                          () => _evacuatorImage = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Benzin dastavka',
                  icon: Icons.local_gas_station_rounded,
                  children: [
                    _fieldLabel('Yetkazib berish narxi (so\'m)'),
                    _numberField(_deliveryFeeCtrl, hint: 'Masalan: 120000'),
                    const SizedBox(height: 14),
                    _fieldLabel('AI-92 — 1 litr narxi (so\'m)'),
                    _numberField(_ai92Ctrl, hint: 'Masalan: 15000'),
                    const SizedBox(height: 14),
                    _fieldLabel('AI-95 — 1 litr narxi (so\'m)'),
                    _numberField(_ai95Ctrl, hint: 'Masalan: 18000'),
                    const SizedBox(height: 14),
                    _fieldLabel('AI-98 — 1 litr narxi (so\'m)'),
                    _numberField(_ai98Ctrl, hint: 'Masalan: 20000'),
                    const SizedBox(height: 14),
                    _fieldLabel('AI-100 — 1 litr narxi (so\'m)'),
                    _numberField(_ai100Ctrl, hint: 'Masalan: 25000'),
                    const SizedBox(height: 14),
                    _fieldLabel('HyperFuel — 1 litr narxi (so\'m)'),
                    _numberField(_hyperfuelCtrl, hint: 'Masalan: 45000'),
                    const SizedBox(height: 10),
                    const Text(
                      'Yakuniy narx foydalanuvchiga avtomatik hisoblanib ko\'rsatiladi: yetkazib berish narxi + (so\'ralgan litr × tanlangan benzin turi narxi).',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    AdminImagePickerField(
                      imageBase64: _fuelImage,
                      fallbackIcon: Icons.local_gas_station_rounded,
                      label: 'Bandning rasmi',
                      onChanged: (v) => setState(
                          () => _fuelImage = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionCard(
                  title: 'Elektr dastavka',
                  icon: Icons.electric_bolt_rounded,
                  children: [
                    _fieldLabel('Qo\'ng\'iroq uchun telefon raqami'),
                    _phoneField(_electricPhoneCtrl,
                        hint: 'Masalan: +998901234567'),
                    const SizedBox(height: 16),
                    AdminImagePickerField(
                      imageBase64: _electricDeliveryImage,
                      fallbackIcon: Icons.electric_bolt_rounded,
                      label: 'Bandning rasmi',
                      onChanged: (v) => setState(() =>
                          _electricDeliveryImage = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Moyka chaqirish',
                  icon: Icons.local_car_wash_rounded,
                  children: [
                    _fieldLabel('Qo\'ng\'iroq uchun telefon raqami'),
                    _phoneField(_carwashPhoneCtrl,
                        hint: 'Masalan: +998901234567'),
                    const SizedBox(height: 16),
                    AdminImagePickerField(
                      imageBase64: _carwashCallImage,
                      fallbackIcon: Icons.local_car_wash_rounded,
                      label: 'Bandning rasmi',
                      onChanged: (v) => setState(() =>
                          _carwashCallImage = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Moyka manzillari',
                  icon: Icons.local_car_wash_outlined,
                  children: [
                    AdminImagePickerField(
                      imageBase64: _carwashLocationsImage,
                      fallbackIcon: Icons.local_car_wash_outlined,
                      label: 'Bandning rasmi',
                      onChanged: (v) => setState(() =>
                          _carwashLocationsImage = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionCard(
                  title: 'Zapravka manzillari',
                  icon: Icons.ev_station_rounded,
                  children: [
                    AdminImagePickerField(
                      imageBase64: _gasstationLocationsImage,
                      fallbackIcon: Icons.ev_station_rounded,
                      label: 'Bandning rasmi',
                      onChanged: (v) => setState(() =>
                          _gasstationLocationsImage = (v == null || v.isEmpty) ? null : v),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GlassGradientButton(
                  label: 'Saqlash',
                  onPressed: _saving ? null : _save,
                  isLoading: _saving,
                  height: 52,
                ),
              ],
            ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );

  Widget _numberField(TextEditingController ctrl, {required String hint}) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.chipBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _phoneField(TextEditingController ctrl, {required String hint}) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.chipBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _sectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ============================================================================
// SERVICES TAB — pending / approved / rejected applications
// ============================================================================
class AdminServicesTab extends StatefulWidget {
  const AdminServicesTab({super.key});
  @override
  State<AdminServicesTab> createState() => _AdminServicesTabState();
}

class _AdminServicesTabState extends State<AdminServicesTab> {
  final List<Map<String, String?>> _filters = [
    {'label': 'Kutilmoqda', 'value': 'pending'},
    {'label': 'Tasdiqlangan', 'value': 'approved'},
    {'label': 'Rad etilgan', 'value': 'rejected'},
    {'label': 'Hammasi', 'value': null},
  ];
  int _filterIndex = 0;

  // Ariza qaysi turdan kelganini (avtoservis / evakuator / benzin dastavka)
  // ko'rsatish va shu bo'yicha filtrlash uchun.
  final List<Map<String, String?>> _typeFilters = [
    {'label': 'Hammasi', 'value': null, 'icon': null},
    {'label': 'Avtoservis', 'value': 'auto_service', 'icon': null},
    {'label': 'Evakuator', 'value': 'evacuator', 'icon': null},
    {'label': 'Benzin dastavka', 'value': 'fuel', 'icon': null},
  ];
  int _typeFilterIndex = 0;

  List<dynamic> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.services(
      status: _filters[_filterIndex]['value'],
      providerType: _typeFilters[_typeFilterIndex]['value'],
    );
    if (!mounted) return;
    setState(() {
      _services = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text('Servis arizalari',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final selected = i == _filterIndex;
              return GestureDetector(
                onTap: () {
                  setState(() => _filterIndex = i);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: selected
                        ? const LinearGradient(
                            colors: AppColors.primaryGradient)
                        : null,
                    color: selected ? null : AppColors.chipBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _filters[i]['label']!,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color:
                            selected ? Colors.white : AppColors.textSecondary),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // Ariza turi bo'yicha filtr: kimdan (avtoservis/evakuator/benzin dastavka) kelgani.
        SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _typeFilters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final selected = i == _typeFilterIndex;
              return GestureDetector(
                onTap: () {
                  setState(() => _typeFilterIndex = i);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withOpacity(0.12)
                        : Colors.transparent,
                    border: Border.all(
                        color: selected ? AppColors.primary : AppColors.border),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _typeFilters[i]['label']!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _services.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 100),
                          Center(
                              child: Text('Arizalar topilmadi',
                                  style:
                                      TextStyle(color: AppColors.textMuted))),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: _services.length,
                        itemBuilder: (_, i) {
                          final s = _services[i] as Map<String, dynamic>;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _serviceCard(s),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  Widget _serviceCard(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => AdminServiceDetailScreen(service: s)),
        );
        if (changed == true) _load();
      },
      child: LiquidGlass(
        radius: 18,
        tintOpacity: 0.9,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primaryPale,
                borderRadius: BorderRadius.circular(14),
                image: (s['logo_url'] != null &&
                        (s['logo_url'] as String).startsWith('data:'))
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(
                            (s['logo_url'] as String).split(',').last)),
                        fit: BoxFit.contain)
                    : null,
              ),
              child: s['logo_url'] == null
                  ? const Icon(Icons.storefront_rounded,
                      color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(s['name'] ?? '',
                            style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${s['owner_name'] ?? ''} • ${s['phone'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _providerTypeColor(s['provider_type'] as String?)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_providerTypeIcon(s['provider_type'] as String?),
                            size: 12,
                            color: _providerTypeColor(
                                s['provider_type'] as String?)),
                        const SizedBox(width: 4),
                        Text(
                          _providerTypeLabel(s['provider_type'] as String?),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _providerTypeColor(
                                  s['provider_type'] as String?)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            statusBadge(s['status'] ?? 'pending'),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FOYDALANUVCHILAR RO'YXATI — dashboarddagi "Jami foydalanuvchi" kartasi
// bosilganda ochiladi. Ro'yxatdan bittasini bosganda uning barcha
// ma'lumotlari ko'rsatiladi.
// ============================================================================
class AdminUsersListScreen extends StatefulWidget {
  const AdminUsersListScreen({super.key});
  @override
  State<AdminUsersListScreen> createState() => _AdminUsersListScreenState();
}

class _AdminUsersListScreenState extends State<AdminUsersListScreen> {
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.users();
    if (!mounted) return;
    setState(() {
      _users = data;
      _loading = false;
    });
  }

  String _roleLabel(String? role, [String? providerType]) {
    switch (role) {
      case 'service_owner':
        return _providerTypeLabel(providerType);
      case 'admin':
        return 'Admin';
      default:
        return 'Foydalanuvchi';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Foydalanuvchilar',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                  child: Text('Foydalanuvchilar topilmadi',
                                      style: TextStyle(
                                          color: AppColors.textMuted))),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            itemCount: _users.length,
                            itemBuilder: (_, i) {
                              final u = _users[i] as Map<String, dynamic>;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => AdminUserDetailScreen(
                                            userId: u['id'] as int)),
                                  ),
                                  child: LiquidGlass(
                                    radius: 18,
                                    tintOpacity: 0.9,
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                              color: AppColors.primaryPale,
                                              borderRadius:
                                                  BorderRadius.circular(14)),
                                          child: const Icon(
                                              Icons.person_rounded,
                                              color: AppColors.primary),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(u['name'] ?? '—',
                                                  style: const TextStyle(
                                                      fontSize: 15.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppColors
                                                          .textPrimary)),
                                              const SizedBox(height: 3),
                                              Text(
                                                  '${u['phone'] ?? ''} • ${_roleLabel(u['role'] as String?, u['provider_type'] as String?)}',
                                                  style: const TextStyle(
                                                      fontSize: 12.5,
                                                      color: AppColors
                                                          .textSecondary)),
                                              const SizedBox(height: 3),
                                              Text(
                                                  'Buyurtmalar: ${u['order_count'] ?? 0}',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          AppColors.textMuted)),
                                            ],
                                          ),
                                        ),
                                        if (u['is_active'] == false)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                                color: AppColors.error
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                            child: const Text('Bloklangan',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.error)),
                                          )
                                        else
                                          const Icon(
                                              Icons.chevron_right_rounded,
                                              color: AppColors.textMuted),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FOYDALANUVCHI TAFSILOTLARI — bitta foydalanuvchining barcha ma'lumotlari:
// mashinalari, buyurtmalari va (agar servis egasi bo'lsa) o'z servisi.
// ============================================================================
class AdminUserDetailScreen extends StatefulWidget {
  final int userId;
  const AdminUserDetailScreen({super.key, required this.userId});
  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.userDetail(widget.userId);
    if (!mounted) return;
    setState(() {
      _user = data;
      _loading = false;
    });
  }

  Future<void> _toggleBlock() async {
    setState(() => _busy = true);
    final ok = await AdminApi.toggleBlockUser(widget.userId);
    if (ok) await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok ? 'Holat yangilandi' : 'Xatolik yuz berdi'),
          backgroundColor: ok ? AppColors.success : AppColors.error),
    );
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'service_owner':
        return 'Servis egasi';
      case 'admin':
        return 'Admin';
      default:
        return 'Foydalanuvchi';
    }
  }

  Widget _infoTile(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LiquidGlass(
        radius: 16,
        tintOpacity: 0.9,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: color ?? AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Foydalanuvchi ma\'lumotlari',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : u == null
                      ? const Center(
                          child: Text('Ma\'lumot topilmadi',
                              style: TextStyle(color: AppColors.textMuted)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            children: [
                              Center(
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: const BoxDecoration(
                                      color: AppColors.primaryPale,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.person_rounded,
                                      color: AppColors.primary, size: 34),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                  child: Text(u['name'] ?? '—',
                                      style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary))),
                              const SizedBox(height: 20),
                              _infoTile(Icons.phone_outlined, 'Telefon',
                                  u['phone'] ?? '—'),
                              _infoTile(Icons.badge_outlined, 'Rol',
                                  _roleLabel(u['role'] as String?)),
                              if (u['city'] != null)
                                _infoTile(Icons.location_city_outlined,
                                    'Shahar', u['city']),
                              _infoTile(
                                u['is_active'] == false
                                    ? Icons.block_rounded
                                    : Icons.check_circle_outline_rounded,
                                'Holati',
                                u['is_active'] == false ? 'Bloklangan' : 'Faol',
                                color: u['is_active'] == false
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                              _infoTile(
                                  Icons.local_shipping_outlined,
                                  'Jami buyurtmalar',
                                  '${(u['orders'] as List?)?.length ?? 0}'),
                              _infoTile(Icons.favorite_outline, 'Sevimlilar',
                                  '${u['favorite_count'] ?? 0}'),
                              _infoTile(Icons.star_outline_rounded, 'Sharhlar',
                                  '${u['review_count'] ?? 0}'),
                              if (u['own_service'] != null)
                                _infoTile(
                                    Icons.storefront_outlined,
                                    'O\'z servisi',
                                    '${u['own_service']['name']} (${_providerTypeLabel(u['own_service']['provider_type'] as String?)})'),
                              if ((u['cars'] as List?)?.isNotEmpty == true) ...[
                                const SizedBox(height: 8),
                                const Text('Mashinalari',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 10),
                                ...List<Widget>.from(
                                    (u['cars'] as List).map((c) => _infoTile(
                                          Icons.directions_car_outlined,
                                          c['model'] ?? 'Mashina',
                                          '${c['plate_number'] ?? '—'} • ${c['year'] ?? ''}',
                                        ))),
                              ],
                              if ((u['orders'] as List?)?.isNotEmpty ==
                                  true) ...[
                                const SizedBox(height: 8),
                                const Text('Buyurtmalar tarixi',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 10),
                                ...List<Widget>.from(
                                    (u['orders'] as List).map((o) => _infoTile(
                                          Icons.receipt_long_outlined,
                                          '${o['service_name'] ?? ''} — ${o['category'] ?? ''}',
                                          '${o['status'] ?? ''}${o['price'] != null ? ' • ${o['price']} so\'m' : ''}',
                                        ))),
                              ],
                            ],
                          ),
                        ),
            ),
            if (!_loading && u != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: GlassGradientButton(
                  label: u['is_active'] == false
                      ? 'Blokdan chiqarish'
                      : 'Bloklash',
                  isLoading: _busy,
                  colors: u['is_active'] == false
                      ? const [AppColors.success, Color(0xFF5FDC7E)]
                      : const [AppColors.error, Color(0xFFFF6961)],
                  onPressed: _toggleBlock,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// JAMI SERVISLAR — dashboarddagi "Jami servislar" kartasi bosilganda ochiladi.
// Statusdan qat'i nazar barcha servislarni ko'rsatadi; bittasini bosganda
// mavjud "Ariza tafsilotlari" (AdminServiceDetailScreen) ekrani ochiladi.
// ============================================================================
class AdminAllServicesScreen extends StatefulWidget {
  const AdminAllServicesScreen({super.key});
  @override
  State<AdminAllServicesScreen> createState() => _AdminAllServicesScreenState();
}

class _AdminAllServicesScreenState extends State<AdminAllServicesScreen> {
  List<dynamic> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.services();
    if (!mounted) return;
    setState(() {
      _services = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Jami servislar',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _services.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                  child: Text('Servislar topilmadi',
                                      style: TextStyle(
                                          color: AppColors.textMuted))),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                            itemCount: _services.length,
                            itemBuilder: (_, i) {
                              final s = _services[i] as Map<String, dynamic>;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GestureDetector(
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              AdminServiceDetailScreen(
                                                  service: s)),
                                    );
                                    _load();
                                  },
                                  child: LiquidGlass(
                                    radius: 18,
                                    tintOpacity: 0.9,
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryPale,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            image: (s['logo_url'] != null &&
                                                    (s['logo_url'] as String)
                                                        .startsWith('data:'))
                                                ? DecorationImage(
                                                    image: MemoryImage(
                                                        base64Decode(
                                                            (s['logo_url']
                                                                    as String)
                                                                .split(',')
                                                                .last)),
                                                    fit: BoxFit.contain)
                                                : null,
                                          ),
                                          child: s['logo_url'] == null
                                              ? const Icon(
                                                  Icons.storefront_rounded,
                                                  color: AppColors.primary)
                                              : null,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(s['name'] ?? '',
                                                  style: const TextStyle(
                                                      fontSize: 15.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppColors
                                                          .textPrimary),
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              const SizedBox(height: 3),
                                              Text(
                                                  '${s['owner_name'] ?? ''} • ${s['phone'] ?? ''}',
                                                  style: const TextStyle(
                                                      fontSize: 12.5,
                                                      color: AppColors
                                                          .textSecondary),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: _providerTypeColor(
                                                          s['provider_type']
                                                              as String?)
                                                      .withOpacity(0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                        _providerTypeIcon(
                                                            s['provider_type']
                                                                as String?),
                                                        size: 12,
                                                        color: _providerTypeColor(
                                                            s['provider_type']
                                                                as String?)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                        _providerTypeLabel(
                                                            s['provider_type']
                                                                as String?),
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: _providerTypeColor(
                                                                s['provider_type']
                                                                    as String?))),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        statusBadge(s['status'] ?? 'pending'),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// BUYURTMALAR RO'YXATI — dashboarddagi "Faol buyurtmalar" / "Bugungi
// buyurtmalar" kartalari bosilganda ochiladi. Bittasini bosganda buyurtmaning
// barcha ma'lumotlari ko'rsatiladi.
// ============================================================================
class AdminOrdersListScreen extends StatefulWidget {
  final String? scope; // 'active' | 'today' | null (hammasi)
  final String? status; // 'completed' | null
  final String title;
  const AdminOrdersListScreen(
      {super.key, this.scope, this.status, required this.title});
  @override
  State<AdminOrdersListScreen> createState() => _AdminOrdersListScreenState();
}

class _AdminOrdersListScreenState extends State<AdminOrdersListScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _orders = [];
  bool _loading = true;
  late final TabController _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // TabBarni swipe qilib ham o'tish mumkin bo'lgani uchun, tugma-indikator
    // (pill) shu listener orqali doim joriy tab bilan sinxron turadi —
    // aks holda tugmani bosganda pill sakrab, notekis harakatlanardi.
    _tabController.addListener(() {
      if (_tabController.index != _tabIndex &&
          !_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isScheduled(Map<String, dynamic> o) =>
      (o['order_type']?.toString() ?? 'now') == 'scheduled';

  // "Hozirgi buyurtmalar" - order_type == 'now' (yoki belgilanmagan).
  List<dynamic> get _nowOrders =>
      _orders.where((o) => !_isScheduled(o as Map<String, dynamic>)).toList();

  // "Bronlar" - order_type == 'scheduled', eng yaqin sana birinchi.
  List<dynamic> get _bookingOrders {
    final list =
        _orders.where((o) => _isScheduled(o as Map<String, dynamic>)).toList();
    list.sort((a, b) {
      final da = DateTime.tryParse(
          (a as Map<String, dynamic>)['scheduled_at']?.toString() ?? '');
      final db2 = DateTime.tryParse(
          (b as Map<String, dynamic>)['scheduled_at']?.toString() ?? '');
      if (da == null && db2 == null) return 0;
      if (da == null) return 1;
      if (db2 == null) return -1;
      return da.compareTo(db2);
    });
    return list;
  }

  // Buyurtma kartochkasidagi turi belgisi: "🕐 Bron: 30.07 14:00" yoki "Hozir".
  Widget _typeBadge(Map<String, dynamic> order) {
    if (_isScheduled(order)) {
      String text = 'Bron';
      final dt = DateTime.tryParse(order['scheduled_at']?.toString() ?? '');
      if (dt != null) {
        final local = dt.toLocal();
        text =
            'Bron: ${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} '
            '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded,
                size: 12, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.textMuted.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.bolt_rounded, size: 12, color: AppColors.textSecondary),
          SizedBox(width: 4),
          Text('Hozir',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data =
        await AdminApi.orders(scope: widget.scope, status: widget.status);
    if (!mounted) return;
    setState(() {
      _orders = data;
      _loading = false;
    });
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'accepted':
        return AppColors.primary;
      default:
        return AppColors.warning;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'completed':
        return 'Yakunlangan';
      case 'cancelled':
        return 'Bekor qilingan';
      case 'accepted':
        return 'Qabul qilindi';
      default:
        return 'Kutilmoqda';
    }
  }

  Widget _orderCard(Map<String, dynamic> o) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    AdminOrderDetailScreen(orderId: o['id'] as int)),
          );
          _load();
        },
        child: LiquidGlass(
          radius: 18,
          tintOpacity: 0.9,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: AppColors.primaryPale,
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.receipt_long_rounded,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${o['service_name'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('${o['user_name'] ?? ''} • ${o['category'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _typeBadge(o),
                        if (o['price'] != null) ...[
                          const SizedBox(width: 8),
                          Text('${o['price']} so\'m',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color:
                        _statusColor(o['status'] as String?).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(_statusLabel(o['status'] as String?),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _statusColor(o['status'] as String?))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ordersListView(List<dynamic> orders) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 100),
                    Center(
                        child: Text('Buyurtmalar topilmadi',
                            style: TextStyle(color: AppColors.textMuted))),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: orders.length,
                  itemBuilder: (_, i) =>
                      _orderCard(orders[i] as Map<String, dynamic>),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(14)),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final segmentWidth = constraints.maxWidth / 2;
                    return Stack(
                      children: [
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: _tabIndex == 0
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            width: segmentWidth,
                            height: double.infinity,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black12, blurRadius: 6)
                                ]),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                                child: _tabButton('Hozirgi buyurtmalar', 0)),
                            Expanded(child: _tabButton('Bronlar', 1)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _ordersListView(_nowOrders),
                  _ordersListView(_bookingOrders),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _tabIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_tabIndex == index) return;
        setState(() => _tabIndex = index);
        _tabController.animateTo(index,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      },
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.textPrimary : AppColors.textSecondary),
        child: Center(child: Text(label, textAlign: TextAlign.center)),
      ),
    );
  }
}

// ============================================================================
// BUYURTMA TAFSILOTLARI
// ============================================================================
class AdminOrderDetailScreen extends StatefulWidget {
  final int orderId;
  const AdminOrderDetailScreen({super.key, required this.orderId});
  @override
  State<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  bool _busy = false;

  final List<Map<String, String>> _statusOptions = const [
    {'value': 'pending', 'label': 'Kutilmoqda'},
    {'value': 'accepted', 'label': 'Qabul qilindi'},
    {'value': 'completed', 'label': 'Yakunlangan'},
    {'value': 'cancelled', 'label': 'Bekor qilingan'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.orderDetail(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = data;
      _loading = false;
    });
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.error : AppColors.success),
    );
  }

  Future<void> _edit() async {
    if (_order == null) return;
    String status = (_order!['status'] as String?) ?? 'pending';
    final priceController =
        TextEditingController(text: _order!['price']?.toString() ?? '');
    final descController =
        TextEditingController(text: _order!['description']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Buyurtmani tahrirlash',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                const Text('Holati:',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _statusOptions.map((opt) {
                    final selected = status == opt['value'];
                    return GestureDetector(
                      onTap: () => setDialogState(() => status = opt['value']!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? const LinearGradient(
                                  colors: AppColors.primaryGradient)
                              : null,
                          color: selected ? null : AppColors.chipBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(opt['label']!,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : AppColors.textSecondary)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Narxi (so\'m):',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(hintText: 'Masalan: 150000')),
                const SizedBox(height: 14),
                const Text('Izoh:',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                    controller: descController,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(hintText: 'Izoh (ixtiyoriy)')),
                const SizedBox(height: 18),
                GlassGradientButton(
                    label: 'Saqlash',
                    height: 48,
                    onPressed: () => Navigator.pop(ctx, true)),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      setState(() => _busy = true);
      final ok = await AdminApi.editOrder(
        widget.orderId,
        status: status,
        price: double.tryParse(priceController.text.trim()),
        description: descController.text.trim(),
      );
      setState(() => _busy = false);
      if (ok) {
        _toast('Buyurtma yangilandi');
        _load();
      } else {
        _toast('Xatolik yuz berdi', error: true);
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buyurtmani o\'chirish'),
        content: const Text(
            'Bu buyurtma butunlay o\'chiriladi. Bu amalni ortga qaytarib bo\'lmaydi. Davom etilsinmi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('O\'chirish',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final ok = await AdminApi.deleteOrder(widget.orderId);
    setState(() => _busy = false);
    if (ok) {
      if (!mounted) return;
      Navigator.pop(context);
    } else {
      _toast('Xatolik yuz berdi', error: true);
    }
  }

  Widget _infoTile(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LiquidGlass(
        radius: 16,
        tintOpacity: 0.9,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: color ?? AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Buyurtma tafsilotlari',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : o == null
                      ? const Center(
                          child: Text('Ma\'lumot topilmadi',
                              style: TextStyle(color: AppColors.textMuted)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            children: [
                              _infoTile(Icons.category_outlined, 'Xizmat turi',
                                  o['category'] ?? '—'),
                              _infoTile(Icons.flag_outlined, 'Holati',
                                  o['status'] ?? '—'),
                              if (o['user'] != null) ...[
                                _infoTile(Icons.person_outline, 'Mijoz',
                                    o['user']['name'] ?? '—'),
                                _infoTile(
                                    Icons.phone_outlined,
                                    'Mijoz telefoni',
                                    o['user']['phone'] ?? '—'),
                              ],
                              if (o['service'] != null) ...[
                                _infoTile(Icons.storefront_outlined, 'Servis',
                                    o['service']['name'] ?? '—'),
                                _infoTile(
                                    Icons.phone_iphone_outlined,
                                    'Servis telefoni',
                                    o['service']['phone'] ?? '—'),
                              ],
                              if (o['price'] != null)
                                _infoTile(Icons.payments_outlined, 'Narxi',
                                    '${o['price']} so\'m',
                                    color: AppColors.primary),
                              if (o['description'] != null &&
                                  o['description'].toString().isNotEmpty)
                                _infoTile(Icons.notes_outlined, 'Izoh',
                                    o['description']),
                            ],
                          ),
                        ),
            ),
            if (!_loading && o != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _IconActionButton(
                        icon: Icons.edit_outlined,
                        isLoading: false,
                        outlined: true,
                        tooltip: 'Tahrirlash',
                        onPressed: _busy ? null : _edit,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _IconActionButton(
                        icon: Icons.delete_outline_rounded,
                        isLoading: _busy,
                        colors: const [AppColors.error, Color(0xFFFF6961)],
                        tooltip: 'O\'chirish',
                        onPressed: _delete,
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

// ============================================================================
// XIZMAT TURLARI TAB — admin boshqaradigan xizmat turlari katalogi
// ============================================================================
// Bu yerda admin nomi va narxini o'zi belgilagan xizmat turlarini
// qo'shadi/tahrirlaydi/o'chiradi. Servis egalari shu katalogdan o'zida bor
// turlarni tanlaydi, foydalanuvchilar esa shu turlar bo'yicha qidiradi.
// Ariza qaysi turdan kelganini (avtoservis / evakuator / benzin dastavka)
// ko'rsatish uchun.
String _providerTypeLabel(String? providerType) {
  switch (providerType) {
    case 'evacuator':
      return 'Evakuator';
    case 'fuel':
      return 'Benzin dastavka';
    default:
      return 'Avtoservis';
  }
}

IconData _providerTypeIcon(String? providerType) {
  switch (providerType) {
    case 'evacuator':
      return Icons.local_shipping_rounded;
    case 'fuel':
      return Icons.local_gas_station_rounded;
    default:
      return Icons.storefront_rounded;
  }
}

Color _providerTypeColor(String? providerType) {
  switch (providerType) {
    case 'evacuator':
      return const Color(0xFFFF9F43);
    case 'fuel':
      return const Color(0xFF20BF6B);
    default:
      return AppColors.primary;
  }
}

IconData _iconForServiceType(String? name) {
  // Endi barcha xizmat turlari uchun bitta umumiy ikonka ishlatiladi —
  // admin xizmat qo'shganda ikonka tanlamaydi.
  return Icons.build_rounded;
}

// ============================================================================
// RASM TANLASH — "Xizmat turlari" va "Qo'shimcha xizmatlar" bandlari uchun
// admin galereyadan rasm tanlaydi (base64 data-URL sifatida saqlanadi).
// Rasm bo'lmasa, foydalanuvchi ilovasida standart ikonka ko'rsatiladi.
// ============================================================================
Future<String?> pickImageAsBase64() async {
  try {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

/// Rasm tanlash/ko'rsatish kartochkasi: rasm bo'lsa preview, bo'lmasa
/// standart ikonka ko'rsatadi. `onChanged(null)` chaqirilsa - rasm o'chirilgan.
class AdminImagePickerField extends StatelessWidget {
  final String? imageBase64;
  final IconData fallbackIcon;
  final ValueChanged<String?> onChanged;
  final String label;

  const AdminImagePickerField({
    super.key,
    required this.imageBase64,
    required this.fallbackIcon,
    required this.onChanged,
    this.label = 'Rasm',
  });

  bool get _hasImage =>
      imageBase64 != null && imageBase64!.startsWith('data:');

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primaryPale.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
            image: _hasImage
                ? DecorationImage(
                    image: MemoryImage(
                        base64Decode(imageBase64!.split(',').last)),
                    fit: BoxFit.cover)
                : null,
          ),
          child: _hasImage
              ? null
              : Icon(fallbackIcon, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await pickImageAsBase64();
                      if (result != null) onChanged(result);
                    },
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: Text(_hasImage ? 'Almashtirish' : 'Rasm tanlash'),
                  ),
                  if (_hasImage)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error)),
                      onPressed: () => onChanged(''),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Rasmni o\'chirish'),
                    ),
                ],
              ),
              if (!_hasImage)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Rasm tanlanmasa, ikonka ko\'rsatiladi.',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class AdminServiceTypesTab extends StatefulWidget {
  const AdminServiceTypesTab({super.key});
  @override
  State<AdminServiceTypesTab> createState() => _AdminServiceTypesTabState();
}

class _AdminServiceTypesTabState extends State<AdminServiceTypesTab> {
  List<dynamic> _types = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.listServiceTypes();
    if (!mounted) return;
    setState(() {
      _types = data;
      _loading = false;
    });
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ServiceTypeFormDialog(existing: existing),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('O\'chirish'),
        content: Text(
            '"${type['name']}" xizmat turini o\'chirmoqchimisiz? Buni tanlagan servislardagi yozuvlar ham o\'chadi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('O\'chirish',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await AdminApi.deleteServiceType(type['id'] as int);
    if (ok) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> type) async {
    final ok = await AdminApi.updateServiceType(type['id'] as int,
        isActive: !(type['is_active'] == true));
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Yangi tur',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Xizmat turlari',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    const Text(
                      'Nomi va narxini shu yerda siz belgilaysiz. Servis egalari faqat shu ro\'yxatdan o\'zida bor turlarni tanlaydi.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary)))
            else if (_types.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Hozircha xizmat turi yo\'q. Pastdagi "+" tugmasi orqali qo\'shing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14.5, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final type = _types[i] as Map<String, dynamic>;
                      final active = type['is_active'] == true;
                      final priceSedan = type['price_sedan'];
                      final priceCrossover = type['price_crossover'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: active
                                  ? AppColors.border
                                  : AppColors.error.withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                AdminLazyTypeImage(
                                  item: type,
                                  fallbackIcon: _iconForServiceType(
                                      type['icon'] as String?),
                                  size: 42,
                                  iconSize: 20,
                                  borderRadius: 12,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(type['name']?.toString() ?? '',
                                          style: const TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                      Text(
                                        'Sedan: ${priceSedan != null ? "$priceSedan so\'m" : "belgilanmagan"}',
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        'Krossover: ${priceCrossover != null ? "$priceCrossover so\'m" : "belgilanmagan"}',
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                    value: active,
                                    activeColor: AppColors.primary,
                                    onChanged: (_) => _toggleActive(type)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openForm(existing: type),
                                    icon: const Icon(Icons.edit_rounded,
                                        size: 16),
                                    label: const Text('Tahrirlash'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error,
                                        side: const BorderSide(
                                            color: AppColors.error)),
                                    onPressed: () => _delete(type),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 16),
                                    label: const Text('O\'chirish'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: _types.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTypeFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ServiceTypeFormDialog({this.existing});
  @override
  State<_ServiceTypeFormDialog> createState() => _ServiceTypeFormDialogState();
}

class _ServiceTypeFormDialogState extends State<_ServiceTypeFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceSedanController;
  late final TextEditingController _priceCrossoverController;
  // Endi ikonka tanlanmaydi — barcha xizmat turlari uchun bitta umumiy
  // ikonkadan foydalaniladi (rasm bo'lmasa shu ikonka ko'rinadi).
  static const String _icon = 'build';
  String? _imageBase64;
  bool _imageRemoved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?['name']?.toString() ?? '');
    _priceSedanController = TextEditingController(
        text: widget.existing?['price_sedan'] != null
            ? '${widget.existing!['price_sedan']}'
            : '');
    _priceCrossoverController = TextEditingController(
        text: widget.existing?['price_crossover'] != null
            ? '${widget.existing!['price_crossover']}'
            : '');
    _imageBase64 = widget.existing?['image_url']?.toString();
    // Ro'yxatda rasmning o'zi emas, faqat `has_image` belgisi keladi
    // (ro'yxat tezkor ochilishi uchun) - tahrirlashda rasmni shu yerda
    // alohida so'rab olamiz.
    if (_imageBase64 == null && widget.existing?['has_image'] == true) {
      final id = widget.existing!['id'] as int;
      AdminApi.getServiceTypeImage(id).then((url) {
        if (!mounted || url == null) return;
        setState(() => _imageBase64 = url);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceSedanController.dispose();
    _priceCrossoverController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final priceSedan = double.tryParse(
        _priceSedanController.text.trim().replaceAll(' ', ''));
    final priceCrossover = double.tryParse(
        _priceCrossoverController.text.trim().replaceAll(' ', ''));
    setState(() => _saving = true);
    bool ok;
    if (widget.existing != null) {
      ok = await AdminApi.updateServiceType(widget.existing!['id'] as int,
          name: name,
          priceSedan: priceSedan,
          priceCrossover: priceCrossover,
          icon: _icon,
          imageUrl: _imageRemoved ? null : _imageBase64,
          removeImage: _imageRemoved);
    } else {
      ok = await AdminApi.createServiceType(
          name, priceSedan, priceCrossover, _icon,
          imageUrl: _imageBase64);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Xizmat turini tahrirlash' : 'Yangi xizmat turi',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              const Text('Nomi:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Motor diagnostikasi')),
              const SizedBox(height: 14),
              const Text('Sedan uchun narxi (so\'m):',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: _priceSedanController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(hintText: 'Masalan: 150000')),
              const SizedBox(height: 14),
              const Text('Krossover uchun narxi (so\'m):',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: _priceCrossoverController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(hintText: 'Masalan: 180000')),
              const SizedBox(height: 18),
              AdminImagePickerField(
                imageBase64: _imageRemoved ? null : _imageBase64,
                fallbackIcon: Icons.build_rounded,
                label: 'Xizmat turi rasmi',
                onChanged: (v) {
                  setState(() {
                    if (v == null || v.isEmpty) {
                      _imageBase64 = null;
                      _imageRemoved = true;
                    } else {
                      _imageBase64 = v;
                      _imageRemoved = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 20),
              GlassGradientButton(
                  label: isEdit ? 'Saqlash' : 'Qo\'shish',
                  isLoading: _saving,
                  onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MOYKA / ZAPRAVKA MANZILLARI — faqat joylashuv (chaqiruv/narx yo'q).
// Admin manzil nomi, ixtiyoriy manzil matni va xaritada bosib joylashuvni
// belgilaydi; foydalanuvchi ilovasida faqat ro'yxat/xarita sifatida chiqadi.
// ============================================================================
class AdminLocationsTab extends StatefulWidget {
  final String locationType; // 'carwash' | 'gasstation'
  final String title;
  const AdminLocationsTab(
      {super.key, required this.locationType, required this.title});
  @override
  State<AdminLocationsTab> createState() => _AdminLocationsTabState();
}

class _AdminLocationsTabState extends State<AdminLocationsTab> {
  List<dynamic> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.listLocations(widget.locationType);
    if (!mounted) return;
    setState(() {
      _locations = data;
      _loading = false;
    });
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _LocationFormDialog(
          locationType: widget.locationType, existing: existing),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> loc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('O\'chirish'),
        content: Text('"${loc['name']}" manzilini o\'chirmoqchimisiz?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('O\'chirish',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await AdminApi.deleteLocation(loc['id'] as int);
    if (ok) _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> loc) async {
    final ok = await AdminApi.updateLocation(loc['id'] as int,
        isActive: !(loc['is_active'] == true));
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.locationType == 'carwash'
        ? Icons.local_car_wash_rounded
        : Icons.ev_station_rounded;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Yangi manzil',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    const Text(
                      'Bu yerda faqat manzil (joylashuv) kiritiladi - narx yoki chaqiruv yo\'q. Foydalanuvchi ilovasida ro\'yxat sifatida ko\'rinadi.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary)))
            else if (_locations.isEmpty)
              const SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Hozircha manzil yo\'q. Pastdagi "+" tugmasi orqali qo\'shing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14.5, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final loc = _locations[i] as Map<String, dynamic>;
                      final active = loc['is_active'] == true;
                      final address = loc['address']?.toString() ?? '';
                      final hasCoords =
                          loc['latitude'] != null && loc['longitude'] != null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: active
                                  ? AppColors.border
                                  : AppColors.error.withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                      color: AppColors.primaryPale
                                          .withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Icon(icon,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(loc['name']?.toString() ?? '',
                                          style: const TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                      Text(
                                        address.isNotEmpty
                                            ? address
                                            : (hasCoords
                                                ? 'Xaritada belgilangan'
                                                : 'Joylashuv belgilanmagan'),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                    value: active,
                                    activeColor: AppColors.primary,
                                    onChanged: (_) => _toggleActive(loc)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openForm(existing: loc),
                                    icon: const Icon(Icons.edit_rounded,
                                        size: 16),
                                    label: const Text('Tahrirlash'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error,
                                        side: const BorderSide(
                                            color: AppColors.error)),
                                    onPressed: () => _delete(loc),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 16),
                                    label: const Text('O\'chirish'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: _locations.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationFormDialog extends StatefulWidget {
  final String locationType;
  final Map<String, dynamic>? existing;
  const _LocationFormDialog({required this.locationType, this.existing});
  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  double? _lat;
  double? _lng;
  bool _saving = false;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existing?['name']?.toString() ?? '');
    _addressController = TextEditingController(
        text: widget.existing?['address']?.toString() ?? '');
    _lat = (widget.existing?['latitude'] as num?)?.toDouble();
    _lng = (widget.existing?['longitude'] as num?)?.toDouble();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    bool ok;
    if (widget.existing != null) {
      ok = await AdminApi.updateLocation(widget.existing!['id'] as int,
          name: name,
          address: _addressController.text.trim(),
          latitude: _lat,
          longitude: _lng);
    } else {
      ok = await AdminApi.createLocation(
        locationType: widget.locationType,
        name: name,
        address: _addressController.text.trim(),
        latitude: _lat,
        longitude: _lng,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final initialCenter =
        LatLng(_lat ?? 41.311081, _lng ?? 69.240562); // Toshkent markazi
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Manzilni tahrirlash' : 'Yangi manzil',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              const Text('Nomi:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                      hintText: 'Masalan: "Tezkor moyka" - Chilonzor')),
              const SizedBox(height: 14),
              const Text('Manzil (matn, ixtiyoriy):',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Chilonzor tumani, 5-kvartal')),
              const SizedBox(height: 14),
              const Text('Xaritadan joylashuvni belgilang:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 220,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: initialCenter,
                          initialZoom: _lat != null ? 15 : 10,
                          onTap: (tapPosition, point) {
                            setState(() {
                              _lat = point.latitude;
                              _lng = point.longitude;
                            });
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.avtoservis.admin',
                          ),
                          if (_lat != null && _lng != null)
                            MarkerLayer(markers: [
                              Marker(
                                point: LatLng(_lat!, _lng!),
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.location_pin,
                                    color: AppColors.error, size: 36),
                              ),
                            ]),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _lat != null && _lng != null
                    ? 'Tanlangan: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                    : 'Joylashuv hali belgilanmagan - xaritaga bosing',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              GlassGradientButton(
                  label: isEdit ? 'Saqlash' : 'Qo\'shish',
                  isLoading: _saving,
                  onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// XIZMATLAR TAB — servis egalari qo'shgan erkin nomli xizmatlarni tasdiqlash
// ============================================================================
class AdminOfferedServicesTab extends StatefulWidget {
  const AdminOfferedServicesTab({super.key});
  @override
  State<AdminOfferedServicesTab> createState() =>
      _AdminOfferedServicesTabState();
}

class _AdminOfferedServicesTabState extends State<AdminOfferedServicesTab> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.pendingOfferedServices();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  Future<void> _approve(int id) async {
    final ok = await AdminApi.approveOfferedService(id);
    if (ok) _load();
  }

  Future<void> _reject(int id) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );
    if (reason == null) return;
    final ok = await AdminApi.rejectOfferedService(id, reason);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Xizmatlarni tasdiqlash',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  const Text(
                    'Servis egalari qo\'shgan yangi xizmatlar shu yerda ko\'rinadi.',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary)))
          else if (_items.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Hozircha tasdiqlanishi kerak bo\'lgan xizmat yo\'q.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14.5, color: AppColors.textSecondary),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final item = _items[i] as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['category'] ?? '',
                              style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(
                            '${item['service_name'] ?? ''} • ${item['owner_name'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                          if (item['price'] != null) ...[
                            const SizedBox(height: 4),
                            Text('${item['price']} so\'m',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _IconActionButton(
                                  icon: Icons.check_rounded,
                                  colors: const [
                                    AppColors.success,
                                    Color(0xFF5FDC7E)
                                  ],
                                  tooltip: 'Tasdiqlash',
                                  onPressed: () => _approve(item['id'] as int),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _IconActionButton(
                                  icon: Icons.close_rounded,
                                  colors: const [
                                    AppColors.error,
                                    Color(0xFFFF6961)
                                  ],
                                  tooltip: 'Rad etish',
                                  onPressed: () => _reject(item['id'] as int),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: _items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// SERVICE DETAIL — ✅ Tasdiqlash / ❌ Rad etish / ✏️ Tahrirlash
// ============================================================================
class AdminServiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const AdminServiceDetailScreen({super.key, required this.service});
  @override
  State<AdminServiceDetailScreen> createState() =>
      _AdminServiceDetailScreenState();
}

class _AdminServiceDetailScreenState extends State<AdminServiceDetailScreen> {
  late Map<String, dynamic> s;
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    s = Map<String, dynamic>.from(widget.service);
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    final ok = await AdminApi.verifyService(s['id']);
    setState(() => _busy = false);
    if (ok) {
      setState(() {
        s['status'] = 'approved';
        _changed = true;
      });
      _toast('Servis tasdiqlandi');
    } else {
      _toast('Xatolik yuz berdi', error: true);
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busy = true);
    final ok = await AdminApi.rejectService(s['id'], reason.trim());
    setState(() => _busy = false);
    if (ok) {
      setState(() {
        s['status'] = 'rejected';
        s['reject_reason'] = reason.trim();
        _changed = true;
      });
      _toast('Ariza rad etildi');
    } else {
      _toast('Xatolik yuz berdi', error: true);
    }
  }

  Future<void> _edit() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => AdminServiceEditScreen(service: s)),
    );
    if (result != null) {
      setState(() {
        s.addAll(result);
        _changed = true;
      });
    }
  }

  Future<void> _toggleBlock() async {
    setState(() => _busy = true);
    final ok = await AdminApi.toggleBlockService(s['id']);
    setState(() => _busy = false);
    if (ok) {
      setState(() {
        s['is_active'] = !(s['is_active'] == true);
        _changed = true;
      });
      _toast(s['is_active'] == true
          ? 'Servis blokdan chiqarildi'
          : 'Servis bloklandi');
    } else {
      _toast('Xatolik yuz berdi', error: true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Servisni o\'chirish'),
        content: Text(
            '"${s['name'] ?? ''}" butunlay o\'chiriladi, shu jumladan uning barcha buyurtmalari va xizmatlari. Bu amalni ortga qaytarib bo\'lmaydi. Davom etilsinmi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('O\'chirish',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final ok = await AdminApi.deleteService(s['id']);
    setState(() => _busy = false);
    if (ok) {
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      _toast('Xatolik yuz berdi', error: true);
    }
  }

  Future<void> _addService() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Xizmat qo\'shish',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                '"${s['name'] ?? ''}" servisiga xizmat qo\'shiladi (darhol tasdiqlangan holda).',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              const Text('Xizmat nomi:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Motor diagnostikasi')),
              const SizedBox(height: 14),
              const Text('Narxi (so\'m):',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(hintText: 'Masalan: 150000')),
              const SizedBox(height: 18),
              GlassGradientButton(
                  label: 'Qo\'shish',
                  height: 48,
                  onPressed: () => Navigator.pop(ctx, true)),
            ],
          ),
        ),
      ),
    );
    if (saved == true && nameController.text.trim().isNotEmpty) {
      final ok = await AdminApi.addOfferedServiceDirect(
        s['id'] as int,
        nameController.text.trim(),
        double.tryParse(priceController.text.trim()),
      );
      _toast(ok ? 'Xizmat qo\'shildi' : 'Xatolik yuz berdi', error: !ok);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: error ? AppColors.error : AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 20),
                        onPressed: () => Navigator.pop(context, _changed)),
                    const Text('Ariza tafsilotlari',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    statusBadge(s['status'] ?? 'pending'),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: AppColors.primaryPale,
                          shape: BoxShape.circle,
                          image: (s['logo_url'] != null &&
                                  (s['logo_url'] as String).startsWith('data:'))
                              ? DecorationImage(
                                  image: MemoryImage(base64Decode(
                                      (s['logo_url'] as String)
                                          .split(',')
                                          .last)),
                                  fit: BoxFit.contain)
                              : null,
                        ),
                        child: s['logo_url'] == null
                            ? const Icon(Icons.storefront_rounded,
                                color: AppColors.primary, size: 34)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Center(
                        child: Text(s['name'] ?? '',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary))),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              _providerTypeColor(s['provider_type'] as String?)
                                  .withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                _providerTypeIcon(
                                    s['provider_type'] as String?),
                                size: 14,
                                color: _providerTypeColor(
                                    s['provider_type'] as String?)),
                            const SizedBox(width: 5),
                            Text(
                              'Ariza turi: ${_providerTypeLabel(s['provider_type'] as String?)}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _providerTypeColor(
                                      s['provider_type'] as String?)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _infoTile(Icons.person_outline, 'Ega/haydovchi ismi',
                        s['owner_name'] ?? '—'),
                    _infoTile(
                        Icons.phone_outlined, 'Telefon', s['phone'] ?? '—'),
                    if (s['provider_type'] == 'auto_service')
                      _infoTile(Icons.location_on_outlined, 'Manzil',
                          s['address'] ?? '—')
                    else
                      _infoTile(
                          Icons.local_shipping_outlined,
                          'Mashina rusmi (turi)',
                          (s['car_model'] == null || s['car_model'] == '')
                              ? 'Belgilanmagan'
                              : s['car_model']),
                    _infoTile(
                        Icons.access_time_outlined,
                        'Ish vaqti',
                        (s['working_hours'] == null || s['working_hours'] == '')
                            ? 'Belgilanmagan'
                            : s['working_hours']),
                    _infoTile(
                        Icons.event_busy_outlined,
                        'Dam olish kuni',
                        (s['day_off'] == null || s['day_off'] == '')
                            ? 'Belgilanmagan'
                            : s['day_off']),
                    if (s['provider_type'] != 'auto_service') ...[
                      _infoTile(
                        s['is_online'] == true
                            ? Icons.location_on
                            : Icons.location_off_outlined,
                        'Joriy holati',
                        s['is_online'] == true
                            ? 'Hozir ish ustida (onlayn)'
                            : 'Hozir oflayn',
                        color: s['is_online'] == true
                            ? AppColors.success
                            : AppColors.textMuted,
                      ),
                      _infoTile(
                        Icons.payments_outlined,
                        s['provider_type'] == 'fuel'
                            ? 'Benzin dastavka narxi'
                            : 'Evakuator narxi',
                        s['price'] == null
                            ? 'Belgilanmagan'
                            : '${s['price']} so\'m',
                        color: s['price'] == null ? null : AppColors.primary,
                      ),
                    ],
                    if (s['status'] == 'rejected' && s['reject_reason'] != null)
                      _infoTile(Icons.info_outline, 'Rad etish sababi',
                          s['reject_reason'],
                          color: AppColors.error),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _IconActionButton(
                            icon: Icons.check_rounded,
                            isLoading: _busy,
                            colors: const [
                              AppColors.success,
                              Color(0xFF5FDC7E)
                            ],
                            tooltip: 'Tasdiqlash',
                            onPressed:
                                s['status'] == 'approved' ? null : _approve,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _IconActionButton(
                            icon: Icons.close_rounded,
                            isLoading: _busy,
                            colors: const [AppColors.error, Color(0xFFFF6961)],
                            tooltip: 'Rad etish',
                            onPressed:
                                s['status'] == 'rejected' ? null : _reject,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _IconActionButton(
                            icon: Icons.edit_outlined,
                            isLoading: false,
                            outlined: true,
                            tooltip: 'Tahrirlash',
                            onPressed: _edit,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _IconActionButton(
                            icon: s['is_active'] == false
                                ? Icons.lock_open_rounded
                                : Icons.block_rounded,
                            isLoading: _busy,
                            outlined: true,
                            tooltip: s['is_active'] == false
                                ? 'Blokdan chiqarish'
                                : 'Bloklash',
                            onPressed: _toggleBlock,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _IconActionButton(
                            icon: Icons.delete_outline_rounded,
                            isLoading: _busy,
                            colors: const [AppColors.error, Color(0xFFFF6961)],
                            tooltip: 'O\'chirish',
                            onPressed: _delete,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: LiquidGlass(
        radius: 16,
        tintOpacity: 0.9,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: color ?? AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();
  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rad etish sababi',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text('Servis egasiga ko\'rsatiladigan sababni yozing.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Masalan: Manzil noto\'g\'ri kiritilgan'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Bekor qilish',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassGradientButton(
                    label: 'Yuborish',
                    height: 46,
                    colors: const [AppColors.error, Color(0xFFFF6961)],
                    onPressed: () => Navigator.pop(context, _controller.text),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// EDIT SERVICE
// ============================================================================
class AdminServiceEditScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const AdminServiceEditScreen({super.key, required this.service});
  @override
  State<AdminServiceEditScreen> createState() => _AdminServiceEditScreenState();
}

class _AdminServiceEditScreenState extends State<AdminServiceEditScreen> {
  late TextEditingController _name;
  late TextEditingController _ownerName;
  late TextEditingController _phone;
  late TextEditingController _address;
  late TextEditingController _carModel;
  late TextEditingController _price;
  TimeOfDay? _workingHoursFrom;
  TimeOfDay? _workingHoursTo;
  String _dayOff = '';
  bool _saving = false;

  static const _days = [
    'Dam olish kuni yo\'q',
    'Yakshanba',
    'Shanba',
    'Dushanba',
    'Seshanba',
    'Chorshanba',
    'Payshanba',
    'Juma'
  ];

  bool get _isAutoService =>
      (widget.service['provider_type'] as String?) != 'evacuator' &&
      (widget.service['provider_type'] as String?) != 'fuel';
  bool get _isFuel => (widget.service['provider_type'] as String?) == 'fuel';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String? get _workingHours {
    if (_workingHoursFrom == null || _workingHoursTo == null) return null;
    return '${_fmtTime(_workingHoursFrom!)}-${_fmtTime(_workingHoursTo!)}';
  }

  // "09:00-18:00" ko'rinishidagi qatorni ikkita TimeOfDay'ga ajratadi.
  TimeOfDay? _parseTime(String s) {
    final parts = s.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.service['name'] ?? '');
    _ownerName =
        TextEditingController(text: widget.service['owner_name'] ?? '');
    _phone = TextEditingController(text: widget.service['phone'] ?? '');
    _address = TextEditingController(text: widget.service['address'] ?? '');
    _carModel = TextEditingController(text: widget.service['car_model'] ?? '');
    _price = TextEditingController(
        text: widget.service['price'] != null
            ? '${widget.service['price']}'
            : '');

    final wh = widget.service['working_hours']?.toString() ?? '';
    final whParts = wh.split('-');
    if (whParts.length == 2) {
      _workingHoursFrom = _parseTime(whParts[0]);
      _workingHoursTo = _parseTime(whParts[1]);
    }
    final existingDayOff = widget.service['day_off']?.toString() ?? '';
    _dayOff = _days.contains(existingDayOff) ? existingDayOff : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _address.dispose();
    _carModel.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickWorkingHour({required bool isFrom}) async {
    final initial = (isFrom ? _workingHoursFrom : _workingHoursTo) ??
        const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _workingHoursFrom = picked;
      } else {
        _workingHoursTo = picked;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final fields = {
      'name': _name.text.trim(),
      'owner_name': _ownerName.text.trim(),
      'phone': _phone.text.trim(),
      'working_hours': _workingHours ?? '',
      'day_off': _dayOff,
      if (_isAutoService)
        'address': _address.text.trim()
      else
        'car_model': _carModel.text.trim(),
      if (!_isAutoService)
        'price': double.tryParse(_price.text.trim().replaceAll(' ', '')),
    };
    final ok = await AdminApi.editService(widget.service['id'], fields);
    setState(() => _saving = false);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, fields);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Saqlashda xatolik'),
            backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 20),
                      onPressed: () => Navigator.pop(context)),
                  const Text('Ma\'lumotlarni tahrirlash',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _label(
                      _isAutoService ? 'Servis nomi' : 'Ko\'rsatiladigan nomi'),
                  TextField(controller: _name),
                  const SizedBox(height: 16),
                  _label('Ega/haydovchi ismi'),
                  TextField(controller: _ownerName),
                  const SizedBox(height: 16),
                  _label('Telefon'),
                  TextField(
                      controller: _phone, keyboardType: TextInputType.phone),
                  const SizedBox(height: 16),
                  if (_isAutoService) ...[
                    _label('Manzil'),
                    TextField(controller: _address, maxLines: 2),
                  ] else ...[
                    _label('Mashina rusmi (turi)'),
                    TextField(
                        controller: _carModel,
                        decoration: const InputDecoration(
                            hintText: 'Masalan: Isuzu evakuator')),
                    const SizedBox(height: 16),
                    // Evakuator/benzin dastavka narxi endi har bir provayderda
                    // alohida emas - butun tizim uchun GLOBAL sozlanadi, shuning
                    // uchun bu yerda faqat shu sozlamalar ekraniga havola bor.
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isFuel
                                  ? 'Benzin dastavka narxi (yetkazib berish + 1 litr) barcha benzinchilar uchun umumiy sozlamada belgilanadi.'
                                  : 'Evakuator narxi barcha evakuatorlar uchun umumiy sozlamada belgilanadi.',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminPricingScreen())),
                      child: const Text('Narxlarni boshqarish →',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _label('Ish vaqti'),
                  _workingHoursPicker(),
                  const SizedBox(height: 16),
                  _label('Dam olish kuni'),
                  _dayOffPicker(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GlassGradientButton(
                  label: 'Saqlash', isLoading: _saving, onPressed: _save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );

  Widget _workingHoursPicker() {
    return Row(
      children: [
        Expanded(
            child: _timeBox(
                label: 'Dan',
                value: _workingHoursFrom,
                onTap: () => _pickWorkingHour(isFrom: true))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('—',
              style: TextStyle(fontSize: 16, color: AppColors.textMuted)),
        ),
        Expanded(
            child: _timeBox(
                label: 'Gacha',
                value: _workingHoursTo,
                onTap: () => _pickWorkingHour(isFrom: false))),
      ],
    );
  }

  Widget _timeBox(
      {required String label,
      required TimeOfDay? value,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            const Icon(Icons.access_time_outlined,
                size: 19, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value != null ? _fmtTime(value) : label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: value != null
                        ? AppColors.textPrimary
                        : AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayOffPicker() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _dayOff.isEmpty ? _days.first : _dayOff,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          items: _days
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (v) =>
              setState(() => _dayOff = v == _days.first ? '' : v!),
        ),
      ),
    );
  }
}

// ============================================================================
// XARITA TAB — barcha servislar, faol buyurtmalar va faol ustalarni xaritada
// ko'rsatadi.
// ============================================================================
class AdminMapTab extends StatefulWidget {
  const AdminMapTab({super.key});
  @override
  State<AdminMapTab> createState() => _AdminMapTabState();
}

class _AdminMapTabState extends State<AdminMapTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _showServices = true;
  bool _showOrders = true;
  bool _showWorkers = true;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.mapData();
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Color _providerColor(String? type) {
    switch (type) {
      case 'evacuator':
        return AppColors.warning;
      case 'fuel':
        return AppColors.primaryDark;
      default:
        return AppColors.primary;
    }
  }

  IconData _providerIcon(String? type) {
    switch (type) {
      case 'evacuator':
        return Icons.local_shipping_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      default:
        return Icons.storefront_rounded;
    }
  }

  void _showInfoSheet(
      String title, String subtitle, IconData icon, Color color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: LiquidGlass(
          radius: 20,
          tintOpacity: 0.96,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    if (_data == null) return markers;

    if (_showServices) {
      for (final s in (_data!['services'] as List? ?? [])) {
        final m = s as Map<String, dynamic>;
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final color = _providerColor(m['provider_type'] as String?);
        markers.add(Marker(
          point: LatLng(lat, lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _showInfoSheet(
                m['name'] ?? 'Servis',
                m['address'] ?? '',
                _providerIcon(m['provider_type'] as String?),
                color),
            child: Container(
              decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]),
              child: Icon(_providerIcon(m['provider_type'] as String?),
                  color: Colors.white, size: 18),
            ),
          ),
        ));
      }
    }

    if (_showOrders) {
      for (final o in (_data!['orders'] as List? ?? [])) {
        final m = o as Map<String, dynamic>;
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        markers.add(Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _showInfoSheet(
                '${m['category'] ?? 'Buyurtma'}',
                '${m['user_name'] ?? ''} → ${m['service_name'] ?? ''}',
                Icons.receipt_long_rounded,
                AppColors.error),
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.receipt_long_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ));
      }
    }

    if (_showWorkers) {
      for (final w in (_data!['active_workers'] as List? ?? [])) {
        final m = w as Map<String, dynamic>;
        final lat = (m['latitude'] as num?)?.toDouble();
        final lng = (m['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        markers.add(Marker(
          point: LatLng(lat, lng),
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _showInfoSheet(
                m['name'] ?? 'Usta',
                m['current_address'] ?? 'Jonli joylashuv',
                Icons.person_pin_circle_rounded,
                AppColors.success),
            child: Container(
              decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
              child: const Icon(Icons.person_pin_circle_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ));
      }
    }

    return markers;
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.14) : AppColors.chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : Colors.transparent, width: 1.3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? color : AppColors.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = _buildMarkers();
    LatLng center = const LatLng(41.311081, 69.240562); // Toshkent markazi
    if (markers.isNotEmpty) {
      final avgLat =
          markers.map((m) => m.point.latitude).reduce((a, b) => a + b) /
              markers.length;
      final avgLng =
          markers.map((m) => m.point.longitude).reduce((a, b) => a + b) /
              markers.length;
      center = LatLng(avgLat, avgLng);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('Xarita',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppColors.textSecondary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                  'Barcha servislar',
                  _showServices,
                  () => setState(() => _showServices = !_showServices),
                  AppColors.primary),
              _chip(
                  'Barcha buyurtmalar',
                  _showOrders,
                  () => setState(() => _showOrders = !_showOrders),
                  AppColors.error),
              _chip(
                  'Faol ustalar',
                  _showWorkers,
                  () => setState(() => _showWorkers = !_showWorkers),
                  AppColors.success),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: markers.isEmpty ? 11 : 12,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.autoservice.admin',
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),
        ),
      ],
    );
  }
}

// ============================================================================
// STATISTIKA TAB — kunlik/haftalik/oylik buyurtmalar dinamikasi, eng mashhur
// xizmat va eng faol servis.
// ============================================================================
class AdminStatisticsTab extends StatefulWidget {
  const AdminStatisticsTab({super.key});
  @override
  State<AdminStatisticsTab> createState() => _AdminStatisticsTabState();
}

class _AdminStatisticsTabState extends State<AdminStatisticsTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  int _periodIndex = 0; // 0=kunlik, 1=haftalik, 2=oylik
  final List<String> _periodLabels = ['Kunlik', 'Haftalik', 'Oylik'];
  final List<String> _periodKeys = ['daily', 'weekly', 'monthly'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await AdminApi.statistics();
    if (!mounted) return;
    setState(() {
      _stats = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final series =
        (_stats?[_periodKeys[_periodIndex]] as List?)?.cast<dynamic>() ?? [];
    int maxCount = 1;
    for (final e in series) {
      final c = (e as Map<String, dynamic>)['count'] as int? ?? 0;
      if (c > maxCount) maxCount = c;
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const Text('Statistika',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()))
          else if (_stats == null)
            const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                    child: Text('Ma\'lumot yuklanmadi',
                        style: TextStyle(color: AppColors.textMuted))))
          else ...[
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: List.generate(_periodLabels.length, (i) {
                  final selected = i == _periodIndex;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _periodIndex = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2))
                                ]
                              : [],
                        ),
                        child: Text(_periodLabels[i],
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textSecondary)),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 18),
            LiquidGlass(
              radius: 20,
              tintOpacity: 0.9,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buyurtmalar soni — ${_periodLabels[_periodIndex]}',
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 18),
                  if (series.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Ma\'lumot yo\'q',
                          style: TextStyle(color: AppColors.textMuted)),
                    )
                  else
                    ...series.map((e) {
                      final m = e as Map<String, dynamic>;
                      final count = m['count'] as int? ?? 0;
                      final revenue = (m['revenue'] as num?)?.toDouble() ?? 0;
                      final ratio = maxCount == 0 ? 0.0 : count / maxCount;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(m['label'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary)),
                                Text(
                                    '$count ta${revenue > 0 ? ' • ${revenue.toStringAsFixed(0)} so\'m' : ''}',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LayoutBuilder(
                                builder: (context, constraints) => Stack(
                                  children: [
                                    Container(
                                      height: 10,
                                      width: constraints.maxWidth,
                                      color: AppColors.chipBg,
                                    ),
                                    Container(
                                      height: 10,
                                      width: constraints.maxWidth * ratio,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                            colors: AppColors.primaryGradient),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_stats!['most_popular_service'] != null)
              _highlightCard(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.warning,
                title: 'Eng mashhur xizmat',
                value: _stats!['most_popular_service']['category'] ?? '—',
                subtitle:
                    '${_stats!['most_popular_service']['count'] ?? 0} ta buyurtma',
              ),
            if (_stats!['most_active_service'] != null) ...[
              const SizedBox(height: 12),
              _highlightCard(
                icon: Icons.emoji_events_rounded,
                color: AppColors.success,
                title: 'Eng faol servis',
                value: _stats!['most_active_service']['name'] ?? '—',
                subtitle:
                    '${_stats!['most_active_service']['count'] ?? 0} ta buyurtma qabul qilingan',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _highlightCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return LiquidGlass(
      radius: 18,
      tintOpacity: 0.9,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
