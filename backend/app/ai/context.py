"""Contexte fourni à Ronda : uniquement des données déjà filtrées par les
permissions de l'utilisateur (spec §17). Le modèle n'a aucun accès direct à
la base : il ne voit que ce texte."""

from dataclasses import dataclass, field
from datetime import date

from sqlalchemy.orm import Session

from app.ai import activity
from app.ai import focus as ai_focus
from app.models import Project, Task, User
from app.schemas.ai import AIFocus, Source
from app.services import permissions, search_service, work_service

MAX_PROJECTS = 20
MAX_SEARCH_HITS = 8


@dataclass
class ContextBuilder:
    max_chars: int
    sections: list[str] = field(default_factory=list)
    sources: list[Source] = field(default_factory=list)

    def add_source(self, source_type: str, entity_id, title: str) -> int:
        number = len(self.sources) + 1
        self.sources.append(Source(number=number, type=source_type, id=entity_id, title=title))
        return number

    def section(self, title: str, lines: list[str]) -> None:
        if lines:
            self.sections.append(f"## {title}\n" + "\n".join(lines))

    def render(self) -> str:
        text = "\n\n".join(self.sections)
        if len(text) <= self.max_chars:
            return text
        return text[: self.max_chars] + "\n[… contexte tronqué …]"


def _project_names(db: Session, user: User) -> dict:
    return dict(
        db.execute(
            permissions.visible_projects_statement(user).with_only_columns(Project.id, Project.name)
        ).all()
    )


def _task_line(builder: ContextBuilder, task: Task, projects: dict) -> str:
    number = builder.add_source("work", task.id, task.title)
    due = f", échéance {task.due_date.isoformat()}" if task.due_date else ""
    project = projects.get(task.project_id, "?")
    return (
        f"[{number}] {task.title} — projet {project}, statut {task.status}, "
        f"priorité {task.priority}{due}"
    )


def build(
    db: Session,
    user: User,
    today: date,
    question: str,
    max_chars: int,
    focus: AIFocus | None = None,
) -> ContextBuilder:
    """Sections de la plus utile à la moins utile : en cas de dépassement,
    c'est l'activité générale (en fin de texte) qui est tronquée."""
    builder = ContextBuilder(max_chars=max_chars)
    projects = _project_names(db, user)

    builder.section(
        "Utilisateur",
        [
            f"Nom : {user.full_name}",
            f"Rôle : {user.job_title or 'non renseigné'}",
            f"Compétences : {', '.join(user.skills) or 'non renseignées'}",
            f"Date du jour : {today.isoformat()}",
        ],
    )

    view = ai_focus.describe(db, user, focus) if focus else None
    if focus and view:
        number = builder.add_source(focus.type.value, focus.id, view.title)
        builder.section(f"Écran consulté par le membre [{number}]", view.lines)

    work = work_service.my_work(db, user, today)
    for title, tasks in (
        ("Mes tâches du jour", work.today),
        ("Mes tâches en retard", work.overdue),
        ("Mes tâches prioritaires", work.priority),
        ("Mes prochaines échéances", work.upcoming),
    ):
        loaded = [db.get(Task, t.id) for t in tasks]
        builder.section(title, [_task_line(builder, t, projects) for t in loaded if t])
    builder.section(
        "Mes réunions à venir",
        [f"- {m.title} le {m.scheduled_at:%d/%m/%Y à %H:%M} UTC" for m in work.meetings],
    )

    visible = db.scalars(
        permissions.visible_projects_statement(user)
        .order_by(Project.updated_at.desc())
        .limit(MAX_PROJECTS)
    )
    project_lines = []
    for project in visible:
        number = builder.add_source("project", project.id, project.name)
        due = f", échéance {project.due_date.isoformat()}" if project.due_date else ""
        project_lines.append(
            f"[{number}] {project.name} — statut {project.status}, priorité {project.priority}{due}"
        )
    builder.section("Projets auxquels j'ai accès", project_lines)

    hits = search_service.search(db, user, question)[:MAX_SEARCH_HITS]
    hit_lines = []
    for hit in hits:
        number = builder.add_source(hit.type, hit.id, hit.title)
        project = f" (projet {projects[hit.project_id]})" if hit.project_id in projects else ""
        hit_lines.append(f"[{number}] {hit.type} « {hit.title} »{project} : {hit.snippet}")
    builder.section("Extraits trouvés dans Astra pour cette question", hit_lines)

    builder.section("Activité récente dans les projets", activity.events(db, user))
    builder.section("Activité récente : derniers messages", activity.messages(db, user))
    builder.section("Activité récente : décisions", activity.decisions(db, user))
    builder.section("Activité récente : réunions", activity.meetings(db, user))
    builder.section("Activité récente : documents", activity.documents(db, user))
    return builder
