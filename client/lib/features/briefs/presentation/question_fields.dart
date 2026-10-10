import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/briefs/data/brief.dart';

/// En-tête commun d'une question : libellé, aide et exemple.
class QuestionHeader extends StatelessWidget {
  const QuestionHeader({required this.question, this.index, super.key});

  final BriefQuestion question;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              if (index != null)
                TextSpan(
                  text: '$index. ',
                  style: TextStyle(color: scheme.primary),
                ),
              TextSpan(text: question.label),
              if (question.required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: scheme.error),
                ),
            ],
          ),
          style: text.titleMedium,
        ),
        if (question.help != null) ...[
          const SizedBox(height: Space.xs),
          Text(question.help!, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (question.example != null) ...[
          const SizedBox(height: Space.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
              border: Border(left: BorderSide(color: scheme.primary, width: 3)),
            ),
            child: Text(
              'Exemple : ${question.example}',
              style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
        const SizedBox(height: Space.md),
      ],
    );
  }
}

/// Champ de saisie adapté au type de la question (hors fichiers).
class QuestionField extends StatelessWidget {
  const QuestionField({
    required this.question,
    required this.value,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final BriefQuestion question;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return switch (question.type) {
      QuestionType.text || QuestionType.longText => _TextAnswer(
        key: ValueKey(question.id),
        initial: value as String? ?? '',
        multiline: question.type == QuestionType.longText,
        errorText: errorText,
        onChanged: (text) => onChanged(text.trim().isEmpty ? null : text),
      ),
      QuestionType.number => _TextAnswer(
        key: ValueKey(question.id),
        initial: value?.toString() ?? '',
        number: true,
        errorText: errorText,
        onChanged: (text) => onChanged(int.tryParse(text.trim())),
      ),
      QuestionType.list => _ListAnswer(
        key: ValueKey(question.id),
        question: question,
        initial: ((value as List<Object?>?) ?? const []).cast<String>(),
        errorText: errorText,
        onChanged: (items) => onChanged(items.isEmpty ? null : items),
      ),
      QuestionType.singleChoice => _SingleChoice(
        question: question,
        selected: value as String?,
        errorText: errorText,
        onChanged: onChanged,
      ),
      QuestionType.multiChoice => _MultiChoice(
        key: ValueKey(question.id),
        question: question,
        value: (value as Map<String, Object?>?) ?? const {},
        errorText: errorText,
        onChanged: onChanged,
      ),
      QuestionType.date => _DateAnswer(
        value: value == null ? null : DateTime.tryParse(value as String),
        onChanged: (date) => onChanged(date == null ? null : isoDay(date)),
      ),
      QuestionType.files => const SizedBox.shrink(),
    };
  }
}

String isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class _TextAnswer extends StatefulWidget {
  const _TextAnswer({
    required this.initial,
    required this.onChanged,
    this.multiline = false,
    this.number = false,
    this.errorText,
    super.key,
  });

  final String initial;
  final bool multiline;
  final bool number;
  final String? errorText;
  final ValueChanged<String> onChanged;

  @override
  State<_TextAnswer> createState() => _TextAnswerState();
}

class _TextAnswerState extends State<_TextAnswer> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      minLines: widget.multiline ? 4 : 1,
      maxLines: widget.multiline ? 12 : 1,
      maxLength: widget.multiline ? 8000 : (widget.number ? 9 : 500),
      keyboardType: widget.number
          ? TextInputType.number
          : (widget.multiline ? TextInputType.multiline : TextInputType.text),
      inputFormatters: widget.number ? [FilteringTextInputFormatter.digitsOnly] : null,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: widget.multiline ? 'Exprimez-vous librement…' : null,
        errorText: widget.errorText,
        counterText: widget.multiline ? null : '',
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _ListAnswer extends StatefulWidget {
  const _ListAnswer({
    required this.question,
    required this.initial,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final BriefQuestion question;
  final List<String> initial;
  final String? errorText;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_ListAnswer> createState() => _ListAnswerState();
}

class _ListAnswerState extends State<_ListAnswer> {
  late final List<TextEditingController> _controllers = [
    for (final item in widget.initial) TextEditingController(text: item),
    if (widget.initial.isEmpty) TextEditingController(),
  ];

  int get _max => widget.question.maxItems ?? 15;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged([
    for (final c in _controllers)
      if (c.text.trim().isNotEmpty) c.text.trim(),
  ]);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, controller) in _controllers.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TextField(
              controller: controller,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('${i + 1}', style: Theme.of(context).textTheme.labelLarge),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 44),
                suffixIcon: _controllers.length > 1
                    ? IconButton(
                        tooltip: 'Retirer',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          setState(() => _controllers.removeAt(i).dispose());
                          _emit();
                        },
                      )
                    : null,
              ),
              onChanged: (_) => _emit(),
            ),
          ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              widget.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
        if (_controllers.length < _max)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _controllers.add(TextEditingController())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter une ligne'),
            ),
          ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.choice,
    required this.selected,
    required this.onTap,
    required this.multi,
  });

  final QuestionChoice choice;
  final bool selected;
  final VoidCallback onTap;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
          child: Row(
            children: [
              Icon(
                multi
                    ? (selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                    : (selected ? Icons.radio_button_checked : Icons.radio_button_off),
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(choice.label, style: Theme.of(context).textTheme.titleSmall),
                    if (choice.description != null)
                      Text(
                        choice.description!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
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

class _SingleChoice extends StatelessWidget {
  const _SingleChoice({
    required this.question,
    required this.selected,
    required this.onChanged,
    this.errorText,
  });

  final BriefQuestion question;
  final String? selected;
  final String? errorText;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ChoiceGrid(
      errorText: errorText,
      children: [
        for (final choice in question.choices)
          _ChoiceCard(
            choice: choice,
            multi: false,
            selected: selected == choice.value,
            onTap: () => onChanged(selected == choice.value ? null : choice.value),
          ),
      ],
    );
  }
}

class _MultiChoice extends StatefulWidget {
  const _MultiChoice({
    required this.question,
    required this.value,
    required this.onChanged,
    this.errorText,
    super.key,
  });

  final BriefQuestion question;
  final Map<String, Object?> value;
  final String? errorText;
  final ValueChanged<Object?> onChanged;

  @override
  State<_MultiChoice> createState() => _MultiChoiceState();
}

class _MultiChoiceState extends State<_MultiChoice> {
  late final Set<String> _selected = {
    ...((widget.value['selected'] as List<Object?>?) ?? const []).cast<String>(),
  };
  late final _other = TextEditingController(text: widget.value['other'] as String? ?? '');
  String? _limitMessage;

  int get _count => _selected.length + (_other.text.trim().isEmpty ? 0 : 1);

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _emit() {
    final other = _other.text.trim();
    widget.onChanged(
      _selected.isEmpty && other.isEmpty
          ? null
          : {'selected': _selected.toList(), 'other': other.isEmpty ? null : other},
    );
  }

  void _toggle(String value) {
    final max = widget.question.maxItems;
    setState(() {
      _limitMessage = null;
      if (_selected.contains(value)) {
        _selected.remove(value);
      } else if (max != null && _count >= max) {
        _limitMessage = '$max choix maximum.';
        return;
      } else {
        _selected.add(value);
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.question.maxItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (max != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'Jusqu\'à $max choix',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        _ChoiceGrid(
          errorText: _limitMessage ?? widget.errorText,
          children: [
            for (final choice in widget.question.choices)
              if (choice.value != 'other')
                _ChoiceCard(
                  choice: choice,
                  multi: true,
                  selected: _selected.contains(choice.value),
                  onTap: () => _toggle(choice.value),
                ),
          ],
        ),
        if (widget.question.allowOther) ...[
          const SizedBox(height: Space.sm),
          TextField(
            controller: _other,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Autre (précisez)', counterText: ''),
            onChanged: (_) => _emit(),
          ),
        ],
      ],
    );
  }
}

/// Choix sur une colonne (téléphone) ou deux (grand écran).
class _ChoiceGrid extends StatelessWidget {
  const _ChoiceGrid({required this.children, this.errorText});

  final List<Widget> children;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 560 ? 2 : 1;
            final width = (constraints.maxWidth - Space.sm * (columns - 1)) / columns;
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [for (final child in children) SizedBox(width: width, child: child)],
            );
          },
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _DateAnswer extends StatelessWidget {
  const _DateAnswer({required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now.add(const Duration(days: 30)),
                firstDate: now,
                lastDate: DateTime(now.year + 5),
              );
              if (picked != null) onChanged(picked);
            },
            icon: const Icon(Icons.event_outlined),
            label: Text(value == null ? 'Choisir une date' : formatDate(value!)),
          ),
        ),
        if (value != null)
          IconButton(
            tooltip: 'Pas de contrainte de date',
            onPressed: () => onChanged(null),
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
  }
}

/// Résumé lisible d'une réponse (récapitulatif et consultation).
String describeAnswer(BriefQuestion question, Object? value) {
  if (value == null) return '—';
  switch (question.type) {
    case QuestionType.list:
      return ((value as List<Object?>).cast<String>()).map((e) => '• $e').join('\n');
    case QuestionType.singleChoice:
      return question.choices.where((c) => c.value == value).firstOrNull?.label ?? '$value';
    case QuestionType.multiChoice:
      final map = value as Map<String, Object?>;
      final labels = [
        for (final v in ((map['selected'] as List<Object?>?) ?? const []).cast<String>())
          question.choices.where((c) => c.value == v).firstOrNull?.label ?? v,
        if ((map['other'] as String?) != null) map['other']! as String,
      ];
      return labels.join(', ');
    case QuestionType.date:
      final date = DateTime.tryParse(value as String);
      return date == null ? value : formatDate(date);
    default:
      return '$value';
  }
}

/// Pastille d'étape, utilisée dans la liste des sections.
class StepDot extends StatelessWidget {
  const StepDot({required this.index, required this.done, required this.active, super.key});

  final int index;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || active ? scheme.primary : scheme.surfaceContainer,
      ),
      alignment: Alignment.center,
      child: done
          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
          : Text(
              '$index',
              style: TextStyle(
                color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
    );
  }
}

/// Pastille de statut d'un cahier des charges.
class BriefStatusPill extends StatelessWidget {
  const BriefStatusPill(this.status, {super.key});

  final BriefStatus status;

  @override
  Widget build(BuildContext context) => StatusPill(label: status.label, tone: status.tone);
}
