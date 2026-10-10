"""Représentations du questionnaire et des cahiers des charges."""

from sqlalchemy.orm import Session

from app.models import ClientCompany, ProjectBrief
from app.schemas.client.brief import (
    BriefFileView,
    BriefHub,
    BriefView,
    ChoiceView,
    QuestionnaireView,
    QuestionView,
    SectionProgress,
    SectionView,
)
from app.schemas.client.common import attached_file
from app.services.client import briefs
from app.services.client.brief_questions import SECTIONS


def questionnaire() -> QuestionnaireView:
    return QuestionnaireView(
        sections=[
            SectionView(
                id=section.id,
                title=section.title,
                intro=section.intro,
                questions=[
                    QuestionView(
                        id=q.id,
                        label=q.label,
                        type=q.type.value,
                        required=q.required,
                        help=q.help,
                        example=q.example,
                        choices=[
                            ChoiceView(value=c.value, label=c.label, description=c.description)
                            for c in q.choices
                        ],
                        min_items=q.min_items,
                        max_items=q.max_items,
                        allow_other=q.allow_other,
                    )
                    for q in section.questions
                ],
            )
            for section in SECTIONS
        ]
    )


def to_view(brief: ProjectBrief) -> BriefView:
    return BriefView(
        id=brief.id,
        status=brief.status,
        title=briefs.title_of(brief),
        answers=brief.answers,
        current_section=brief.current_section,
        progress=[
            SectionProgress(section_id=section_id, answered=answered, total=total)
            for section_id, (answered, total) in briefs.section_progress(brief).items()
        ],
        missing_required=[q.id for q in briefs.missing_required(brief)],
        files=[
            BriefFileView(id=f.id, question_id=f.question_id, file=attached_file(f))
            for f in brief.files
            if f.file_key
        ],
        submitted_at=brief.submitted_at,
        project_id=brief.project_id,
        created_at=brief.created_at,
        updated_at=brief.updated_at,
    )


def to_hub(db: Session, brief: ProjectBrief) -> BriefHub:
    company = db.get(ClientCompany, brief.company_id)
    return BriefHub(
        **to_view(brief).model_dump(),
        company_id=company.id,
        company_name=company.name,
        company_self_registered=company.self_registered,
        author_name=brief.account.full_name if brief.account else None,
        proposed_plan=briefs.plan_for(brief),
    )
