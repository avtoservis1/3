import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'dart:math';
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
// Xizmat turlari ro'yxati (/api/service-owner/service-types) tezkor
// ochilishi uchun rasmni o'zida saqlamaydi - faqat `has_image` belgisini
// beradi. Shu widget ro'yxat allaqachon ko'rinib turgan holda, har bir
// qator uchun rasmni fonda alohida-alohida so'raydi (ApiService.
// getServiceTypeImage orqali) va tayyor bo'lgach ustiga chizadi. Rasm hali
// kelmagan yoki umuman bo'lmasa ham, qator/ro'yxat ko'rinishda qoladi -
// faqat ikonka ko'rsatiladi.
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

class OwnerLazyTypeImage extends StatefulWidget {
  final Map<String, dynamic> item;
  final IconData fallbackIcon;
  final double size;
  final double iconSize;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? iconColor;

  const OwnerLazyTypeImage({
    super.key,
    required this.item,
    required this.fallbackIcon,
    this.size = 44,
    this.iconSize = 20,
    this.borderRadius = 12,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  State<OwnerLazyTypeImage> createState() => _OwnerLazyTypeImageState();
}

class _OwnerLazyTypeImageState extends State<OwnerLazyTypeImage> {
  String? _imageUrl;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.item['image_url'] as String?;
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant OwnerLazyTypeImage old) {
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
    final hasImage = _imageUrl != null && _imageUrl!.startsWith('data:');
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? AppColors.chipBg,
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
              color: widget.iconColor ?? AppColors.primary,
              size: widget.iconSize),
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
    final glassContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor.withOpacity(tintOpacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.glassBorder, width: 1),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.0),
          ],
        ),
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
                blurRadius: 28,
                offset: const Offset(0, 12),
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
    this.height = 56,
    this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    // True frosted Liquid Glass surface — blue text/icons on top of the glass,
    // no solid gradient fill.
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
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
    );

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : onPressed,
            splashColor: Colors.white.withOpacity(0.18),
            highlightColor: Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (kIsWeb)
                  glassBackground
                else
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: glassBackground,
                  ),
                Center(
                  child: isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: contentColor,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: contentColor, size: 18),
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
          ),
        ),
      ),
    );
  }
}

// Lightweight action button - no BackdropFilter/blur. Used inside scrolling
// lists (order cards) where many buttons render at once; stacking many
// BackdropFilter blurs in a ListView is what was causing the press
// animation to glitch and flash across the whole screen instead of
// staying inside the button. This keeps the same look via a solid
// gradient instead of a blurred glass surface, and clips its own ripple
// tightly to its rounded rect so the tap feedback never leaks outside it.
class SolidActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool filled;
  final double height;

  const SolidActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.filled = true,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    final radius = height / 2;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        type: MaterialType.button,
        color: filled
            ? AppColors.primary.withOpacity(disabled ? 0.35 : 1.0)
            : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onPressed,
          splashColor:
              (filled ? Colors.white : AppColors.primary).withOpacity(0.18),
          highlightColor:
              (filled ? Colors.white : AppColors.primary).withOpacity(0.10),
          child: Center(
            child: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: filled ? Colors.white : AppColors.primary),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: filled ? Colors.white : AppColors.primary,
                    ),
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
        // Servis egasi/provayder uchun ham admin bo'lmasa server token
        // bermaydi - o'rniga SMS kod yuboradi (requires_otp: true). Bunday
        // holda hali prefs'ga hech narsa yozmaymiz - token faqat
        // loginVerifyOtp muvaffaqiyatli bo'lgach saqlanadi.
        if (data['requires_otp'] == true) {
          return {'success': true, 'requiresOtp': true, 'data': data};
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('user_id', data['user_id'].toString());
        await prefs.setString('role', data['role']?.toString() ?? 'user');
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
    // "auto_service" | "evacuator" | "fuel"
    String providerType = 'auto_service',
    String? serviceName,
    String? address,
    double? latitude,
    double? longitude,
    String? carModel,
    String? workingHours,
    String? dayOff,
    String? logoBase64,
    // Ro'yxatdan o'tishda darhol tanlangan xizmat turlari (faqat
    // auto_service uchun mazmunli) - admin katalogidagi ServiceType ID'lari.
    List<int>? serviceTypeIds,
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
          'provider_type': providerType,
          if (serviceName != null && serviceName.isNotEmpty)
            'service_name': serviceName,
          if (address != null && address.isNotEmpty) 'address': address,
          if (latitude != null) 'latitude': latitude,
          if (longitude != null) 'longitude': longitude,
          if (carModel != null && carModel.isNotEmpty) 'car_model': carModel,
          if (workingHours != null && workingHours.isNotEmpty)
            'working_hours': workingHours,
          if (dayOff != null && dayOff.isNotEmpty) 'day_off': dayOff,
          if (logoBase64 != null) 'logo_base64': logoBase64,
          if (serviceTypeIds != null && serviceTypeIds.isNotEmpty)
            'service_type_ids': serviceTypeIds,
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
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/orders?user_id=$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': serviceId,
          'category': category,
          if (description != null) 'description': description,
          if (userLatitude != null) 'user_latitude': userLatitude,
          if (userLongitude != null) 'user_longitude': userLongitude,
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
      int userId, String name, String? avatarBase64) async {
    try {
      final response = await http.put(
        Uri.parse(
            '$baseUrl/api/users/me?phone='), // phone orqali emas, user_id kerak
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false};
    } catch (e) {
      return {'success': false};
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
  // (/api/service-owner/service-types, /api/service-types) tezkor ochilishi
  // uchun rasmni o'zida saqlamaydi - faqat `has_image` belgisini beradi,
  // rasm shu orqali fonda so'raladi.
  static Future<String?> getServiceTypeImage(int id) async {
    try {
      final response =
          await http.get(Uri.parse('$baseUrl/api/service-types/$id/image'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['image_url'] as String?;
      }
    } catch (_) {}
    return null;
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

  // ---- Evakuator / benzin dastavka: ish holati va jonli joylashuv ----
  static Future<Map<String, dynamic>> goOnline(
      int ownerId, double latitude, double longitude) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/service-owner/go-online?owner_id=$ownerId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> goOffline(int ownerId) async {
    try {
      final response = await http.put(
          Uri.parse('$baseUrl/api/service-owner/go-offline?owner_id=$ownerId'));
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
    }
  }

  static Future<Map<String, dynamic>> updateLocation(
      int ownerId, double latitude, double longitude) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/service-owner/location?owner_id=$ownerId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
      );
      return {'success': response.statusCode == 200};
    } catch (e) {
      return {'success': false};
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

  /// Admin katalogidagi (nomi va narxi admin tomonidan belgilangan) xizmat
  /// turlari ro'yxati - har biri shu servisda yoqilgan/yoqilmaganligi bilan.
  static Future<Map<String, dynamic>> getServiceTypesForOwner(
      int ownerId) async {
    try {
      final response = await http.get(Uri.parse(
          '$baseUrl/api/service-owner/service-types?owner_id=$ownerId'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  /// Hali ro'yxatdan o'tmagan (owner_id yo'q) foydalanuvchi uchun - admin
  /// katalogidagi barcha faol xizmat turlarining ochiq ro'yxati. Ro'yxatdan
  /// o'tish jarayonida "qaysi xizmat turlarini taklif qilasiz" ekranida
  /// ishlatiladi.
  static Future<Map<String, dynamic>> getPublicServiceTypes() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/service-types'));
      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body) as List};
      }
      return {'success': false, 'data': []};
    } catch (e) {
      return {'success': false, 'data': []};
    }
  }

  /// Servis egasi admin katalogidagi bir xizmat turini o'zida bor/yo'qligini
  /// belgilaydi. Nomi va narxini o'zi kirita olmaydi - bular katalogdan olinadi.
  static Future<Map<String, dynamic>> toggleServiceType(
      int ownerId, int serviceTypeId, bool isActive) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/service-owner/service-types?owner_id=$ownerId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'service_type_id': serviceTypeId, 'is_active': isActive}),
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
      description: 'Yangi buyurtma, chat va boshqa xabarlar',
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
        Uri.parse('${ApiService.baseUrl}/api/register-fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'token': token}),
      );
    } catch (_) {}
  }
}

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
// AUTH ROUTING (Servis egasi ilovasi)
// ========================================================================
Future<void> routeAfterAuth(BuildContext context,
    {required String role, required int userId, String? name}) async {
  if (role != UserRole.serviceOwner.apiValue) {
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

  final result = await ApiService.getServiceOwnerService(userId);
  if (!context.mounted) return;

  if (result['success'] != true) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(result['message'] ?? 'Servis topilmadi'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating),
    );
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()), (r) => false);
    return;
  }

  final data = result['data'] as Map<String, dynamic>;
  final status = data['status'] as String? ?? 'pending';
  final providerType = data['provider_type'] as String? ?? 'auto_service';

  PushNotificationService.registerToken(userId);

  if (status == 'approved') {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (_) => ServiceOwnerHomeScreen(
              ownerId: userId,
              serviceId: data['id'] as int,
              serviceName: data['name'] as String? ?? '',
              providerType: providerType)),
      (r) => false,
    );
  } else {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (_) => ServiceOwnerPendingScreen(
              serviceId: data['id'] as int,
              serviceName: data['name'] as String? ?? '',
              ownerId: userId,
              providerType: providerType)),
      (r) => false,
    );
  }
}

// ========================================================================
// APP WIDGET (Servis egasi ilovasi)
// ========================================================================
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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GoFix ustalar',
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
  String _role = 'user';
  int _userId = 0;

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
      _role = role;
      _userId = userId;
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
// 1. WELCOME SCREEN (Servis egasi ilovasi)
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
                      child: const Icon(Icons.storefront_rounded,
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
                      'Avtoservis, evakuator va benzin yetkazish\nUstalari uchun boshqaruv ilovasi.\nBuyurtmalarni qabul qiling va biznesingizni yuriting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          height: 1.5),
                    ),
                    const Spacer(flex: 2),
                    GlassGradientButton(
                      label: 'Usta sifatida ro\'yxatdan o\'tish',
                      icon: Icons.storefront_outlined,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProviderTypeScreen()),
                      ),
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

// ========================================================================
// 1.5 PROVIDER TYPE SELECTION — avto servis egasi / evakuator / benzin yetkazish
// ========================================================================

class ProviderTypeScreen extends StatelessWidget {
  const ProviderTypeScreen({super.key});

  static const _types = [
    (
      'auto_service',
      'Avtoservis egasi',
      'O\'z avtoservisingizni ro\'yxatdan o\'tkazing va xizmatlaringizni ko\'rsating',
      Icons.storefront_rounded,
    ),
    (
      'evacuator',
      'Evakuator haydovchisi',
      'Yo\'lda qolgan mijozlarga evakuator xizmatini ko\'rsating',
      Icons.local_shipping_rounded,
    ),
    (
      'fuel',
      'Benzin yetkazish',
      'Mijozlarga joyida yoqilg\'i yetkazib berish xizmatini ko\'rsating',
      Icons.local_gas_station_rounded,
    ),
  ];

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
                const Text('Qaysi turdagi\nusta sifatida?',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.25)),
                const SizedBox(height: 10),
                const Text(
                    'Ro\'yxatdan o\'tishdan oldin xizmat turingizni tanlang.',
                    style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 26),
                for (final t in _types) ...[
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PhoneEntryScreen(
                              isServiceOwner: true, providerType: t.$1)),
                    ),
                    child: LiquidGlass(
                      radius: 18,
                      tintOpacity: 0.78,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    colors: AppColors.primaryGradient),
                                shape: BoxShape.circle),
                            child: Icon(t.$4, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.$2,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary)),
                                const SizedBox(height: 3),
                                Text(t.$3,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                        height: 1.35)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PhoneEntryScreen extends StatefulWidget {
  final bool isServiceOwner;
  final String providerType;
  const PhoneEntryScreen(
      {super.key,
      this.isServiceOwner = false,
      this.providerType = 'auto_service'});
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
            isServiceOwner: widget.isServiceOwner,
            providerType: widget.providerType),
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
  final String providerType;
  const OtpScreen(
      {super.key,
      required this.phone,
      this.isServiceOwner = false,
      this.providerType = 'auto_service'});
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
        builder: (_) => ServiceOwnerSetupScreen(
            phone: widget.phone.replaceAll(' ', ''),
            providerType: widget.providerType),
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
// 4. PROFILE SETUP SCREEN
// ========================================================================

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

class ServiceOwnerSetupScreen extends StatefulWidget {
  final String phone;
  // "auto_service" | "evacuator" | "fuel"
  final String providerType;
  const ServiceOwnerSetupScreen(
      {super.key, required this.phone, this.providerType = 'auto_service'});
  @override
  State<ServiceOwnerSetupScreen> createState() =>
      _ServiceOwnerSetupScreenState();
}

class _ServiceOwnerSetupScreenState extends State<ServiceOwnerSetupScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _serviceNameController = TextEditingController();
  final _carModelController = TextEditingController();
  TimeOfDay? _workingHoursFrom;
  TimeOfDay? _workingHoursTo;
  final _dayOffController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _isAutoService => widget.providerType == 'auto_service';

  String? _logoBase64;
  Uint8List? _logoPreview;
  String? _address;
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  String? _error;

  // Ro'yxatdan o'tishda darhol tanlanadigan xizmat turlari (faqat
  // auto_service uchun) - admin katalogidan (ServiceType) olinadi.
  List<Map<String, dynamic>> _serviceTypes = [];
  bool _loadingServiceTypes = true;
  final Set<int> _selectedServiceTypeIds = {};

  @override
  void initState() {
    super.initState();
    if (_isAutoService) _loadServiceTypes();
  }

  Future<void> _loadServiceTypes() async {
    final result = await ApiService.getPublicServiceTypes();
    if (!mounted) return;
    setState(() {
      _serviceTypes =
          (result['data'] as List? ?? []).cast<Map<String, dynamic>>();
      _loadingServiceTypes = false;
    });
  }

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

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _serviceNameController.dispose();
    _carModelController.dispose();
    _dayOffController.dispose();
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

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String? get _workingHours {
    if (_workingHoursFrom == null || _workingHoursTo == null) return null;
    return '${_fmtTime(_workingHoursFrom!)}-${_fmtTime(_workingHoursTo!)}';
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

  bool get _canSubmit {
    final baseOk = _firstNameController.text.trim().isNotEmpty &&
        _lastNameController.text.trim().isNotEmpty &&
        _passwordController.text.length >= 6 &&
        _confirmPasswordController.text == _passwordController.text &&
        _workingHoursFrom != null &&
        _workingHoursTo != null;
    if (!baseOk) return false;
    if (_isAutoService) {
      return _serviceNameController.text.trim().isNotEmpty &&
          _address != null &&
          _latitude != null &&
          _longitude != null;
    }
    // Evakuator / benzin yetkazish: mashina rusmi (turi) majburiy.
    return _carModelController.text.trim().isNotEmpty;
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final ext = file.name.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      setState(() {
        _logoPreview = bytes;
        _logoBase64 = 'data:$mime;base64,${base64Encode(bytes)}';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rasm tanlab bo\'lmadi')));
    }
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (result == null) return;
    setState(() {
      _address = result['address'] as String;
      _latitude = result['latitude'] as double;
      _longitude = result['longitude'] as double;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final dayOff = _dayOffController.text.trim().isEmpty
        ? null
        : _dayOffController.text.trim();

    final result = await ApiService.registerServiceOwner(
      phone: widget.phone,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      password: _passwordController.text,
      providerType: widget.providerType,
      serviceName: _isAutoService ? _serviceNameController.text.trim() : null,
      address: _isAutoService ? _address : null,
      latitude: _isAutoService ? _latitude : null,
      longitude: _isAutoService ? _longitude : null,
      carModel: _isAutoService ? null : _carModelController.text.trim(),
      workingHours: _workingHours,
      dayOff: dayOff,
      logoBase64: _logoBase64,
      serviceTypeIds: _isAutoService ? _selectedServiceTypeIds.toList() : null,
    );

    setState(() => _isSubmitting = false);
    if (!mounted) return;

    if (result['success'] != true) {
      setState(() => _error =
          result['message'] ?? 'Ariza yuborilmadi, qayta urinib ko\'ring');
      return;
    }

    final data = result['data'] as Map<String, dynamic>?;
    final prefs = await SharedPreferences.getInstance();
    if (data != null && data['token'] != null) {
      await prefs.setString('token', data['token']);
      await prefs.setString('user_id', data['user_id'].toString());
      await prefs.setString('role', 'service_owner');
    }

    final displayName = _isAutoService
        ? _serviceNameController.text.trim()
        : '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceOwnerPendingScreen(
          serviceId: data?['service_id'] as int? ?? 0,
          serviceName: displayName,
          ownerId: data?['user_id'] as int? ?? 0,
          providerType: widget.providerType,
        ),
      ),
      (r) => false,
    );
  }

  String get _screenTitle {
    switch (widget.providerType) {
      case 'evacuator':
        return 'Evakuator haydovchisi arizasi';
      case 'fuel':
        return 'Benzin yetkazish arizasi';
      default:
        return 'Servis egasi arizasi';
    }
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
                Text(_screenTitle,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 10),
                const Text(
                    'Ma\'lumotlaringizni to\'ldiring, ariza admin tomonidan ko\'rib chiqiladi.',
                    style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                        height: 1.45)),
                const SizedBox(height: 26),
                _sectionTitle('1', 'Shaxsiy ma\'lumotlar'),
                const SizedBox(height: 16),
                _label('Ism'),
                TextField(
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Bobur',
                      prefixIcon: Icon(Icons.person_outline,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 18),
                _label('Familiya'),
                TextField(
                  controller: _lastNameController,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      hintText: 'Masalan: Aliyev',
                      prefixIcon: Icon(Icons.person_outline,
                          color: AppColors.textMuted)),
                ),
                const SizedBox(height: 18),
                _label('Telefon raqam'),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border)),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded,
                          size: 18, color: AppColors.textMuted),
                      const SizedBox(width: 10),
                      Text(widget.phone,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _label('Parol'),
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
                const SizedBox(height: 18),
                _label('Parolni tasdiqlang'),
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
                const SizedBox(height: 28),
                if (_isAutoService)
                  ..._autoServiceFields()
                else
                  ..._providerFields(),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.error,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 32),
                GlassGradientButton(
                  label: 'Tasdiqlash',
                  isLoading: _isSubmitting,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Avtoservis egasi uchun maydonlar ----
  List<Widget> _autoServiceFields() {
    return [
      _sectionTitle('2', 'Servis ma\'lumotlari'),
      const SizedBox(height: 16),
      _label('Servis nomi'),
      TextField(
        controller: _serviceNameController,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
            hintText: 'Masalan: Bobur Avto Servis',
            prefixIcon:
                Icon(Icons.storefront_outlined, color: AppColors.textMuted)),
      ),
      const SizedBox(height: 18),
      _label('Servis logotipi'),
      _logoPicker('Rasm yuklash'),
      const SizedBox(height: 18),
      _label('Manzil'),
      _locationPicker(),
      const SizedBox(height: 18),
      _label('Ish vaqti'),
      _workingHoursPicker(),
      const SizedBox(height: 18),
      _label('Dam olish kuni (ixtiyoriy)'),
      _dayOffPicker(),
      const SizedBox(height: 28),
      _sectionTitle('3', 'Xizmat turlari'),
      const SizedBox(height: 6),
      const Text(
          'Servisingizda mavjud bo\'lgan xizmat turlarini tanlang - mijozlar servis profilingizga kirganda shularni ko\'radi (keyinroq ham qo\'shish/o\'chirish mumkin).',
          style: TextStyle(
              fontSize: 12.5, color: AppColors.textSecondary, height: 1.4)),
      const SizedBox(height: 14),
      _serviceTypesPicker(),
    ];
  }

  Widget _serviceTypesPicker() {
    if (_loadingServiceTypes) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child:
            Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_serviceTypes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Hozircha admin xizmat turi qo\'shmagan',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _serviceTypes.map((t) {
        final id = t['id'] as int;
        final name = t['name']?.toString() ?? 'Xizmat';
        final selected = _selectedServiceTypeIds.contains(id);
        return GestureDetector(
          onTap: () => setState(() {
            if (selected) {
              _selectedServiceTypeIds.remove(id);
            } else {
              _selectedServiceTypeIds.add(id);
            }
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 16,
                    color: selected ? Colors.white : AppColors.textMuted),
                const SizedBox(width: 6),
                Text(name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? Colors.white : AppColors.textPrimary)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---- Evakuator / benzin yetkazish uchun maydonlar ----
  List<Widget> _providerFields() {
    final isFuel = widget.providerType == 'fuel';
    return [
      _sectionTitle(
          '2', isFuel ? 'Xizmat ma\'lumotlari' : 'Mashina ma\'lumotlari'),
      const SizedBox(height: 16),
      _label(isFuel ? 'Mashina rasmi' : 'Mashina (evakuator) rasmi'),
      _logoPicker(isFuel
          ? 'Sisterna/mashina rasmini yuklash'
          : 'Evakuator rasmini yuklash'),
      const SizedBox(height: 18),
      _label('Mashina rusmi (turi)'),
      TextField(
        controller: _carModelController,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText:
              isFuel ? 'Masalan: Damas sisterna' : 'Masalan: Isuzu evakuator',
          prefixIcon: const Icon(Icons.local_shipping_outlined,
              color: AppColors.textMuted),
        ),
      ),
      const SizedBox(height: 18),
      _label('Ish vaqti'),
      _workingHoursPicker(),
      const SizedBox(height: 18),
      _label('Dam olish kuni (ixtiyoriy)'),
      _dayOffPicker(),
    ];
  }

  Widget _logoPicker(String emptyLabel) {
    return GestureDetector(
      onTap: _pickLogo,
      child: LiquidGlass(
        radius: 16,
        tintOpacity: 0.75,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryPale,
                image: _logoPreview != null
                    ? DecorationImage(
                        image: MemoryImage(_logoPreview!), fit: BoxFit.contain)
                    : null,
              ),
              child: _logoPreview == null
                  ? const Icon(Icons.camera_alt_outlined,
                      color: AppColors.primary, size: 22)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _logoPreview != null ? 'Rasm tanlandi' : emptyLabel,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _locationPicker() {
    return GestureDetector(
      onTap: _pickLocation,
      child: LiquidGlass(
        radius: 16,
        tintOpacity: 0.75,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: AppColors.primaryGradient),
                  shape: BoxShape.circle),
              child:
                  const Icon(Icons.location_on, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _address ?? 'Xaritada nuqta tanlash',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _address != null
                        ? AppColors.textPrimary
                        : AppColors.textMuted),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

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
          value: _dayOffController.text.isEmpty
              ? _days.first
              : _dayOffController.text,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          items: _days
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (v) => setState(
              () => _dayOffController.text = v == _days.first ? '' : v!),
        ),
      ),
    );
  }

  Widget _sectionTitle(String number, String title) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
              gradient: LinearGradient(colors: AppColors.primaryGradient),
              shape: BoxShape.circle),
          child: Text(number,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 0),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );
}

// ========================================================================
// OSM TILE LAYER & HELPERS
// ========================================================================
TileLayer osmTileLayer() {
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'uz.avtoservis.app',
    maxNativeZoom: 19,
  );
}

Future<ll.LatLng?> resolveCurrentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return ll.LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

// ========================================================================
// YO'L BO'YLAB YO'NALISH (ROUTING) — xaritada ikki nuqta orasidagi chiziq
// to'g'ri chiziq emas, balki haqiqiy yo'l (ko'cha) bo'ylab chiziladi.
// Buning uchun bepul OSRM (Open Source Routing Machine) demo serveridan
// foydalaniladi. Server javob bermasa - ikkita nuqta orasidagi oddiy
// to'g'ri chiziqqa qaytiladi (xarita hech qachon bo'sh ko'rinmasligi uchun).
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
  return [start, end];
}

Future<String?> reverseGeocode(ll.LatLng point) async {
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=12&addressdetails=1&accept-language=uz',
    );
    final response =
        await http.get(uri, headers: {'User-Agent': 'avtoservis-flutter-app'});
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return data['display_name'] as String?;

      // Viloyat (yoki respublika ahamiyatiga ega shahar, masalan Toshkent).
      final region = (addr['state'] as String?) ??
          (addr['region'] as String?) ??
          (addr['city'] as String?);

      // Tuman (yoki shahar ichidagi tuman/shahar).
      final district = (addr['county'] as String?) ??
          (addr['city_district'] as String?) ??
          (addr['town'] as String?) ??
          (addr['municipality'] as String?) ??
          (addr['suburb'] as String?);

      if (region != null && district != null && district != region) {
        return '$region, $district';
      }
      return region ?? district ?? (data['display_name'] as String?);
    }
  } catch (_) {}
  return null;
}

// ========================================================================
// CUSTOMER LOCATION SCREEN (mijoz joylashuvini xaritada ko'rsatish)
// ========================================================================

class CustomerLocationScreen extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String customerName;
  const CustomerLocationScreen(
      {super.key,
      required this.latitude,
      required this.longitude,
      required this.customerName});
  @override
  State<CustomerLocationScreen> createState() => _CustomerLocationScreenState();
}

// Ikkita gradus qiymati orasidan eng qisqa yo'l bilan (masalan 350° -> 10°
// oralig'ida 360° aylanib chiqmasdan) silliq interpolyatsiya qiladi.
// Bu xarita burilishi (rotation) va yo'nalish (bearing) sakramasligi uchun.
double _lerpAngleDeg(double a, double b, double t) {
  double diff = (b - a) % 360;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  final result = (a + diff * t) % 360;
  return result < 0 ? result + 360 : result;
}

class _CustomerLocationScreenState extends State<CustomerLocationScreen>
    with TickerProviderStateMixin {
  late final _point = ll.LatLng(widget.latitude, widget.longitude);
  final _mapController = MapController();

  ll.LatLng? _myLocation;
  List<ll.LatLng> _routePoints = [];
  bool _loadingRoute = true;
  bool _following = false;
  bool _mapReady = false;
  double? _distanceMeters;
  StreamSubscription<Position>? _posSub;

  // ---------------------------------------------------------------------
  // NAVIGATSIYA REJIMI (Google Maps / Yandex Navigator / Uber uslubida):
  // - haydovchi markeri ekranning pastki qismida (taxminan 70-75% balandlikda)
  //   qotib turadi, uning o'rniga xarita siljiydi;
  // - xarita harakat yo'nalishiga (bearing) qarab avtomatik buriladi;
  // - kamera biroz "engashgan" (pseudo-3D tilt) ko'rinishda bo'ladi;
  // - har bir GPS yangilanishida kamera sakramasdan, silliq animatsiya
  //   bilan yangi holatga o'tadi.
  // ---------------------------------------------------------------------
  static const double _navZoom = 17.5;
  static const double _navTiltDeg = 52; // kamera og'ish burchagi (45-60°)
  static const double _navMarkerFraction =
      0.72; // marker ekran balandligining necha ulushida turishi (0.5=markaz)

  Position? _lastRawPos;
  double _bearing = 0; // joriy silliqlangan harakat yo'nalishi (0-360°)
  double _mapViewHeight = 0; // xarita widgetining joriy balandligi (piksel)

  late final AnimationController _camCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late ll.LatLng _camBeginCenter = _point;
  late ll.LatLng _camEndCenter = _point;
  double _camBeginZoom = 15;
  double _camEndZoom = 15;
  double _camBeginRotation = 0;
  double _camEndRotation = 0;

  @override
  void initState() {
    super.initState();
    _camCtrl.addListener(_onCameraTick);
    _loadInitial();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _camCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final loc = await resolveCurrentLocation();
    if (!mounted) return;
    setState(() {
      _myLocation = loc;
      _loadingRoute = false;
    });
    if (loc != null) {
      _distanceMeters = Geolocator.distanceBetween(
          loc.latitude, loc.longitude, _point.latitude, _point.longitude);
      final route = await fetchRoadRoute(loc, _point);
      if (!mounted) return;
      setState(() => _routePoints = route);
      _fitBounds();
    }
  }

  void _fitBounds() {
    if (!_mapReady || _myLocation == null) return;
    try {
      final dist = Geolocator.distanceBetween(
        _myLocation!.latitude,
        _myLocation!.longitude,
        _point.latitude,
        _point.longitude,
      );
      // Ikki nuqta bir-biriga judayam yaqin (yoki bir xil) bo'lsa, bounds
      // o'lchami deyarli nolga teng bo'lib qoladi va flutter_map cheksiz
      // (Infinity) zoom hisoblab, xaritani buzib qo'yadi. Bunday holatda
      // shunchaki o'sha nuqtaga belgilangan zoom bilan markazlashtiramiz.
      if (dist < 30) {
        _mapController.move(_point, 16);
        return;
      }
      final bounds = LatLngBounds.fromPoints([_myLocation!, _point]);
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.fromLTRB(50, 90, 50, 140),
        maxZoom: 17,
      ));
    } catch (_) {}
  }

  // "Ketdik" tugmasi — Yandex/taxi ilovalaridagidek, mijoz oldiga yetib
  // borguncha o'z joylashuvini jonli kuzatib, xaritada mijozgacha bo'lgan
  // yo'lni doimiy yangilab boradi. Bu rejimda xarita to'liq navigatsiya
  // kamerasiga o'tadi (marker pastda, xarita buriladi).
  Future<void> _startNavigation() async {
    final has = await Geolocator.isLocationServiceEnabled();
    if (!has) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Joylashuv xizmatini yoqing'),
            backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _following = true);
    _lastRawPos = null;

    // "Ketdik" bosilgan zahoti, birinchi GPS yangilanishini kutmasdan,
    // xaritani darhol qolgan MARSHRUT yo'nalishi bo'yicha buramiz — shunda
    // chizilgan yo'l boshidanoq ekranning tepa qismida ko'rinadi (avvalgi
    // rasmda yo'l pastda/orqada ko'rinib turishining sababi shu — birinchi
    // GPS harakat/kompas signali kelguncha xarita hali shimol tepada
    // burilmagan holda qolib ketardi).
    if (_myLocation != null) {
      final initialBearing = _bearingAlongRoute(_myLocation!, _routePoints);
      if (initialBearing != null) _bearing = initialBearing;
      _flyToNavigationCamera(_myLocation!);
    }

    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) async {
      if (!mounted) return;
      final me = ll.LatLng(pos.latitude, pos.longitude);
      final dist = Geolocator.distanceBetween(
          me.latitude, me.longitude, _point.latitude, _point.longitude);

      // Marshrutni AVVAL yangilaymiz — shunda yo'nalish va kamera eskirgan
      // emas, aynan shu yangi marshrutga mos hisoblanadi.
      final route = await fetchRoadRoute(me, _point);
      if (!mounted) return;
      setState(() => _routePoints = route);

      _updateBearing(pos, routeBearingOverride: _bearingAlongRoute(me, route));

      setState(() {
        _myLocation = me;
        _distanceMeters = dist;
      });

      if (!mounted) return;
      _flyToNavigationCamera(me);

      if (dist < 60) {
        _stopNavigation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Siz mijoz manziliga yetib keldingiz'),
              backgroundColor: AppColors.success),
        );
      }
    });
  }

  void _stopNavigation() {
    _posSub?.cancel();
    _posSub = null;
    if (mounted) {
      setState(() => _following = false);
      // Kuzatish to'xtaganda xaritani odatdagi (shimol tepada, tiltsiz) holatga
      // silliq qaytaramiz.
      _flyCamera(_myLocation ?? _point, 15, 0);
    }
  }

  // Haydovchi joriy turgan nuqtadan boshlab, MARSHRUT chizig'i bo'ylab
  // biroz oldinga (taxminan 25 metr) siljigan nuqtagacha bo'lgan
  // yo'nalishni (bearing) hisoblaydi — ya'ni "hali bosib o'tilmagan, oldinda
  // turgan yo'l qaysi tomonga ketyapti". Bu, GPS harakat/kompas
  // yo'nalishidan farqli o'laroq, doim mavjud va barqaror bo'lgani uchun,
  // xaritani ana shu yo'nalishga qarab burish natijasida chizilgan yo'l
  // (marshrut) har doim ekranning YUQORI qismida, haydovchining oldida
  // ko'rsatiladi — xuddi Google Maps/Yandex Navigatordagi kabi.
  double? _bearingAlongRoute(ll.LatLng from, List<ll.LatLng> route) {
    if (route.length < 2) return null;

    // Marshrut bo'ylab haydovchiga eng yaqin nuqtani topamiz (haydovchi
    // marshrutdan biroz chetga chiqib qolgan bo'lishi ham mumkin).
    int nearestIdx = 0;
    double nearestDist = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = Geolocator.distanceBetween(
          from.latitude, from.longitude, route[i].latitude, route[i].longitude);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIdx = i;
      }
    }

    // Shu nuqtadan boshlab, ~25 metr oldinga siljigan nuqtagacha marshrut
    // bo'ylab yuramiz — bearing shu ikki nuqta orasidan hisoblanadi. Bu
    // marshrutning darhol keyingi burilishidan emas, biroz "kengroq"
    // yo'nalishidan kelib chiqqani uchun, xarita har bir mayda zigzagda
    // emas, umumiy yo'l yo'nalishida silliq buriladi.
    const lookaheadMeters = 25.0;
    double accumulated = 0;
    ll.LatLng target = route[nearestIdx];
    for (var i = nearestIdx; i < route.length - 1; i++) {
      accumulated += Geolocator.distanceBetween(route[i].latitude,
          route[i].longitude, route[i + 1].latitude, route[i + 1].longitude);
      target = route[i + 1];
      if (accumulated >= lookaheadMeters) break;
    }

    if (target.latitude == from.latitude &&
        target.longitude == from.longitude) {
      return null;
    }
    return Geolocator.bearingBetween(
        from.latitude, from.longitude, target.latitude, target.longitude);
  }

  // Haydovchining joriy harakat yo'nalishini (bearing) hisoblaydi.
  // Ustuvorlik tartibi:
  //  1) routeBearingOverride — marshrut chizig'i bo'yicha hisoblangan
  //     yo'nalish (har doim mavjud bo'lsa, shu ishlatiladi, chunki eng
  //     barqaror va chizilgan yo'lni doim tepada ko'rsatishni kafolatlaydi);
  //  2) oxirgi ikkita GPS nuqtasi orasidagi haqiqiy harakat yo'nalishi;
  //  3) qurilma kompasi (faqat ishonchli va harakatda bo'lganda).
  // Natija har doim silliqlanadi — shu tufayli xarita burilishi to'satdan
  // sakramaydi.
  void _updateBearing(Position pos, {double? routeBearingOverride}) {
    double? bearing = routeBearingOverride;
    if (bearing == null && _lastRawPos != null) {
      final moved = Geolocator.distanceBetween(_lastRawPos!.latitude,
          _lastRawPos!.longitude, pos.latitude, pos.longitude);
      if (moved > 3) {
        bearing = Geolocator.bearingBetween(_lastRawPos!.latitude,
            _lastRawPos!.longitude, pos.latitude, pos.longitude);
      }
    }
    bearing ??= (pos.headingAccuracy >= 0 &&
            pos.headingAccuracy < 40 &&
            pos.heading >= 0 &&
            pos.speed > 0.6)
        ? pos.heading
        : null;
    _lastRawPos = pos;
    if (bearing == null) return; // yo'nalishni bilmasak, eskisini saqlaymiz
    if (bearing < 0) bearing += 360;
    _bearing = _lerpAngleDeg(_bearing, bearing, 0.55);
  }

  // Haydovchi joylashuvini olib, navigatsiya kamerasi uchun yangi markaz,
  // zoom va burilishni hisoblab, silliq animatsiya bilan xaritani yangilaydi.
  void _flyToNavigationCamera(ll.LatLng me) {
    final screenH = _mapViewHeight > 0 ? _mapViewHeight : 500.0;
    // Markerni ekranning pastki qismida (masalan 72%) ushlab turish uchun,
    // xarita markazini haydovchi turgan joydan OLDINGA (harakat yo'nalishi
    // bo'yicha) siljitamiz. Shunda markaz "oldinda"ligi sababli, haydovchi
    // ekranda markazdan pastroqda, ya'ni ekranning quyi qismida ko'rinadi.
    final centerOffsetPx = (_navMarkerFraction - 0.5) * screenH;
    final metersPerPixel =
        156543.03392 * cos(me.latitude * pi / 180) / pow(2, _navZoom);
    final aheadMeters = centerOffsetPx * metersPerPixel;
    final navCenter = aheadMeters > 1
        ? const ll.Distance().offset(me, aheadMeters, _bearing)
        : me;
    // Xaritani -bearing gradusga buramiz — shunda haydovchi yo'nalishi
    // doim ekranning tepasiga (oldinga) qarab turadi, xuddi navigatordagidek.
    _flyCamera(navCenter, _navZoom, -_bearing);
  }

  // Xaritani joriy kamera holatidan berilgan yangi holatga (markaz, zoom,
  // burilish) 700ms davomida silliq animatsiya bilan olib boradi — hech
  // qanday sakrash bo'lmaydi.
  void _flyCamera(
      ll.LatLng targetCenter, double targetZoom, double targetRotation) {
    if (!mounted) return;
    final cam = _mapController.camera;
    _camBeginCenter = cam.center;
    _camBeginZoom = cam.zoom;
    _camBeginRotation = cam.rotation;
    _camEndCenter = targetCenter;
    _camEndZoom = targetZoom;
    _camEndRotation = targetRotation;
    _camCtrl
      ..stop()
      ..value = 0
      ..forward();
  }

  void _onCameraTick() {
    final t = Curves.easeOutCubic.transform(_camCtrl.value);
    final lat = _camBeginCenter.latitude +
        (_camEndCenter.latitude - _camBeginCenter.latitude) * t;
    final lng = _camBeginCenter.longitude +
        (_camEndCenter.longitude - _camBeginCenter.longitude) * t;
    final zoom = _camBeginZoom + (_camEndZoom - _camBeginZoom) * t;
    final rot = _lerpAngleDeg(_camBeginRotation, _camEndRotation, t);
    _mapController.moveAndRotate(ll.LatLng(lat, lng), zoom, rot);
  }

  String _formatDistance(double? meters) {
    if (meters == null) return '—';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Widget _buildNavMap() {
    final map = FlutterMap(
      key: const ValueKey('nav_map'),
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _myLocation ?? _point,
        initialZoom: 15,
        // Navigatsiya rejimida foydalanuvchi qo'lda surib/burab yubormasligi
        // uchun interaktivlikni o'chiramiz — kamera to'liq avtomatik boshqariladi.
        interactionOptions: InteractionOptions(
          flags: _following ? InteractiveFlag.none : InteractiveFlag.all,
        ),
        onMapReady: () {
          _mapReady = true;
          _fitBounds();
        },
      ),
      children: [
        osmTileLayer(),
        if (_routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              // GPS ilovalaridagi (Google Maps/Yandex Navigator) kabi
              // marshrut chizig'i har doim xarita ustida aniq ko'rinishi
              // uchun oq "konturli" (casing) uslub qo'llanadi — shunda
              // chiziq ko'cha nomlari/rangli fonlar ostida yo'qolib
              // qolmaydi.
              Polyline(
                points: _routePoints,
                strokeWidth: 6,
                color: AppColors.primary,
                borderStrokeWidth: 2.5,
                borderColor: Colors.white,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        MarkerLayer(markers: [
          Marker(
            point: _point,
            width: 42,
            height: 42,
            child: Container(
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: AppColors.primaryGradient),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 6))
                ],
              ),
              child: const Icon(Icons.person_pin_circle_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
          if (_myLocation != null)
            Marker(
              point: _myLocation!,
              width: 40,
              height: 40,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.textPrimary, width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                // Xarita o'zi harakat yo'nalishiga qarab burilgani uchun
                // (rotation = -bearing), "yuqoriga qaragan" belgi navigatsiya
                // paytida doim to'g'ri (oldinga qarab) ko'rinadi.
                child: Icon(
                    _following
                        ? Icons.navigation_rounded
                        : Icons.local_shipping_rounded,
                    color: AppColors.textPrimary,
                    size: 20),
              ),
            ),
        ]),
      ],
    );

    // -----------------------------------------------------------------
    // ESLATMA: Ilgari bu yerda rotateX + perspektiv Transform orqali
    // pseudo-3D "engashgan kamera" effekti yaratilgan edi. flutter_map buni
    // chinakam qo'llab-quvvatlamagani uchun, tilt burchagi oshganda (52°)
    // xarita trapezoid shaklga kichrayib, konteynerning yuqori qismida
    // bo'sh (oq) joy qolib ketardi — aynan shu "Kuzatilmoqda" rejimida
    // xarita yarim bo'sh ko'rinishining sababi shu edi.
    // Google Maps'ning marshrut skrinshotidagi kabi (tekis, yuqoridan
    // ko'rinish) ishonchli va har doim konteynerni to'liq to'ldiradigan
    // natija uchun, endi xarita hech qanday sun'iy tilt/scale'siz, to'g'ridan
    // -to'g'ri ko'rsatiladi. Yo'nalishga qarab burilish (bearing) hali ham
    // _flyCamera orqali moveAndRotate bilan ishlayveradi — faqat soxta 3D
    // "engashish" olib tashlandi.
    // -----------------------------------------------------------------
    return map;
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
                    child: Text(widget.customerName,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _mapViewHeight = constraints.maxHeight;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          _buildNavMap(),
                          if (_loadingRoute)
                            const Positioned(
                                top: 16, child: CircularProgressIndicator()),
                          if (!_loadingRoute && _distanceMeters != null)
                            Positioned(
                              top: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3))
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                        _following
                                            ? Icons.navigation_rounded
                                            : Icons.social_distance_rounded,
                                        size: 16,
                                        color: AppColors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      _following
                                          ? 'Kuzatilmoqda • ${_formatDistance(_distanceMeters)} qoldi'
                                          : 'Masofa: ${_formatDistance(_distanceMeters)}',
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: _following
                  ? SolidActionButton(
                      label: 'Kuzatishni to\'xtatish',
                      onPressed: _stopNavigation,
                    )
                  : GlassGradientButton(
                      label: 'Ketdik',
                      icon: Icons.navigation_rounded,
                      onPressed: _myLocation == null ? null : _startNavigation,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================================================
// MAP PICKER
// ========================================================================

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const ll.LatLng _defaultCenter = ll.LatLng(39.6542, 66.9597);

  final _mapController = MapController();
  final _addressController = TextEditingController();
  ll.LatLng? _selectedPoint;
  Timer? _debounce;
  bool _resolvingAddress = false;
  bool _locating = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  void _scheduleReverseGeocode() {
    if (_selectedPoint == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _resolvingAddress = true);
      final address = await reverseGeocode(_selectedPoint!);
      if (!mounted) return;
      setState(() {
        _resolvingAddress = false;
        if (address != null) _addressController.text = address;
      });
    });
  }

  void _onMapTap(ll.LatLng point) {
    setState(() {
      _selectedPoint = point;
      _addressController.text = '';
    });
    _scheduleReverseGeocode();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final loc = await resolveCurrentLocation();
    setState(() => _locating = false);
    if (loc == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Joylashuvni aniqlab bo\'lmadi, ruxsat berilganini tekshiring')),
      );
      return;
    }
    _mapController.move(loc, 16);
    setState(() {
      _selectedPoint = loc;
      _addressController.text = '';
    });
    _scheduleReverseGeocode();
  }

  void _confirm() {
    if (_selectedPoint == null) return;
    final address = _addressController.text.trim().isEmpty
        ? 'Xaritada belgilangan manzil (${_selectedPoint!.latitude.toStringAsFixed(5)}, ${_selectedPoint!.longitude.toStringAsFixed(5)})'
        : _addressController.text.trim();
    Navigator.pop(context, {
      'address': address,
      'latitude': _selectedPoint!.latitude,
      'longitude': _selectedPoint!.longitude
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  authBackButton(context),
                  const SizedBox(width: 14),
                  const Text('Xaritada nuqta tanlash',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Xizmat joylashgan nuqtani xaritada bosib belgilang',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _defaultCenter,
                          initialZoom: 12,
                          onTap: (tapPosition, point) => _onMapTap(point),
                        ),
                        children: [
                          osmTileLayer(),
                          if (_selectedPoint != null)
                            MarkerLayer(markers: [
                              Marker(
                                point: _selectedPoint!,
                                width: 42,
                                height: 42,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: AppColors.primaryGradient),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.primary
                                              .withOpacity(0.4),
                                          blurRadius: 14,
                                          offset: const Offset(0, 6))
                                    ],
                                  ),
                                  child: const Icon(Icons.build_circle,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ]),
                        ],
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FloatingActionButton.small(
                          heroTag: 'locate',
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                          onPressed: _locating ? null : _useMyLocation,
                          child: _locating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.2))
                              : const Icon(Icons.my_location_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                  TextField(
                    controller: _addressController,
                    readOnly: true,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    decoration: InputDecoration(
                      hintText: _selectedPoint == null
                          ? 'Avval xaritadan nuqta tanlang'
                          : 'Hudud aniqlanmoqda...',
                      prefixIcon: const Icon(Icons.location_on_outlined,
                          color: AppColors.textMuted),
                      suffixIcon: _resolvingAddress
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassGradientButton(
                      label: 'Tasdiqlash',
                      onPressed: _selectedPoint == null ? null : _confirm),
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
// SERVICE OWNER PENDING SCREEN
// ========================================================================

class ServiceOwnerPendingScreen extends StatefulWidget {
  final int serviceId;
  final String serviceName;
  final int ownerId;
  final String providerType;
  const ServiceOwnerPendingScreen(
      {super.key,
      required this.serviceId,
      required this.serviceName,
      required this.ownerId,
      this.providerType = 'auto_service'});
  @override
  State<ServiceOwnerPendingScreen> createState() =>
      _ServiceOwnerPendingScreenState();
}

class _ServiceOwnerPendingScreenState extends State<ServiceOwnerPendingScreen> {
  String _status = 'pending';
  String? _rejectReason;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (widget.serviceId == 0) return;
    final result = await ApiService.serviceOwnerStatus(widget.serviceId);
    if (!mounted || result['success'] != true) return;
    final data = result['data'] as Map<String, dynamic>;
    setState(() {
      _status = data['status'] ?? 'pending';
      _rejectReason = data['reject_reason'];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isApproved = _status == 'approved';
    final isRejected = _status == 'rejected';
    final Color color = isApproved
        ? AppColors.success
        : (isRejected ? AppColors.error : AppColors.warning);
    final IconData icon = isApproved
        ? Icons.check_rounded
        : (isRejected ? Icons.close_rounded : Icons.hourglass_top_rounded);
    final String title = isApproved
        ? 'Arizangiz tasdiqlandi!'
        : (isRejected ? 'Ariza rad etildi' : 'Arizangiz ko\'rib chiqilmoqda');
    final String subtitle = isApproved
        ? '${widget.serviceName} endi ilovada ko\'rinadi va buyurtmalarni qabul qila boshlaydi.'
        : (isRejected
            ? (_rejectReason?.isNotEmpty == true
                ? _rejectReason!
                : 'Admin arizani rad etdi. Ma\'lumotlarni tekshirib qayta yuboring.')
            : '${widget.serviceName} arizasi admin tomonidan tekshirilmoqda. Bu odatda tez amalga oshadi.');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 44),
              ),
              const SizedBox(height: 24),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      height: 1.5)),
              if (_status == 'pending') ...[
                const SizedBox(height: 20),
                const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.primary)),
              ],
              const Spacer(flex: 2),
              if (isApproved)
                GlassGradientButton(
                  label: 'Boshlash',
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ServiceOwnerHomeScreen(
                            ownerId: widget.ownerId,
                            serviceId: widget.serviceId,
                            serviceName: widget.serviceName,
                            providerType: widget.providerType)),
                    (r) => false,
                  ),
                )
              else
                GlassGradientButton(
                  label: 'Chiqish',
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const WelcomeScreen()),
                          (r) => false);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================================================
// LOGIN SCREEN
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

  Future<void> _goToOtpStep() async {
    if (_digits.length < 9 || _isSendingOtp) return;
    final phone = _formatPhone(_phoneController.text);
    // Apple App Store Connect reviewer test raqami: qayta kirishda SMS
    // bosqichi butunlay o'tkazib yuborilib, to'g'ridan-to'g'ri parol
    // bosqichiga o'tiladi.
    if (phone == '+998889791000') {
      setState(() => _step = 2);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _passwordFocusNode.requestFocus());
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
// HOME SCREEN (MIJOZ) — bottom nav: Bosh sahifa / Xarita / Buyurtmalar / Chat / Profil
// ========================================================================

class ServiceOwnerHomeScreen extends StatefulWidget {
  final int ownerId;
  final int serviceId;
  final String serviceName;
  // "auto_service" | "evacuator" | "fuel"
  final String providerType;
  const ServiceOwnerHomeScreen(
      {super.key,
      required this.ownerId,
      required this.serviceId,
      required this.serviceName,
      this.providerType = 'auto_service'});

  @override
  State<ServiceOwnerHomeScreen> createState() => _ServiceOwnerHomeScreenState();
}

class _ServiceOwnerHomeScreenState extends State<ServiceOwnerHomeScreen> {
  int _selectedIndex = 0;

  bool get _isAutoService => widget.providerType == 'auto_service';

  // Evakuator/benzin yetkazish uchun "Xizmatlar" bo'limi kerak emas - ular
  // faqat o'zining bitta xizmat turini ko'rsatadi, admin katalogidan tanlash shart emas.
  late final _tabs = _isAutoService
      ? [
          ServiceOwnerDashboardTab(
              ownerId: widget.ownerId,
              serviceName: widget.serviceName,
              providerType: widget.providerType),
          ServiceOwnerOrdersTab(
              ownerId: widget.ownerId, providerType: widget.providerType),
          ServiceOwnerServicesTab(ownerId: widget.ownerId),
          ServiceOwnerStatsTab(ownerId: widget.ownerId),
          ServiceOwnerProfileTab(ownerId: widget.ownerId),
        ]
      : [
          ServiceOwnerDashboardTab(
              ownerId: widget.ownerId,
              serviceName: widget.serviceName,
              providerType: widget.providerType),
          ServiceOwnerOrdersTab(
              ownerId: widget.ownerId, providerType: widget.providerType),
          ServiceOwnerStatsTab(ownerId: widget.ownerId),
          ServiceOwnerProfileTab(ownerId: widget.ownerId),
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
    final items = _isAutoService
        ? [
            (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Asosiy'),
            (
              Icons.receipt_long_outlined,
              Icons.receipt_long_rounded,
              'Buyurtmalar'
            ),
            (Icons.build_outlined, Icons.build_rounded, 'Xizmatlar'),
            (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Statistika'),
            (Icons.person_outline, Icons.person_rounded, 'Profil'),
          ]
        : [
            (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Asosiy'),
            (
              Icons.receipt_long_outlined,
              Icons.receipt_long_rounded,
              'Buyurtmalar'
            ),
            (Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'Statistika'),
            (Icons.person_outline, Icons.person_rounded, 'Profil'),
          ];
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.82),
            border: const Border(
                top: BorderSide(color: AppColors.border, width: 0.6)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final selected = _selectedIndex == i;
                final (outline, filled, label) = items[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selectedIndex = i),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(selected ? filled : outline,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textMuted,
                            size: 24),
                        const SizedBox(height: 4),
                        Text(label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                            )),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Dashboard tab -----------------------------------------------------

// ---- Evakuator/benzin dastavka buyurtmalari uchun umumiy yordamchilar ----
// Bir nechta ekranda (Bosh sahifa/"Yangi buyurtma", Buyurtmalar bo'limi)
// bir xil ko'rinishda ishlatilishi uchun top-level qilib chiqarilgan.
const Map<String, String> fuelTypeLabels = {
  'ai92': 'AI-92',
  'ai95': 'AI-95',
  'ai98': 'AI-98',
  'ai100': 'AI-100',
  'hyperfuel': 'HyperFuel',
};

String formatSomPrice(num v) {
  final s = v.toInt().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '$buf so\'m';
}

// Evakuator/benzin dastavka buyurtmalari uchun "Shoshilinch" / "Shoshilinch
// emas" holatini sezilarli darajada (qizil/yashil) ko'rsatadigan banner.
Widget? orderUrgencyBanner(Map<String, dynamic> order) {
  final providerType = order['provider_type'] as String? ?? 'auto_service';
  final isMobileProvider =
      providerType == 'evacuator' || providerType == 'fuel';
  if (!isMobileProvider) return null;
  final isUrgent = order['is_urgent'] == true;
  final color = isUrgent ? AppColors.error : AppColors.success;
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 1.4),
    ),
    child: Row(
      children: [
        Icon(isUrgent ? Icons.bolt_rounded : Icons.check_circle_outline_rounded,
            size: 17, color: color),
        const SizedBox(width: 6),
        Text(
          isUrgent ? 'SHOSHILINCH BUYURTMA' : "Shoshilinch emas",
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
        ),
      ],
    ),
  );
}

// Benzin dastavka buyurtmasida qaysi benzin turi so'ralganini ko'rsatadi.
Widget? orderFuelTypeInfo(Map<String, dynamic> order) {
  final providerType = order['provider_type'] as String? ?? 'auto_service';
  if (providerType != 'fuel') return null;
  final fuelType = order['fuel_type'] as String?;
  if (fuelType == null) return null;
  final label = fuelTypeLabels[fuelType] ?? fuelType;
  final liters = order['liters'];
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        const Icon(Icons.local_gas_station_rounded,
            size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          liters != null
              ? 'Benzin turi: $label ($liters L)'
              : 'Benzin turi: $label',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primary),
        ),
      ],
    ),
  );
}

// Buyurtma narxini (agar mavjud bo'lsa) ko'rsatadigan qator - har qanday
// buyurtma kartochkasida bir xil ko'rinishda ishlatiladi.
Widget? orderPriceInfo(Map<String, dynamic> order) {
  final price = order['price'];
  if (price == null) return null;
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        const Icon(Icons.payments_rounded, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(
          'Narxi: ${formatSomPrice(price as num)}',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.primary),
        ),
      ],
    ),
  );
}

Widget orderTypeBadge(Map<String, dynamic> order) {
  final isScheduled = (order['order_type']?.toString() ?? 'now') == 'scheduled';
  if (isScheduled) {
    String text = 'Bron';
    final date = DateTime.tryParse(order['scheduled_at']?.toString() ?? '');
    if (date != null) {
      final local = date.toLocal();
      text =
          'Bron: ${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded,
              size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 11.5,
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
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.bolt_rounded, size: 13, color: AppColors.textSecondary),
        SizedBox(width: 4),
        Text('Hozir',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
      ],
    ),
  );
}

class ServiceOwnerDashboardTab extends StatefulWidget {
  final int ownerId;
  final String serviceName;
  // "auto_service" | "evacuator" | "fuel"
  final String providerType;
  const ServiceOwnerDashboardTab(
      {super.key,
      required this.ownerId,
      required this.serviceName,
      this.providerType = 'auto_service'});
  @override
  State<ServiceOwnerDashboardTab> createState() =>
      _ServiceOwnerDashboardTabState();
}

class _ServiceOwnerDashboardTabState extends State<ServiceOwnerDashboardTab> {
  Map<String, dynamic>? _dashboard;
  List<dynamic> _newOrders = [];
  bool _loading = true;
  Timer? _poller;
  int _unreadNotifications = 0;

  // ---- Evakuator/benzin dastavka: ish vaqti va jonli joylashuv holati ----
  bool get _isProvider =>
      widget.providerType == 'evacuator' || widget.providerType == 'fuel';
  bool _isOnline = false;
  bool _locationMissing = false;
  bool _locationPermissionIssue = false;
  Timer? _workWindowTimer;
  Timer? _locationTimer;
  bool _promptShowing = false;

  static const _dayNames = [
    'Yakshanba',
    'Dushanba',
    'Seshanba',
    'Chorshanba',
    'Payshanba',
    'Juma',
    'Shanba'
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _poller = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    if (_isProvider) {
      _workWindowTimer = Timer.periodic(
          const Duration(seconds: 20), (_) => _checkWorkWindow());
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    _workWindowTimer?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_dashboard == null) setState(() => _loading = true);
    final results = await Future.wait([
      ApiService.getServiceOwnerDashboard(widget.ownerId),
      ApiService.getServiceOwnerOrders(widget.ownerId),
    ]);
    if (!mounted) return;
    final dashboardResult = results[0];
    final ordersResult = results[1];
    final orders = ordersResult['success'] == true
        ? ordersResult['data'] as List
        : <dynamic>[];
    setState(() {
      _dashboard = dashboardResult['data'] as Map<String, dynamic>?;
      _newOrders = orders
          .where((o) => (o as Map<String, dynamic>)['status'] == 'pending')
          .toList();
      _isOnline = _dashboard?['is_online'] == true;
      _loading = false;
    });
    if (_isProvider) _checkWorkWindow();
    final unread = await ApiService.getUnreadNotificationsCount(widget.ownerId);
    if (mounted) setState(() => _unreadNotifications = unread);
  }

  // Ish vaqti oralig'ini ("09:00-18:00") va dam olish kunini tekshiradi.
  bool _isWithinWorkingHours() {
    final wh = _dashboard?['working_hours'] as String?;
    if (wh == null || !wh.contains('-')) return false;
    final dayOff = _dashboard?['day_off'] as String?;
    final now = DateTime.now();
    if (dayOff != null &&
        dayOff.isNotEmpty &&
        dayOff != 'Dam olish kuni yo\'q') {
      final todayName = _dayNames[now.weekday - 1];
      if (todayName == dayOff) return false;
    }
    final parts = wh.split('-');
    if (parts.length != 2) return false;
    TimeOfDay? parse(String s) {
      final hm = s.trim().split(':');
      if (hm.length != 2) return null;
      return TimeOfDay(
          hour: int.tryParse(hm[0]) ?? 0, minute: int.tryParse(hm[1]) ?? 0);
    }

    final from = parse(parts[0]);
    final to = parse(parts[1]);
    if (from == null || to == null) return false;
    final nowMin = now.hour * 60 + now.minute;
    final fromMin = from.hour * 60 + from.minute;
    final toMin = to.hour * 60 + to.minute;
    if (fromMin <= toMin) {
      return nowMin >= fromMin && nowMin < toMin;
    }
    // Tungi smena (masalan 22:00-06:00) uchun
    return nowMin >= fromMin || nowMin < toMin;
  }

  Future<void> _checkWorkWindow() async {
    if (!mounted || !_isProvider || _dashboard == null) return;
    final inWindow = _isWithinWorkingHours();

    if (!inWindow) {
      if (_isOnline) {
        await ApiService.goOffline(widget.ownerId);
        _locationTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _isOnline = false;
          _locationMissing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Ish vaqti tugadi — xizmatingiz xaritadan olib tashlandi'),
              backgroundColor: AppColors.warning),
        );
      }
      return;
    }

    // Ish vaqti boshlangan/davom etmoqda - joylashuv holatini tekshiramiz.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (_isOnline) {
        await ApiService.goOffline(widget.ownerId);
        _locationTimer?.cancel();
        if (mounted) setState(() => _isOnline = false);
      }
      if (mounted) {
        setState(() {
          _locationMissing = true;
          _locationPermissionIssue = false;
        });
      }
      _promptEnableLocation();
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (_isOnline) {
        await ApiService.goOffline(widget.ownerId);
        _locationTimer?.cancel();
        if (mounted) setState(() => _isOnline = false);
      }
      if (mounted) {
        setState(() {
          _locationMissing = true;
          _locationPermissionIssue = true;
        });
      }
      _promptEnableLocation();
      return;
    }

    if (mounted) {
      setState(() {
        _locationMissing = false;
        _locationPermissionIssue = false;
      });
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!_isOnline) {
        await ApiService.goOnline(widget.ownerId, pos.latitude, pos.longitude);
        _locationTimer?.cancel();
        _locationTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
          if (!mounted) return;
          try {
            final p = await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.high),
            );
            await ApiService.updateLocation(
                widget.ownerId, p.latitude, p.longitude);
          } catch (_) {}
        });
        if (mounted) setState(() => _isOnline = true);
      } else {
        await ApiService.updateLocation(
            widget.ownerId, pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  Future<void> _promptEnableLocation() async {
    if (_promptShowing || !mounted) return;
    _promptShowing = true;
    final permissionIssue = _locationPermissionIssue;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
            permissionIssue ? 'Joylashuvga ruxsat kerak' : 'Joylashuvni yoqing',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          permissionIssue
              ? 'Ish vaqtingiz boshlandi. Buyurtmalar sizga yetib borishi va xaritada ko\'rinishingiz uchun ilova sozlamalaridan joylashuvga ruxsat bering.'
              : 'Ish vaqtingiz boshlandi. Buyurtmalar sizga yetib borishi va xaritada ko\'rinishingiz uchun telefoningizda joylashuv (GPS) xizmatini yoqing.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keyinroq')),
          GlassGradientButton(
            label: 'Sozlamalarga o\'tish',
            height: 42,
            onPressed: () {
              Navigator.pop(ctx);
              // Ikkala holatda ham Geolocator mos tizim sozlamalarini
              // ochadi - iOS'da ham, Android'da ham ishlaydi.
              if (permissionIssue) {
                Geolocator.openAppSettings();
              } else {
                Geolocator.openLocationSettings();
              }
            },
          ),
        ],
      ),
    );
    _promptShowing = false;
  }

  Future<void> _respond(int orderId, String status) async {
    final result = await ApiService.updateOrderStatus(orderId, status);
    if (!mounted) return;
    if (result['success'] == true) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Xatolik'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _workStatusCard() {
    final Color color = _locationMissing
        ? AppColors.error
        : (_isOnline ? AppColors.success : AppColors.textMuted);
    final String title = _locationMissing
        ? 'Joylashuv o\'chirilgan'
        : (_isOnline ? 'Xizmatda — xaritada ko\'rinyapsiz' : 'Hozircha oflayn');
    final String subtitle = _locationMissing
        ? 'Buyurtmalarga chiqish uchun GPSni yoqing'
        : (_isOnline
            ? 'Joylashuvingiz mijozlarga jonli ko\'rsatilmoqda'
            : 'Ish vaqti boshlanishi bilan avtomatik onlayn bo\'lasiz');
    return LiquidGlass(
      radius: 16,
      tintOpacity: 0.9,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (_locationMissing)
            TextButton(
              onPressed: () => _locationPermissionIssue
                  ? Geolocator.openAppSettings()
                  : Geolocator.openLocationSettings(),
              child: const Text('Yoqish',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Servis paneli',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                      Text(widget.serviceName,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => OwnerNotificationsScreen(
                                ownerId: widget.ownerId)));
                    _load();
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                            color: AppColors.chipBg,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.notifications_none_rounded,
                            color: AppColors.textPrimary, size: 22),
                      ),
                      if (_unreadNotifications > 0)
                        Positioned(
                          right: 8,
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
                if (_dashboard != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_dashboard!['status'] == 'approved'
                              ? AppColors.success
                              : AppColors.warning)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _dashboard!['status'] == 'approved'
                          ? 'Faol'
                          : 'Kutilmoqda',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _dashboard!['status'] == 'approved'
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
            if (_isProvider && _dashboard != null) ...[
              const SizedBox(height: 16),
              _workStatusCard(),
            ],
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
            else if (_dashboard == null)
              const Center(child: Text('Ma\'lumot yuklanmadi'))
            else
              Column(
                children: [
                  if (_newOrders.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text('🆕 Yangi buyurtmalar',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('${_newOrders.length}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final o in _newOrders)
                      _newOrderCard(o as Map<String, dynamic>),
                    const SizedBox(height: 10),
                  ],
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.35,
                    children: [
                      _statCard(
                          'Bugungi buyurtmalar',
                          '${_dashboard!['today_orders'] ?? 0}',
                          Icons.today_rounded,
                          AppColors.primary),
                      _statCard(
                          'Faol buyurtmalar',
                          '${_dashboard!['active_orders'] ?? 0}',
                          Icons.local_shipping_rounded,
                          AppColors.warning),
                      _statCard(
                          'Yakunlangan',
                          '${_dashboard!['completed_orders'] ?? 0}',
                          Icons.check_circle_rounded,
                          AppColors.success),
                      _statCard(
                          'Daromad',
                          '${_dashboard!['revenue']?.toStringAsFixed(0) ?? 0} so\'m',
                          Icons.attach_money_rounded,
                          AppColors.primaryDark),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('So\'nggi buyurtmalar',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 14),
                  if ((_dashboard!['recent_orders'] as List? ?? [])
                      .where((o) =>
                          (o as Map<String, dynamic>)['status'] != 'pending')
                      .isEmpty)
                    const Center(
                        child: Text('Hozircha buyurtmalar yo\'q',
                            style: TextStyle(color: AppColors.textMuted)))
                  else
                    for (final o
                        in (_dashboard!['recent_orders'] as List? ?? []))
                      if ((o as Map<String, dynamic>)['status'] != 'pending')
                        _recentOrderCard(o),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Yangi (pending) buyurtma kartasi - mijoz joylashuvi va mashina turini
  // ko'rsatadi, to'g'ridan-to'g'ri qabul qilish/bekor qilish tugmalari bilan.
  Widget _newOrderCard(Map<String, dynamic> o) {
    final id = o['id'] as int;
    final providerType = o['provider_type'] as String? ?? 'auto_service';
    final isMobileProvider =
        providerType == 'evacuator' || providerType == 'fuel';
    final isUrgent = o['is_urgent'] == true;
    final accentColor = isUrgent ? AppColors.error : AppColors.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isMobileProvider
                ? accentColor.withOpacity(0.55)
                : AppColors.primary.withOpacity(0.25),
            width: isMobileProvider ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (orderUrgencyBanner(o) != null) orderUrgencyBanner(o)!,
          Row(
            children: [
              Expanded(
                child: Text(o['customer_name']?.toString() ?? 'Mijoz',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Yangi',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning)),
              ),
            ],
          ),
          if ((o['category'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.build_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(o['category'].toString(),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))),
              orderTypeBadge(o),
            ]),
          ],
          if (orderFuelTypeInfo(o) != null) orderFuelTypeInfo(o)!,
          if (orderPriceInfo(o) != null) orderPriceInfo(o)!,
          if (o['customer_phone'] != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_outlined,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(o['customer_phone'].toString(),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted)),
            ]),
          ],
          if (o['car_info'] != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.directions_car_outlined,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                  child: Text('Mashinasi: ${o['car_info']}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textMuted))),
            ]),
          ],
          if (o['user_latitude'] != null && o['user_longitude'] != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerLocationScreen(
                      latitude: (o['user_latitude'] as num).toDouble(),
                      longitude: (o['user_longitude'] as num).toDouble(),
                      customerName: o['customer_name']?.toString() ?? 'Mijoz',
                    ),
                  )),
              child: Row(children: const [
                Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.primary),
                SizedBox(width: 4),
                Text('Mijoz lokatsiyasi mavjud',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline)),
              ]),
            ),
          ],
          if ((o['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(o['description'].toString(),
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textPrimary)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SolidActionButton(
                  label: 'Bekor qilish',
                  filled: false,
                  height: 46,
                  onPressed: () => _respond(id, 'cancelled'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SolidActionButton(
                  label: 'Qabul qilish',
                  height: 46,
                  onPressed: () => _respond(id, 'accepted'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return LiquidGlass(
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
    );
  }

  Widget _recentOrderCard(Map<String, dynamic> o) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: AppColors.primaryPale.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.person_outline,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o['customer_name']?.toString() ?? 'Mijoz',
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(o['category']?.toString() ?? '',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatTime(o['created_at']?.toString()),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted)),
              if (o['price'] != null) ...[
                const SizedBox(height: 2),
                Text(formatSomPrice(o['price'] as num),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

// ---- Orders tab --------------------------------------------------------

class ServiceOwnerOrdersTab extends StatefulWidget {
  final int ownerId;
  // "auto_service" | "evacuator" | "fuel" — evakuator/benzin dastavka oldindan
  // bron qilinadigan xizmat emas, shuning uchun ularda "Hozirgi/Bronlar"
  // bo'linishi kerak emas, faqat avtoservis egasida bo'ladi.
  final String providerType;
  const ServiceOwnerOrdersTab(
      {super.key, required this.ownerId, this.providerType = 'auto_service'});
  @override
  State<ServiceOwnerOrdersTab> createState() => _ServiceOwnerOrdersTabState();
}

class _ServiceOwnerOrdersTabState extends State<ServiceOwnerOrdersTab>
    with SingleTickerProviderStateMixin {
  List<dynamic> _orders = [];
  bool _isLoading = true;
  Timer? _poller;
  late final TabController _tabController;

  bool get _isAutoService => widget.providerType == 'auto_service';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _refresh();
    _poller = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  bool _isScheduled(Map<String, dynamic> order) =>
      (order['order_type']?.toString() ?? 'now') == 'scheduled';

  // "Hozirgi" (darhol) buyurtmalar - order_type == 'now' (yoki belgilanmagan).
  List<dynamic> get _nowOrders =>
      _orders.where((o) => !_isScheduled(o as Map<String, dynamic>)).toList();

  // "Bronlar" - order_type == 'scheduled', eng yaqin sana birinchi bo'lib saralanadi.
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
                size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 11.5,
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
          Icon(Icons.bolt_rounded, size: 13, color: AppColors.textSecondary),
          SizedBox(width: 4),
          Text('Hozir',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final result = await ApiService.getServiceOwnerOrders(widget.ownerId);
    if (!mounted) return;
    setState(() {
      if (result['success'] == true) _orders = result['data'] as List;
      _isLoading = false;
    });
  }

  Future<void> _setStatus(int orderId, String status) async {
    final result = await ApiService.updateOrderStatus(orderId, status);
    if (!mounted) return;
    if (result['success'] == true) {
      _refresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result['message'] ?? 'Xatolik'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
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

  Widget? _actionButtons(Map<String, dynamic> order) {
    final id = order['id'] as int;
    final status = order['status'] as String? ?? 'pending';
    final providerType = order['provider_type'] as String? ?? 'auto_service';
    // Evakuator va benzin yetkazish provayderlari mijozning oldiga boradi -
    // shu sababli "Yo'lga chiqdim" / "Yetib keldim" bosqichlari kerak.
    // Avto servis uchun esa mijozning o'zi servisga keladi, shuning uchun
    // qabul qilingandan keyin to'g'ridan-to'g'ri yakunlash bosqichi bo'ladi.
    final isMobileProvider =
        providerType == 'evacuator' || providerType == 'fuel';

    switch (status) {
      case 'pending':
        return Row(
          children: [
            Expanded(
              child: SolidActionButton(
                label: 'Rad etish',
                filled: false,
                height: 46,
                onPressed: () => _setStatus(id, 'cancelled'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SolidActionButton(
                label: 'Qabul qilish',
                height: 46,
                onPressed: () => _setStatus(id, 'accepted'),
              ),
            ),
          ],
        );
      case 'accepted':
        if (isMobileProvider) {
          return SolidActionButton(
            label: "Yo'lga chiqdim",
            onPressed: () => _setStatus(id, 'on_way'),
          );
        }
        return SolidActionButton(
          label: 'Yakunlash',
          onPressed: () => _setStatus(id, 'completed'),
        );
      case 'on_way':
        return SolidActionButton(
          label: 'Yetib keldim',
          onPressed: () => _setStatus(id, 'arrived'),
        );
      case 'arrived':
        return SolidActionButton(
          label: 'Yakunlash',
          onPressed: () => _setStatus(id, 'completed'),
        );
      default:
        return null;
    }
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final (label, color) = _statusInfo(order['status'] as String? ?? 'pending');
    final actions = _actionButtons(order);
    final providerType = order['provider_type'] as String? ?? 'auto_service';
    final isMobileProvider =
        providerType == 'evacuator' || providerType == 'fuel';
    final isUrgent = order['is_urgent'] == true;
    final accentColor = isUrgent ? AppColors.error : AppColors.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isMobileProvider
                ? accentColor.withOpacity(0.55)
                : AppColors.border,
            width: isMobileProvider ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (orderUrgencyBanner(order) != null) orderUrgencyBanner(order)!,
          Row(
            children: [
              Expanded(
                child: Text(
                  order['customer_name']?.toString() ?? 'Mijoz',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        orderId: order['id'] as int,
                        ownerId: widget.ownerId,
                        customerName:
                            order['customer_name']?.toString() ?? 'Mijoz',
                      ),
                    )),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: AppColors.primaryPale.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      color: AppColors.primary, size: 18),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: Text(order['category']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textSecondary))),
              _typeBadge(order),
            ],
          ),
          if (orderFuelTypeInfo(order) != null) orderFuelTypeInfo(order)!,
          if (orderPriceInfo(order) != null) orderPriceInfo(order)!,
          if ((order['description'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(order['description'].toString(),
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textPrimary)),
          ],
          if (order['customer_phone'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(order['customer_phone'].toString(),
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ],
          if (order['car_info'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.directions_car_outlined,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                    child: Text('Mashinasi: ${order['car_info']}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textMuted))),
              ],
            ),
          ],
          if (order['user_latitude'] != null &&
              order['user_longitude'] != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerLocationScreen(
                      latitude: (order['user_latitude'] as num).toDouble(),
                      longitude: (order['user_longitude'] as num).toDouble(),
                      customerName:
                          order['customer_name']?.toString() ?? 'Mijoz',
                    ),
                  )),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  const Text('Mijoz lokatsiyasi',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: 14),
            actions,
          ],
        ],
      ),
    );
  }

  Widget _ordersList(List<dynamic> orders, String emptyText) {
    if (_isLoading)
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(emptyText,
                style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
        itemCount: orders.length,
        itemBuilder: (context, index) =>
            _orderCard(orders[index] as Map<String, dynamic>),
      ),
    );
  }

  // ---- Chiroyli segment tugmalar (Hozirgi buyurtmalar / Bronlar) --------
  Widget _segmentedControl() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segmentItem(
              index: 0,
              icon: Icons.bolt_rounded,
              label: 'Hozirgi',
              count: _nowOrders.length,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _segmentItem(
              index: 1,
              icon: Icons.schedule_rounded,
              label: 'Bronlar',
              count: _bookingOrders.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentItem(
      {required int index,
      required IconData icon,
      required String label,
      required int count}) {
    final selected = _tabController.index == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tabController.animateTo(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 46,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 17,
                color: selected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color:
                    selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(0.14)
                      : AppColors.textMuted.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ],
        ),
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Buyurtmalar',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh_rounded,
                          color: AppColors.primary)),
                ],
              ),
            ),
            if (_isAutoService) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: _segmentedControl(),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ordersList(_nowOrders, "Hozircha buyurtmalar yo'q"),
                    _ordersList(_bookingOrders, "Hozircha bronlar yo'q"),
                  ],
                ),
              ),
            ] else
              // Evakuator/benzin dastavka — bron qilinadigan xizmat emas,
              // shuning uchun "Hozirgi/Bronlar" bo'linishisiz barcha
              // buyurtmalar bitta ro'yxatda ko'rsatiladi.
              Expanded(
                child: _ordersList(_orders, "Hozircha buyurtmalar yo'q"),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Services tab ------------------------------------------------------

class ServiceOwnerServicesTab extends StatefulWidget {
  final int ownerId;
  const ServiceOwnerServicesTab({super.key, required this.ownerId});
  @override
  State<ServiceOwnerServicesTab> createState() =>
      _ServiceOwnerServicesTabState();
}

class _ServiceOwnerServicesTabState extends State<ServiceOwnerServicesTab> {
  List<Map<String, dynamic>> _types = [];
  bool _loading = true;
  int? _togglingId;

  // Admin katalogida ishlatilishi mumkin bo'lgan ikonka nomlarini ko'rsatish
  // uchun xarita. Admin panelida ham xuddi shu ikonka nomlari tanlanadi.
  static const _serviceIcons = {
    'evacuator': Icons.local_shipping_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'battery': Icons.battery_charging_full_rounded,
    'tire': Icons.tire_repair_rounded,
    'tech_support': Icons.build_rounded,
    'diagnostics': Icons.search_rounded,
    'oil_change': Icons.oil_barrel_rounded,
    'electrician': Icons.electrical_services_rounded,
    'engine': Icons.settings_rounded,
    'ac': Icons.ac_unit_rounded,
    'build': Icons.build_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ApiService.getServiceTypesForOwner(widget.ownerId);
    if (!mounted) return;
    setState(() {
      _types = (result['data'] as List? ?? []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _toggle(Map<String, dynamic> type) async {
    final id = type['id'] as int;
    final currentlyActive = type['is_selected'] == true;
    setState(() => _togglingId = id);
    final result = await ApiService.toggleServiceType(
        widget.ownerId, id, !currentlyActive);
    if (!mounted) return;
    setState(() => _togglingId = null);
    if (result['success'] == true) {
      setState(() => type['is_selected'] = !currentlyActive);
    }
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Xizmatlarni boshqarish',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      const Text(
                        'Nomi va narxini admin belgilaydi. Sizda mavjud bo\'lgan xizmat turlarini yoqib qo\'ying.',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.4),
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
              else if (_types.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text('Hozircha admin xizmat turi qo\'shmagan',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final type = _types[i];
                        final id = type['id'] as int;
                        final name = type['name']?.toString() ?? 'Xizmat';
                        final priceSedan = type['price_sedan'] != null
                            ? (type['price_sedan'] as num).toDouble()
                            : null;
                        final priceCrossover = type['price_crossover'] != null
                            ? (type['price_crossover'] as num).toDouble()
                            : null;
                        final iconName = type['icon'] as String? ?? 'build';
                        final icon =
                            _serviceIcons[iconName] ?? Icons.build_rounded;
                        final active = type['is_selected'] == true;
                        final isToggling = _togglingId == id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: active ? 1.5 : 1),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3))
                            ],
                          ),
                          child: Row(
                            children: [
                              OwnerLazyTypeImage(
                                item: type,
                                fallbackIcon: icon,
                                size: 44,
                                iconSize: 22,
                                borderRadius: 12,
                                backgroundColor: active
                                    ? AppColors.primary.withOpacity(0.12)
                                    : AppColors.chipBg,
                                iconColor: active
                                    ? AppColors.primary
                                    : AppColors.textMuted,
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
                                    Text(
                                      'Sedan: ${priceSedan != null ? "${priceSedan.toStringAsFixed(0)} so\'m" : "belgilanmagan"}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Krossover: ${priceCrossover != null ? "${priceCrossover.toStringAsFixed(0)} so\'m" : "belgilanmagan"}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              isToggling
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: AppColors.primary))
                                  : Switch.adaptive(
                                      value: active,
                                      activeColor: AppColors.primary,
                                      onChanged: (_) => _toggle(type),
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
      ),
    );
  }
}

// ---- Stats tab ---------------------------------------------------------

class ServiceOwnerStatsTab extends StatefulWidget {
  final int ownerId;
  const ServiceOwnerStatsTab({super.key, required this.ownerId});
  @override
  State<ServiceOwnerStatsTab> createState() => _ServiceOwnerStatsTabState();
}

class _ServiceOwnerStatsTabState extends State<ServiceOwnerStatsTab> {
  String _period = 'daily';
  Map<String, dynamic>? _stats;
  bool _loading = true;

  final _periods = [
    {'label': 'Kunlik', 'value': 'daily'},
    {'label': 'Haftalik', 'value': 'weekly'},
    {'label': 'Oylik', 'value': 'monthly'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result =
        await ApiService.getServiceOwnerStats(widget.ownerId, _period);
    if (!mounted) return;
    setState(() {
      _stats = result['data'] as Map<String, dynamic>?;
      _loading = false;
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Statistika',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    scrollDirection: Axis.horizontal,
                    itemCount: _periods.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final selected = _periods[i]['value'] == _period;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _period = _periods[i]['value']!);
                          _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: selected
                                ? const LinearGradient(
                                    colors: AppColors.primaryGradient)
                                : null,
                            color: selected ? null : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: selected
                                ? null
                                : Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            _periods[i]['label']!,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : AppColors.textSecondary),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                else if (_stats == null)
                  const Center(child: Text('Ma\'lumot yo\'q'))
                else ...[
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.35,
                    children: [
                      _statCard(
                          'Jami buyurtmalar',
                          '${_stats!['total_orders'] ?? 0}',
                          Icons.receipt_long_rounded,
                          AppColors.primary),
                      _statCard(
                          'Jami daromad',
                          '${_stats!['total_revenue']?.toStringAsFixed(0) ?? 0} so\'m',
                          Icons.attach_money_rounded,
                          AppColors.success),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Buyurtmalar dinamikasi',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 14),
                  if ((_stats!['labels'] as List?)?.isEmpty == true)
                    const Center(
                        child: Text('Ma\'lumot yetarli emas',
                            style: TextStyle(color: AppColors.textMuted)))
                  else
                    Container(
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
                        children: [
                          for (int i = 0;
                              i < (_stats!['labels'] as List).length;
                              i++)
                            _barItem(
                              (_stats!['labels'] as List)[i].toString(),
                              (_stats!['order_counts'] as List)[i] as int,
                              ((_stats!['order_counts'] as List)
                                  .cast<int>()
                                  .reduce((a, b) => a > b ? a : b)),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return LiquidGlass(
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
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
              maxLines: 2),
        ],
      ),
    );
  }

  Widget _barItem(String label, int value, int max) {
    final pct = max > 0 ? value / max : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.chipBg,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Profile tab -------------------------------------------------------

class ServiceOwnerProfileTab extends StatefulWidget {
  final int ownerId;
  const ServiceOwnerProfileTab({super.key, required this.ownerId});
  @override
  State<ServiceOwnerProfileTab> createState() => _ServiceOwnerProfileTabState();
}

class _ServiceOwnerProfileTabState extends State<ServiceOwnerProfileTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await ApiService.getServiceOwnerProfile(widget.ownerId);
    if (!mounted) return;
    setState(() {
      _profile = result['data'] as Map<String, dynamic>?;
      _loading = false;
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
    final service = _profile?['service'] as Map<String, dynamic>?;
    final owner = _profile?['owner'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Profil',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                else if (_profile == null)
                  const Center(child: Text('Ma\'lumot yuklanmadi'))
                else ...[
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.primaryPale,
                            shape: BoxShape.circle,
                            image: (service?['logo_url'] != null &&
                                    (service!['logo_url'] as String)
                                        .startsWith('data:'))
                                ? DecorationImage(
                                    image: MemoryImage(base64Decode(
                                        (service['logo_url'] as String)
                                            .split(',')
                                            .last)),
                                    fit: BoxFit.contain)
                                : null,
                          ),
                          child: service?['logo_url'] == null
                              ? Icon(
                                  service?['provider_type'] == 'evacuator'
                                      ? Icons.local_shipping_rounded
                                      : (service?['provider_type'] == 'fuel'
                                          ? Icons.local_gas_station_rounded
                                          : Icons.storefront_rounded),
                                  color: AppColors.primary,
                                  size: 40,
                                )
                              : null,
                        ),
                        const SizedBox(height: 14),
                        Text(service?['name'] ?? 'Servis',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                            'Reyting: ${service?['rating'] ?? 0} ⭐ (${service?['review_count'] ?? 0} ta baho)',
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  _infoTile(
                      Icons.person_outline, 'Egasi', owner?['name'] ?? '—'),
                  _infoTile(Icons.phone_outlined, 'Telefon',
                      service?['phone'] ?? '—'),
                  if (service?['provider_type'] == 'evacuator' ||
                      service?['provider_type'] == 'fuel')
                    _infoTile(
                        Icons.local_shipping_outlined,
                        'Mashina rusmi (turi)',
                        service?['car_model'] ?? 'Belgilanmagan')
                  else
                    _infoTile(Icons.location_on_outlined, 'Manzil',
                        service?['address'] ?? '—'),
                  _infoTile(Icons.access_time_outlined, 'Ish vaqti',
                      service?['working_hours'] ?? 'Belgilanmagan'),
                  _infoTile(Icons.event_busy_outlined, 'Dam olish kuni',
                      service?['day_off'] ?? 'Belgilanmagan'),
                  if (service?['description'] != null)
                    _infoTile(Icons.notes_outlined, 'Tavsif',
                        service?['description']),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: Material(
                      color: AppColors.primaryPale.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => ChangePasswordScreen(
                                    userId: widget.ownerId))),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 18, color: AppColors.primary),
                              SizedBox(width: 8),
                              Text('Parolni o\'zgartirish',
                                  style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
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
}

// ========================================================================
// CHANGE PASSWORD SCREEN — servis egasi o'z kirish parolini o'zgartiradi.
// Umumiy backend endpointdan (/api/change-password) foydalanadi.
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
// SERVICE DETAIL SCREEN
// ========================================================================

// ========================================================================
// CHAT SCREEN (servis egasi <-> mijoz)
// ========================================================================

class ChatScreen extends StatefulWidget {
  final int orderId;
  final int ownerId;
  final String customerName;
  const ChatScreen(
      {super.key,
      required this.orderId,
      required this.ownerId,
      required this.customerName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
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
    } else if (_loading) {
      setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ApiService.sendChatMessage(widget.orderId, widget.ownerId, text);
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
                    child: Text(widget.customerName,
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
                  : _messages.isEmpty
                      ? Center(
                          child: Text('Hozircha xabar yo\'q',
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final m = _messages[i] as Map<String, dynamic>;
                            final isMe =
                                (m['sender_id'] as int?) == widget.ownerId;
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
                                        MediaQuery.of(context).size.width *
                                            0.75),
                                decoration: BoxDecoration(
                                  color:
                                      isMe ? AppColors.primary : Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(16).copyWith(
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
// OWNER NOTIFICATIONS SCREEN (ilova ichi bildirishnomalar)
// ========================================================================

class OwnerNotificationsScreen extends StatefulWidget {
  final int ownerId;
  const OwnerNotificationsScreen({super.key, required this.ownerId});
  @override
  State<OwnerNotificationsScreen> createState() =>
      _OwnerNotificationsScreenState();
}

class _OwnerNotificationsScreenState extends State<OwnerNotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;

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
    final result = await ApiService.getNotifications(widget.ownerId);
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
                            await ApiService.markAllNotificationsRead(
                                widget.ownerId);
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
