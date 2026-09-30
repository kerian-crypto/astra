import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/knowledge/data/knowledge.dart';
import 'package:astra_hub/features/knowledge/data/knowledge_repository.dart';

/// Recherche dans Astra : projets, tâches, décisions, réunions, documents et
/// messages auxquels le membre a accès (filtré côté serveur).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _minLength = 2;
  static const _debounce = Duration(milliseconds: 400);

  final _query = TextEditingController();
  Timer? _timer;
  AsyncValue<List<SearchHit>>? _results;
  int _requestId = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _timer?.cancel();
    // Temporisation : évite une requête par frappe sur une connexion lente.
    _timer = Timer(_debounce, () => _search(text));
  }

  Future<void> _search(String text) async {
    final query = text.trim();
    if (query.length < _minLength) {
      setState(() => _results = null);
      return;
    }
    final requestId = ++_requestId;
    setState(() => _results = const AsyncLoading());
    try {
      final hits = await ref.read(knowledgeRepositoryProvider).search(query);
      if (mounted && requestId == _requestId) setState(() => _results = AsyncData(hits));
    } on ApiException catch (error, stack) {
      if (mounted && requestId == _requestId) setState(() => _results = AsyncError(error, stack));
    }
  }

  String? _routeFor(SearchHit hit) => switch (hit.type) {
    SearchType.project => Routes.project(hit.id),
    SearchType.task => Routes.task(hit.id),
    SearchType.meeting => Routes.meeting(hit.id),
    SearchType.decision =>
      hit.parentId != null
          ? Routes.meeting(hit.parentId!)
          : (hit.projectId != null ? Routes.project(hit.projectId!) : null),
    SearchType.message => hit.parentId == null ? null : Routes.chat(hit.parentId!),
    SearchType.document =>
      hit.projectId == null ? Routes.documents : Routes.project(hit.projectId!),
  };

  /// Le serveur encadre les mots trouvés par « » : on les met en gras.
  Widget _snippet(String snippet) {
    final parts = snippet.split(RegExp('[«»]'));
    return Text.rich(
      TextSpan(
        children: [
          for (final (index, part) in parts.indexed)
            TextSpan(
              text: part,
              style: index.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Rechercher dans Astra',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _search,
        ),
      ),
      body: switch (_results) {
        null => const EmptyState(
          icon: Icons.search,
          message: 'Projets, tâches, décisions, réunions, documents et messages.',
        ),
        final results => AsyncValueView(
          value: results,
          onRetry: () => _search(_query.text),
          data: (hits) => hits.isEmpty
              ? const EmptyState(icon: Icons.search_off, message: 'Aucun résultat.')
              : ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final hit = hits[index];
                    final route = _routeFor(hit);
                    return ListTile(
                      leading: Chip(label: Text(hit.type.label)),
                      title: Text(hit.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: _snippet(hit.snippet),
                      onTap: route == null ? null : () => context.push(route),
                    );
                  },
                ),
        ),
      },
    );
  }
}
