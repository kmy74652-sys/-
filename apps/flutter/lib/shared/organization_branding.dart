import 'package:supabase_flutter/supabase_flutter.dart';

class OrganizationBranding {
  const OrganizationBranding({
    required this.name,
    required this.tagline,
    required this.logoUrl,
  });

  final String name;
  final String tagline;
  final String? logoUrl;

  static const fallback = OrganizationBranding(
    name: 'مؤسسة الشاعري للتجارة العامة',
    tagline: 'Smart Business Management',
    logoUrl: null,
  );
}

class OrganizationBrandingStore {
  OrganizationBrandingStore._();
  static final instance = OrganizationBrandingStore._();
  final _client = Supabase.instance.client;
  OrganizationBranding? _authenticated;
  String? _authenticatedUserId;

  Future<OrganizationBranding> forSession() async {
    final userId = _client.auth.currentUser?.id;
    if (_authenticated != null && _authenticatedUserId == userId) {
      return _authenticated!;
    }
    try {
      final profile = await _client.rpc('mobile_my_profile');
      final employee = profile is Map ? profile['employee'] : null;
      final organizationId = employee is Map
          ? (employee['institutionId'] ??
                    employee['institution_id'] ??
                    employee['organization_id'])
                ?.toString()
          : null;
      if (organizationId == null || organizationId.isEmpty) {
        return OrganizationBranding.fallback;
      }
      final row = await _client
          .from('organizations')
          .select('name,settings')
          .eq('id', organizationId)
          .maybeSingle();
      final settings = row?['settings'] is Map
          ? Map<String, dynamic>.from(row!['settings'] as Map)
          : <String, dynamic>{};
      final branding = settings['branding'] is Map
          ? Map<String, dynamic>.from(settings['branding'] as Map)
          : <String, dynamic>{};
      _authenticatedUserId = userId;
      return _authenticated = OrganizationBranding(
        name: '${row?['name'] ?? OrganizationBranding.fallback.name}',
        tagline: '${branding['tagline'] ?? OrganizationBranding.fallback.tagline}',
        logoUrl: _clean(branding['logo_url']),
      );
    } catch (_) {
      return OrganizationBranding.fallback;
    }
  }

  Future<OrganizationBranding> forEmployeeNumber(String employeeNo) async {
    if (employeeNo.trim().isEmpty) return OrganizationBranding.fallback;
    try {
      final value = await _client.rpc(
        'get_login_branding',
        params: {'p_employee_no': employeeNo.trim()},
      );
      if (value is! Map) return OrganizationBranding.fallback;
      return OrganizationBranding(
        name: '${value['name'] ?? OrganizationBranding.fallback.name}',
        tagline: '${value['tagline'] ?? OrganizationBranding.fallback.tagline}',
        logoUrl: _clean(value['logo_url']),
      );
    } catch (_) {
      return OrganizationBranding.fallback;
    }
  }

  void invalidate() {
    _authenticated = null;
    _authenticatedUserId = null;
  }

  String? _clean(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
