"""Questionnaire de cadrage proposé aux clients (cahier des charges).

Source unique : Astra Client l'affiche écran par écran, le serveur valide
les réponses avec, et Astra Hub relit les réponses avec les mêmes libellés.
Repris du formulaire « Création d'Identité Visuelle - Cahier de charge »
d'UP DESIGN, complété d'une question sur le type de projet pour que le
cadrage serve à toutes les prestations d'Astra.
"""

from dataclasses import dataclass, field
from enum import StrEnum


class QuestionType(StrEnum):
    TEXT = "text"  # réponse courte
    LONG_TEXT = "long_text"
    NUMBER = "number"
    LIST = "list"  # plusieurs entrées courtes (produits, concurrents…)
    SINGLE_CHOICE = "single_choice"
    MULTI_CHOICE = "multi_choice"
    DATE = "date"
    FILES = "files"  # images de référence, envoyées séparément


@dataclass(frozen=True)
class Choice:
    value: str
    label: str
    description: str | None = None


@dataclass(frozen=True)
class Question:
    id: str
    label: str
    type: QuestionType
    required: bool = True
    help: str | None = None
    example: str | None = None
    choices: tuple[Choice, ...] = ()
    min_items: int | None = None
    max_items: int | None = None
    allow_other: bool = False  # choix « Autre » avec précision libre


@dataclass(frozen=True)
class Section:
    id: str
    title: str
    intro: str
    questions: tuple[Question, ...] = field(default_factory=tuple)


T = QuestionType

PROJECT_TYPES = (
    Choice("visual_identity", "Identité visuelle / logo", "Logo, charte graphique, supports"),
    Choice("website", "Site web", "Vitrine, e-commerce, landing page"),
    Choice("mobile_app", "Application mobile", "Android, iOS"),
    Choice("software", "Logiciel / plateforme", "Application web ou desktop sur mesure"),
    Choice("digital_marketing", "Marketing digital", "Réseaux sociaux, publicité, contenus"),
    Choice("other", "Autre", None),
)

SECTIONS: tuple[Section, ...] = (
    Section(
        "company",
        "Présentation de l'entreprise",
        "Pour répondre à vos besoins, nous devons comprendre vos défis et où vous en êtes. "
        "Exprimez-vous librement : chaque détail nous aide.",
        (
            Question(
                "company_name",
                "Nom de votre entreprise",
                T.LONG_TEXT,
                help="Si possible, quelle est la genèse de ce nom ? D'où vient-il ?",
            ),
            Question(
                "whatsapp",
                "Numéro de téléphone (WhatsApp)",
                T.TEXT,
                help="Avec l'indicatif de votre pays.",
                example="(+237) 6 90 00 00 00",
            ),
            Question("country", "Pays de résidence", T.TEXT),
            Question("founded_year", "Année de création", T.NUMBER),
            Question("employees", "Nombre d'employés", T.NUMBER),
            Question("sector", "Secteur d'activité", T.TEXT),
            Question(
                "activity",
                "Présentation de l'activité",
                T.LONG_TEXT,
                help="Décrivez votre activité. Comment gagnez-vous de l'argent pour faire vivre "
                "l'entreprise et atteindre ses objectifs ? (réponse détaillée)",
            ),
            Question(
                "differentiation",
                "Quelle est votre politique de service principale ?",
                T.LONG_TEXT,
                help="Ce qui vous différencie des autres.",
            ),
            Question(
                "flagship_offers",
                "Vos produits et/ou services phares",
                T.LIST,
                help="Une liste, des plus vendus aux moins vendus.",
                min_items=1,
                max_items=15,
            ),
            Question(
                "specific_requests",
                "Demandes spécifiques",
                T.LONG_TEXT,
                help="Projetez-vous et indiquez tous les détails propres à votre activité qui "
                "devraient apparaître dans le résultat final. Soyez précis.",
            ),
            Question(
                "pitch",
                "S'il fallait présenter ce projet en 10 phrases maximum, que diriez-vous ?",
                T.LONG_TEXT,
            ),
            Question(
                "competitors",
                "Vos 5 principaux concurrents, et pourquoi",
                T.LIST,
                help="Noms et site web ou réseaux sociaux.",
                min_items=1,
                max_items=5,
            ),
            Question(
                "role_model",
                "L'entreprise que vous prenez comme modèle de réussite, et pour quelles raisons",
                T.LONG_TEXT,
                help="Qu'est-ce qui vous a autant marqué chez cette personne ou entreprise ?",
            ),
        ),
    ),
    Section(
        "project",
        "Votre projet",
        "Aidez-nous à cerner vos besoins en présentant votre projet. Inspirez-vous des exemples, "
        "puis répondez librement selon votre situation.",
        (
            Question(
                "project_types",
                "Que souhaitez-vous réaliser avec Astra ?",
                T.MULTI_CHOICE,
                choices=PROJECT_TYPES,
                min_items=1,
                allow_other=True,
            ),
            Question(
                "project_description",
                "Description du projet",
                T.LONG_TEXT,
                help="Expliquez votre projet pour qu'une personne extérieure comprenne vite le "
                "contexte : comment il est né, votre mission, votre vision à moyen ou long terme.",
            ),
            Question(
                "success_picture",
                "À quoi ressemblerait le succès de ce projet à vos yeux ?",
                T.LONG_TEXT,
                help="Quelle est « l'image du succès » que vous avez en tête ?",
            ),
            Question(
                "why_now",
                "Pourquoi faites-vous ce projet maintenant ?",
                T.LONG_TEXT,
                help="Quel est l'élément déclencheur ? Donnez-nous un maximum de contexte.",
            ),
            Question(
                "consequences",
                "Quelles seraient les conséquences si vous ne pouviez pas atteindre cet objectif ?",
                T.LONG_TEXT,
            ),
            Question(
                "stage",
                "À quel stade se trouve votre projet ?",
                T.SINGLE_CHOICE,
                choices=(
                    Choice("launch", "Lancement"),
                    Choice("growth", "Croissance"),
                    Choice("repositioning", "Repositionnement"),
                ),
            ),
            Question(
                "stage_details",
                "Précisez votre situation actuelle",
                T.LONG_TEXT,
                required=False,
                example="« Nous vendons déjà, mais nous devons améliorer notre image pour "
                "paraître plus professionnels. »",
            ),
            Question(
                "sales_channels",
                "Comment vendez-vous actuellement vos produits ou services ?",
                T.MULTI_CHOICE,
                choices=(
                    Choice("field", "Prospection sur le terrain"),
                    Choice("whatsapp", "WhatsApp"),
                    Choice("social", "Réseaux sociaux"),
                    Choice("website", "Site web"),
                    Choice("shop", "Boutique"),
                    Choice("ads", "Campagnes publicitaires (ADS)"),
                    Choice("not_yet", "Pas encore commercialisé"),
                ),
                min_items=1,
                allow_other=True,
            ),
            Question(
                "sales_details",
                "Détaillez vos canaux de vente",
                T.LONG_TEXT,
                required=False,
                help="Où vos clients vous découvrent-ils et achètent-ils ?",
            ),
            Question(
                "scope_elements",
                "Quels éléments (produits, services, catégories) le projet devra-t-il couvrir ?",
                T.LONG_TEXT,
                help="Même une estimation approximative suffit.",
                example="« 3 services principaux (formation, accompagnement, consulting) et "
                "2 catégories de produits numériques. »",
            ),
            Question(
                "past_freelancers",
                "Avez-vous déjà travaillé avec des prestataires sur ce type de projet ?",
                T.LONG_TEXT,
                help="Bonne ou mauvaise expérience : qu'en retenez-vous ?",
            ),
            Question(
                "why_us",
                "Qu'est-ce qui vous décide à travailler avec nous aujourd'hui ?",
                T.LONG_TEXT,
            ),
        ),
    ),
    Section(
        "goals",
        "Objectifs",
        "Présentez les objectifs principaux du projet, le cas échéant face à la concurrence.",
        (
            Question("objectives", "Objectifs attendus", T.LONG_TEXT),
            Question(
                "target",
                "Quelle cible souhaitez-vous atteindre ?",
                T.LONG_TEXT,
            ),
            Question(
                "target_aspirations",
                "Quelles sont les aspirations de cette cible et en quoi pouvez-vous l'aider ?",
                T.LONG_TEXT,
                help="Décrivez le profil type de vos clients (une sorte de persona).",
                example="« Homme, 39 ans, responsable marketing dans une PME à Douala… »",
            ),
            Question(
                "message",
                "Quel message et quelles émotions le projet doit-il transmettre ?",
                T.LONG_TEXT,
            ),
        ),
    ),
    Section(
        "brand",
        "Plateforme de marque",
        "Posons les bases de votre marque : ce que vous défendez, ce que vous combattez.",
        (
            Question(
                "values",
                "Au moins 3 de vos valeurs",
                T.LONG_TEXT,
                help="Une valeur n'a de sens que si elle s'oppose à celle de la concurrence "
                "(ex. Liberté vs Sécurité).",
            ),
            Question(
                "vision",
                "Votre vision",
                T.LONG_TEXT,
                help="Complétez : « Nous croyons à un monde où… » ou « Nous croyons que… ».",
            ),
            Question(
                "mission",
                "Votre mission",
                T.LONG_TEXT,
                help="Ce que vous faites concrètement aujourd'hui pour avancer vers cette vision.",
            ),
            Question(
                "enemies",
                "Vos ennemis",
                T.LONG_TEXT,
                help="Un problème, une attitude ou une situation qui bloque vos clients et que "
                "vous voulez éliminer.",
            ),
            Question(
                "weapons",
                "Vos armes",
                T.LONG_TEXT,
                help="Vos forces, compétences, méthodes, technologies qui vous rendent différent.",
            ),
            Question(
                "tone",
                "Votre tonalité",
                T.LONG_TEXT,
                help="Comment l'entreprise s'exprime : formel ou décontracté, motivant ou "
                "rassurant, audacieux ou professionnel…",
            ),
        ),
    ),
    Section(
        "visual",
        "Univers graphique",
        "Vos goûts et références visuelles, pour un résultat qui vous ressemble.",
        (
            Question(
                "inspiration_files",
                "Exemples d'identités graphiques qui vous plaisent",
                T.FILES,
                required=False,
                help="Logos d'autres entreprises, visuels… de votre secteur ou non.",
                max_items=10,
            ),
            Question(
                "inspiration_feedback",
                "Qu'est-ce qui vous marque dans ces exemples ?",
                T.LONG_TEXT,
                required=False,
            ),
            Question(
                "logo_request",
                "Type de demande",
                T.SINGLE_CHOICE,
                required=False,
                choices=(Choice("new", "Nouveau logo"), Choice("evolution", "Évolution d'un logo")),
            ),
            Question(
                "words_to_evoke",
                "3 mots que les gens doivent associer à votre entreprise",
                T.LIST,
                required=False,
                example="Nike = victoire, passer à l'action, être le meilleur",
                max_items=3,
            ),
            Question(
                "words_to_avoid",
                "3 mots qu'ils ne doivent surtout pas associer à votre logo",
                T.LIST,
                required=False,
                max_items=3,
            ),
            Question(
                "colors",
                "Couleurs souhaitées (2 à 3)",
                T.MULTI_CHOICE,
                required=False,
                choices=tuple(
                    Choice(value, label)
                    for value, label in (
                        ("red", "Rouge"),
                        ("orange", "Orange"),
                        ("yellow", "Jaune"),
                        ("green", "Vert"),
                        ("blue", "Bleu"),
                        ("indigo", "Indigo"),
                        ("violet", "Violet"),
                        ("black", "Noir"),
                        ("white", "Blanc"),
                    )
                ),
                max_items=3,
                allow_other=True,
            ),
            Question(
                "logo_types",
                "Quel type de logo vous semble adapté ?",
                T.MULTI_CHOICE,
                required=False,
                choices=(
                    Choice(
                        "wordmark", "Logotype", "Le nom seul, en typographie travaillée (Google)"
                    ),
                    Choice("monogram", "Monogramme", "Les initiales de l'entreprise (IBM, CNN)"),
                    Choice("icon", "Icône", "Un symbole seul, fort et reconnaissable (Apple)"),
                    Choice("abstract", "Logo abstrait", "Une forme non figurative (Nike, Pepsi)"),
                    Choice("combination", "Logo combiné", "Texte + symbole (Adidas, Lacoste)"),
                    Choice("emblem", "Emblème", "Texte intégré dans un blason (Starbucks)"),
                    Choice("mascot", "Mascotte", "Un personnage illustré (KFC, La vache qui rit)"),
                ),
            ),
            Question(
                "slogan",
                "Slogan de votre marque",
                T.TEXT,
                required=False,
                example="« Just do it » de Nike",
            ),
            Question(
                "reference_files",
                "Références : logos à suivre ou ancien logo (rebranding)",
                T.FILES,
                required=False,
                max_items=10,
            ),
        ),
    ),
    Section(
        "delivery",
        "Supports et délais",
        "Dernière étape : où sera utilisé le résultat, et pour quand.",
        (
            Question(
                "supports",
                "Supports de communication principaux dont vous avez besoin",
                T.LIST,
                help="Site web, réseaux sociaux, cartes de visite, flyers, T-shirts, kakémono…",
                min_items=1,
                max_items=20,
            ),
            Question(
                "deadline",
                "Le projet est-il soumis à une contrainte de date ?",
                T.DATE,
                required=False,
                help="Ex. un lancement de produit ou d'entreprise.",
            ),
            Question(
                "anything_else",
                "Avez-vous autre chose à nous partager ?",
                T.LONG_TEXT,
                required=False,
            ),
        ),
    ),
)

QUESTIONS: dict[str, Question] = {q.id: q for s in SECTIONS for q in s.questions}
FILE_QUESTIONS = frozenset(q.id for q in QUESTIONS.values() if q.type == T.FILES)
