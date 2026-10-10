import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:astra_client/core/layout/breakpoints.dart';
import 'package:astra_client/core/router/routes.dart';
import 'package:astra_client/core/theme/client_theme.dart';
import 'package:astra_client/core/utils/formatting.dart';
import 'package:astra_client/core/utils/picked_file.dart';
import 'package:astra_client/core/widgets/state_views.dart';
import 'package:astra_client/core/widgets/ui.dart';
import 'package:astra_client/features/briefs/data/brief.dart';
import 'package:astra_client/features/briefs/data/brief_repository.dart';
import 'package:astra_client/features/briefs/presentation/question_fields.dart';
import 'package:astra_client/features/dashboard/data/dashboard.dart';

/// Questionnaire de cadrage sur plusieurs écrans : accueil, une étape par
/// section, récapitulatif, remerciement. Les réponses sont enregistrées à
/// chaque étape : le client reprend là où il s'était arrêté.
class BriefWizardScreen extends ConsumerStatefulWidget {
  const BriefWizardScreen({this.briefId, super.key});

  /// Nul : nouveau cahier des charges (ou reprise du brouillon en cours).
  final String? briefId;

  @override
  ConsumerState<BriefWizardScreen> createState() => _BriefWizardScreenState();
}

class _BriefWizardScreenState extends ConsumerState<BriefWizardScreen> {
  Brief? _brief;
  Object? _loadError;
  final Map<String, Object?> _answers = {};
  final Set<String> _dirty = {};
  Map<String, String> _errors = const {};
  // 0 = accueil, 1..n = sections, n+1 = récapitulatif.
  int _step = 0;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final repository = ref.read(briefRepositoryProvider);
      final questionnaire = await ref.read(questionnaireProvider.future);
      final brief = widget.briefId == null
          ? await repository.start()
          : await repository.get(widget.briefId!);
      if (!mounted) return;
      if (!brief.isDraft) {
        context.pushReplacement(Routes.brief(brief.id));
        return;
      }
      final resumeIndex = questionnaire.sections.indexWhere((s) => s.id == brief.currentSection);
      setState(() {
        _brief = brief;
        _answers
          ..clear()
          ..addAll(brief.answers);
        // Un questionnaire déjà entamé reprend à sa dernière étape.
        _step = brief.answers.length > 3 && resumeIndex >= 0 ? resumeIndex + 1 : 0;
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  bool _isAnswered(BriefQuestion question) => question.type == QuestionType.files
      ? (_brief?.filesFor(question.id).isNotEmpty ?? false)
      : question.isAnswered(_answers[question.id]);

  Map<String, String> _validate(BriefSection section) => {
    for (final question in section.questions)
      if (question.required && !_isAnswered(question))
        question.id: question.minItems != null && question.type == QuestionType.list
            ? 'Indiquez au moins ${question.minItems} élément(s).'
            : 'Cette réponse est obligatoire.',
  };

  Future<bool> _saveDirty({String? section}) async {
    final brief = _brief;
    if (brief == null) return false;
    if (_dirty.isEmpty && section == null) return true;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(briefRepositoryProvider)
          .save(brief.id, answers: {for (final id in _dirty) id: _answers[id]}, section: section);
      _dirty.clear();
      if (mounted) setState(() => _brief = saved);
      return true;
    } on Exception catch (error) {
      if (mounted) showError(context, error);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next(Questionnaire questionnaire) async {
    final sections = questionnaire.sections;
    if (_step >= 1 && _step <= sections.length) {
      final errors = _validate(sections[_step - 1]);
      setState(() => _errors = errors);
      if (errors.isNotEmpty) {
        showError(context, 'Complétez les réponses obligatoires pour continuer.');
        return;
      }
    }
    final nextSection = _step < sections.length ? sections[_step].id : null;
    if (!await _saveDirty(section: nextSection)) return;
    setState(() {
      _errors = const {};
      _step += 1;
    });
  }

  Future<void> _previous() async {
    await _saveDirty();
    if (mounted) setState(() => _step = (_step - 1).clamp(0, 999));
  }

  Future<void> _goTo(int step) async {
    await _saveDirty();
    if (mounted) setState(() => _step = step);
  }

  Future<void> _submit() async {
    final brief = _brief;
    if (brief == null || !await _saveDirty()) return;
    setState(() => _busy = true);
    try {
      final submitted = await ref.read(briefRepositoryProvider).submit(brief.id);
      ref
        ..invalidate(briefsProvider)
        ..invalidate(dashboardProvider);
      if (mounted) {
        setState(() {
          _brief = submitted;
          _done = true;
        });
      }
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setAnswer(String id, Object? value) {
    _answers[id] = value;
    _dirty.add(id);
    if (_errors.containsKey(id)) setState(() => _errors = {..._errors}..remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final questionnaire = ref.watch(questionnaireProvider);
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mon projet')),
        body: ErrorStateView(error: _loadError!, onRetry: _load),
      );
    }
    if (_brief == null || !questionnaire.hasValue) {
      return const Scaffold(body: LoadingView());
    }
    if (_done) return const _ThankYou();
    final q = questionnaire.requireValue;
    final sections = q.sections;
    final total = sections.length;
    final content = switch (_step) {
      0 => const _Welcome(),
      final int s when s <= total => _SectionStep(
        key: ValueKey(sections[s - 1].id),
        section: sections[s - 1],
        sectionIndex: s,
        brief: _brief!,
        answers: _answers,
        errors: _errors,
        onChanged: _setAnswer,
        onBriefChanged: (brief) => setState(() => _brief = brief),
      ),
      _ => _Recap(
        questionnaire: q,
        brief: _brief!,
        answers: _answers,
        isAnswered: _isAnswered,
        onEdit: (index) => _goTo(index + 1),
      ),
    };
    final isRecap = _step > total;
    final bottom = _NavBar(
      busy: _busy,
      canGoBack: _step > 0,
      nextLabel: _step == 0
          ? 'Commencer'
          : isRecap
          ? 'Envoyer à Astra'
          : _step == total
          ? 'Voir le récapitulatif'
          : 'Suivant',
      onBack: _previous,
      onNext: isRecap ? _submit : () => _next(q),
    );
    final expanded = context.windowSize != WindowSize.compact;

    return PopScope(
      canPop: _dirty.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _saveDirty() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cahier des charges'),
          actions: [
            if (_step > 0)
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _saveDirty() && context.mounted) {
                          showSuccess(
                            context,
                            'Brouillon enregistré. Vous pourrez reprendre plus tard.',
                          );
                          context.pop();
                        }
                      },
                child: const Text('Plus tard'),
              ),
          ],
          bottom: _step == 0
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: (_step / (total + 1)).clamp(0, 1)),
                ),
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (expanded && _step > 0)
              SizedBox(
                width: 280,
                child: _StepList(
                  sections: sections,
                  step: _step,
                  isComplete: (s) => _validate(s).isEmpty,
                  onSelect: (index) => _goTo(index),
                ),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: SizedBox(height: double.infinity, child: content),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: bottom,
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.busy,
    required this.canGoBack,
    required this.nextLabel,
    required this.onBack,
    required this.onNext,
  });

  final bool busy;
  final bool canGoBack;
  final String nextLabel;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 480;
                  return Row(
                    children: [
                      if (canGoBack)
                        narrow
                            ? IconButton.outlined(
                                tooltip: 'Précédent',
                                onPressed: busy ? null : onBack,
                                icon: const Icon(Icons.arrow_back_rounded),
                              )
                            : OutlinedButton.icon(
                                onPressed: busy ? null : onBack,
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('Précédent'),
                              ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          heightFactor: 1,
                          child: FilledButton(
                            onPressed: busy ? null : onNext,
                            child: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(nextLabel, overflow: TextOverflow.ellipsis),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.arrow_forward_rounded, size: 18),
                                    ],
                                  ),
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
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({
    required this.sections,
    required this.step,
    required this.isComplete,
    required this.onSelect,
  });

  final List<BriefSection> sections;
  final int step;
  final bool Function(BriefSection) isComplete;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Text(
          'ÉTAPES',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: Space.md),
        for (final (i, section) in sections.indexed)
          ListTile(
            selected: step == i + 1,
            selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
            leading: StepDot(
              index: i + 1,
              done: isComplete(section) && step > i + 1,
              active: step == i + 1,
            ),
            title: Text(section.title),
            onTap: () => onSelect(i + 1),
          ),
        ListTile(
          selected: step > sections.length,
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Récapitulatif'),
          onTap: () => onSelect(sections.length + 1),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget point(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToneIcon(icon),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(body, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.all(Breakpoints.gutter(context)),
      children: [
        const SizedBox(height: Space.lg),
        Text('Bienvenue !', style: text.headlineMedium),
        const SizedBox(height: Space.md),
        Text(
          'Ce questionnaire a été conçu pour bien comprendre votre projet, vos besoins et votre '
          'vision. Il nous permet de cadrer précisément votre demande et de planifier le travail '
          'de votre équipe Astra.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: Space.xl),
        point(
          Icons.edit_note_rounded,
          'Exprimez-vous librement',
          'Chaque détail compte : plus vous partagez, mieux nous pourrons vous aider.',
        ),
        point(
          Icons.save_outlined,
          'Enregistré à chaque étape',
          'Vous pouvez vous arrêter et reprendre plus tard, même sur un autre appareil.',
        ),
        point(
          Icons.timer_outlined,
          '6 étapes, environ 15 minutes',
          'Entreprise, projet, objectifs, marque, univers graphique, supports et délais.',
        ),
        point(
          Icons.handshake_outlined,
          'Nous vous accompagnons',
          'Votre équipe Astra étudie vos réponses et revient vers vous avec un plan de projet.',
        ),
      ],
    );
  }
}

class _SectionStep extends ConsumerWidget {
  const _SectionStep({
    required this.section,
    required this.sectionIndex,
    required this.brief,
    required this.answers,
    required this.errors,
    required this.onChanged,
    required this.onBriefChanged,
    super.key,
  });

  final BriefSection section;
  final int sectionIndex;
  final Brief brief;
  final Map<String, Object?> answers;
  final Map<String, String> errors;
  final void Function(String id, Object? value) onChanged;
  final ValueChanged<Brief> onBriefChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: EdgeInsets.all(Breakpoints.gutter(context)),
      children: [
        Text(
          'ÉTAPE $sectionIndex',
          style: text.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(section.title, style: text.headlineSmall),
        const SizedBox(height: Space.sm),
        Text(
          section.intro,
          style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.xl),
        for (final (i, question) in section.questions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.lg),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    QuestionHeader(question: question, index: i + 1),
                    if (question.type == QuestionType.files)
                      _FilesAnswer(
                        brief: brief,
                        question: question,
                        errorText: errors[question.id],
                        onBriefChanged: onBriefChanged,
                      )
                    else
                      QuestionField(
                        question: question,
                        value: answers[question.id],
                        errorText: errors[question.id],
                        onChanged: (value) => onChanged(question.id, value),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FilesAnswer extends ConsumerStatefulWidget {
  const _FilesAnswer({
    required this.brief,
    required this.question,
    required this.onBriefChanged,
    this.errorText,
  });

  final Brief brief;
  final BriefQuestion question;
  final String? errorText;
  final ValueChanged<Brief> onBriefChanged;

  @override
  ConsumerState<_FilesAnswer> createState() => _FilesAnswerState();
}

class _FilesAnswerState extends ConsumerState<_FilesAnswer> {
  bool _uploading = false;

  Future<void> _add({required bool camera}) async {
    final file = camera
        ? await takePhoto()
        : await pickDocument(extensions: const ['png', 'jpg', 'jpeg', 'pdf']);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      widget.onBriefChanged(
        await ref.read(briefRepositoryProvider).addFile(widget.brief.id, widget.question.id, file),
      );
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _remove(BriefFile file) async {
    try {
      widget.onBriefChanged(
        await ref.read(briefRepositoryProvider).removeFile(widget.brief.id, file.id),
      );
    } on Exception catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.brief.filesFor(widget.question.id);
    final max = widget.question.maxItems ?? 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final file in files)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const ToneIcon(Icons.image_outlined, tone: Tone.info),
            title: Text(file.file.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(formatFileSize(file.file.sizeBytes)),
            trailing: IconButton(
              tooltip: 'Retirer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _remove(file),
            ),
          ),
        if (_uploading) const LinearProgressIndicator(),
        if (files.length < max)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _add(camera: false),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Ajouter une image ou un PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _add(camera: true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Photo'),
              ),
            ],
          ),
        if (widget.errorText != null)
          Text(widget.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    );
  }
}

class _Recap extends StatelessWidget {
  const _Recap({
    required this.questionnaire,
    required this.brief,
    required this.answers,
    required this.isAnswered,
    required this.onEdit,
  });

  final Questionnaire questionnaire;
  final Brief brief;
  final Map<String, Object?> answers;
  final bool Function(BriefQuestion) isAnswered;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final missing = [
      for (final section in questionnaire.sections)
        for (final q in section.questions)
          if (q.required && !isAnswered(q)) q,
    ];
    return ListView(
      padding: EdgeInsets.all(Breakpoints.gutter(context)),
      children: [
        Text('Récapitulatif', style: text.headlineSmall),
        const SizedBox(height: Space.sm),
        Text(
          'Relisez vos réponses avant de les envoyer. Vous pouvez modifier chaque étape.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.lg),
        if (missing.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(Space.md),
            margin: const EdgeInsets.only(bottom: Space.lg),
            decoration: BoxDecoration(
              color: Tone.warning.background(scheme),
              borderRadius: BorderRadius.circular(ClientTheme.radiusSmall),
            ),
            child: Text(
              'Il reste ${missing.length} réponse(s) obligatoire(s) : '
              '${missing.take(3).map((q) => '« ${q.label} »').join(', ')}'
              '${missing.length > 3 ? '…' : ''}',
              style: TextStyle(color: Tone.warning.foreground(scheme)),
            ),
          ),
        for (final (i, section) in questionnaire.sections.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: SectionCard(
              title: '${i + 1}. ${section.title}',
              trailing: TextButton.icon(
                onPressed: () => onEdit(i),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Modifier'),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final question in section.questions)
                    if (isAnswered(question))
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              question.label,
                              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              question.type == QuestionType.files
                                  ? brief.filesFor(question.id).map((f) => f.file.name).join(', ')
                                  : describeAnswer(question, answers[question.id]),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ThankYou extends StatelessWidget {
  const _ThankYou();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const ToneIcon(Icons.celebration_outlined, tone: Tone.success, size: 88),
                  const SizedBox(height: Space.xl),
                  Text(
                    'Merci infiniment pour votre temps 🙏',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    'Votre cahier des charges a bien été transmis. Chaque réponse va nous aider à '
                    'construire une solution juste et alignée avec vos besoins. Votre équipe Astra '
                    'l\'étudie et revient vers vous avec un plan de projet.',
                    style: text.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.xxl),
                  FilledButton.icon(
                    onPressed: () => context.go(Routes.home),
                    icon: const Icon(Icons.space_dashboard_rounded),
                    label: const Text('Accéder à mon espace'),
                  ),
                  const SizedBox(height: Space.md),
                  TextButton(
                    onPressed: () => context.go(Routes.messages),
                    child: const Text('Écrire à mon équipe Astra'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
