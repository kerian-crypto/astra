import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_hub/core/network/api_exception.dart';
import 'package:astra_hub/core/router/routes.dart';
import 'package:astra_hub/core/utils/formatting.dart';
import 'package:astra_hub/core/widgets/astra_app_bar.dart';
import 'package:astra_hub/core/widgets/async_value_view.dart';
import 'package:astra_hub/features/auth/presentation/auth_controller.dart';
import 'package:astra_hub/features/chat/data/chat.dart';
import 'package:astra_hub/features/chat/data/chat_repository.dart';
import 'package:astra_hub/features/chat/presentation/channel_avatar.dart';
import 'package:astra_hub/features/members/data/member.dart';
import 'package:astra_hub/features/members/data/member_repository.dart';
import 'package:astra_hub/features/members/presentation/member_avatar.dart';

class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key});

  Future<void> _newConversation(BuildContext context, WidgetRef ref) async {
    final member = await showModalBottomSheet<Member>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _MemberPicker(),
    );
    if (member == null || !context.mounted) return;
    try {
      final channel = await ref.read(chatRepositoryProvider).openDirect(member.id);
      ref.invalidate(channelsProvider);
      if (context.mounted) context.go(Routes.chat(channel.id));
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsProvider);
    return Scaffold(
      appBar: const AstraAppBar(title: 'Messages'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouvelle conversation',
        onPressed: () => _newConversation(context, ref),
        child: const Icon(Icons.edit_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(channelsProvider.future),
        child: AsyncValueView(
          value: channels,
          onRetry: () => ref.invalidate(channelsProvider),
          data: (items) => items.isEmpty
              ? const EmptyState(
                  icon: Icons.forum_outlined,
                  message: 'Aucune conversation. Les canaux d\'Astra apparaîtront ici.',
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => _ChannelTile(channel: items[index]),
                ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final unread = channel.unreadCount > 0;
    return ListTile(
      leading: ChannelAvatar(channel: channel),
      title: Text(
        channel.title,
        style: unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: channel.description == null ? null : Text(channel.description!, maxLines: 1),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (channel.lastMessageAt != null)
            Text(
              formatShortMoment(channel.lastMessageAt!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (unread) Badge(label: Text('${channel.unreadCount}')),
        ],
      ),
      onTap: () => context.go(Routes.chat(channel.id)),
    );
  }
}

class _MemberPicker extends ConsumerWidget {
  const _MemberPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider).value;
    final members = ref.watch(membersProvider);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: AsyncValueView(
        value: members,
        onRetry: () => ref.invalidate(membersProvider),
        data: (items) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Écrire à…', style: Theme.of(context).textTheme.titleLarge),
            for (final member in items.where((m) => m.id != me?.id))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: MemberAvatar(member: member),
                title: Text(member.fullName),
                subtitle: member.jobTitle == null ? null : Text(member.jobTitle!),
                onTap: () => Navigator.pop(context, member),
              ),
          ],
        ),
      ),
    );
  }
}
