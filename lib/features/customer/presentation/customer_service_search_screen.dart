import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../services/data/service_catalog_repository.dart';
import 'customer_back_button.dart';

class CustomerServiceSearchScreen extends ConsumerStatefulWidget {
  const CustomerServiceSearchScreen({super.key});

  @override
  ConsumerState<CustomerServiceSearchScreen> createState() =>
      _CustomerServiceSearchScreenState();
}

class _CustomerServiceSearchScreenState
    extends ConsumerState<CustomerServiceSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(serviceCatalogProvider).valueOrNull ??
        AppConstants.applianceCategories;
    final normalized = _query.trim().toLowerCase();
    final filtered = services
        .where((service) =>
            normalized.isEmpty ||
            service.name.toLowerCase().contains(normalized))
        .toList();

    return Scaffold(
      appBar: AppBar(
        leading: const CustomerBackButton(),
        titleSpacing: 0,
        title: TextField(
          key: const Key('service-search-field'),
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search services',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
                _focusNode.requestFocus();
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: filtered.isEmpty
          ? const Center(child: Text('No matching service found.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final service = filtered[index];
                return ListTile(
                  key: ValueKey('service-result-${service.name}'),
                  leading: const Icon(
                    Icons.home_repair_service_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(service.name),
                  subtitle: Text(service.startingPrice),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '/book/${Uri.encodeComponent(service.name)}',
                  ),
                );
              },
            ),
    );
  }
}
