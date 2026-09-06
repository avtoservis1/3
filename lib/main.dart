import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

import 'admin_main.dart' as admin;
import 'main_owner.dart' as owner;

// ============================================================================
// "Xizmat turlari" va "Qo'shimcha xizmatlar" bandlari uchun: admin panelda
// rasm yuklangan bo'lsa o'sha rasm, bo'lmasa standart ikonka ko'rsatiladi.
// ============================================================================
class CategoryIconImage extends StatelessWidget {
  final String? imageUrl; // base64 data-URL (masalan "data:image/png;base64,...")
  final IconData fallbackIcon;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? backgroundColor;
  final double borderRadius;

  const CategoryIconImage({
    super.key,
    required this.imageUrl,
    required this.fallbackIcon,
    this.size = 46,
    this.iconSize = 22,
    this.iconColor,
    this.backgroundColor,
    this.borderRadius = 13,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.startsWith('data:');
    Uint8List? bytes;
    if (hasImage) {
      try {
        bytes = base64Decode(imageUrl!.split(',').last);
      } catch (_) {
        bytes = null;
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primaryPale.withOpacity(0.55),
        borderRadius: BorderRadius.circular(borderRadius),
        image: bytes != null
            ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover)
            : null,
      ),
      child: bytes != null
          ? null
          : Icon(fallbackIcon,
              color: iconColor ?? AppColors.primary, size: iconSize),
    );
  }
}

// Xizmat turlari ro'yxati (/api/categories, /api/service-types) tezkor
// ochilishi uchun rasmni o'zida saqlamaydi - faqat `has_image` belgisini
// beradi. Shu widget ro'yxat allaqachon ko'rinib turgan holda, har bir
// qator uchun rasmni fonda alohida-alohida so'raydi (ApiService.
// getServiceTypeImage orqali) va tayyor bo'lgach ustiga chizadi. Rasm hali
// kelmagan yoki umuman bo'lmasa ham, qator/ro'yxat ko'rinishda qoladi -
// faqat ikonka ko'rsatiladi.
class LazyCategoryIconImage extends StatefulWidget {
  final Map<String, dynamic> item;
  final IconData fallbackIcon;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? backgroundColor;
  final double borderRadius;

  const LazyCategoryIconImage({
    super.key,
    required this.item,
    required this.fallbackIcon,
    this.size = 46,
    this.iconSize = 22,
    this.iconColor,
    this.backgroundColor,
    this.borderRadius = 13,
  });

  @override
  State<LazyCategoryIconImage> createState() => _LazyCategoryIconImageState();
}

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

class _LazyCategoryIconImageState extends State<LazyCategoryIconImage> {
  String? _imageUrl;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.item['image_url'] as String?;
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant LazyCategoryIconImage old) {
    super.didUpdateWidget(old);
    final directUrl = widget.item['image_url'] as String?;
    if (old.item['id'] != widget.item['id'] || directUrl != old.item['image_url']) {
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
    _ServiceTypeImageCache.load(id, () => ApiService.getServiceTypeImage(id))
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
    return CategoryIconImage(
      imageUrl: _imageUrl,
      fallbackIcon: widget.fallbackIcon,
      size: widget.size,
      iconSize: widget.iconSize,
      iconColor: widget.iconColor,
      backgroundColor: widget.backgroundColor,
      borderRadius: widget.borderRadius,
    );
  }
}

class AppColors {
  // Accent — reserved for text, icons, and selection states only.
  // Liquid Glass surfaces (buttons, bars, cards) never fill with this color.
  static const Color primary = Color(0xFF3A7BFF);
  static const Color primaryDark = Color(0xFF2E63D8);
  static const Color primaryLight = Color(0xFF6CA8FF);
  static const Color primaryPale = Color(0xFFD7E6FF);
  static const List<Color> primaryGradient = [primary, primaryLight];

  static const Color background = Color(0xFFF2F2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color chipBg = Color(0xFFF1F3F8);

  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF6B7080);
  static const Color textMuted = Color(0xFFA7ACBA);
  static const Color border = Color(0xFFE6E9F2);

  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color error = Color(0xFFFF3B30);

  // ---- Liquid Glass material tokens -----------------------------------
  static const Color glassBorder = Color(0x66FFFFFF);
  static const Color glassFill = Color(0xFFFFFFFF);
  static const Color glassStrokeTop = Color(0xE6FFFFFF);
  static const Color glassStrokeBottom = Color(0x22FFFFFF);
  static const Color glassShadow = Color(0x1F1B1D23);
  static const Color glassHighlight = Color(0x59FFFFFF);
}

// A soft "specular" sheen painted across the top of a glass surface —
// the light-catching edge that makes Liquid Glass read as real material.
List<double> _glassSaturationMatrix([double sat = 1.35]) {
  final r = (1 - sat) * 0.213, g = (1 - sat) * 0.715, b = (1 - sat) * 0.072;
  return <double>[
    r + sat,
    g,
    b,
    0,
    0,
    r,
    g + sat,
    b,
    0,
    0,
    r,
    g,
    b + sat,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _GlassSheen extends StatelessWidget {
  final double radius;
  const _GlassSheen({required this.radius});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Column(
          children: [
            Container(
              height: 0.9,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  AppColors.glassStrokeTop,
                  Colors.transparent,
                ]),
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment(0, 0.7),
                    colors: [Color(0x33FFFFFF), Colors.transparent],
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

// Full screen map tracker for an active order's driver_location
class MapTrackingScreen extends StatefulWidget {
  final int orderId;
  const MapTrackingScreen({super.key, required this.orderId});
  @override
  State<MapTrackingScreen> createState() => _MapTrackingScreenState();
}

class _MapTrackingScreenState extends State<MapTrackingScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  Timer? _poller;
  final _mapController = MapController();
  List<ll.LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await ApiService.getOrderDetail(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = res['data'] as Map<String, dynamic>?;
      _loading = false;
    });
    if (_order != null && _order!['driver_location'] != null) {
      try {
        final lat = ((_order!['driver_location']['lat']) as num).toDouble();
        final lng = ((_order!['driver_location']['lng']) as num).toDouble();
        final driverPoint = ll.LatLng(lat, lng);
        _mapController.move(driverPoint, 14);
        // Mijoz joylashuvi ma'lum bo'lsa - haydovchidan mijozgacha bo'lgan
        // yo'lni (ko'cha bo'ylab) chizish uchun.
        final userLat = (_order!['user_latitude'] as num?)?.toDouble();
        final userLng = (_order!['user_longitude'] as num?)?.toDouble();
        if (userLat != null && userLng != null) {
          final points =
              await fetchRoadRoute(driverPoint, ll.LatLng(userLat, userLng));
          if (!mounted) return;
          setState(() => _routePoints = points);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final userLat = (_order?['user_latitude'] as num?)?.toDouble();
    final userLng = (_order?['user_longitude'] as num?)?.toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Kuzatish')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_order == null || _order!['driver_location'] == null)
              ? const Center(
                  child: Text(
                      'Haydovchi hali belgilanmagan yoki joylashuv mavjud emas'))
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                      initialCenter: ll.LatLng(
                          ((_order!['driver_location']['lat']) as num)
                              .toDouble(),
                          ((_order!['driver_location']['lng']) as num)
                              .toDouble()),
                      initialZoom: 14),
                  children: [
                    osmTileLayer(),
                    if (_routePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                              points: _routePoints,
                              strokeWidth: 4,
                              color: AppColors.primary),
                        ],
                      ),
                    MarkerLayer(markers: [
                      Marker(
                        point: ll.LatLng(
                            ((_order!['driver_location']['lat']) as num)
                                .toDouble(),
                            ((_order!['driver_location']['lng']) as num)
                                .toDouble()),
                        width: 48,
                        height: 48,
                        child: const Icon(Icons.local_shipping_rounded,
                            color: AppColors.primary, size: 36),
                      ),
                      if (userLat != null && userLng != null)
                        Marker(
                          point: ll.LatLng(userLat, userLng),
                          width: 42,
                          height: 42,
                          child: const Icon(Icons.location_on,
                              color: AppColors.error, size: 40),
                        ),
                    ]),
                  ],
                ),
    );
  }
}

// ========================================================================
// LIQUID GLASS
// ========================================================================

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
    this.radius = 24,
    this.blur = 24,
    this.tintOpacity = 0.72,
    this.padding,
    this.shadow,
    this.tintColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final glassContent = Stack(
      children: [
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor.withOpacity(tintOpacity * 0.62),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.glassBorder, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withOpacity(0.34),
                Colors.white.withOpacity(0.06),
              ],
            ),
          ),
          child: child,
        ),
        Positioned.fill(child: _GlassSheen(radius: radius)),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ??
            [
              BoxShadow(
                  color: AppColors.glassShadow,
                  blurRadius: 30,
                  offset: const Offset(0, 14)),
              BoxShadow(
                  color: AppColors.textPrimary.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: kIsWeb
            ? glassContent
            : BackdropFilter(
                // Blur + a touch of extra saturation is what makes the glass feel
                // like it's genuinely refracting what's behind it, not just fading it.
                filter: ImageFilter.compose(
                  outer: ColorFilter.matrix(_glassSaturationMatrix()),
                  inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ),
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
  final List<Color>?
      colors; // kept for API compatibility; no longer used to tint the glass
  // Agar true bo'lsa - shisha effekti (blur/gradient/soya/yaltirash) butunlay
  // olib tashlanadi, faqat tekis rangli tugmaning o'zi qoladi (orqa fon yo'q).
  final bool flat;

  const GlassGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.height = 56,
    this.colors,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final radius = height / 2; // true capsule, iOS 27 style

    if (flat) {
      // Faqat knopkaning o'zi - shishasiz, blursiz, soyasiz, orqa panelsiz.
      final bg = disabled
          ? AppColors.primary.withOpacity(0.4)
          : AppColors.primary;
      return SizedBox(
        height: height,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: disabled ? null : onPressed,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 19),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    // Pure white Liquid Glass with blue text/icons on top.
    final contentColor = AppColors.primary.withOpacity(disabled ? 0.4 : 1.0);
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
          color: Colors.white.withOpacity(disabled ? 0.30 : 0.85),
          width: 1.1,
        ),
        boxShadow: disabled
            ? []
            : [
                BoxShadow(
                    color: AppColors.glassShadow,
                    blurRadius: 22,
                    offset: const Offset(0, 9)),
                BoxShadow(
                    color: Colors.white.withOpacity(0.5),
                    blurRadius: 1,
                    offset: const Offset(0, -1)),
              ],
      ),
    );

    return _PressableGlass(
      onTap: disabled ? null : onPressed,
      borderRadius: radius,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: kIsWeb
                ? glassBackground
                : BackdropFilter(
                    filter: ImageFilter.compose(
                      outer: ColorFilter.matrix(_glassSaturationMatrix()),
                      inner: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                    ),
                    child: glassBackground,
                  ),
          ),
          if (!disabled) Positioned.fill(child: _GlassShimmer(radius: radius)),
          Positioned.fill(child: _GlassSheen(radius: radius)),
          Center(
            child: isLoading
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: contentColor),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: contentColor, size: 19),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: contentColor,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// A slow, looping diagonal light sweep across a glass surface — the subtle
// "liquid" shimmer that keeps premium glass controls feeling alive at rest.
class _GlassShimmer extends StatefulWidget {
  final double radius;
  const _GlassShimmer({required this.radius});
  @override
  State<_GlassShimmer> createState() => _GlassShimmerState();
}

class _GlassShimmerState extends State<_GlassShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final dx = (-w * 0.6) + (_c.value * w * 1.9);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Transform.rotate(
                    angle: -0.42,
                    child: Container(
                      width: w * 0.32,
                      height: constraints.maxHeight * 2.6,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white.withOpacity(0.0),
                            Colors.white.withOpacity(0.30),
                            Colors.white.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// Shared tactile wrapper: gives every glass control the same soft
// "press and settle" squish that iOS Liquid Glass controls have.
class _PressableGlass extends StatefulWidget {
  final VoidCallback? onTap;
  final double borderRadius;
  final double height;
  final Widget child;
  const _PressableGlass({
    required this.onTap,
    required this.borderRadius,
    required this.height,
    required this.child,
  });
  @override
  State<_PressableGlass> createState() => _PressableGlassState();
}

class _PressableGlassState extends State<_PressableGlass> {
  bool _pressed = false;
  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Stack(
              children: [
                widget.child,
                AnimatedOpacity(
                  opacity: _pressed ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(color: Colors.white.withOpacity(0.14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AuthBackground extends StatelessWidget {
  final Widget child;
  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6F9FF), Color(0xFFEFF4FF), Color(0xFFF4F6FA)],
        ),
      ),
      child: child,
    );
  }
}

Widget authBackButton(BuildContext context, {VoidCallback? onTap}) {
  return SizedBox(
    height: 40,
    width: 40,
    child: LiquidGlass(
      radius: 12,
      tintOpacity: 0.7,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? () => Navigator.pop(context),
          child: const Center(
            child: Icon(Icons.arrow_back_ios_new,
                size: 16, color: AppColors.textPrimary),
          ),
        ),
      ),
    ),
  );
}

// ========================================================================
// API SERVICE
// ========================================================================

class ApiService {
  static const String baseUrl = String.fromEnvironment('API_URL',
      defaultValue: 'https://1-production-9aab.up.railway.app');

  static Future<Map<String, dynamic>> register({
    required String phone,
    required String name,
    required String password,
    required String city,
    String? carModel,
    String? plateNumber,
    int? year,
    String? color,
    String? fuelType,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'name': name,
          'city': city,
          'password': password,
          if (carModel != null && carModel.isNotEmpty) 'car_model': carModel,
          if (plateNumber != null) 'plate_number': plateNumber,
          if (year != null) 'year': year,
          if (color != null) 'color': color,
          if (fuelType != null) 'fuel_type': fuelType,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Xatolik yuz berdi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> sendOtp(String phone) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'SMS yuborilmadi'
      };
    } catch (e) {
      return {'success': true};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String phone, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Noto\'g\'ri kod'
      };
    } catch (e) {
      return {'success': true};
    }
  }

  static Future<Map<String, dynamic>> login(
      String phone, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Admin bo'lmasa, server token bermaydi - o'rniga SMS kod yuboradi
        // (requires_otp: true). Bunday holda hali prefs'ga hech narsa
        // yozmaymiz - token faqat loginVerifyOtp muvaffaqiyatli bo'lgach saqlanadi.
        if (data['requires_otp'] == true) {
          return {'success': true, 'requiresOtp': true, 'data': data};
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('user_id', data['user_id'].toString());
        await prefs.setString('role', data['role']?.toString() ?? 'user');
        await prefs.setString('phone', phone);
        if (data['name'] != null)
          await prefs.setString('user_name', data['name'].toString());
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Login xatolik'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  /// Login - 2-bosqich: kirishni tasdiqlovchi SMS kodni tekshiradi va
  /// muvaffaqiyatli bo'lsa tokenni prefs'ga saqlaydi.
  static Future<Map<String, dynamic>> loginVerifyOtp(
      String phone, String code) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/login/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'code': code}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('user_id', data['user_id'].toString());
        await prefs.setString('role', data['role']?.toString() ?? 'user');
        await prefs.setString('phone', phone);
        if (data['name'] != null)
          await prefs.setString('user_name', data['name'].toString());
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Noto\'g\'ri kod'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> registerServiceOwner({
    required String phone,
    required String firstName,
    required String lastName,
    required String password,
    required String serviceName,
    required String address,
    required double latitude,
    required double longitude,
    String? dayOff,
    String? logoBase64,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/service-owner/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'first_name': firstName,
          'last_name': lastName,
          'password': password,
          'service_name': serviceName,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          if (dayOff != null && dayOff.isNotEmpty) 'day_off': dayOff,
          if (logoBase64 != null) 'logo_base64': logoBase64,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Ariza yuborilmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getNearbyServices({
    required double latitude,
    required double longitude,
    double radiusKm = 15,
    String? category,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/services').replace(queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
        'radius': radiusKm.toString(),
        if (category != null && category.isNotEmpty) 'category': category,
      });
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'message': 'Servislar yuklanmadi'};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getServiceDetail(int serviceId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/services/$serviceId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Servis topilmadi'};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> createOrder({
    required int userId,
    required int serviceId,
    required String category,
    String? description,
    double? userLatitude,
    double? userLongitude,
    String orderType = 'now',
    String? scheduledAt,
    double? liters,
    String? fuelType,
    bool? isUrgent,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/orders?user_id=$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': serviceId,
          'category': category,
          if (description != null) 'description': description,
          'order_type': orderType,
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
          if (userLatitude != null) 'user_latitude': userLatitude,
          if (userLongitude != null) 'user_longitude': userLongitude,
          if (liters != null) 'liters': liters,
          if (fuelType != null) 'fuel_type': fuelType,
          if (isUrgent != null) 'is_urgent': isUrgent,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Buyurtma yaratilmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getUserOrders(int userId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/orders?user_id=$userId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> getOrderDetail(int orderId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/orders/$orderId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Buyurtma topilmadi'};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> sendChatMessage(
      int orderId, int senderId, String message) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat?sender_id=$senderId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'order_id': orderId, 'message': message}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> getChatMessages(int orderId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/chat/$orderId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> addFavorite(
      int userId, int serviceId) async {
    try {
      final response = await http.post(
        Uri.parse(
            '$baseUrl/api/favorites?user_id=$userId&service_id=$serviceId'),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> removeFavorite(
      int userId, int serviceId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/favorites/$serviceId?user_id=$userId'),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> getFavorites(int userId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/favorites?user_id=$userId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> checkFavorite(
      int userId, int serviceId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/favorites/check?user_id=$userId&service_id=$serviceId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'is_favorite': data['is_favorite'] ?? false};
      }
      return {'success': false, 'is_favorite': false};
    } catch (e) {
      return {'success': false, 'is_favorite': false};
    }
  }

  static Future<Map<String, dynamic>> createReview({
    required int userId,
    required int serviceId,
    required int orderId,
    required int rating,
    String? comment,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/reviews?user_id=$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': serviceId,
          'order_id': orderId,
          'rating': rating,
          if (comment != null) 'comment': comment,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Baholashda xatolik'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> updateUserProfile(
      String phone, String name) async {
    try {
      final uri = Uri.parse('$baseUrl/api/users/me').replace(queryParameters: {
        'phone': phone,
        'name': name,
      });
      final response =
          await http.put(uri, headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Profil yangilanmadi'};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  // Kirish parolini o'zgartirish (joriy parol tasdiqlanadi, keyin yangisi saqlanadi).
  static Future<Map<String, dynamic>> changePassword(
      int userId, String oldPassword, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      String message = 'Parol o\'zgartirilmadi';
      try {
        message = jsonDecode(response.body)['detail'] ?? message;
      } catch (_) {}
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  // -- Cars --
  static Future<Map<String, dynamic>> getUserCars(int userId) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/cars?user_id=$userId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> addCar({
    required int userId,
    required String model,
    String? plateNumber,
    int? year,
    String? color,
    String? fuelType,
    bool isPrimary = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/cars?user_id=$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          if (plateNumber != null) 'plate_number': plateNumber,
          if (year != null) 'year': year,
          if (color != null) 'color': color,
          if (fuelType != null) 'fuel_type': fuelType,
          'is_primary': isPrimary,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false, 'message': 'Mashina qo\'shilmadi'};
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getCategories() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/categories'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  // Xizmat turi rasmini alohida-alohida (lazy) yuklab olish uchun. Ro'yxat
  // (/api/categories, /api/service-types) tezkor ochilishi uchun rasmni
  // o'zida saqlamaydi - faqat `has_image` belgisini beradi; ro'yxat
  // ko'rinishi chiqqach, har bir qator uchun rasm shu orqali fonda
  // alohida-alohida yuklanadi (rasm yuklanmasa ham ro'yxat ko'rinib turadi).
  static Future<String?> getServiceTypeImage(int id) async {
    try {
      final res =
          await http.get(Uri.parse('$baseUrl/api/service-types/$id/image'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['image_url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // Evakuator/benzin dastavka uchun global narxlar (admin belgilagan) -
  // "Chaqirish" oynasida narxni ko'rsatish uchun ishlatiladi.
  static Future<Map<String, dynamic>?> getPricing() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/pricing'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // Moyka/zapravka manzillari - faqat joylashuv, admin kiritadi.
  // locationType: "carwash" (moyka) yoki "gasstation" (zapravka).
  static Future<List<Map<String, dynamic>>> getLocations(
      String locationType) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/api/locations?location_type=$locationType'));
      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as List)
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  // -- Service owner --
  static Future<Map<String, dynamic>> serviceOwnerStatus(int serviceId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/service-owner/status?service_id=$serviceId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> getServiceOwnerService(
      int ownerId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/service-owner/service?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Servis topilmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getServiceOwnerOrders(int ownerId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/service-owner/orders?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> getServiceOwnerDashboard(
      int ownerId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/service-owner/dashboard?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Yuklanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getServiceOwnerStats(
      int ownerId, String period) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/api/service-owner/stats?owner_id=$ownerId&period=$period'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Yuklanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getServiceOwnerReviews(
      int ownerId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/service-owner/reviews?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Yuklanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getServicesOffered(int ownerId) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/api/service-owner/services-offered?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<Map<String, dynamic>> upsertServiceOffered(
      int ownerId, String category, double? price, bool isActive) async {
    try {
      final response = await http.post(
        Uri.parse(
            '$baseUrl/api/service-owner/services-offered?owner_id=$ownerId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'category': category, 'price': price, 'is_active': isActive}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Saqlanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> updateServiceOwnerProfile(
      int ownerId, Map<String, dynamic> fields) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/service-owner/profile?owner_id=$ownerId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(fields),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Yangilanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> updateOrderStatus(
      int orderId, String status) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/orders/$orderId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Yangilanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }

  static Future<Map<String, dynamic>> getNotifications(int userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/notifications?user_id=$userId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  static Future<int> getUnreadNotificationsCount(int userId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/notifications/unread-count?user_id=$userId'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['unread_count'] ?? 0;
      }
    } catch (e) {}
    return 0;
  }

  static Future<void> markNotificationRead(int notificationId) async {
    try {
      await http
          .put(Uri.parse('$baseUrl/api/notifications/$notificationId/read'));
    } catch (e) {}
  }

  static Future<void> markAllNotificationsRead(int userId) async {
    try {
      await http.put(
          Uri.parse('$baseUrl/api/notifications/read-all?user_id=$userId'));
    } catch (e) {}
  }

  static Future<void> deleteNotification(int notificationId) async {
    try {
      await http
          .delete(Uri.parse('$baseUrl/api/notifications/$notificationId'));
    } catch (e) {}
  }

  static Future<Map<String, dynamic>> getServiceOwnerProfile(
      int ownerId) async {
    try {
      final response = await http.get(
          Uri.parse('$baseUrl/api/service-owner/profile?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      return {
        'success': false,
        'message': jsonDecode(response.body)['detail'] ?? 'Yuklanmadi'
      };
    } catch (e) {
      return {'success': false, 'message': 'Server bilan aloqa yo\'q'};
    }
  }
}

// ========================================================================
// PUSH BILDIRISHNOMALAR (Firebase Cloud Messaging - Android)
// ========================================================================
// Ilova fon rejimida (background/terminated) bo'lganda kelgan xabarni qayta
// ishlash uchun Flutter talabiga ko'ra bu funksiya top-level (klassdan
// tashqarida) va @pragma('vm:entry-point') bilan belgilangan bo'lishi kerak.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Fon rejimida FCM tizim darajasida bildirishnomani o'zi ko'rsatadi,
  // shuning uchun bu yerda faqat kerak bo'lsa ma'lumotni logga yozish kifoya.
}

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String _androidChannelId = 'autoservis_default';

  /// main() ichida Firebase.initializeApp() dan keyin bir marta chaqiriladi.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

    // Local notifications - ilova OCHIQ (foreground) turganda kelgan xabarni
    // ko'rsatish uchun (FCM foreground xabarlarni avtomatik ko'rsatmaydi).
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);
    const channel = AndroidNotificationChannel(
      _androidChannelId,
      'Asosiy bildirishnomalar',
      description: 'Buyurtma holati, chat va boshqa xabarlar',
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

  /// Foydalanuvchi tizimga kirgach (yoki ilova ochilib, u allaqachon kirgan
  /// bo'lsa) qurilmaning joriy FCM tokenini backendga yuboradi. Token
  /// yangilansa (masalan ilova qayta o'rnatilganda) ham qayta yuboriladi.
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
    } catch (_) {
      // Push ro'yxatdan o'tmasa ham ilovaning asosiy ishlashiga xalaqit bermasin.
    }
  }

  static Future<void> _sendTokenToBackend(int userId, String token) async {
    try {
      await http.post(
        Uri.parse('${ApiService.baseUrl}/api/register-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'token': token}),
      );
    } catch (_) {
      // Internet yo'q bo'lsa jimgina o'tkazib yuboriladi - keyingi ochilishda qayta urinadi.
    }
  }
}

// ========================================================================
// AUTH ROUTING
// ========================================================================

enum UserRole { user, serviceOwner, admin }

extension UserRoleName on UserRole {
  String get apiValue {
    switch (this) {
      case UserRole.user:
        return 'user';
      case UserRole.serviceOwner:
        return 'service_owner';
      case UserRole.admin:
        return 'admin';
    }
  }
}

// ========================================================================
// AUTH ROUTING (Foydalanuvchi ilovasi)
// ========================================================================
Future<void> routeAfterAuth(BuildContext context,
    {required String role, required int userId, String? name}) async {
  if (role == UserRole.serviceOwner.apiValue ||
      role == UserRole.admin.apiValue) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Bu hisob ushbu ilovaga mos emas'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating),
    );
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()), (r) => false);
    return;
  }

  PushNotificationService.registerToken(userId);

  Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
}

// ========================================================================
// HELPER FUNCTIONS
// ========================================================================
Future<ll.LatLng?> resolveCurrentLocation() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
    return ll.LatLng(position.latitude, position.longitude);
  } catch (e) {
    return null;
  }
}

/// Evakuator va benzin dastavka kabi joylashuv SHART bo'lgan chaqiruvlar
/// uchun: GPS o'chiq bo'lsa yoki ruxsat berilmagan bo'lsa, foydalanuvchidan
/// buni yoqishni/ruxsat berishni so'raydi (iOS'da ham, Android'da ham
/// ishlaydi - Geolocator tizim sozlamalarini ochadi). Faqat shundan keyin
/// joylashuvni qaytaradi; foydalanuvchi rad etsa yoki yoqmasa - null.
Future<ll.LatLng?> resolveCurrentLocationRequired(BuildContext context) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (!context.mounted) return null;
    final wantsToEnable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Joylashuvni yoqing',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Evakuator/benzin dastavka chaqirish uchun joylashuv (GPS) doim yoqilgan bo\'lishi shart - shu orqali haydovchi qayerga borishni biladi.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish')),
          GlassGradientButton(
            label: 'Yoqish',
            height: 42,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (wantsToEnable != true) return null;
    // Geolocator.openLocationSettings() ikkala platformada ham (iOS va
    // Android) tizim joylashuv sozlamalarini ochadi.
    await Geolocator.openLocationSettings();
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    if (!context.mounted) return null;
    final wantsToOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Joylashuvga ruxsat kerak',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Chaqiruvni yuborish uchun ilova sozlamalaridan joylashuvga ruxsat bering.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish')),
          GlassGradientButton(
            label: 'Sozlamalarga o\'tish',
            height: 42,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (wantsToOpenSettings != true) return null;
    // Geolocator.openAppSettings() ham iOS'da, ham Android'da ilova
    // sozlamalari sahifasini ochadi.
    await Geolocator.openAppSettings();
    permission = await Geolocator.checkPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 15),
    );
    return ll.LatLng(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}

TileLayer osmTileLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.avtoservis.app',
  );
}

// ========================================================================
// YO'L BO'YLAB YO'NALISH (ROUTING) — xaritada ikki nuqta orasidagi chiziq
// endi to'g'ri chiziq emas, balki haqiqiy yo'l (ko'cha) bo'ylab chiziladi.
// Buning uchun bepul OSRM (Open Source Routing Machine) demo serveridan
// foydalaniladi. Agar internet/server bilan muammo bo'lsa, ikkita nuqta
// orasidagi oddiy to'g'ri chiziqqa qaytiladi (foydalanuvchi hech qachon
// bo'sh xarita ko'rmasligi uchun).
// ========================================================================
Future<List<ll.LatLng>> fetchRoadRoute(ll.LatLng start, ll.LatLng end) async {
  try {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes != null && routes.isNotEmpty) {
        final coords = routes.first['geometry']?['coordinates'] as List?;
        if (coords != null && coords.isNotEmpty) {
          return coords
              .map<ll.LatLng>((c) =>
                  ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
        }
      }
    }
  } catch (_) {}
  // Yo'l topilmasa (server javob bermasa) - to'g'ri chiziqqa qaytish.
  return [start, end];
}

// ========================================================================
// ISH VAQTI TEKSHIRUVI (faqat oddiy avtoservis uchun) — evakuator/benzin
// dastavka faqat ish ustida (onlayn) bo'lgandagina umuman ro'yxatda/xaritada
// ko'rinadi, shuning uchun ularga alohida tekshiruv shart emas.
// ========================================================================
const _weekDayNames = [
  'Dushanba',
  'Seshanba',
  'Chorshanba',
  'Payshanba',
  'Juma',
  'Shanba',
  'Yakshanba'
];

bool isAutoServiceOpenNow(Map<String, dynamic>? service) {
  if (service == null) return true;
  final providerType = service['provider_type']?.toString() ?? 'auto_service';
  if (providerType != 'auto_service')
    return true; // evakuator/fuel - is_online orqali boshqariladi

  final dayOff = service['day_off']?.toString();
  final now = DateTime.now();
  if (dayOff != null && dayOff.isNotEmpty && dayOff != 'Dam olish kuni yo\'q') {
    if (_weekDayNames[now.weekday - 1] == dayOff) return false;
  }

  final wh = service['working_hours']?.toString();
  if (wh == null || !wh.contains('-'))
    return true; // ish vaqti belgilanmagan - cheklamaymiz
  final parts = wh.split('-');
  if (parts.length != 2) return true;
  List<int>? parse(String s) {
    final hm = s.trim().split(':');
    if (hm.length != 2) return null;
    final h = int.tryParse(hm[0]);
    final m = int.tryParse(hm[1]);
    if (h == null || m == null) return null;
    return [h, m];
  }

  final from = parse(parts[0]);
  final to = parse(parts[1]);
  if (from == null || to == null) return true;
  final nowMin = now.hour * 60 + now.minute;
  final fromMin = from[0] * 60 + from[1];
  final toMin = to[0] * 60 + to[1];
  if (fromMin <= toMin) return nowMin >= fromMin && nowMin < toMin;
  return nowMin >= fromMin || nowMin < toMin; // tungi smena
}

Future<void> showServiceClosedDialog(BuildContext context,
    {String? serviceName}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Ish vaqti tugagan',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: Text(
        '${serviceName ?? 'Bu servis'} hozir ishlamayapti — ish vaqti tugagan yoki bugun dam olish kuni. Iltimos, ish vaqtida qayta urinib ko\'ring.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tushunarli')),
      ],
    ),
  );
}

// ========================================================================
// APP WIDGET (Foydalanuvchi ilovasi)
// ========================================================================
void main() {
  const flavor = String.fromEnvironment('APP_FLAVOR', defaultValue: 'user');

  if (flavor == 'owner') {
    owner.main();
    return;
  }

  if (flavor == 'admin') {
    admin.main();
    return;
  }

  startUserApp();
}

Future<void> startUserApp() async {
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GoFix',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.primaryLight,
          surface: AppColors.surface,
        ),
        fontFamily: 'SF Pro Display',
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        textTheme: const TextTheme(
          displayLarge: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              letterSpacing: 0.2),
          titleLarge: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
          titleMedium: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 16, color: AppColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.error)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isChecking = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final loggedIn = token != null;
    final role = prefs.getString('role') ?? 'user';
    final userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    setState(() {
      _isLoggedIn = loggedIn;
      _isChecking = false;
    });
    if (loggedIn && userId > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) routeAfterAuth(context, role: role, userId: userId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking || _isLoggedIn) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.primary)));
    }
    return const WelcomeScreen();
  }
}

// ========================================================================
// 1. WELCOME SCREEN
// ========================================================================

// ========================================================================
// 1. WELCOME SCREEN (Foydalanuvchi ilovasi)
// ========================================================================
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: AppColors.primaryGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.32),
                              blurRadius: 32,
                              offset: const Offset(0, 16)),
                        ],
                      ),
                      child: const Icon(Icons.directions_car_filled_rounded,
                          size: 58, color: Colors.white),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Xush kelibsiz!',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Avtoservis ilovasiga xush kelibsiz,\nxizmatlardan bir zumda foydalaning.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          height: 1.5),
                    ),
                    const Spacer(flex: 2),
                    GlassGradientButton(
                      label: 'Telefon orqali davom etish',
                      icon: Icons.phone_iphone_rounded,
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PhoneEntryScreen())),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen())),
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                                fontSize: 14.5, color: AppColors.textSecondary),
                            children: [
                              TextSpan(text: 'Hisobingiz bormi? '),
                              TextSpan(
                                  text: 'Kirish',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
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

class PhoneEntryScreen extends StatefulWidget {
  final bool isServiceOwner;
  const PhoneEntryScreen({super.key, this.isServiceOwner = false});
  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _UzPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 9 ? digits.substring(0, 9) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      buffer.write(limited[i]);
      if (i == 1 || i == 4 || i == 6) {
        if (i != limited.length - 1) buffer.write(' ');
      }
    }
    final text = buffer.toString();
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;

  String get _digits => _controller.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_digits.length < 9) return;
    setState(() => _isLoading = true);
    await ApiService.sendOtp('+998$_digits');
    setState(() => _isLoading = false);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(
            phone: '+998 ${_controller.text}',
            isServiceOwner: widget.isServiceOwner),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                authBackButton(context),
                const SizedBox(height: 24),
                Text(
                  widget.isServiceOwner
                      ? 'Servis egasi sifatida\nro\'yxatdan o\'tish'
                      : 'Telefon raqamingizni\nkiriting',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.25),
                ),
                const SizedBox(height: 10),
                const Text('Tasdiqlash kodi SMS orqali yuboriladi.',
                    style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 26),
                LiquidGlass(
                  radius: 18,
                  tintOpacity: 0.75,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                        decoration: const BoxDecoration(
                            border: Border(
                                right: BorderSide(color: AppColors.border))),
                        child: const Text('+998',
                            style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [_UzPhoneFormatter()],
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _continue(),
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                                hintText: '90 123 45 67',
                                border: InputBorder.none,
                                isCollapsed: true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                GlassGradientButton(
                  label: 'Davom etish',
                  isLoading: _isLoading,
                  onPressed: _digits.length == 9 ? _continue : null,
                ),
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 14.5, color: AppColors.textSecondary),
                        children: [
                          TextSpan(text: 'Hisobingiz bormi? '),
                          TextSpan(
                              text: 'Kirish',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
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

// ========================================================================
// 3. OTP SCREEN
// ========================================================================

class OtpScreen extends StatefulWidget {
  final String phone;
  final bool isServiceOwner;
  const OtpScreen(
      {super.key, required this.phone, this.isServiceOwner = false});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _secondsLeft = 45;
  Timer? _timer;
  bool _isVerifying = false;
  String? _error;

  String get _code => _controller.text;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
    _controller.addListener(() {
      setState(() => _error = null);
      if (_controller.text.length == 4) _verify();
    });
  }

  Future<void> _verify() async {
    setState(() => _isVerifying = true);
    final result =
        await ApiService.verifyOtp(widget.phone.replaceAll(' ', ''), _code);
    if (!mounted) return;
    setState(() => _isVerifying = false);
    if (result['success'] != true) {
      setState(() => _error =
          result['message'] ?? 'Noto\'g\'ri kod, qayta urinib ko\'ring');
      _controller.clear();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(phone: widget.phone),
      ),
    );
  }

  void _startTimer() {
    _secondsLeft = 45;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _timerText {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                authBackButton(context),
                const SizedBox(height: 24),
                const Text('Tasdiqlash kodi',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Text('${widget.phone} raqamiga yuborilgan kodni kiriting.',
                    style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 30),
                GestureDetector(
                  onTap: () => _focusNode.requestFocus(),
                  child: Stack(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, (i) {
                          final filled = i < _code.length;
                          return Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: filled
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: filled ? 1.6 : 1),
                              boxShadow: [
                                BoxShadow(
                                  color: filled
                                      ? AppColors.primary.withOpacity(0.15)
                                      : Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              filled ? _code[i] : '',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary),
                            ),
                          );
                        }),
                      ),
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                counterText: '', border: InputBorder.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.error,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
                if (_isVerifying) ...[
                  const SizedBox(height: 16),
                  const Center(
                      child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.primary))),
                ],
                const SizedBox(height: 22),
                Center(
                  child: _secondsLeft > 0
                      ? RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 14.5, color: AppColors.textSecondary),
                            children: [
                              const TextSpan(text: 'Kod qayta yuborish: '),
                              TextSpan(
                                  text: _timerText,
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            ApiService.sendOtp(
                                widget.phone.replaceAll(' ', ''));
                            _startTimer();
                          },
                          child: const Text('Kodni qayta yuborish',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
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

// ========================================================================
// 3b. LOGIN OTP SCREEN (kirish - 2-bosqich SMS tasdiqlash)
// ========================================================================

class LoginOtpScreen extends StatefulWidget {
  final String phone;
  final String password;
  const LoginOtpScreen(
      {super.key, required this.phone, required this.password});
  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _secondsLeft = 45;
  Timer? _timer;
  bool _isVerifying = false;
  String? _error;

  String get _code => _controller.text;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
    _controller.addListener(() {
      setState(() => _error = null);
      if (_controller.text.length == 4) _verify();
    });
  }

  Future<void> _verify() async {
    setState(() => _isVerifying = true);
    final result = await ApiService.loginVerifyOtp(widget.phone, _code);
    if (!mounted) return;
    setState(() => _isVerifying = false);
    if (result['success'] != true) {
      setState(() => _error =
          result['message'] ?? 'Noto\'g\'ri kod, qayta urinib ko\'ring');
      _controller.clear();
      return;
    }
    final data = result['data'] as Map<String, dynamic>;
    await routeAfterAuth(context,
        role: data['role']?.toString() ?? 'user',
        userId: data['user_id'] as int);
  }

  void _startTimer() {
    _secondsLeft = 45;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _timerText {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                authBackButton(context),
                const SizedBox(height: 24),
                const Text('Kirishni tasdiqlash',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Text('${widget.phone} raqamiga yuborilgan kodni kiriting.',
                    style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 30),
                GestureDetector(
                  onTap: () => _focusNode.requestFocus(),
                  child: Stack(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(4, (i) {
                          final filled = i < _code.length;
                          return Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: filled
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: filled ? 1.6 : 1),
                              boxShadow: [
                                BoxShadow(
                                  color: filled
                                      ? AppColors.primary.withOpacity(0.15)
                                      : Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              filled ? _code[i] : '',
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary),
                            ),
                          );
                        }),
                      ),
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                                counterText: '', border: InputBorder.none),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(_error!,
                        style: const TextStyle(
                            fontSize: 13.5,
                            color: AppColors.error,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
                if (_isVerifying) ...[
                  const SizedBox(height: 16),
                  const Center(
                      child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.primary))),
                ],
                const SizedBox(height: 22),
                Center(
                  child: _secondsLeft > 0
                      ? RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 14.5, color: AppColors.textSecondary),
                            children: [
                              const TextSpan(text: 'Kod qayta yuborish: '),
                              TextSpan(
                                  text: _timerText,
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            ApiService.login(widget.phone, widget.password);
                            _startTimer();
                          },
                          child: const Text('Kodni qayta yuborish',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
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

// ========================================================================
// 4. PROFILE SETUP SCREEN
// ========================================================================

class ProfileSetupScreen extends StatefulWidget {
  final String phone;
  const ProfileSetupScreen({super.key, this.phone = ''});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  // Ilova endi faqat Toshkent shahri uchun ishlaydi - shahar tanlash
  // imkoniyati olib tashlandi, har doim "Toshkent" yuboriladi.
  final String _city = 'Toshkent';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? get _passwordError {
    if (_passwordController.text.isEmpty) return null;
    if (_passwordController.text.length < 6)
      return 'Parol kamida 6 ta belgidan iborat bo\'lishi kerak';
    return null;
  }

  String? get _confirmPasswordError {
    if (_confirmPasswordController.text.isEmpty) return null;
    if (_confirmPasswordController.text != _passwordController.text)
      return 'Parollar mos kelmadi';
    return null;
  }

  bool get _canContinue =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _passwordController.text.length >= 6 &&
      _confirmPasswordController.text == _passwordController.text;

  void _continue() {
    if (!_canContinue) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarSetupScreen(
          phone: widget.phone,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          password: _passwordController.text,
          city: _city,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                authBackButton(context),
                const SizedBox(height: 24),
                const Text('Profil ma\'lumotlari',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                const Text('O\'zingiz haqingizda ma\'lumotlarni kiriting.',
                    style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 26),
                const Text('Ism',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Asliddin',
                      prefixIcon: Icon(Icons.person_outline,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 20),
                const Text('Familiya',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastNameController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Xurramov',
                      prefixIcon: Icon(Icons.person_outline,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 20),
                const Text('Parol',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  keyboardType: TextInputType.visiblePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Kamida 6 ta belgi',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppColors.textMuted),
                    errorText: _passwordError,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textMuted),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Parolni tasdiqlang',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  keyboardType: TextInputType.visiblePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Parolni qayta kiriting',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppColors.textMuted),
                    errorText: _confirmPasswordError,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textMuted),
                      onPressed: () => setState(() =>
                          _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                GlassGradientButton(
                    label: 'Davom etish',
                    onPressed: _canContinue ? _continue : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// 5. CAR SETUP SCREEN
// ========================================================================

enum _FuelType { benzin, gaz, dizel, elektr }

extension on _FuelType {
  String get label {
    switch (this) {
      case _FuelType.benzin:
        return 'Benzin';
      case _FuelType.gaz:
        return 'Gaz';
      case _FuelType.dizel:
        return 'Dizel';
      case _FuelType.elektr:
        return 'Elektr';
    }
  }
}

class CarSetupScreen extends StatefulWidget {
  final String phone;
  final String firstName;
  final String lastName;
  final String password;
  final String city;

  const CarSetupScreen({
    super.key,
    required this.phone,
    required this.firstName,
    required this.lastName,
    required this.password,
    required this.city,
  });

  @override
  State<CarSetupScreen> createState() => _CarSetupScreenState();
}

class _CarSetupScreenState extends State<CarSetupScreen> {
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _plateController = TextEditingController();
  final _colorController = TextEditingController();
  _FuelType? _fuelType;
  bool _isLoading = false;

  static const _popularModels = ['Cobalt', 'Gentra', 'Malibu', 'Tracker'];

  @override
  void dispose() {
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  bool get _canFinish => _modelController.text.trim().isNotEmpty;

  Future<void> _finish() async {
    if (!_canFinish) return;
    setState(() => _isLoading = true);

    final fullName = '${widget.firstName} ${widget.lastName}';
    final result = await ApiService.register(
      phone: widget.phone.isNotEmpty
          ? widget.phone.replaceAll(' ', '')
          : '+998000000000',
      name: fullName,
      password: widget.password,
      city: widget.city,
      carModel: _modelController.text.trim(),
      plateNumber: _plateController.text.trim().isEmpty
          ? null
          : _plateController.text.trim(),
      year: int.tryParse(_yearController.text.trim()),
      color: _colorController.text.trim().isEmpty
          ? null
          : _colorController.text.trim(),
      fuelType: _fuelType?.label,
    );

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (!result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ??
                'Ro\'yxatdan o\'tmadi, qayta urinib ko\'ring'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final data = result['data'] as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', data['token']?.toString() ?? '');
    await prefs.setString('user_id', data['user_id'].toString());
    await prefs.setString('role', data['role']?.toString() ?? 'user');
    await prefs.setString('user_name', fullName);
    await prefs.setString('city', widget.city);
    await prefs.setString(
        'phone',
        widget.phone.isNotEmpty
            ? widget.phone.replaceAll(' ', '')
            : '+998000000000');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
  }

  Widget _fuelChip(_FuelType type) {
    final selected = _fuelType == type;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _fuelType = type),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border),
              ),
              alignment: Alignment.center,
              child: Text(
                type.label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                authBackButton(context),
                const SizedBox(height: 24),
                const Text('Mashinangizni qo\'shing',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                const Text(
                    'Xizmatlarni tezroq buyurtma qilish uchun mashina ma\'lumotlarini kiriting.',
                    style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 26),
                const Text('Model',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _modelController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Cobalt',
                      prefixIcon: Icon(Icons.directions_car_outlined,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _popularModels.map((m) {
                    return GestureDetector(
                      onTap: () => setState(() => _modelController.text = m),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                            color: AppColors.chipBg,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(m,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                const Text('Ishlab chiqarilgan yil',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _yearController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4)
                  ],
                  decoration: const InputDecoration(
                      hintText: 'Masalan: 2023',
                      prefixIcon: Icon(Icons.event_outlined,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 20),
                const Text('Davlat raqami',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      hintText: 'Masalan: 01 A 123 BC',
                      prefixIcon:
                          Icon(Icons.pin_outlined, color: AppColors.textMuted)),
                ),
                const SizedBox(height: 20),
                const Text('Yoqilg\'i turi',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Row(children: _FuelType.values.map(_fuelChip).toList()),
                const SizedBox(height: 20),
                const Text('Rangi (ixtiyoriy)',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _colorController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Oq',
                      prefixIcon: Icon(Icons.palette_outlined,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 32),
                GlassGradientButton(
                    label: 'Tayyor',
                    isLoading: _isLoading,
                    onPressed: _canFinish ? _finish : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// SERVICE OWNER SETUP
// ========================================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _obscure = true;
  String? _otpError;
  int _secondsLeft = 45;
  Timer? _timer;
  // 0 = telefon, 1 = SMS kod (telefonni tasdiqlash), 2 = parol
  int _step = 0;

  String get _digits => _phoneController.text.replaceAll(RegExp(r'\D'), '');
  String get _otpCode => _otpController.text;

  // Apple App Store Connect reviewerlari uchun maxsus test raqami:
  // bu raqam kiritilganda na SMS, na parol so'raladi - telefon raqami
  // kiritilishi bilanoq to'g'ridan-to'g'ri akkauntga kirib boriladi
  // (chunki reviewer haqiqiy SMS kodini ololmaydi, parol ekrani esa
  // ilova tekshiruvida keraksiz qo'shimcha qadam). Backend (/api/login)
  // ham shu raqam uchun SMS/OTP so'ramasdan tokenni darhol qaytaradi.
  static const String _appleReviewTestPhone = '+998889791007';
  static const String _appleReviewTestPassword = 'asliddin';

  Future<void> _autoLoginTestAccount(String phone) async {
    setState(() => _isSendingOtp = true);
    final result = await ApiService.login(phone, _appleReviewTestPassword);
    setState(() => _isSendingOtp = false);
    if (!mounted) return;
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Kirishda xatolik'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final data = result['data'] as Map<String, dynamic>;
    await routeAfterAuth(context,
        role: data['role']?.toString() ?? 'user',
        userId: data['user_id'] as int);
  }

  Future<void> _goToOtpStep() async {
    if (_digits.length < 9 || _isSendingOtp) return;
    final phone = _formatPhone(_phoneController.text);
    if (phone == _appleReviewTestPhone) {
      await _autoLoginTestAccount(phone);
      return;
    }
    setState(() => _isSendingOtp = true);
    final result = await ApiService.sendOtp(phone);
    setState(() => _isSendingOtp = false);
    if (!mounted) return;
    if (result['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'SMS yuborilmadi'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() {
      _step = 1;
      _otpController.clear();
      _otpError = null;
    });
    _startTimer();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _otpFocusNode.requestFocus());
  }

  Future<void> _verifyOtpStep() async {
    if (_otpCode.length != 4 || _isVerifyingOtp) return;
    setState(() {
      _isVerifyingOtp = true;
      _otpError = null;
    });
    final phone = _formatPhone(_phoneController.text);
    final result = await ApiService.verifyOtp(phone, _otpCode);
    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);
    if (result['success'] != true) {
      setState(() => _otpError =
          result['message'] ?? 'Noto\'g\'ri kod, qayta urinib ko\'ring');
      _otpController.clear();
      return;
    }
    _timer?.cancel();
    setState(() => _step = 2);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _passwordFocusNode.requestFocus());
  }

  void _backToPhoneStep() {
    _timer?.cancel();
    setState(() {
      _step = 0;
      _otpController.clear();
      _otpError = null;
      _passwordController.clear();
    });
  }

  void _backOneStep() {
    if (_step == 2) {
      setState(() {
        _step = 1;
        _passwordController.clear();
      });
    } else if (_step == 1) {
      _backToPhoneStep();
    } else {
      Navigator.pop(context);
    }
  }

  void _startTimer() {
    _secondsLeft = 45;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String get _timerText {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _login() async {
    if (_passwordController.text.isEmpty) return;
    setState(() => _isLoading = true);
    final phone = _formatPhone(_phoneController.text);
    final result = await ApiService.login(phone, _passwordController.text);
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (result['success']) {
      if (result['requiresOtp'] == true) {
        // Ehtiyot chorasi: agar tasdiqlash muddati o'tib ketgan bo'lsa,
        // server qayta SMS yuboradi - shu holat uchun eski ekran ishlatiladi.
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => LoginOtpScreen(
                  phone: phone, password: _passwordController.text)),
        );
        return;
      }
      final data = result['data'] as Map<String, dynamic>;
      await routeAfterAuth(context,
          role: data['role']?.toString() ?? 'user',
          userId: data['user_id'] as int);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Xatolik'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  String _formatPhone(String phone) {
    // Ro'yxatdan o'tishdagi bilan bir xil mantiq: foydalanuvchi faqat
    // 9 xonali mahalliy raqamni kiritadi (_UzPhoneFormatter buni cheklaydi),
    // shuning uchun har doim +998 old qo'shiladi. "998" bilan boshlanish
    // holatini alohida tekshirish shart emas edi va bu raqamni noto'g'ri
    // formatlab, login/registerdagi raqamlar mos kelmasligiga sabab bo'lardi.
    phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return '+998$phone';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Widget _stepBackButton() {
    return SizedBox(
      height: 40,
      width: 40,
      child: LiquidGlass(
        radius: 12,
        tintOpacity: 0.7,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _backOneStep,
            child: const Center(
              child: Icon(Icons.arrow_back_ios_new,
                  size: 16, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          const Icon(Icons.phone_iphone_rounded,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text('+998 ${_phoneController.text}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const Spacer(),
          GestureDetector(
            onTap: _backToPhoneStep,
            child: const Text('O\'zgartirish',
                style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stepBackButton(),
                const SizedBox(height: 24),
                const Text('Kirish',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                Text(
                  _step == 0
                      ? 'Akkauntingizga kirish uchun telefon raqamingizni kiriting.'
                      : _step == 1
                          ? '${_formatPhone(_phoneController.text)} raqamiga yuborilgan kodni kiriting.'
                          : 'Endi akkauntingiz paroli bilan tasdiqlang.',
                  style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      height: 1.45),
                ),
                const SizedBox(height: 26),
                if (_step == 0) ...[
                  const Text('Telefon raqam',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    inputFormatters: [_UzPhoneFormatter()],
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _goToOtpStep(),
                    decoration: const InputDecoration(
                        hintText: '90 123 45 67',
                        prefixIcon: Icon(Icons.phone_outlined,
                            color: AppColors.textMuted)),
                  ),
                  const SizedBox(height: 28),
                  GlassGradientButton(
                      label: 'Davom etish',
                      isLoading: _isSendingOtp,
                      onPressed: _digits.length == 9 ? _goToOtpStep : null),
                ] else if (_step == 1) ...[
                  _phoneChip(),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () => _otpFocusNode.requestFocus(),
                    child: Stack(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(4, (i) {
                            final filled = i < _otpCode.length;
                            return Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: filled
                                        ? AppColors.primary
                                        : AppColors.border,
                                    width: filled ? 1.6 : 1),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                filled ? _otpCode[i] : '',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary),
                              ),
                            );
                          }),
                        ),
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0,
                            child: TextField(
                              controller: _otpController,
                              focusNode: _otpFocusNode,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onChanged: (v) {
                                setState(() => _otpError = null);
                                if (v.length == 4) _verifyOtpStep();
                              },
                              decoration: const InputDecoration(
                                  counterText: '', border: InputBorder.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_otpError != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Text(_otpError!,
                          style: const TextStyle(
                              fontSize: 13.5,
                              color: AppColors.error,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                  if (_isVerifyingOtp) ...[
                    const SizedBox(height: 16),
                    const Center(
                        child: SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: AppColors.primary))),
                  ],
                  const SizedBox(height: 22),
                  Center(
                    child: _secondsLeft > 0
                        ? RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.textSecondary),
                              children: [
                                const TextSpan(text: 'Kod qayta yuborish: '),
                                TextSpan(
                                    text: _timerText,
                                    style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: _isSendingOtp ? null : _goToOtpStep,
                            child: const Text('Kodni qayta yuborish',
                                style: TextStyle(
                                    fontSize: 14.5,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                  ),
                ] else ...[
                  _phoneChip(),
                  const SizedBox(height: 20),
                  const Text('Parol',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscure,
                    keyboardType: TextInputType.visiblePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      hintText: 'Parolingizni kiriting',
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: AppColors.textMuted),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.textMuted),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  GlassGradientButton(
                    label: 'Kirish',
                    isLoading: _isLoading,
                    onPressed:
                        _passwordController.text.isNotEmpty ? _login : null,
                  ),
                ],
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WelcomeScreen())),
                    child: RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 14.5, color: AppColors.textSecondary),
                        children: [
                          TextSpan(text: 'Akkauntingiz yo\'qmi? '),
                          TextSpan(
                              text: 'Ro\'yxatdan o\'tish',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
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

// ========================================================================
// HOME SCREEN (MIJOZ) — bottom nav: Bosh sahifa / Buyurtmalar / Chat / Profil
// ========================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final _tabs = const [
    HomeTab(),
    OrdersTab(),
    ChatListTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(bottom: false, child: _tabs[_selectedIndex]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      (Icons.home_outlined, Icons.home_rounded, 'Bosh sahifa'),
      (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Buyurtmalar'),
      (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat'),
      (Icons.person_outline, Icons.person_rounded, 'Profil'),
    ];
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, bottomInset > 0 ? bottomInset + 8 : 16),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 26,
                offset: const Offset(0, 10)),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / items.length;
            return Stack(
              children: [
                // Tanlangan bo'limning haqiqiy Liquid Glass (blur + sheen)
                // pilli - ikki tugma orasida silliq sirg'alib o'tadi.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  top: 8,
                  bottom: 8,
                  left: segmentWidth * _selectedIndex,
                  width: segmentWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: LiquidGlass(
                      radius: 20,
                      blur: 18,
                      tintOpacity: 0.8,
                      shadow: [
                        BoxShadow(
                            color: AppColors.glassShadow,
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(items.length, (i) {
                      final selected = _selectedIndex == i;
                      final (outline, filled, label) = items[i];
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _selectedIndex = i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Icon(selected ? filled : outline,
                                  color: selected
                                      ? AppColors.textPrimary.withOpacity(0.88)
                                      : AppColors.textMuted,
                                  size: 23),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                child: selected
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(label,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary
                                                  .withOpacity(0.88),
                                            )),
                                      )
                                    : const SizedBox(height: 2),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---- Home tab ----------------------------------------------------------

// ---- Bosh sahifadagi 4 ta asosiy bo'lim (rasmga mos "feature card" to'ri) --
// Har biri o'z pastel rangidagi kvadratsimon karta: yuqorida sarlavha va
// qisqa izoh, pastda rangli aylana ichida strelka tugmasi, o'ng pastda esa
// bo'limga xos, qo'lda chizilgan "yumshoq 3D" illyustratsiya (tekis
// Material ikonka emas) - xarita ustidagi joylashuv belgisi, mashina,
// kublar to'plami va toj. 2x2 to'r shaklida joylashtirilgan.
class _HomeWheelActionsGrid extends StatelessWidget {
  final int userId;
  const _HomeWheelActionsGrid({required this.userId});

  @override
  Widget build(BuildContext context) {
    final items = <_WheelActionData>[
      _WheelActionData(
        title: 'Yaqin atrofdagi\nservislar',
        subtitle: 'Atrofingizdagi servislarni toping',
        icon: Icons.near_me_rounded,
        bgColors: const [Color(0xFFDCEBFF), Color(0xFFF3F7FF)],
        accent: const Color(0xFF3A7BFF),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NearbyServicesMapScreen())),
      ),
      _WheelActionData(
        title: 'Mashinalarim',
        subtitle: 'Avtomobilingiz haqida ma\'lumotlar',
        icon: Icons.directions_car_filled_rounded,
        bgColors: const [Color(0xFFD8F5E9), Color(0xFFF2FBF7)],
        accent: const Color(0xFF23B26D),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => MyCarsScreen(userId: userId))),
      ),
      _WheelActionData(
        title: 'Kategoriya\nbo\'yicha',
        subtitle: 'Xizmatlarni turkum bo\'yicha tanlang',
        icon: Icons.grid_view_rounded,
        bgColors: const [Color(0xFFFFE9CF), Color(0xFFFFF6EB)],
        accent: const Color(0xFFFF8A00),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PopularServicesScreen())),
      ),
      _WheelActionData(
        title: 'Premium\nservis',
        subtitle: 'VIP xizmatlar va imtiyozlar',
        icon: Icons.workspace_premium_rounded,
        bgColors: const [Color(0xFFEBE0FF), Color(0xFFF7F2FF)],
        accent: const Color(0xFF8B5CF6),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PremiumServiceScreen())),
      ),
    ];

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _WheelActionCard(data: items[0])),
            const SizedBox(width: 12),
            Expanded(child: _WheelActionCard(data: items[1])),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _WheelActionCard(data: items[2])),
            const SizedBox(width: 12),
            Expanded(child: _WheelActionCard(data: items[3])),
          ],
        ),
      ],
    );
  }
}

class _WheelActionData {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> bgColors;
  final Color accent;
  final VoidCallback onTap;
  _WheelActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bgColors,
    required this.accent,
    required this.onTap,
  });
}

// Bitta feature karta: yumshoq pastel gradient fon, yuqorida qalin
// sarlavha va kulrang izoh, pastda rangli aylana strelka tugmasi, o'ng
// pastda bo'limga xos qo'lda chizilgan illyustratsiya.
class _WheelActionCard extends StatefulWidget {
  final _WheelActionData data;
  const _WheelActionCard({required this.data});

  @override
  State<_WheelActionCard> createState() => _WheelActionCardState();
}

class _WheelActionCardState extends State<_WheelActionCard> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return GestureDetector(
      onTap: data.onTap,
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: 180,
          padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: data.bgColors,
            ),
            boxShadow: [
              BoxShadow(
                color: data.accent.withOpacity(0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Karta ichida, o'ng pastda - premium darajadagi, shisha
              // effektli (glassmorphism) dumaloq ikon-nishoncha: gradient fon,
              // yumshoq soya, yaltiroq shisha bezagi va aniq Material ikonka.
              Positioned(
                right: -6,
                bottom: -6,
                child: _PremiumIconBadge(icon: data.icon, accent: data.accent),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(
                    data.title,
                    maxLines: 2,
                    style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary.withOpacity(0.85),
                        height: 1.25),
                  ),
                  const Spacer(),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: data.accent.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: data.accent, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Har bir kartaning o'ng-past burchagidagi premium darajadagi ikon-nishoncha:
// aylana gradient fon (accent rangdan quyuqroq soyagacha), nozik shisha
// (glassmorphism) yaltirash bezagi, yumshoq rangli soya va markazda oq,
// aniq Material ikonka. Oldingi qo'lda chizilgan tekis illyustratsiyalar
// o'rniga hozirgi zamon fintech-ilovalariga xos "3D shisha" uslubi.
class _PremiumIconBadge extends StatelessWidget {
  final IconData icon;
  final Color accent;
  const _PremiumIconBadge({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(accent, Colors.white, 0.35)!;
    final dark = Color.lerp(accent, Colors.black, 0.18)!;

    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Pastdagi yumshoq, rangli "sochilgan yorug'lik" soyasi - ikonkaga
          // suzayotgandek hajm beradi.
          Positioned(
            bottom: -2,
            child: Container(
              width: 46,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: accent.withOpacity(0.28),
              ),
            ),
          ),
          // Asosiy dumaloq nishoncha - diagonal gradient + qatlamli soya bilan
          // porloq, "shisha shar" hissini beradi.
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [light, accent, dark],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.6),
                  blurRadius: 6,
                  offset: const Offset(-2, -2),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.5),
                width: 1.2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Yuqori chap burchakdagi shisha yaltirash chizig'i.
                Positioned(
                  top: 8,
                  left: 10,
                  child: Container(
                    width: 22,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.45),
                    ),
                  ),
                ),
                Icon(icon, color: Colors.white, size: 27),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Map<String, dynamic>> _categories = [];
  bool _loadingCategories = true;
  int _unreadNotifications = 0;
  Map<String, dynamic>?
      _pricing; // evakuator/benzin dastavka uchun global narxlar

  // Tepadagi 4 ta asosiy bo'lim (Yaqin atrofdagi servislar, Mashinalarim,
  // Kategoriya bo'yicha, Premium servis) endi ketma-ket almashinadigan
  // banner-karusel emas - barchasi bir vaqtning o'zida, mashina g'ildiragiga
  // o'xshash dumaloq tugmalar sifatida 2x2 to'r ko'rinishida ko'rsatiladi
  // (_HomeWheelActionsGrid orqali).
  int _userId = 0;

  static const _serviceIcons = {
    'evacuator': Icons.local_shipping_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'local_shipping': Icons.local_shipping_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'battery': Icons.battery_charging_full_rounded,
    'tire': Icons.tire_repair_rounded,
    'tech_support': Icons.build_rounded,
    'diagnostics': Icons.search_rounded,
    'oil_change': Icons.oil_barrel_rounded,
    'electrician': Icons.electrical_services_rounded,
    'engine': Icons.settings_rounded,
    'ac': Icons.ac_unit_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnreadCount();
    _loadPricing();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    if (!mounted) return;
    setState(() => _userId = id);
  }

  Future<void> _loadUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    if (userId == 0) return;
    final count = await ApiService.getUnreadNotificationsCount(userId);
    if (!mounted) return;
    setState(() => _unreadNotifications = count);
  }

  Future<void> _loadCategories() async {
    final result = await ApiService.getCategories();
    if (!mounted) return;
    setState(() {
      _loadingCategories = false;
      if (result['success'] == true) {
        _categories = (result['data'] as List).cast<Map<String, dynamic>>();
      }
    });
  }

  // Evakuator va benzin dastavka - admin katalogidagi oddiy xizmat turlaridan
  // farqli o'laroq alohida, global narxga ega (ServiceType.price'ga ega emas),
  // shuning uchun narxi /api/pricing'dan alohida olib, "Xizmat turlari"
  // ro'yxatida ko'rsatish uchun shu yerda saqlanadi.
  Future<void> _loadPricing() async {
    final result = await ApiService.getPricing();
    if (!mounted) return;
    setState(() => _pricing = result);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: AppColors.primary, size: 18),
                  SizedBox(width: 4),
                  Text('Toshkent shahri',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textMuted, size: 20),
                ],
              ),
              GestureDetector(
                onTap: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationsScreen()));
                  _loadUnreadCount();
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.notifications_none_rounded,
                          color: AppColors.textPrimary, size: 22),
                    ),
                    if (_unreadNotifications > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(10)),
                          constraints: const BoxConstraints(minWidth: 18),
                          child: Text(
                            _unreadNotifications > 9
                                ? '9+'
                                : '$_unreadNotifications',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _HomeWheelActionsGrid(userId: _userId),
          const SizedBox(height: 26),
          const Text('Xizmat turlari',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          // "Xizmat turlari" endi bosh sahifada 1 ta katta tugma - bosilganda
          // ichida mashina turi (Sedan / Krossover) bo'yicha to'liq xizmatlar
          // ro'yxati ochiladigan alohida sahifaga o'tadi.
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CarServiceTypesScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 5))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                        color: AppColors.primaryPale.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.build_rounded,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Xizmat turlarini ko\'rish',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        SizedBox(height: 3),
                        Text('Sedan va Krossover uchun narxlar',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          const Text('Qo\'shimcha xizmatlar',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          // Evakuator va benzin dastavka - "Qo'shimcha xizmatlar" ro'yxatida
          // eng yuqorida, narx va navigatsiya bilan ko'rsatiladi.
          Builder(
            builder: (context) {
              final items = _categories
                  .where((c) =>
                      (c['id'] as String? ?? '') == 'evacuator' ||
                      (c['id'] as String? ?? '') == 'fuel')
                  .toList()
                ..sort((a, b) => (a['id'] == 'evacuator' ? 0 : 1)
                    .compareTo(b['id'] == 'evacuator' ? 0 : 1));
              return Column(
                children:
                    items.map((c) => _buildServiceListItem(c)).toList(),
              );
            },
          ),
          // Moyka/zapravka manzillari - faqat joylashuv ko'rsatiladi (admin
          // kiritadi). Elektr dastavka/moyka chaqirish - admin belgilagan
          // bitta telefon raqamiga to'g'ridan-to'g'ri qo'ng'iroq qilinadi.
          _buildExtraServiceItem(
            icon: Icons.local_car_wash_rounded,
            label: 'Moyka manzillari',
            imageUrl: _pricing?['carwash_locations_image'] as String?,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PartnerLocationsScreen(
                        locationType: 'carwash',
                        title: 'Moyka manzillari'))),
          ),
          _buildExtraServiceItem(
            icon: Icons.ev_station_rounded,
            label: 'Zapravka manzillari',
            imageUrl: _pricing?['gasstation_locations_image'] as String?,
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PartnerLocationsScreen(
                        locationType: 'gasstation',
                        title: 'Zapravka manzillari'))),
          ),
          _buildExtraServiceItem(
            icon: Icons.electric_bolt_rounded,
            label: 'Elektr dastavka',
            imageUrl: _pricing?['electric_delivery_image'] as String?,
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _PhoneCallSheet(
                  title: 'Elektr dastavka',
                  subtitle: 'Elektr dastavka chaqirish uchun qo\'ng\'iroq qiling',
                  pricingField: 'electric_delivery_phone'),
            ),
          ),
          _buildExtraServiceItem(
            icon: Icons.local_car_wash_outlined,
            label: 'Moyka chaqirish',
            imageUrl: _pricing?['carwash_call_image'] as String?,
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _PhoneCallSheet(
                  title: 'Moyka chaqirish',
                  subtitle: 'Moyka chaqirish uchun qo\'ng\'iroq qiling',
                  pricingField: 'carwash_call_phone'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraServiceItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? imageUrl,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            CategoryIconImage(
              imageUrl: imageUrl,
              fallbackIcon: icon,
              size: 46,
              iconSize: 22,
              borderRadius: 13,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '';
    final n =
        price is num ? price.toInt() : int.tryParse(price.toString()) ?? 0;
    if (n <= 0) return '';
    return "${_formatNumber(n)} so'm";
  }

  String _formatNumber(num value) {
    final digits = value.toInt().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      if (i > 0 && fromEnd % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  Widget _buildServiceListItem(Map<String, dynamic> cat) {
    final iconName = cat['icon'] as String? ?? 'build';
    final icon = _serviceIcons[iconName] ?? Icons.build_rounded;
    final label = cat['name'] as String? ?? 'Xizmat';
    final id = cat['id'] as String? ?? '';

    // Evakuator/benzin dastavka narxi ServiceType katalogida emas, balki
    // admin belgilagan global narxlarda (/api/pricing) saqlanadi.
    String priceText;
    if (id == 'evacuator') {
      final price = (_pricing?['evacuator_price'] as num?)?.toDouble() ?? 0;
      priceText = price > 0 ? _formatPrice(price) : '';
    } else if (id == 'fuel') {
      final fee = (_pricing?['fuel_delivery_fee'] as num?)?.toDouble() ?? 0;
      priceText = fee > 0 ? _formatPrice(fee) : '';
    } else {
      priceText = _formatPrice(cat['price']);
    }

    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ServiceLocationChoiceScreen(
                  categoryId: id, categoryName: label))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            LazyCategoryIconImage(
              item: cat,
              fallbackIcon: icon,
              size: 46,
              iconSize: 22,
              borderRadius: 13,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            if (priceText.isNotEmpty) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  priceText,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}

// ---- Elektr dastavka / Moyka chaqirish - telefon raqamiga qo'ng'iroq ----
// Bularda ko'plab provayder emas, faqat admin belgilagan bitta raqam bor -
// shu sababli alohida chaqiruv/buyurtma oqimi kerak emas, faqat "Qo'ng'iroq
// qilish" tugmasi bilan pastdan chiqadigan varaq (bottom sheet) yetarli.
class _PhoneCallSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String pricingField; // 'electric_delivery_phone' | 'carwash_call_phone'
  const _PhoneCallSheet(
      {required this.title,
      required this.subtitle,
      required this.pricingField});

  @override
  State<_PhoneCallSheet> createState() => _PhoneCallSheetState();
}

class _PhoneCallSheetState extends State<_PhoneCallSheet> {
  bool _loading = true;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pricing = await ApiService.getPricing();
    if (!mounted) return;
    setState(() {
      _phone = (pricing?[widget.pricingField] as String?) ?? '+998770907394';
      _loading = false;
    });
  }

  Future<void> _call() async {
    if (_phone == null || _phone!.trim().isEmpty) return;
    final uri = Uri.parse('tel:${_phone!.trim()}');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = _phone != null && _phone!.trim().isNotEmpty;
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(
            22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: AppColors.primaryPale.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.phone_in_talk_rounded,
                  color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(widget.subtitle,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child:
                    CircularProgressIndicator(color: AppColors.primary),
              ))
            else if (!hasPhone)
              const Text(
                'Hozircha telefon raqami belgilanmagan. Iltimos keyinroq urinib ko\'ring.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
              )
            else ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(14)),
                child: Text(_phone!,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _call,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Qo\'ng\'iroq qilish',
                      style: TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Moyka / zapravka manzillari - faqat joylashuv (admin kiritadi) ----
// Bu sahifada foydalanuvchi faqat manzillar ro'yxatini ko'radi - chaqiruv,
// narx yoki buyurtma yo'q. Manzil ustiga bosilsa xaritada ochiladi.
class PartnerLocationsScreen extends StatefulWidget {
  final String locationType; // 'carwash' | 'gasstation'
  final String title;
  const PartnerLocationsScreen(
      {super.key, required this.locationType, required this.title});

  @override
  State<PartnerLocationsScreen> createState() =>
      _PartnerLocationsScreenState();
}

class _PartnerLocationsScreenState extends State<PartnerLocationsScreen> {
  final _mapController = MapController();
  List<Map<String, dynamic>> _locations = [];
  bool _loading = true;
  ll.LatLng _center = const ll.LatLng(39.6542, 66.9597);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final myLocation = await resolveCurrentLocation();
    if (myLocation != null) _center = myLocation;
    final data = await ApiService.getLocations(widget.locationType);
    if (!mounted) return;
    setState(() {
      _locations = data;
      _loading = false;
    });
    // Agar manzillar bo'lsa, xaritani birinchi manzilga markazlashtiramiz -
    // aks holda foydalanuvchining joriy joylashuvida qoladi.
    final withCoords = _locations.where(
        (l) => l['latitude'] != null && l['longitude'] != null).toList();
    if (withCoords.isNotEmpty) {
      final first = withCoords.first;
      _center = ll.LatLng((first['latitude'] as num).toDouble(),
          (first['longitude'] as num).toDouble());
    }
    _mapController.move(_center, withCoords.isNotEmpty ? 12 : 12);
  }

  void _openLocationCard(Map<String, dynamic> loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocationBottomSheet(
          location: loc, locationType: widget.locationType),
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.locationType == 'carwash'
        ? Icons.local_car_wash_rounded
        : Icons.ev_station_rounded;
    final withCoords = _locations
        .where((l) => l['latitude'] != null && l['longitude'] != null)
        .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.my_location_rounded,
                          color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter: _center, initialZoom: 12, maxZoom: 19),
                    children: [
                      osmTileLayer(),
                      MarkerLayer(
                        markers: [
                          for (final loc in withCoords)
                            Marker(
                              point: ll.LatLng(
                                  (loc['latitude'] as num).toDouble(),
                                  (loc['longitude'] as num).toDouble()),
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                onTap: () => _openLocationCard(loc),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2.5),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.25),
                                              blurRadius: 6)
                                        ],
                                      ),
                                      child: Icon(icon,
                                          color: Colors.white, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (_loading)
                    const Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(child: CircularProgressIndicator())),
                  if (!_loading && withCoords.isEmpty)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 40),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 16)
                            ]),
                        child: const Text(
                          'Hozircha xaritada manzil qo\'shilmagan',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                  // Manzillar soni bo'yicha pastki kichik yorliq - ro'yxatga
                  // aylantirmasdan, foydalanuvchiga nechta borligini eslatadi.
                  if (!_loading && withCoords.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4))
                            ]),
                        child: Row(
                          children: [
                            Icon(icon, color: AppColors.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${withCoords.length} ta manzil xaritada - belgi ustiga bosing',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
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

// Xaritadagi belgi bosilganda pastdan chiqadigan qisqa ma'lumot varag'i -
// manzil nomi, matnli manzili va yo'nalish olish uchun tashqi xarita
// ilovasini ochish tugmasi.
class _LocationBottomSheet extends StatelessWidget {
  final Map<String, dynamic> location;
  final String locationType;
  const _LocationBottomSheet(
      {required this.location, required this.locationType});

  Future<void> _openDirections() async {
    final lat = (location['latitude'] as num).toDouble();
    final lng = (location['longitude'] as num).toDouble();
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final icon = locationType == 'carwash'
        ? Icons.local_car_wash_rounded
        : Icons.ev_station_rounded;
    final address = location['address']?.toString() ?? '';
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                      color: AppColors.primaryPale.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(location['name']?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(address,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _openDirections,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.directions_rounded),
                label: const Text('Yo\'nalishni ko\'rish',
                    style:
                        TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- "Servislar kategoriya bo'yicha" sahifasi ---------------------------
// Ilgari bosh sahifadagi "Mashhur servislar" segmentida ko'rsatilgan
// ro'yxat endi shu alohida sahifaga ko'chirildi va yuqoridagi banner
// karuselidagi "Servislar kategoriya bo'yicha" tugmasi orqali ochiladi.
// Har bir servis kartasida endi shu servisning xaritadagi joylashuvini
// ko'rsatuvchi tugma ham mavjud.
class PopularServicesScreen extends StatefulWidget {
  const PopularServicesScreen({super.key});
  @override
  State<PopularServicesScreen> createState() => _PopularServicesScreenState();
}

class _PopularServicesScreenState extends State<PopularServicesScreen> {
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Reyting va baholar soniga qarab eng mashhurlari tepaga chiqariladi.
  Future<void> _load() async {
    setState(() => _loading = true);
    final loc = await resolveCurrentLocation();
    final lat = loc?.latitude ?? 39.6542;
    final lng = loc?.longitude ?? 66.9597;
    final result =
        await ApiService.getNearbyServices(latitude: lat, longitude: lng);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        final list = (result['data'] as List).cast<Map<String, dynamic>>();
        list.sort((a, b) {
          final ratingA = (a['rating'] as num?)?.toDouble() ?? 0;
          final ratingB = (b['rating'] as num?)?.toDouble() ?? 0;
          if (ratingB != ratingA) return ratingB.compareTo(ratingA);
          final reviewsA = (a['review_count'] as num?)?.toInt() ?? 0;
          final reviewsB = (b['review_count'] as num?)?.toInt() ?? 0;
          return reviewsB.compareTo(reviewsA);
        });
        _services = list.take(20).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      authBackButton(context),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('Servislar kategoriya bo\'yicha',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_services.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('Hozircha servislar mavjud emas',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textMuted)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _popularServiceCard(_services[i]),
                      childCount: _services.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Servis kartasi - nomi, manzili, reytingi va shu servisni xaritada
  // ko'rish uchun alohida tugma (NearbyServicesMapScreen'ga focusService
  // bilan o'tadi va shu servisning joylashuvini xaritada ko'rsatadi).
  Widget _popularServiceCard(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? 'Servis';
    final address = s['address']?.toString() ?? '';
    final rating = s['rating'];
    final reviewCount = s['review_count'];
    final logoUrl = s['logo_url'] as String?;
    final hasLogo = logoUrl != null && logoUrl.startsWith('data:');
    final hasLocation = s['latitude'] != null && s['longitude'] != null;
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ServiceDetailScreen(serviceId: s['id'] as int))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPale.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(14),
                    image: hasLogo
                        ? DecorationImage(
                            image: MemoryImage(
                                base64Decode(logoUrl.split(',').last)),
                            fit: BoxFit.contain)
                        : null,
                  ),
                  child: !hasLogo
                      ? const Icon(Icons.storefront_rounded,
                          color: AppColors.primary, size: 22)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 3),
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 2),
                        Text('${rating ?? 0}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${reviewCount ?? 0} ta baho',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
            if (hasLocation) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            NearbyServicesMapScreen(focusService: s))),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPale.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined,
                          size: 16, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Xaritada ko\'rish',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- "Premium servis" sahifasi -------------------------------------------
// Bosh sahifadagi banner karuselidagi 4-tugma orqali ochiladi. Premium
// servisning vazifasi: mijozning mashinasini turgan joyidan olib ketish,
// tanlangan avtoservislardan biriga yetkazib, ta'mirlattirish, so'ngra
// mashinani qaytadan mijoz ko'rsatgan manzilga olib borib qo'yish - ya'ni
// "eshikdan-eshikkacha" to'liq xizmat. Shu tavsif operator raqami bilan
// birga shu sahifada ko'rsatiladi.
class PremiumServiceScreen extends StatelessWidget {
  const PremiumServiceScreen({super.key});

  // Premium servis operatorining telefon raqami. Kerak bo'lsa shu yerdan
  // o'zgartiring.
  static const String _operatorPhone = '+998770907394';

  Future<void> _callOperator() async {
    final uri = Uri.parse('tel:$_operatorPhone');
    await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Premium servis',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: AppColors.primaryGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primary.withOpacity(0.32),
                                blurRadius: 26,
                                offset: const Offset(0, 14))
                          ]),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: Colors.white, size: 44),
                    ),
                    const SizedBox(height: 18),
                    const Text('Premium servis nima?',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Xizmat nima qilishini bosqichma-bosqich tushuntirish.
              _PremiumStep(
                number: '1',
                icon: Icons.directions_car_filled_rounded,
                title: 'Mashinani olib ketamiz',
                description:
                    'Siz ko\'rsatgan manzilga borib, mashinangizni o\'z vaqtida olib ketamiz - siz shu yerda kutib turishingiz shart emas.',
              ),
              _PremiumStep(
                number: '2',
                icon: Icons.build_circle_rounded,
                title: 'Servisga yetkazamiz va ta\'mirlatamiz',
                description:
                    'Mashinangizni tanlangan yoki eng mos avtoservislardan biriga olib borib, kerakli ta\'mirlash ishlarini bajartiramiz.',
              ),
              _PremiumStep(
                number: '3',
                icon: Icons.home_rounded,
                title: 'Joyiga qaytarib qo\'yamiz',
                description:
                    'Ta\'mirlash tugagach, mashinangizni qaytadan siz ko\'rsatgan manzilga olib borib qo\'yamiz - to\'liq "eshikdan-eshikkacha" xizmat.',
                isLast: true,
              ),
              const SizedBox(height: 26),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6))
                    ]),
                child: Column(
                  children: [
                    const Text('Premium servis operatori',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    const Text(
                      'Buyurtma berish, mashinangizni olib ketish vaqtini va servisni tanlash uchun operatorimizga qo\'ng\'iroq qiling',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    Text(_operatorPhone,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 18),
                    GlassGradientButton(
                      label: 'Qo\'ng\'iroq qilish',
                      onPressed: _callOperator,
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
}

// Premium servis tushuntirish sahifasidagi bosqichlardan biri.
class _PremiumStep extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String description;
  final bool isLast;
  const _PremiumStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.primaryPale.withOpacity(0.55),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: AppColors.primary, size: 19),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.border,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$number-bosqich: $title',
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 5),
                    Text(description,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Map tab -----------------------------------------------------------

class MapTab extends StatefulWidget {
  const MapTab({super.key});
  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final _mapController = MapController();
  ll.LatLng _center = const ll.LatLng(39.6542, 66.9597);
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final myLocation = await resolveCurrentLocation();
    if (myLocation != null) _center = myLocation;
    final result = await ApiService.getNearbyServices(
      latitude: _center.latitude,
      longitude: _center.longitude,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _services = (result['data'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
      _mapController.move(_center, 13);
    } else {
      setState(() => _loading = false);
    }
  }

  void _openServiceCard(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceBottomSheet(service: s),
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                      icon: const Icon(Icons.my_location_rounded,
                          color: AppColors.primary)),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter: _center, initialZoom: 13, maxZoom: 19),
                    children: [
                      osmTileLayer(),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _center,
                            width: 26,
                            height: 26,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 6)
                                ],
                              ),
                            ),
                          ),
                          for (final s in _services)
                            if (s['latitude'] != null && s['longitude'] != null)
                              Marker(
                                point: ll.LatLng(
                                    (s['latitude'] as num).toDouble(),
                                    (s['longitude'] as num).toDouble()),
                                width: 42,
                                height: 42,
                                child: GestureDetector(
                                  onTap: () => _openServiceCard(s),
                                  child: const Icon(Icons.location_on,
                                      color: AppColors.primaryDark, size: 42),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                  if (_loading)
                    const Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(child: CircularProgressIndicator())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceBottomSheet extends StatelessWidget {
  final Map<String, dynamic> service;
  const _ServiceBottomSheet({required this.service});

  // Evakuator va benzin dastavka — oldindan bron qilinadigan xizmat emas,
  // shuning uchun ular uchun "Bronlash" o'rniga to'g'ridan-to'g'ri
  // "Chaqirish" (qo'ng'iroq qilib, mijoz turgan joyga chaqirish) ko'rsatiladi.
  bool get _isCallOutOnly {
    final providerType = service['provider_type']?.toString() ?? 'auto_service';
    return providerType == 'evacuator' || providerType == 'fuel';
  }

  Future<void> _callOwner() async {
    final phone = service['phone']?.toString();
    if (phone == null || phone.isEmpty) return;
    try {
      final uri = Uri.parse('tel:$phone');
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 16),
          Text(service['name']?.toString() ?? 'Servis',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          if (service['address'] != null)
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(service['address'].toString(),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary))),
            ]),
          const SizedBox(height: 4),
          Row(children: [
            if (service['rating'] != null) ...[
              const Icon(Icons.star_rounded,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 2),
              Text('${service['rating']}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 10),
            ],
            if (service['distance'] != null)
              Text('${service['distance']} km',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 18),
          if (_isCallOutOnly)
            // Evakuator / benzin dastavka: bron yo'q — narxni ko'rsatib,
            // mijoz turgan joyga chaqirish so'rovini yuborish uchun.
            Row(
              children: [
                if (service['phone'] != null) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 56,
                    height: 56,
                    child: Material(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _callOwner,
                        child: const Center(
                            child: Icon(Icons.phone, color: AppColors.primary)),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: GlassGradientButton(
                    label: 'Chaqirish',
                    icon: Icons.local_shipping_rounded,
                    onPressed: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _CallOutRequestSheet(service: service),
                      );
                    },
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                if (service['phone'] != null) ...[
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    width: 56,
                    height: 56,
                    child: Material(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _callOwner,
                        child: const Center(
                            child: Icon(Icons.phone, color: AppColors.primary)),
                      ),
                    ),
                  ),
                ],
                Expanded(
                  child: GlassGradientButton(
                    label: 'Bronlash / Xizmatga yozilish',
                    onPressed: () {
                      if (!isAutoServiceOpenNow(service)) {
                        showServiceClosedDialog(context,
                            serviceName: service['name']?.toString());
                        return;
                      }
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderBookingScreen(
                              serviceName:
                                  service['name']?.toString() ?? 'Servis',
                              serviceId: service['id'] as int?,
                              category: service['name']?.toString() ?? 'Servis',
                            ),
                          ));
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// Evakuator/benzin dastavka uchun "Chaqirish" tugmasi bosilganda ochiladigan
// oyna: narxni (admin belgilagan global narxlardan) ko'rsatadi, benzin
// uchun litr miqdorini so'raydi, so'ngra chaqiruvni (Order) yaratib,
// kuzatuv ekraniga o'tkazadi. Bu yerda hech qanday sana/vaqt yoki "bron"
// so'zi ishlatilmaydi — bu darhol yuboriladigan chaqiruv.
class _CallOutRequestSheet extends StatefulWidget {
  final Map<String, dynamic> service;
  const _CallOutRequestSheet({required this.service});
  @override
  State<_CallOutRequestSheet> createState() => _CallOutRequestSheetState();
}

class _CallOutRequestSheetState extends State<_CallOutRequestSheet> {
  final _litersController = TextEditingController(text: '10');
  Map<String, dynamic>? _pricing;
  bool _loadingPricing = true;
  bool _submitting = false;
  bool _resolvingLocation = true;
  double? _latitude;
  double? _longitude;
  // Benzin dastavka uchun tanlangan benzin turi (masalan "ai92") - majburiy.
  String? _fuelType;
  // Evakuator/benzin dastavka uchun majburiy: true = Shoshilinch, false =
  // Shoshilinch emas, null = hali tanlanmagan.
  bool? _isUrgent;

  // Benzin turlari ro'yxati - id, ko'rinadigan nom va admin belgilagan narx.
  static const List<Map<String, String>> _fuelTypeOptions = [
    {'id': 'ai92', 'label': 'AI-92'},
    {'id': 'ai95', 'label': 'AI-95'},
    {'id': 'ai98', 'label': 'AI-98'},
    {'id': 'ai100', 'label': 'AI-100'},
    {'id': 'hyperfuel', 'label': 'HyperFuel'},
  ];

  double? _fuelTypePrice(String id) {
    if (_pricing == null) return null;
    return (_pricing!['fuel_price_$id'] as num?)?.toDouble();
  }

  bool get _isFuel => widget.service['provider_type']?.toString() == 'fuel';

  @override
  void initState() {
    super.initState();
    _load();
    _litersController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _litersController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pricing = await ApiService.getPricing();
    if (!mounted) return;
    setState(() {
      _pricing = pricing;
      _loadingPricing = false;
    });
    await _resolveLocation();
  }

  // Evakuator/benzin dastavka uchun joylashuv har doim yoqilgan bo'lishi
  // shart - shu orqali haydovchi/dastavkachi qayerga borishni biladi.
  // O'chiq bo'lsa, foydalanuvchidan uni yoqishni so'raymiz.
  Future<void> _resolveLocation() async {
    setState(() => _resolvingLocation = true);
    final loc = await resolveCurrentLocationRequired(context);
    if (!mounted) return;
    setState(() {
      _latitude = loc?.latitude;
      _longitude = loc?.longitude;
      _resolvingLocation = false;
    });
  }

  double? get _totalPrice {
    if (_pricing == null) return null;
    if (_isFuel) {
      if (_fuelType == null) return null;
      final liters = double.tryParse(_litersController.text.trim());
      if (liters == null || liters <= 0) return null;
      final fee = (_pricing!['fuel_delivery_fee'] as num?)?.toDouble() ?? 0;
      final perLiter = _fuelTypePrice(_fuelType!) ?? 0;
      return fee + liters * perLiter;
    }
    return (_pricing!['evacuator_price'] as num?)?.toDouble();
  }

  String _formatSom(double v) {
    final s = v.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf so\'m';
  }

  Future<void> _confirm() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    if (userId == 0) return;
    final serviceId = widget.service['id'] as int?;
    if (serviceId == null) return;

    setState(() => _submitting = true);
    final result = await ApiService.createOrder(
      userId: userId,
      serviceId: serviceId,
      category: widget.service['provider_type']?.toString() ??
          (_isFuel ? 'fuel' : 'evacuator'),
      userLatitude: _latitude,
      userLongitude: _longitude,
      liters: _isFuel ? double.tryParse(_litersController.text.trim()) : null,
      fuelType: _isFuel ? _fuelType : null,
      isUrgent: _isUrgent,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result['success'] == true) {
      final id =
          (result['data'] is Map) ? (result['data']['id'] as int?) : null;
      Navigator.pop(context);
      if (id != null) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: id)));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Chaqiruv yuborilmadi'),
            backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalPrice;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4))),
            ),
            const SizedBox(height: 16),
            Text(
              _isFuel ? 'Benzin dastavka chaqirish' : 'Evakuator chaqirish',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              widget.service['name']?.toString() ?? '',
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            if (_loadingPricing)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: CircularProgressIndicator()))
            else ...[
              if (_isFuel) ...[
                const Text('Necha litr kerak?',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _litersController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: 'litr',
                    filled: true,
                    fillColor: AppColors.chipBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Benzin turini tanlang',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _fuelTypeOptions.map((opt) {
                    final id = opt['id']!;
                    final selected = _fuelType == id;
                    final price = _fuelTypePrice(id);
                    return GestureDetector(
                      onTap: () => setState(() => _fuelType = id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary
                              : AppColors.chipBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(opt['label']!,
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.textPrimary)),
                            if (price != null)
                              Text('${_formatSom(price)}/litr',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: selected
                                          ? Colors.white.withOpacity(0.85)
                                          : AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_fuelType == null) ...[
                  const SizedBox(height: 6),
                  const Text('Benzin turini tanlash majburiy',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.error)),
                ],
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.primaryPale.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.payments_rounded,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isFuel
                            ? 'Yetkazib berish + benzin narxi'
                            : 'Chaqiruv narxi',
                        style: const TextStyle(
                            fontSize: 13.5, color: AppColors.textSecondary),
                      ),
                    ),
                    Text(
                      total != null ? _formatSom(total) : '—',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Chaqiruv turi',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isUrgent = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isUrgent == true
                              ? AppColors.error
                              : AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.error,
                              width: _isUrgent == true ? 0 : 1.2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt_rounded,
                                size: 18,
                                color: _isUrgent == true
                                    ? Colors.white
                                    : AppColors.error),
                            const SizedBox(width: 6),
                            Text('Shoshilinch',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _isUrgent == true
                                        ? Colors.white
                                        : AppColors.error)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isUrgent = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isUrgent == false
                              ? AppColors.success
                              : AppColors.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.success,
                              width: _isUrgent == false ? 0 : 1.2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 18,
                                color: _isUrgent == false
                                    ? Colors.white
                                    : AppColors.success),
                            const SizedBox(width: 6),
                            Text('Shoshilinch emas',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: _isUrgent == false
                                        ? Colors.white
                                        : AppColors.success)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_isUrgent == null) ...[
                const SizedBox(height: 6),
                const Text('Chaqiruv turini tanlash majburiy',
                    style: TextStyle(fontSize: 12, color: AppColors.error)),
              ],
              if (!_resolvingLocation &&
                  (_latitude == null || _longitude == null)) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_off_rounded,
                              color: AppColors.error, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Joylashuv o\'chirilgan',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Haydovchi qayerga borishni bilishi uchun GPS yoqilgan bo\'lishi shart.',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: GlassGradientButton(
                          label: 'Joylashuvni yoqish',
                          height: 40,
                          onPressed: _resolveLocation,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              GlassGradientButton(
                label: 'Chaqirishni tasdiqlash',
                isLoading: _submitting || _resolvingLocation,
                onPressed: (total == null ||
                        _latitude == null ||
                        _longitude == null ||
                        _isUrgent == null ||
                        (_isFuel && _fuelType == null))
                    ? null
                    : _confirm,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Orders tab --------------------------------------------------------

class OrdersTab extends StatefulWidget {
  const OrdersTab({super.key});
  @override
  State<OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<OrdersTab> {
  List<dynamic> _orders = [];
  bool _loading = true;
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    setState(() => _userId = id);
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (_userId == 0) return;
    setState(() => _loading = true);
    final result = await ApiService.getUserOrders(_userId);
    if (!mounted) return;
    setState(() {
      _orders = result['data'] ?? [];
      _loading = false;
    });
  }

  (String, Color) _statusInfo(String status) {
    switch (status) {
      case 'pending':
        return ("Kutilmoqda", AppColors.warning);
      case 'accepted':
        return ("Qabul qilindi", AppColors.primary);
      case 'on_way':
        return ("Yo'lda", AppColors.primary);
      case 'arrived':
        return ("Yetib keldi", AppColors.success);
      case 'completed':
        return ("Yakunlandi", AppColors.success);
      case 'cancelled':
        return ("Bekor qilindi", AppColors.error);
      default:
        return (status, AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Text('Buyurtmalarim',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_orders.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                              color: AppColors.primaryPale.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.receipt_long_rounded,
                              color: AppColors.primary, size: 38),
                        ),
                        const SizedBox(height: 18),
                        const Text('Hozircha buyurtmalar yo\'q',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        const Text(
                            'Xizmat tanlab birinchi buyurtmangizni bering',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final o = _orders[i] as Map<String, dynamic>;
                        final (label, color) =
                            _statusInfo(o['status'] as String? ?? 'pending');
                        return GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    OrderDetailScreen(orderId: o['id'] as int),
                              )),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
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
                                    Expanded(
                                      child: Text(
                                          o['service_name']?.toString() ??
                                              'Servis',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text(label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: color)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(o['category']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded,
                                        size: 14, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                        _formatDate(
                                            o['created_at']?.toString()),
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textMuted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _orders.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}

// ---- Chat list tab -----------------------------------------------------

class ChatListTab extends StatefulWidget {
  const ChatListTab({super.key});
  @override
  State<ChatListTab> createState() => _ChatListTabState();
}

class _ChatListTabState extends State<ChatListTab> {
  List<dynamic> _orders = [];
  bool _loading = true;
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    setState(() => _userId = id);
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (_userId == 0) return;
    setState(() => _loading = true);
    final result = await ApiService.getUserOrders(_userId);
    if (!mounted) return;
    // Faqat active buyurtmalarni ko'rsatamiz
    final all = result['data'] ?? [];
    final active = all.where((o) {
      final s = (o as Map<String, dynamic>)['status'] as String? ?? '';
      return s != 'completed' && s != 'cancelled';
    }).toList();
    setState(() {
      _orders = active;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrders,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Text('Chatlar',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_orders.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                              color: AppColors.primaryPale.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.chat_bubble_outline_rounded,
                              color: AppColors.primary, size: 38),
                        ),
                        const SizedBox(height: 18),
                        const Text('Hozircha chatlar yo\'q',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        const Text(
                            'Faol buyurtmalar bo\'yicha chatlar shu yerda ko\'rinadi',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final o = _orders[i] as Map<String, dynamic>;
                        return GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                    orderId: o['id'] as int,
                                    serviceName:
                                        o['service_name']?.toString() ??
                                            'Chat'),
                              )),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
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
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                      color: AppColors.primaryPale
                                          .withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.chat_rounded,
                                      color: AppColors.primary, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          o['service_name']?.toString() ??
                                              'Servis',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                      const SizedBox(height: 3),
                                      Text(
                                          'Buyurtma #${o['id']} — ${o['category'] ?? ''}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded,
                                    size: 14, color: AppColors.textMuted),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _orders.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Profile tab -------------------------------------------------------

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String _name = 'Foydalanuvchi';
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('user_name') ?? 'Foydalanuvchi';
      _userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.primaryPale,
                AppColors.primaryPale.withOpacity(0.4)
              ]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(_name,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 28),
          _menuItem(Icons.person_outline, 'Profilni tahrirlash', () async {
            final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProfileEditScreen(currentName: _name)));
            if (updated == true) _loadProfile();
          }),
          _menuItem(Icons.lock_outline, 'Parolni o\'zgartirish', () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ChangePasswordScreen(userId: _userId)));
          }),
          _menuItem(
              Icons.favorite_border,
              'Sevimlilar',
              () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => FavoritesScreen(userId: _userId)))),
          _menuItem(Icons.history_rounded, 'Buyurtmalar tarixi', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrderHistoryScreen()));
          }),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Material(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _logout,
                child: const Center(
                    child: Text('Chiqish',
                        style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 15))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: AppColors.primaryPale.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        title: Text(title,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: AppColors.textMuted),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// ========================================================================
// PROFILE EDIT SCREEN
// ========================================================================

class ProfileEditScreen extends StatefulWidget {
  final String currentName;
  const ProfileEditScreen({super.key, required this.currentName});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.currentName);
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ismingizni kiriting'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone') ?? '';
    final result = await ApiService.updateUserProfile(phone, name);
    setState(() => _isSaving = false);
    if (!mounted) return;

    if (!result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(result['message'] ?? 'Saqlanmadi, qayta urinib ko\'ring'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    await prefs.setString('user_name', name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Profil yangilandi'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating),
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Text('Profilni tahrirlash',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.primaryPale,
                      AppColors.primaryPale.withOpacity(0.4)
                    ]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person,
                      size: 40, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 28),
              const Text('Ism va familiya',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Ismingizni kiriting',
                    prefixIcon:
                        Icon(Icons.person_outline, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 32),
              GlassGradientButton(
                  label: 'Saqlash', isLoading: _isSaving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// CHANGE PASSWORD SCREEN — foydalanuvchi, servis egasi va admin uchun ham
// ishlatiladigan umumiy backend endpointga murojaat qiladi.
// ========================================================================

class ChangePasswordScreen extends StatefulWidget {
  final int userId;
  const ChangePasswordScreen({super.key, required this.userId});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  String? _error;

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
    final result =
        await ApiService.changePassword(widget.userId, oldPass, newPass);
    setState(() => _isSaving = false);
    if (!mounted) return;

    if (!result['success']) {
      setState(() => _error = result['message'] ?? 'Parol o\'zgartirilmadi');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Parol muvaffaqiyatli o\'zgartirildi'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Text('Parolni o\'zgartirish',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 28),
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
              if (_error != null) ...[
                Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 13.5)),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
              GlassGradientButton(
                  label: 'Saqlash', isLoading: _isSaving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// MY CARS SCREEN
// ========================================================================

class MyCarsScreen extends StatefulWidget {
  final int userId;
  const MyCarsScreen({super.key, required this.userId});
  @override
  State<MyCarsScreen> createState() => _MyCarsScreenState();
}

class _MyCarsScreenState extends State<MyCarsScreen> {
  List<dynamic> _cars = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ApiService.getUserCars(widget.userId);
    if (!mounted) return;
    setState(() {
      _cars = result['data'] ?? [];
      _loading = false;
    });
  }

  void _openAddCarSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCarSheet(userId: widget.userId, onAdded: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddCarSheet,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      authBackButton(context),
                      const SizedBox(width: 14),
                      const Text('Mashinalarim',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_cars.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                              color: AppColors.primaryPale.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.directions_car_outlined,
                              color: AppColors.primary, size: 38),
                        ),
                        const SizedBox(height: 18),
                        const Text('Hozircha mashina qo\'shilmagan',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        const Text(
                            'Pastdagi + tugmasi orqali mashina qo\'shing',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final c = _cars[i] as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
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
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                    color:
                                        AppColors.primaryPale.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(14)),
                                child: const Icon(Icons.directions_car_rounded,
                                    color: AppColors.primary, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c['model']?.toString() ?? 'Mashina',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary)),
                                    const SizedBox(height: 3),
                                    Text(
                                      [
                                        if (c['year'] != null)
                                          c['year'].toString(),
                                        if (c['color'] != null &&
                                            c['color'].toString().isNotEmpty)
                                          c['color'].toString(),
                                        if (c['plate_number'] != null &&
                                            c['plate_number']
                                                .toString()
                                                .isNotEmpty)
                                          c['plate_number'].toString(),
                                      ].join(' • '),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (c['is_primary'] == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color:
                                          AppColors.primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(20)),
                                  child: const Text('Asosiy',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary)),
                                ),
                            ],
                          ),
                        );
                      },
                      childCount: _cars.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCarSheet extends StatefulWidget {
  final int userId;
  final VoidCallback onAdded;
  const _AddCarSheet({required this.userId, required this.onAdded});
  @override
  State<_AddCarSheet> createState() => _AddCarSheetState();
}

class _AddCarSheetState extends State<_AddCarSheet> {
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _plateController = TextEditingController();
  final _colorController = TextEditingController();
  _FuelType? _fuelType;
  bool _isSaving = false;

  @override
  void dispose() {
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final model = _modelController.text.trim();
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mashina modelini kiriting'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }
    setState(() => _isSaving = true);
    final result = await ApiService.addCar(
      userId: widget.userId,
      model: model,
      plateNumber: _plateController.text.trim().isEmpty
          ? null
          : _plateController.text.trim(),
      year: int.tryParse(_yearController.text.trim()),
      color: _colorController.text.trim().isEmpty
          ? null
          : _colorController.text.trim(),
      fuelType: _fuelType?.label,
    );
    setState(() => _isSaving = false);
    if (!mounted) return;

    if (!result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Mashina qo\'shilmadi'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
      return;
    }

    widget.onAdded();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 18),
              const Text('Mashina qo\'shish',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 18),
              const Text('Model',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _modelController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Masalan: Cobalt',
                    prefixIcon: Icon(Icons.directions_car_outlined,
                        color: AppColors.textMuted)),
              ),
              const SizedBox(height: 16),
              const Text('Ishlab chiqarilgan yil',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _yearController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4)
                ],
                decoration: const InputDecoration(
                    hintText: 'Masalan: 2023',
                    prefixIcon:
                        Icon(Icons.event_outlined, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 16),
              const Text('Davlat raqami',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _plateController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    hintText: 'Masalan: 01 A 123 BC',
                    prefixIcon:
                        Icon(Icons.pin_outlined, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 16),
              const Text('Rangi (ixtiyoriy)',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: _colorController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    hintText: 'Masalan: Oq',
                    prefixIcon: Icon(Icons.palette_outlined,
                        color: AppColors.textMuted)),
              ),
              const SizedBox(height: 16),
              const Text('Yoqilg\'i turi',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _FuelType.values.map((type) {
                  final selected = _fuelType == type;
                  return GestureDetector(
                    onTap: () => setState(() => _fuelType = type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : AppColors.chipBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(type.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppColors.textPrimary)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              GlassGradientButton(
                  label: 'Saqlash', isLoading: _isSaving, onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// ORDER HISTORY SCREEN
// ========================================================================

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});
  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    await _loadOrders(id);
  }

  Future<void> _loadOrders([int? userId]) async {
    final prefs = await SharedPreferences.getInstance();
    final id = userId ?? int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    if (id == 0) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final result = await ApiService.getUserOrders(id);
    if (!mounted) return;
    final all = List<dynamic>.from(result['data'] ?? []);
    all.sort((a, b) => (b['created_at']?.toString() ?? '')
        .compareTo(a['created_at']?.toString() ?? ''));
    setState(() {
      _orders = all;
      _loading = false;
    });
  }

  (String, Color) _statusInfo(String status) {
    switch (status) {
      case 'pending':
        return ("Kutilmoqda", AppColors.warning);
      case 'accepted':
        return ("Qabul qilindi", AppColors.primary);
      case 'on_way':
        return ("Yo'lda", AppColors.primary);
      case 'arrived':
        return ("Yetib keldi", AppColors.success);
      case 'completed':
        return ("Yakunlandi", AppColors.success);
      case 'cancelled':
        return ("Bekor qilindi", AppColors.error);
      default:
        return (status, AppColors.textSecondary);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadOrders(),
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      authBackButton(context),
                      const SizedBox(width: 14),
                      const Text('Buyurtmalar tarixi',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_orders.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                              color: AppColors.primaryPale.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.history_rounded,
                              color: AppColors.primary, size: 38),
                        ),
                        const SizedBox(height: 18),
                        const Text('Hozircha buyurtmalar tarixi yo\'q',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final o = _orders[i] as Map<String, dynamic>;
                        final (label, color) =
                            _statusInfo(o['status'] as String? ?? 'pending');
                        return GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    OrderDetailScreen(orderId: o['id'] as int),
                              )),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
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
                                    Expanded(
                                      child: Text(
                                          o['service_name']?.toString() ??
                                              'Servis',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color: color.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: Text(label,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: color)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(o['category']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded,
                                        size: 14, color: AppColors.textMuted),
                                    const SizedBox(width: 4),
                                    Text(
                                        _formatDate(
                                            o['created_at']?.toString()),
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            color: AppColors.textMuted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _orders.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// SERVICE SELECTION SCREEN
// ========================================================================

// ========================================================================
// CATEGORY SERVICES SCREEN — foydalanuvchi bosh ekrandan bir xizmat turini
// tanlaganda, aynan shu turni taklif qiladigan (yoqib qo'ygan) avtoservislar
// shu yerda ro'yxat qilinadi.
// ========================================================================

// ========================================================================
// SERVICE LOCATION CHOICE SCREEN
// Bitta xizmat turi tanlangandan keyin, mijoz albatta ikki usuldan birini
// tanlashi kerak: xarita orqali (eng yaqinini ko'rish) yoki reyting bo'yicha.
// ========================================================================

class ServiceLocationChoiceScreen extends StatelessWidget {
  final String categoryId;
  final String categoryName;
  const ServiceLocationChoiceScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(categoryName,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Text('Servis joyini qanday tanlaysiz?',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text(
                  'Davom etish uchun quyidagi ikki usuldan birini tanlang',
                  style: TextStyle(
                      fontSize: 13.5, color: AppColors.textSecondary)),
              const SizedBox(height: 26),
              _choiceCard(
                context,
                icon: Icons.map_rounded,
                title: 'Xarita orqali tanlash',
                subtitle:
                    'Yaqin atrofdagi servislarni xaritada ko\'ring va eng yaqinini tanlang',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NearbyServicesMapScreen(
                          categoryId: categoryId.isEmpty ? null : categoryId),
                    )),
              ),
              const SizedBox(height: 16),
              _choiceCard(
                context,
                icon: Icons.star_rounded,
                title: 'Reyting bo\'yicha tanlash',
                subtitle:
                    'Eng yuqori baholangan servislar ro\'yxatidan tanlang',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryServicesScreen(
                          categoryId: categoryId, categoryName: categoryName),
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: AppColors.primaryPale.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: AppColors.primary, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ========================================================================
// CAR SERVICE TYPES SCREEN — "Xizmat turlari" bosh sahifadagi tugma orqali
// shu yerga o'tiladi. Tepada 2 ta mashina turi (Sedan / Krossov) tugmasi,
// pastda esa tanlangan turga tegishli barcha xizmatlar va narxlari
// ro'yxati ko'rsatiladi (admin bergan narxnoma asosida).
// ========================================================================


class CarServiceTypesScreen extends StatefulWidget {
  const CarServiceTypesScreen({super.key});
  @override
  State<CarServiceTypesScreen> createState() => _CarServiceTypesScreenState();
}

class _CarServiceTypesScreenState extends State<CarServiceTypesScreen> {
  String _selectedCar = 'Sedan';
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;
  List<Map<String, dynamic>> _allItems = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Xizmat turlari endi admin boshqaradigan katalogdan (ServiceType) real
  // vaqtda olinadi - admin bironta xizmatni qo'shsa/tahrirlasa/o'chirsa,
  // bu yerda darhol aks etadi. "evacuator"/"fuel"/"auto_service" - alohida
  // bo'limlar, shu sababli bu ro'yxatga kirmaydi.
  Future<void> _load() async {
    final result = await ApiService.getCategories();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _allItems = (result['data'] as List)
            .cast<Map<String, dynamic>>()
            .where((c) {
              final id = c['id'] as String? ?? '';
              return id != 'evacuator' && id != 'fuel' && id != 'auto_service';
            })
            .toList();
      }
    });
  }

  String _formatPrice(num price) {
    final s = price.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf so\'m';
  }

  @override
  Widget build(BuildContext context) {
    // Sedan va Krossover uchun narxlar admin panelida alohida-alohida
    // belgilanadi (price_sedan / price_crossover); ro'yxat bir xil, lekin
    // har bir xizmat qatorida tanlangan mashina turiga mos narx ko'rsatiladi.
    final items = _query.isEmpty
        ? _allItems
        : _allItems
            .where((it) =>
                (it['name'] as String? ?? '').toLowerCase().contains(_query))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Text('Xizmat turlari',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  Expanded(child: _carTypeButton('Sedan')),
                  const SizedBox(width: 12),
                  Expanded(child: _carTypeButton('Krossover')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(16)),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Qidirish',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 15),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: AppColors.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : items.isEmpty
                      ? const Center(
                          child: Text('Hech narsa topilmadi',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 14)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _serviceRow(items[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carTypeButton(String car) {
    final selected = _selectedCar == car;
    return GestureDetector(
      onTap: () => setState(() => _selectedCar = car),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Center(
          child: Text(car,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textPrimary)),
        ),
      ),
    );
  }

  Widget _serviceRow(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? 'Xizmat';
    // Tanlangan mashina turiga (Sedan / Krossover) qarab mos narx ko'rsatiladi.
    final price = _selectedCar == 'Krossover'
        ? ((item['price_crossover'] as num?) ?? 0)
        : ((item['price_sedan'] as num?) ?? (item['price'] as num?) ?? 0);
    final priceText = price > 0 ? _formatPrice(price) : '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ServiceLocationChoiceScreen(
                categoryId: 'auto_service', categoryName: name)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            LazyCategoryIconImage(
              item: item,
              fallbackIcon: Icons.build_rounded,
              size: 46,
              iconSize: 22,
              borderRadius: 13,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                priceText,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- All services screen (full list, iOS style, icon based) -----------

class AllServicesScreen extends StatefulWidget {
  const AllServicesScreen({super.key});
  @override
  State<AllServicesScreen> createState() => _AllServicesScreenState();
}

class _AllServicesScreenState extends State<AllServicesScreen> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  static const _serviceIcons = {
    'evacuator': Icons.local_shipping_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'local_shipping': Icons.local_shipping_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'battery': Icons.battery_charging_full_rounded,
    'tire': Icons.tire_repair_rounded,
    'tech_support': Icons.build_rounded,
    'diagnostics': Icons.search_rounded,
    'oil_change': Icons.oil_barrel_rounded,
    'electrician': Icons.electrical_services_rounded,
    'engine': Icons.settings_rounded,
    'ac': Icons.ac_unit_rounded,
  };

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await ApiService.getCategories();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _categories = (result['data'] as List)
            .cast<Map<String, dynamic>>()
            .where((c) => c['id'] != 'auto_service')
            .toList();
        _filtered = _categories;
      }
    });
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _categories
          : _categories
              .where(
                  (c) => (c['name'] as String? ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  String _formatPrice(num price) {
    final s = price.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf so\'m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Text('Xizmat turlari',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(16)),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Qidirish',
                    hintStyle:
                        TextStyle(color: AppColors.textMuted, fontSize: 15),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: AppColors.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _filtered.isEmpty
                      ? const Center(
                          child: Text('Hech narsa topilmadi',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 14)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 110),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            return _AnimatedListItem(
                                index: i, child: _serviceRow(_filtered[i]));
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceRow(Map<String, dynamic> cat) {
    final iconName = cat['icon'] as String? ?? 'build';
    final icon = _serviceIcons[iconName] ?? Icons.build_rounded;
    final name = cat['name'] as String? ?? 'Xizmat';
    final id = cat['id'] as String? ?? '';
    final price = cat['price'];

    return _PressableCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ServiceLocationChoiceScreen(
                categoryId: id, categoryName: name)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            LazyCategoryIconImage(
              item: cat,
              fallbackIcon: icon,
              size: 48,
              iconSize: 24,
              borderRadius: 14,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 10),
            if (price != null)
              Text(_formatPrice(price as num),
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success))
            else
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// iOS-style press scale wrapper for tappable cards
class _PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressableCard({required this.child, required this.onTap});
  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  double _scale = 1.0;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) => setState(() => _scale = 1.0),
      onTapCancel: () => setState(() => _scale = 1.0),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// Staggered fade + slide entrance animation for list items
class _AnimatedListItem extends StatelessWidget {
  final int index;
  final Widget child;
  const _AnimatedListItem({required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 30).clamp(0, 260)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
              offset: Offset(0, (1 - value) * 16), child: child),
        );
      },
      child: child,
    );
  }
}

class CategoryServicesScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  const CategoryServicesScreen(
      {super.key, required this.categoryId, required this.categoryName});

  @override
  State<CategoryServicesScreen> createState() => _CategoryServicesScreenState();
}

class _CategoryServicesScreenState extends State<CategoryServicesScreen> {
  List<Map<String, dynamic>> _services = [];
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
    final loc = await resolveCurrentLocation();
    final result = await ApiService.getNearbyServices(
      latitude: loc?.latitude ?? 39.6542,
      longitude: loc?.longitude ?? 66.9597,
      category: widget.categoryId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _services = (result['data'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } else {
      setState(() {
        _error = result['message'] as String? ?? 'Servislar yuklanmadi';
        _loading = false;
      });
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(widget.categoryName,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppColors.textSecondary)))
                      : _services.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Bu xizmat turi bo\'yicha hozircha servis topilmadi',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppColors.primary,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: _services.length,
                                itemBuilder: (context, i) =>
                                    _providerCard(_services[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerCard(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ServiceDetailScreen(
                  serviceId: s['id'] as int,
                  initialCategoryName: widget.categoryName))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                  color: AppColors.primaryPale.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.storefront_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s['name']?.toString() ?? 'Servis',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(
                    s['address']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text('${s['rating'] ?? 0}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ],
                ),
                if (s['distance'] != null) ...[
                  const SizedBox(height: 2),
                  Text('${s['distance']} km',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceSelectionScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final int? serviceId;
  const ServiceSelectionScreen(
      {super.key,
      required this.categoryId,
      required this.categoryName,
      this.serviceId});

  @override
  State<ServiceSelectionScreen> createState() => _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState extends State<ServiceSelectionScreen> {
  int _selectedService = 0;
  List<Map<String, dynamic>> _services = [];
  bool _loading = true;
  List<Map<String, dynamic>> _topServices = [];
  bool _topLoading = true;

  static const _defaultItems = [
    ('Dvigatel diagnostikasi', Icons.speed_rounded, '120 000 so\'m', null),
    ('Yog\' va filtr almashtirish', Icons.oil_barrel_rounded, '100 000 so\'m',
        null),
    ('Tormoz tizimi tekshiruvi', Icons.disc_full_rounded, '80 000 so\'m',
        null),
    ('Xodovoy qismi ta\'miri', Icons.build_circle_rounded, '150 000 so\'mdan',
        null),
    (
      'Elektr tizimi ishlari',
      Icons.electrical_services_rounded,
      '120 000 so\'mdan',
      null
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.serviceId != null) {
      _loadServiceDetail();
    } else {
      setState(() => _loading = false);
      _loadTopServices();
    }
  }

  Future<void> _loadTopServices() async {
    setState(() => _topLoading = true);
    final loc = await resolveCurrentLocation();
    final result = await ApiService.getNearbyServices(
      latitude: loc?.latitude ?? 39.6542,
      longitude: loc?.longitude ?? 66.9597,
      category: widget.categoryId.isEmpty ? null : widget.categoryId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final all = (result['data'] as List).cast<Map<String, dynamic>>();
      all.sort((a, b) =>
          ((b['rating'] ?? 0) as num).compareTo((a['rating'] ?? 0) as num));
      setState(() {
        _topServices = all;
        _topLoading = false;
      });
    } else {
      setState(() => _topLoading = false);
    }
  }

  Future<void> _loadServiceDetail() async {
    final result = await ApiService.getServiceDetail(widget.serviceId!);
    if (!mounted) return;
    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;
      final cats = (data['categories'] as List?) ?? [];
      setState(() {
        _services = cats.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _services.isEmpty
        ? _defaultItems
        : _services
            .map((s) => (
                  s['category']?.toString() ?? 'Xizmat',
                  Icons.build_rounded,
                  s['price'] != null
                      ? '${s['price']} so\'m'
                      : 'Narx kelishiladi',
                  s['image_url'] as String?
                ))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  Text(widget.categoryName,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  if (widget.serviceId == null)
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => NearbyServicesMapScreen(
                                  categoryId: widget.categoryId.isEmpty
                                      ? null
                                      : widget.categoryId))),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: AppColors.chipBg,
                            borderRadius: BorderRadius.circular(12)),
                        child: Row(children: const [
                          Icon(Icons.map_outlined, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text('Xaritadan tanlash',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700))
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      children: [
                        const Text('Xizmatlar ro\'yxati',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 14),
                        for (int i = 0; i < items.length; i++)
                          _serviceRow(i, items[i]),
                        if (widget.serviceId == null) ...[
                          const SizedBox(height: 14),
                          const Text('Reytingi baland xizmatlar',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 10),
                          if (_topLoading)
                            const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary))
                          else if (_topServices.isEmpty)
                            const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                    'Bu hududda top xizmatlar topilmadi',
                                    style:
                                        TextStyle(color: AppColors.textMuted)))
                          else
                            for (final s in _topServices.take(5))
                              _providerRowForTop(s),
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GlassGradientButton(
                label: 'Davom etish',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderBookingScreen(
                        serviceName: widget.serviceId != null
                            ? widget.categoryName
                            : items[_selectedService].$1,
                        serviceId: widget.serviceId,
                        category: items[_selectedService].$1,
                      ),
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceRow(int i, (String, IconData, String, String?) item) {
    final (title, icon, price, imageUrl) = item;
    final selected = _selectedService == i;
    return GestureDetector(
      onTap: () => setState(() => _selectedService = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1),
          boxShadow: [
            BoxShadow(
                color: selected
                    ? AppColors.primary.withOpacity(0.12)
                    : Colors.black.withOpacity(0.02),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            CategoryIconImage(
              imageUrl: imageUrl,
              fallbackIcon: icon,
              size: 46,
              iconSize: 21,
              borderRadius: 13,
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
                  const SizedBox(height: 3),
                  Text(price,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected ? AppColors.primary : AppColors.textMuted,
                size: 22),
          ],
        ),
      ),
    );
  }

  Widget _providerRowForTop(Map<String, dynamic> s) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ServiceDetailScreen(
                  serviceId: s['id'] as int,
                  initialCategoryName: widget.categoryName))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ]),
        child: Row(
          children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: AppColors.primaryPale.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.storefront_rounded,
                    color: AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(s['name']?.toString() ?? 'Servis',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (s['address'] != null)
                    Text(s['address'].toString(),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12))
                ])),
            const SizedBox(width: 8),
            Column(children: [
              Row(children: [
                const Icon(Icons.star_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 4),
                Text('${s['rating'] ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w700))
              ]),
              if (s['distance'] != null)
                Text('${s['distance']} km',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted))
            ])
          ],
        ),
      ),
    );
  }
}

// ========================================================================
// NEARBY SERVICES MAP SCREEN
// ========================================================================

class NearbyServicesMapScreen extends StatefulWidget {
  final String? categoryId;
  // Berilsa, xarita to'g'ridan-to'g'ri shu servisga yo'nalish chizadi
  // (masalan buyurtma qabul qilingandan keyin "Servisga yo'nalish" tugmasidan).
  final Map<String, dynamic>? focusService;
  const NearbyServicesMapScreen(
      {super.key, this.categoryId, this.focusService});
  @override
  State<NearbyServicesMapScreen> createState() =>
      _NearbyServicesMapScreenState();
}

class _NearbyServicesMapScreenState extends State<NearbyServicesMapScreen> {
  static const ll.LatLng _defaultCenter = ll.LatLng(39.6542, 66.9597);

  final _mapController = MapController();
  ll.LatLng _center = _defaultCenter;
  List<Map<String, dynamic>> _services = [];
  Map<String, dynamic>? _selected;
  List<ll.LatLng> _routePoints = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _distanceKm(ll.LatLng a, ll.LatLng b) {
    const dist = ll.Distance();
    return dist.as(ll.LengthUnit.Kilometer, a, b);
  }

  // Sarlavha va tugma matni tanlangan turga (evakuator/benzin dastavka)
  // qarab o'zgaradi - boshqa turlar uchun umumiy "servis" so'zi qoladi.
  String get _screenTitle {
    if (widget.focusService != null) {
      return widget.focusService!['name']?.toString() ?? 'Servisga yo\'nalish';
    }
    switch (widget.categoryId) {
      case 'evacuator':
        return 'Yaqin atrofdagi evakuatorlar';
      case 'fuel':
        return 'Yaqin atrofdagi benzin dastavkachilar';
      default:
        return 'Yaqin atrofdagi servislar';
    }
  }

  String get _selectNearestLabel {
    switch (widget.categoryId) {
      case 'evacuator':
        return 'Eng yaqin evakuatorni tanlash';
      case 'fuel':
        return 'Eng yaqin benzin dastavkachini tanlash';
      default:
        return 'Eng yaqin servisni tanlash';
    }
  }

  // Tanlangan servisgacha bo'lgan yo'lni (ko'cha bo'ylab) yuklab, xaritada
  // to'g'ri chiziq o'rniga haqiqiy yo'nalishni chizish uchun.
  Future<void> _loadRouteTo(ll.LatLng dest) async {
    final points = await fetchRoadRoute(_center, dest);
    if (!mounted) return;
    setState(() => _routePoints = points);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final myLocation = await resolveCurrentLocation();
    if (myLocation != null) _center = myLocation;
    if (widget.focusService != null) {
      final lat = (widget.focusService!['latitude'] as num?)?.toDouble();
      final lng = (widget.focusService!['longitude'] as num?)?.toDouble();
      setState(() {
        _services = [widget.focusService!];
        _selected = widget.focusService;
        _loading = false;
      });
      if (lat != null && lng != null) {
        _mapController.move(ll.LatLng(lat, lng), 14);
        _loadRouteTo(ll.LatLng(lat, lng));
      }
      return;
    }
    final result = await ApiService.getNearbyServices(
      latitude: _center.latitude,
      longitude: _center.longitude,
      category: widget.categoryId,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _services = (result['data'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
      _mapController.move(_center, 13);
    } else {
      setState(() {
        _error = result['message'] as String? ?? 'Servislar yuklanmadi';
        _loading = false;
      });
    }
  }

  void _selectNearest() {
    if (_services.isEmpty) return;
    Map<String, dynamic>? nearest;
    double best = double.infinity;
    for (final s in _services) {
      if (s['latitude'] == null || s['longitude'] == null) continue;
      final p = ll.LatLng((s['latitude'] as num).toDouble(),
          (s['longitude'] as num).toDouble());
      final d = _distanceKm(_center, p);
      if (d < best) {
        best = d;
        nearest = s;
      }
    }
    if (nearest == null) return;
    setState(() => _selected = nearest);
    final p = ll.LatLng((nearest['latitude'] as num).toDouble(),
        (nearest['longitude'] as num).toDouble());
    _mapController.move(p, 14);
    _loadRouteTo(p);
    _openServiceCard(nearest);
  }

  void _openServiceCard(Map<String, dynamic> s) {
    setState(() => _selected = s);
    if (s['latitude'] != null && s['longitude'] != null) {
      _loadRouteTo(ll.LatLng((s['latitude'] as num).toDouble(),
          (s['longitude'] as num).toDouble()));
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceBottomSheet(service: s),
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(_screenTitle,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.my_location_rounded,
                          color: AppColors.primary)),
                ],
              ),
            ),
            if (widget.focusService == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: GlassGradientButton(
                    label: _selectNearestLabel,
                    icon: Icons.near_me_rounded,
                    height: 48,
                    onPressed: _services.isEmpty ? null : _selectNearest,
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                        initialCenter: _center, initialZoom: 13, maxZoom: 19),
                    children: [
                      osmTileLayer(),
                      if (_selected != null &&
                          _selected!['latitude'] != null &&
                          _selected!['longitude'] != null)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints.length >= 2
                                  ? _routePoints
                                  : [
                                      _center,
                                      ll.LatLng(
                                          (_selected!['latitude'] as num)
                                              .toDouble(),
                                          (_selected!['longitude'] as num)
                                              .toDouble()),
                                    ],
                              strokeWidth: 4,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _center,
                            width: 26,
                            height: 26,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.25),
                                      blurRadius: 6)
                                ],
                              ),
                            ),
                          ),
                          for (final s in _services)
                            if (s['latitude'] != null && s['longitude'] != null)
                              Marker(
                                point: ll.LatLng(
                                    (s['latitude'] as num).toDouble(),
                                    (s['longitude'] as num).toDouble()),
                                width: 42,
                                height: 42,
                                child: GestureDetector(
                                  onTap: () => _openServiceCard(s),
                                  child: const Icon(Icons.location_on,
                                      color: AppColors.primaryDark, size: 42),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                  if (_loading)
                    const Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(child: CircularProgressIndicator())),
                  if (_error != null)
                    Positioned(
                      top: 12,
                      left: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 8)
                            ]),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
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

// ========================================================================
// ORDER BOOKING SCREEN
// ========================================================================

class OrderBookingScreen extends StatefulWidget {
  final String serviceName;
  final int? serviceId;
  final String category;
  const OrderBookingScreen(
      {super.key,
      required this.serviceName,
      this.serviceId,
      required this.category});
  @override
  State<OrderBookingScreen> createState() => _OrderBookingScreenState();
}

class _OrderBookingScreenState extends State<OrderBookingScreen> {
  final _noteController = TextEditingController();
  bool _isSubmitting = false;
  bool _loadingLocation = true;
  double? _latitude;
  double? _longitude;
  DateTime? _scheduledAt;
  // 'now' - Hozir borish, 'scheduled' - Bron qilish
  String _orderType = 'now';

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  // Joylashuv buyurtma berish uchun majburiy: o'chiq bo'lsa yoqishni,
  // ruxsat berilmagan bo'lsa ruxsat so'raydi (resolveCurrentLocationRequired
  // orqali), foydalanuvchi rad etmaguncha yoki yoqmaguncha davom etmaydi.
  Future<void> _getLocation() async {
    setState(() => _loadingLocation = true);
    final loc = await resolveCurrentLocationRequired(context);
    if (!mounted) return;
    setState(() {
      _latitude = loc?.latitude;
      _longitude = loc?.longitude;
      _loadingLocation = false;
    });
  }

  Future<void> _submit() async {
    if (_orderType == 'scheduled' && _scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bron uchun sana va vaqtni tanlang'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    if (_latitude == null || _longitude == null) {
      // Joylashuv hali olinmagan - qayta so'raymiz (majburiy).
      await _getLocation();
      if (!mounted) return;
      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Buyurtma berish uchun joylashuvni yoqish shart'),
              backgroundColor: AppColors.error),
        );
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    if (userId == 0) return;

    setState(() => _isSubmitting = true);
    final result = await ApiService.createOrder(
      userId: userId,
      serviceId: widget.serviceId ?? 1,
      category: widget.category,
      description: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      userLatitude: _latitude,
      userLongitude: _longitude,
      orderType: _orderType,
      scheduledAt:
          _orderType == 'scheduled' ? _scheduledAt?.toIso8601String() : null,
    );
    setState(() => _isSubmitting = false);
    if (!mounted) return;

    if (result['success'] == true) {
      final id =
          (result['data'] is Map) ? (result['data']['id'] as int?) : null;
      if (id != null) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: id)),
            (r) => r.isFirst);
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  OrderStatusScreen(serviceName: widget.serviceName)),
          (r) => r.isFirst,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Buyurtma yaratilmadi'),
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Text('Buyurtma berish',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mapPreview(),
                    const SizedBox(height: 10),
                    _locationStatus(),
                    const SizedBox(height: 22),
                    _label('Servis'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border)),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_outlined,
                              color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(widget.serviceName,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('Xizmat'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border)),
                      child: Row(
                        children: [
                          const Icon(Icons.build_outlined,
                              color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(widget.category,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('Qachon borasiz?'),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: AppColors.chipBg,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _orderType = 'now'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _orderType == 'now'
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: _orderType == 'now'
                                      ? const [
                                          BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 6)
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.directions_run_rounded,
                                        size: 18,
                                        color: _orderType == 'now'
                                            ? AppColors.primary
                                            : AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text('Hozir borish',
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: _orderType == 'now'
                                                ? AppColors.textPrimary
                                                : AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _orderType = 'scheduled'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _orderType == 'scheduled'
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: _orderType == 'scheduled'
                                      ? const [
                                          BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 6)
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.calendar_month_rounded,
                                        size: 18,
                                        color: _orderType == 'scheduled'
                                            ? AppColors.primary
                                            : AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text('Bron qilish',
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: _orderType == 'scheduled'
                                                ? AppColors.textPrimary
                                                : AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_orderType == 'scheduled') ...[
                      const SizedBox(height: 18),
                      _label('Bron sanasi va vaqti'),
                      GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate:
                                DateTime.now().add(const Duration(days: 1)),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date == null) return;
                          final time = await showTimePicker(
                              context: context,
                              initialTime:
                                  const TimeOfDay(hour: 12, minute: 0));
                          if (time == null) return;
                          final dt = DateTime(date.year, date.month, date.day,
                              time.hour, time.minute);
                          setState(() => _scheduledAt = dt);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: _scheduledAt == null
                                    ? AppColors.error.withOpacity(0.4)
                                    : AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined,
                                  color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                    _scheduledAt == null
                                        ? 'Sanani va vaqtni tanlang'
                                        : '${_scheduledAt!.day.toString().padLeft(2, '0')}.${_scheduledAt!.month.toString().padLeft(2, '0')}.${_scheduledAt!.year} ${_scheduledAt!.hour.toString().padLeft(2, '0')}:${_scheduledAt!.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (_scheduledAt != null)
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _scheduledAt = null),
                                  child: const Icon(Icons.close,
                                      color: AppColors.textMuted),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    _label('Qo\'shimcha izoh (ixtiyoriy)'),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          hintText: 'Izoh qoldiring...',
                          alignLabelWithHint: true),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GlassGradientButton(
                label: 'Buyurtmani tasdiqlash',
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
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

  Widget _locationStatus() {
    if (_loadingLocation) {
      return const Row(
        children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary)),
          SizedBox(width: 8),
          Text('Joylashuv aniqlanmoqda...',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      );
    }
    if (_latitude == null || _longitude == null) {
      return GestureDetector(
        onTap: _getLocation,
        child: Row(
          children: [
            const Icon(Icons.location_off_rounded,
                size: 16, color: AppColors.error),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                  'Joylashuv o\'chiq. Buyurtma berish uchun majburiy - yoqish uchun bosing',
                  style: TextStyle(fontSize: 12.5, color: AppColors.error)),
            ),
          ],
        ),
      );
    }
    return const Row(
      children: [
        Icon(Icons.location_on_rounded, size: 16, color: AppColors.success),
        SizedBox(width: 6),
        Text('Joylashuv aniqlandi',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _mapPreview() {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: CustomPaint(size: Size.infinite, painter: _MapGridPainter()),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.primaryGradient),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 6))
              ],
            ),
            child: const Icon(Icons.location_on, color: Colors.white, size: 22),
          ),
          const Positioned(
              top: 30,
              right: 46,
              child: Icon(Icons.build_circle,
                  color: AppColors.textSecondary, size: 22)),
        ],
      ),
    );
  }
}

class _MapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 26) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ========================================================================
// ORDER STATUS SCREEN
// ========================================================================

class OrderStatusScreen extends StatelessWidget {
  final String serviceName;
  const OrderStatusScreen({super.key, required this.serviceName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context,
                      onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (r) => false)),
                  const SizedBox(width: 14),
                  const Text('Buyurtma holati',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: AppColors.primaryGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withOpacity(0.32),
                              blurRadius: 26,
                              offset: const Offset(0, 14))
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 32),
                          ),
                          const SizedBox(height: 16),
                          const Text('Buyurtmangiz qabul qilindi',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          const SizedBox(height: 8),
                          Text(
                              '$serviceName servis qabul qildi va ustaxonada\nishlar boshlangan',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  color: Colors.white70,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _timelineStep('Qabul qilindi', '14:30',
                        done: true, isFirst: true),
                    _timelineStep('Ustaga yuborildi', '14:32', done: true),
                    _timelineStep('Ishlar davom etmoqda', '14:45',
                        inProgress: true),
                    _timelineStep('Tugallandi', '—', isLast: true),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: LiquidGlass(
                  radius: 18,
                  tintOpacity: 0.75,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (r) => false),
                      child: const Center(
                        child: Text('Bosh sahifaga',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
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

  Widget _timelineStep(String title, String time,
      {bool done = false,
      bool inProgress = false,
      bool isFirst = false,
      bool isLast = false}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done
                      ? AppColors.primary
                      : (inProgress ? Colors.white : AppColors.chipBg),
                  border: inProgress
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 15)
                    : inProgress
                        ? Center(
                            child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle)))
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                      width: 2,
                      color: done
                          ? AppColors.primary.withOpacity(0.4)
                          : AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: done || inProgress
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        )),
                  ),
                  Text(time,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ========================================================================
// ORDER DETAIL SCREEN
// ========================================================================

class OrderDetailScreen extends StatefulWidget {
  final int orderId;
  const OrderDetailScreen({super.key, required this.orderId});
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  Timer? _poller;
  List<ll.LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  Future<void> _load() async {
    final result = await ApiService.getOrderDetail(widget.orderId);
    if (!mounted) return;
    setState(() {
      _order = result['data'] as Map<String, dynamic>?;
      _loading = false;
    });
    // Haydovchi va mijoz joylashuvi ma'lum bo'lsa - orasidagi yo'lni
    // (ko'cha bo'ylab) chizish uchun mini-xaritada ishlatiladi.
    final driverLoc = _order?['driver_location'] as Map<String, dynamic>?;
    final userLat = (_order?['user_latitude'] as num?)?.toDouble();
    final userLng = (_order?['user_longitude'] as num?)?.toDouble();
    if (driverLoc != null && userLat != null && userLng != null) {
      try {
        final driverPoint = ll.LatLng((driverLoc['lat'] as num).toDouble(),
            (driverLoc['lng'] as num).toDouble());
        final points =
            await fetchRoadRoute(driverPoint, ll.LatLng(userLat, userLng));
        if (!mounted) return;
        setState(() => _routePoints = points);
      } catch (_) {}
    }
  }

  (String, Color) _statusInfo(String status) {
    switch (status) {
      case 'pending':
        return ("Kutilmoqda", AppColors.warning);
      case 'accepted':
        return ("Qabul qilindi", AppColors.primary);
      case 'on_way':
        return ("Yo'lda", AppColors.primary);
      case 'arrived':
        return ("Yetib keldi", AppColors.success);
      case 'completed':
        return ("Yakunlandi", AppColors.success);
      case 'cancelled':
        return ("Bekor qilindi", AppColors.error);
      default:
        return (status, AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _order == null
                ? const Center(child: Text('Buyurtma topilmadi'))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Row(
                          children: [
                            authBackButton(context),
                            const SizedBox(width: 14),
                            const Text('Buyurtma tafsilotlari',
                                style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LiquidGlass(
                                radius: 20,
                                tintOpacity: 0.9,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text('Buyurtma holati',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: AppColors.textMuted,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _statusInfo(_order!['status']
                                                        as String? ??
                                                    'pending')
                                                .$2
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _statusInfo(_order!['status']
                                                        as String? ??
                                                    'pending')
                                                .$1,
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: _statusInfo(
                                                        _order!['status']
                                                                as String? ??
                                                            'pending')
                                                    .$2),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _infoRow(
                                        Icons.storefront_outlined,
                                        'Servis',
                                        _order!['service']?['name'] ?? '—'),
                                    _infoRow(Icons.build_outlined, 'Xizmat',
                                        _order!['category'] ?? '—'),
                                    _infoRow(
                                        Icons.location_on_outlined,
                                        'Manzil',
                                        _order!['service']?['address'] ?? '—'),
                                    _infoRow(Icons.phone_outlined, 'Telefon',
                                        _order!['service']?['phone'] ?? '—'),
                                    if ((_order!['description'] as String?)
                                            ?.isNotEmpty ==
                                        true)
                                      _infoRow(Icons.notes_outlined, 'Izoh',
                                          _order!['description']),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (_order!['driver_location'] != null)
                                Container(
                                  height: 180,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border:
                                          Border.all(color: AppColors.border)),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: FlutterMap(
                                      mapController: MapController(),
                                      options: MapOptions(
                                          initialCenter: ll.LatLng(
                                              ((_order!['driver_location']
                                                      ['lat']) as num)
                                                  .toDouble(),
                                              ((_order!['driver_location']
                                                      ['lng']) as num)
                                                  .toDouble()),
                                          initialZoom: 13,
                                          maxZoom: 19),
                                      children: [
                                        osmTileLayer(),
                                        if (_routePoints.length >= 2)
                                          PolylineLayer(
                                            polylines: [
                                              Polyline(
                                                  points: _routePoints,
                                                  strokeWidth: 4,
                                                  color: AppColors.primary),
                                            ],
                                          ),
                                        MarkerLayer(
                                          markers: [
                                            Marker(
                                              point: ll.LatLng(
                                                  ((_order!['driver_location']
                                                          ['lat']) as num)
                                                      .toDouble(),
                                                  ((_order!['driver_location']
                                                          ['lng']) as num)
                                                      .toDouble()),
                                              width: 36,
                                              height: 36,
                                              child: const Icon(
                                                  Icons.local_shipping_rounded,
                                                  color: AppColors.primary),
                                            ),
                                            if (_order!['user_latitude'] !=
                                                    null &&
                                                _order!['user_longitude'] !=
                                                    null)
                                              Marker(
                                                point: ll.LatLng(
                                                    (_order!['user_latitude']
                                                            as num)
                                                        .toDouble(),
                                                    (_order!['user_longitude']
                                                            as num)
                                                        .toDouble()),
                                                width: 32,
                                                height: 32,
                                                child: const Icon(
                                                    Icons.location_on,
                                                    color: AppColors.error,
                                                    size: 32),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if ((_order!['status'] as String?) == 'completed')
                                GlassGradientButton(
                                  label: 'Baholash',
                                  onPressed: () => _showReviewDialog(),
                                )
                              else ...[
                                if (_order!['driver_location'] != null &&
                                    (_order!['status'] as String?) ==
                                        'accepted')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GlassGradientButton(
                                      label: 'Xaritada kuzatish',
                                      onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) => MapTrackingScreen(
                                                  orderId: widget.orderId))),
                                    ),
                                  ),
                                if (_order!['driver_location'] == null &&
                                    (_order!['status'] as String?) ==
                                        'accepted')
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GlassGradientButton(
                                      label: 'Servisga yo\'nalish',
                                      icon: Icons.directions_rounded,
                                      onPressed: () {
                                        final svc = _order!['service']
                                            as Map<String, dynamic>?;
                                        final lat = svc != null
                                            ? (svc['latitude'] as num?)
                                                ?.toDouble()
                                            : null;
                                        final lng = svc != null
                                            ? (svc['longitude'] as num?)
                                                ?.toDouble()
                                            : null;
                                        if (lat == null || lng == null) return;
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  NearbyServicesMapScreen(
                                                categoryId: _order!['category']
                                                    ?.toString(),
                                                focusService: {
                                                  'id': _order!['service']
                                                      ?['id'],
                                                  'name': svc?['name'],
                                                  'address': svc?['address'],
                                                  'latitude': lat,
                                                  'longitude': lng,
                                                },
                                              ),
                                            ));
                                      },
                                    ),
                                  ),
                                GlassGradientButton(
                                  label: 'Chat',
                                  icon: Icons.chat_bubble_outline_rounded,
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                            orderId: widget.orderId,
                                            serviceName: _order!['service']
                                                    ?['name'] ??
                                                'Chat'),
                                      )),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
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
                label == 'Telefon'
                    ? GestureDetector(
                        onTap: () async {
                          try {
                            final uri = Uri.parse('tel:$value');
                            await launchUrl(uri);
                          } catch (_) {}
                        },
                        child: Text(value,
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      )
                    : Text(value,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReviewDialog() {
    int rating = 5;
    final commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Servisni baholang',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    return GestureDetector(
                      onTap: () => setSt(() => rating = i + 1),
                      child: Icon(
                        i < rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: i < rating
                            ? AppColors.warning
                            : AppColors.textMuted,
                        size: 36,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(hintText: 'Izohingiz (ixtiyoriy)'),
                ),
                const SizedBox(height: 18),
                GlassGradientButton(
                  label: 'Yuborish',
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final userId =
                        int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
                    await ApiService.createReview(
                      userId: userId,
                      serviceId: _order!['service']?['id'] as int? ?? 0,
                      orderId: widget.orderId,
                      rating: rating,
                      comment: commentController.text.trim().isEmpty
                          ? null
                          : commentController.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Rahmat! Bahongiz qabul qilindi.'),
                          backgroundColor: AppColors.success),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// CHAT SCREEN
// ========================================================================

class ChatScreen extends StatefulWidget {
  final int orderId;
  final String serviceName;
  const ChatScreen(
      {super.key, required this.orderId, required this.serviceName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  int _userId = 0;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(
        () => _userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0);
    _loadMessages();
    _poller =
        Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final result = await ApiService.getChatMessages(widget.orderId);
    if (!mounted) return;
    final msgs = result['data'] ?? [];
    if (msgs.length != _messages.length) {
      setState(() {
        _messages = msgs;
        _loading = false;
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _userId == 0) return;
    _controller.clear();
    await ApiService.sendChatMessage(widget.orderId, _userId, text);
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(widget.serviceName,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i] as Map<String, dynamic>;
                        final isMe = (m['sender_id'] as int?) == _userId;
                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: isMe ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(16).copyWith(
                                bottomRight:
                                    isMe ? const Radius.circular(4) : null,
                                bottomLeft:
                                    !isMe ? const Radius.circular(4) : null,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                            child: Text(
                              m['message']?.toString() ?? '',
                              style: TextStyle(
                                  fontSize: 14.5,
                                  color: isMe
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                  height: 1.4),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Xabar yozing...',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                          gradient:
                              LinearGradient(colors: AppColors.primaryGradient),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
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

// ========================================================================
// FAVORITES SCREEN
// ========================================================================

class FavoritesScreen extends StatefulWidget {
  final int userId;
  const FavoritesScreen({super.key, required this.userId});
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<dynamic> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ApiService.getFavorites(widget.userId);
    if (!mounted) return;
    setState(() {
      _favorites = result['data'] ?? [];
      _loading = false;
    });
  }

  Future<void> _remove(int serviceId) async {
    await ApiService.removeFavorite(widget.userId, serviceId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      authBackButton(context),
                      const SizedBox(width: 14),
                      const Text('Sevimlilar',
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_favorites.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                              color: AppColors.primaryPale.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.favorite_border,
                              color: AppColors.primary, size: 38),
                        ),
                        const SizedBox(height: 18),
                        const Text('Hozircha sevimlilar yo\'q',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final f = _favorites[i] as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
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
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                    color:
                                        AppColors.primaryPale.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(14)),
                                child: const Icon(Icons.storefront_rounded,
                                    color: AppColors.primary, size: 22),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(f['name']?.toString() ?? 'Servis',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary)),
                                    const SizedBox(height: 3),
                                    Text(f['address']?.toString() ?? '',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.favorite_rounded,
                                    color: AppColors.error),
                                onPressed: () => _remove(f['id'] as int),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: _favorites.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// SERVICE OWNER HOME SCREEN — to'liq panel: Dashboard / Buyurtmalar / Xizmatlar / Statistika / Profil
// ========================================================================

class ServiceDetailScreen extends StatefulWidget {
  final int serviceId;
  // Foydalanuvchi bu servisga oldin bitta xizmat turini (masalan "Xizmat
  // turlari" ro'yxatidan) tanlab kelgan bo'lsa, o'sha nom shu yerga
  // uzatiladi va servis ichiga kirganda avtomatik tanlangan holda turadi.
  final String? initialCategoryName;
  const ServiceDetailScreen(
      {super.key, required this.serviceId, this.initialCategoryName});
  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _isFavorite = false;
  int _userId = 0;
  // Mijoz "Xizmatlar" ro'yxatidan tanlagan xizmat turlari (bir nechtasini
  // birga tanlash mumkin) - shu tanlov "Buyurtma berish" bosilganda
  // OrderBookingScreen'ga uzatiladi va servis egasiga ham aynan shu nomlar
  // bilan ko'rinadi.
  final Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(
        () => _userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0);
    _loadService();
  }

  Future<void> _loadService() async {
    setState(() => _loading = true);
    final result = await ApiService.getServiceDetail(widget.serviceId);
    if (!mounted) return;
    setState(() {
      _service = result['data'] as Map<String, dynamic>?;
      _loading = false;
      // Avval boshqa ekrandan tanlab kelingan xizmat turi shu servisning
      // ro'yxatida mavjud bo'lsa - avtomatik belgilab qo'yamiz.
      if (widget.initialCategoryName != null) {
        final cats = (_service?['categories'] as List?) ?? [];
        final match = cats.cast<Map<String, dynamic>>().any((c) =>
            c['category']?.toString() == widget.initialCategoryName &&
            c['is_active'] == true);
        if (match) _selectedCategories.add(widget.initialCategoryName!);
      }
    });
    if (_userId > 0) {
      final favResult =
          await ApiService.checkFavorite(_userId, widget.serviceId);
      if (mounted)
        setState(() => _isFavorite = favResult['is_favorite'] == true);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isFavorite) {
      await ApiService.removeFavorite(_userId, widget.serviceId);
    } else {
      await ApiService.addFavorite(_userId, widget.serviceId);
    }
    setState(() => _isFavorite = !_isFavorite);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _service == null
                ? const Center(child: Text('Servis topilmadi'))
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            children: [
                              authBackButton(context),
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                    _isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: AppColors.error),
                                onPressed: _userId > 0 ? _toggleFavorite : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryPale,
                                    shape: BoxShape.circle,
                                    image: (_service!['logo_url'] != null &&
                                            (_service!['logo_url'] as String)
                                                .startsWith('data:'))
                                        ? DecorationImage(
                                            image: MemoryImage(base64Decode(
                                                (_service!['logo_url']
                                                        as String)
                                                    .split(',')
                                                    .last)),
                                            fit: BoxFit.contain)
                                        : null,
                                  ),
                                  child: _service!['logo_url'] == null
                                      ? const Icon(Icons.storefront_rounded,
                                          color: AppColors.primary, size: 40)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                    _service!['name']?.toString() ?? 'Servis',
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary)),
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 18, color: AppColors.warning),
                                    const SizedBox(width: 4),
                                    Text('${_service!['rating'] ?? 0}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary)),
                                    const SizedBox(width: 8),
                                    Text(
                                        '(${_service!['review_count'] ?? 0} ta baho)',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              _infoCard(Icons.location_on_outlined, 'Manzil',
                                  _service!['address']?.toString() ?? '—'),
                              if (_service!['latitude'] != null &&
                                  _service!['longitude'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: GestureDetector(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                NearbyServicesMapScreen(
                                                    focusService:
                                                        _service!))),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryPale
                                            .withOpacity(0.45),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.map_outlined,
                                              size: 18,
                                              color: AppColors.primary),
                                          SizedBox(width: 8),
                                          Text('Xaritada ko\'rish',
                                              style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              _infoCard(Icons.phone_outlined, 'Telefon',
                                  _service!['phone']?.toString() ?? '—'),
                              _infoCard(
                                  Icons.access_time_outlined,
                                  'Ish vaqti',
                                  _service!['working_hours']?.toString() ??
                                      'Belgilanmagan'),
                              const SizedBox(height: 24),
                              const Text('Xizmatlar',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 14),
                              if ((_service!['categories'] as List?)?.isEmpty ==
                                  true)
                                const Text('Xizmatlar ro\'yxati bo\'sh',
                                    style:
                                        TextStyle(color: AppColors.textMuted))
                              else
                                for (final c
                                    in (_service!['categories'] as List? ?? []))
                                  _categoryCard(c as Map<String, dynamic>),
                              const SizedBox(height: 24),
                              if ((_service!['reviews'] as List?)?.isNotEmpty ==
                                  true) ...[
                                const Text('Fikrlar',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 14),
                                for (final r
                                    in (_service!['reviews'] as List? ?? []))
                                  _reviewCard(r as Map<String, dynamic>),
                              ],
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      // Tugma endi pastda doim ko'rinib turadigan (scroll bilan ketmaydigan)
      // holda - lekin ortidagi oq panel/soya olib tashlandi, faqat
      // tugmaning o'zi shaffof fonda ko'rinadi.
      bottomNavigationBar: (_loading || _service == null)
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: GlassGradientButton(
                  label: (_service!['provider_type']?.toString() == 'fuel' ||
                          _service!['provider_type']?.toString() ==
                              'evacuator')
                      ? 'Chaqirish'
                      : 'Buyurtma berish',
                  flat: true,
                  onPressed: () {
                    // Evakuator va benzin dastavka — bron qilinadigan xizmat
                    // emas, shuning uchun reyting ro'yxati orqali tanlanganda ham
                    // xuddi xarita orqali tanlangandagidek litr (benzin uchun) va
                    // mijozning haqiqiy joylashuvini so'raydigan oynani ochamiz.
                    final providerType =
                        _service!['provider_type']?.toString();
                    if (providerType == 'fuel' || providerType == 'evacuator') {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _CallOutRequestSheet(service: _service!),
                      );
                      return;
                    }
                    if (!isAutoServiceOpenNow(_service)) {
                      showServiceClosedDialog(context,
                          serviceName: _service!['name']?.toString());
                      return;
                    }
                    // Mijoz avval "Xizmatlar" ro'yxatidan kamida bitta
                    // xizmat turini tanlashi shart (bir nechtasini birga
                    // tanlash mumkin) - shundagina buyurtma o'sha tur(lar)
                    // bilan yaratiladi.
                    if (_selectedCategories.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Iltimos, avval xizmat turini tanlang'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderBookingScreen(
                            serviceName: _service!['name']?.toString() ??
                                'Servis',
                            serviceId: widget.serviceId,
                            category: _selectedCategories.join(', '),
                          ),
                        ));
                  },
                ),
              ),
            ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
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
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryCard(Map<String, dynamic> c) {
    final active = c['is_active'] == true;
    final name = c['category']?.toString() ?? 'Xizmat';
    final selected = active && _selectedCategories.contains(name);
    return GestureDetector(
      onTap: active
          ? () => setState(() {
                if (selected) {
                  _selectedCategories.remove(name);
                } else {
                  _selectedCategories.add(name);
                }
              })
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? Colors.white : AppColors.chipBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected
                  ? AppColors.primary
                  : (active ? AppColors.border : AppColors.border),
              width: selected ? 1.6 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.primary.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: active
                    ? (selected ? AppColors.primary : AppColors.textMuted)
                    : AppColors.textMuted.withOpacity(0.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? AppColors.textPrimary
                          : AppColors.textMuted)),
            ),
            if (c['price'] != null)
              Text('${c['price']} so\'m',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(r['user_name']?.toString() ?? 'Mijoz',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < (r['rating'] as int? ?? 0)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 16,
                    color: AppColors.warning,
                  );
                }),
              ),
            ],
          ),
          if (r['comment'] != null) ...[
            const SizedBox(height: 6),
            Text(r['comment'].toString(),
                style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textSecondary,
                    height: 1.4)),
          ],
        ],
      ),
    );
  }
}

// ========================================================================
// NOTIFICATIONS SCREEN (ilova ichi bildirishnomalar)
// ========================================================================

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  int _userId = 0;

  static const _typeIcons = {
    'order_status': Icons.local_shipping_rounded,
    'new_order': Icons.receipt_long_rounded,
    'chat': Icons.chat_bubble_rounded,
    'admin': Icons.campaign_rounded,
    'review': Icons.star_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    if (_userId == 0) {
      setState(() => _loading = false);
      return;
    }
    final result = await ApiService.getNotifications(_userId);
    if (!mounted) return;
    setState(() {
      _notifications = result['data'] ?? [];
      _loading = false;
    });
  }

  Future<void> _onTapNotification(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      await ApiService.markNotificationRead(n['id']);
    }
    final type = n['type'] as String?;
    final relatedId = n['related_id'];
    if ((type == 'order_status' ||
            type == 'new_order' ||
            type == 'chat' ||
            type == 'review') &&
        relatedId != null) {
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: relatedId as int)));
    }
    _load();
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '';
    final diff = DateTime.now().toUtc().difference(date.toUtc());
    if (diff.inMinutes < 1) return 'hozirgina';
    if (diff.inMinutes < 60) return '${diff.inMinutes} daqiqa oldin';
    if (diff.inHours < 24) return '${diff.inHours} soat oldin';
    return '${diff.inDays} kun oldin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      authBackButton(context),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text('Bildirishnomalar',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                      if (_notifications.isNotEmpty)
                        GestureDetector(
                          onTap: () async {
                            await ApiService.markAllNotificationsRead(_userId);
                            _load();
                          },
                          child: const Text('Barchasini o\'qish',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)))
              else if (_notifications.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                              color: AppColors.primaryPale.withOpacity(0.5),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.notifications_none_rounded,
                              color: AppColors.primary, size: 38),
                        ),
                        const SizedBox(height: 18),
                        const Text('Hozircha bildirishnoma yo\'q',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final n = _notifications[i] as Map<String, dynamic>;
                        final isRead = n['is_read'] == true;
                        final icon = _typeIcons[n['type']] ??
                            Icons.notifications_rounded;
                        return GestureDetector(
                          onTap: () => _onTapNotification(n),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isRead
                                  ? Colors.white
                                  : AppColors.primaryPale.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4))
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                      color: AppColors.primaryPale
                                          .withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: Icon(icon,
                                      color: AppColors.primary, size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(n['title'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary)),
                                      const SizedBox(height: 4),
                                      Text(n['message'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 6),
                                      Text(_timeAgo(n['created_at'] as String?),
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                                if (!isRead)
                                  Container(
                                    width: 9,
                                    height: 9,
                                    margin:
                                        const EdgeInsets.only(top: 4, left: 6),
                                    decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _notifications.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
