"""Libellés français des statuts, pour les textes envoyés aux membres."""

from app.models.enums import ProjectStatus, TaskStatus

TASK_STATUS_LABELS = {
    TaskStatus.TODO: "À faire",
    TaskStatus.IN_PROGRESS: "En cours",
    TaskStatus.REVIEW: "En revue",
    TaskStatus.DONE: "Terminée",
}

PROJECT_STATUS_LABELS = {
    ProjectStatus.IDEA: "Idée",
    ProjectStatus.PLANNING: "Planification",
    ProjectStatus.ACTIVE: "Actif",
    ProjectStatus.REVIEW: "En revue",
    ProjectStatus.DONE: "Terminé",
    ProjectStatus.ARCHIVED: "Archivé",
}
