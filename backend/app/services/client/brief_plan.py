"""Déduction d'un plan de projet (phases et tâches) à partir des réponses
au questionnaire de cadrage.

Règles déterministes et lisibles : chaque tâche découle d'une réponse
précise (type de projet, supports, couleurs, concurrents, échéance…). Le
plan est une proposition : un membre d'Astra le relit et le valide avant
toute création, comme les plans de Ronda.
"""

from datetime import date, timedelta
from typing import Any

from app.models.enums import Priority
from app.schemas.plan import PlannedPhase, PlannedTask, ProjectPlan
from app.services.client.brief_questions import QUESTIONS

DEFAULT_DURATION_DAYS = 45
MAX_SUPPORT_TASKS = 15


def _labels(question_id: str, answer: Any) -> list[str]:
    """Libellés des choix cochés (+ précision « Autre »)."""
    if not isinstance(answer, dict):
        return []
    names = {c.value: c.label for c in QUESTIONS[question_id].choices}
    labels = [names[v] for v in answer.get("selected") or [] if v in names and v != "other"]
    if answer.get("other"):
        labels.append(answer["other"])
    return labels


def _selected(answers: dict[str, Any], question_id: str) -> set[str]:
    answer = answers.get(question_id)
    return set(answer.get("selected") or []) if isinstance(answer, dict) else set()


def _task(
    title: str, description: str | None = None, priority: Priority = Priority.MEDIUM
) -> PlannedTask:
    return PlannedTask(
        title=title[:200],
        description=(description or None) and description[:5_000],
        priority=priority,
    )


def _identity_phases(answers: dict[str, Any]) -> list[PlannedPhase]:
    colors = ", ".join(_labels("colors", answers.get("colors"))) or "à définir"
    logo_types = ", ".join(_labels("logo_types", answers.get("logo_types"))) or "à définir"
    evoke = ", ".join(answers.get("words_to_evoke") or []) or "à préciser"
    avoid = ", ".join(answers.get("words_to_avoid") or [])
    request = answers.get("logo_request")
    creation = [
        _task(
            "Moodboard et pistes graphiques",
            f"Couleurs souhaitées : {colors}. Types de logo envisagés : {logo_types}. "
            f"Mots à évoquer : {evoke}." + (f" Mots à éviter : {avoid}." if avoid else ""),
            Priority.HIGH,
        ),
        _task(
            "Évolution du logo existant"
            if request == "evolution"
            else "Création de 3 pistes de logo",
            answers.get("specific_requests"),
            Priority.HIGH,
        ),
        _task("Présentation des pistes et validation client", "Publier les pistes en livrable."),
        _task("Finalisation du logo retenu"),
        _task("Déclinaisons du logo (couleur, monochrome, icône, petites tailles)"),
    ]
    charter = [
        _task(
            "Charte graphique (couleurs, typographies, règles d'usage, interdits)",
            priority=Priority.HIGH,
        )
    ]
    if answers.get("slogan"):
        charter.append(_task(f"Intégration du slogan « {answers['slogan']} »"))
    else:
        charter.append(_task("Proposition de slogan"))
    supports = (answers.get("supports") or [])[:MAX_SUPPORT_TASKS]
    declinations = [_task(f"Déclinaison : {support}") for support in supports]
    phases = [
        PlannedPhase(name="Création du logo", tasks=creation),
        PlannedPhase(name="Charte graphique", tasks=charter),
    ]
    if declinations:
        phases.append(PlannedPhase(name="Supports de communication", tasks=declinations))
    return phases


def _website_phase(answers: dict[str, Any]) -> PlannedPhase:
    return PlannedPhase(
        name="Site web",
        tasks=[
            _task("Arborescence et contenus du site", answers.get("scope_elements"), Priority.HIGH),
            _task("Maquettes UX/UI (mobile et ordinateur)", priority=Priority.HIGH),
            _task("Validation des maquettes par le client"),
            _task("Développement et intégration"),
            _task("Référencement naturel (SEO) de base"),
            _task("Recette et corrections"),
            _task("Mise en ligne et formation du client"),
        ],
    )


def _app_phase(name: str, answers: dict[str, Any]) -> PlannedPhase:
    return PlannedPhase(
        name=name,
        tasks=[
            _task("Spécifications fonctionnelles", answers.get("scope_elements"), Priority.HIGH),
            _task("Parcours utilisateurs et maquettes UX/UI", priority=Priority.HIGH),
            _task("Validation des maquettes par le client"),
            _task("Architecture technique et backend"),
            _task("Développement de l'interface"),
            _task("Tests et recette"),
            _task("Déploiement / publication"),
        ],
    )


def _marketing_phase(answers: dict[str, Any]) -> PlannedPhase:
    channels = ", ".join(_labels("sales_channels", answers.get("sales_channels"))) or "à définir"
    return PlannedPhase(
        name="Marketing digital",
        tasks=[
            _task(
                "Stratégie de communication par canal",
                f"Canaux actuels : {channels}.",
                Priority.HIGH,
            ),
            _task("Calendrier éditorial", answers.get("target")),
            _task("Création des visuels et contenus"),
            _task("Campagnes publicitaires ciblées"),
            _task("Suivi des performances et rapport mensuel"),
        ],
    )


def _spread_due_dates(phases: list[PlannedPhase], start: date, end: date) -> list[PlannedPhase]:
    """Répartit les échéances des phases entre le cadrage et la date limite."""
    span = max((end - start).days, len(phases))
    result = []
    for index, phase in enumerate(phases, start=1):
        due = start + timedelta(days=round(span * index / len(phases)))
        result.append(phase.model_copy(update={"due_date": due}))
    return result


def propose_plan(answers: dict[str, Any], *, title: str, today: date) -> ProjectPlan:
    types = _selected(answers, "project_types") or {"other"}
    competitors = answers.get("competitors") or []

    framing = [
        _task("Étude du cahier des charges et appel de cadrage", priority=Priority.HIGH),
        _task("Plateforme de marque : valeurs, vision, mission, tonalité", answers.get("values")),
    ]
    if competitors:
        framing.insert(
            1, _task("Analyse des concurrents", "Concurrents cités : " + ", ".join(competitors))
        )
    if answers.get("target"):
        framing.append(_task("Persona et parcours de la cible", answers.get("target_aspirations")))
    phases = [PlannedPhase(name="Cadrage", tasks=framing)]

    if "visual_identity" in types:
        phases += _identity_phases(answers)
    if "website" in types:
        phases.append(_website_phase(answers))
    if "mobile_app" in types:
        phases.append(_app_phase("Application mobile", answers))
    if "software" in types:
        phases.append(_app_phase("Logiciel / plateforme", answers))
    if "digital_marketing" in types:
        phases.append(_marketing_phase(answers))
    if types == {"other"}:
        phases.append(
            PlannedPhase(
                name="Réalisation",
                tasks=[
                    _task(
                        "Définir le périmètre détaillé avec le client",
                        answers.get("scope_elements"),
                    )
                ],
            )
        )
    phases.append(
        PlannedPhase(
            name="Livraison",
            tasks=[
                _task("Livraison des fichiers finaux au client"),
                _task("Bilan et satisfaction client"),
            ],
        )
    )

    deadline = answers.get("deadline")
    due = (
        date.fromisoformat(deadline) if deadline else today + timedelta(days=DEFAULT_DURATION_DAYS)
    )
    if due <= today:
        due = today + timedelta(days=7)
    urgent = (due - today).days < 30
    return ProjectPlan(
        name=title[:150],
        description=answers.get("project_description"),
        objective=answers.get("objectives"),
        priority=Priority.HIGH if urgent else Priority.MEDIUM,
        due_date=due,
        phases=_spread_due_dates(phases, today, due),
    )
