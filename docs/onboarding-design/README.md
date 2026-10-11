# Static onboarding wireframes

**DESIGN_ONLY.** These SVGs/gallery are designed screens, not screenshots or implemented onboarding.
Synthetic Atlas names do not identify a real project. Canvas pixels describe this drawing, not a measured product window.
See [the coherent design](../PROJECT_ONBOARDING_HOLISTIC_V1.md#ux) and [gallery](index.html).

## Screen inventory

| ID | View | Artifact |
| --- | --- | --- |
| 01-overview | Project toevoegen · light | [01-overview.svg](01-overview.svg) |
| 02-new | Nieuw project · light | [02-new.svg](02-new.svg) |
| 03-link | Project koppelen · dark | [03-link.svg](03-link.svg) |
| 04-adopt | Code adopteren · light | [04-adopt.svg](04-adopt.svg) |
| 05-repositories | Bronnen bevestigen · dark | [05-repositories.svg](05-repositories.svg) |
| 06-analysis | Analysevoortgang · light | [06-analysis.svg](06-analysis.svg) |
| 06a-analysis-plan | Analyseplan · dark | [06a-analysis-plan.svg](06a-analysis-plan.svg) |
| 07-finding | Bevinding bespreken · dark | [07-finding.svg](07-finding.svg) |
| 08-approval | Inrichtingsvoorstel · light | [08-approval.svg](08-approval.svg) |
| 09-add-repository | Repository toevoegen · dark | [09-add-repository.svg](09-add-repository.svg) |
| 10-narrow | Bronnen en gesprek · light | [10-narrow.svg](10-narrow.svg) |

## Locale copy and expansion

| Decision / label | en | nl | de | fr | es |
| --- | --- | --- | --- | --- | --- |
| New | New project | Nieuw project | Neues Projekt | Nouveau projet | Nuevo proyecto |
| Link | Link project | Project koppelen | Projekt verbinden | Associer un projet | Vincular proyecto |
| Adopt | Adopt code | Code adopteren | Code übernehmen | Adopter le code | Adoptar código |
| Sources | Confirm sources | Bronnen bevestigen | Quellen bestätigen | Confirmer les sources | Confirmar fuentes |
| Analysis consent | Start scoped analysis | Start begrensde analyse | Begrenzte Analyse starten | Lancer l’analyse limitée | Iniciar análisis limitado |
| Discuss | Discuss findings | Bevindingen bespreken | Befunde besprechen | Discuter des constats | Comentar hallazgos |
| Exact effect | Confirm this setup | Deze inrichting bevestigen | Diese Einrichtung bestätigen | Confirmer cette configuration | Confirmar esta configuración |
| Child | Add repository | Repository toevoegen | Repository hinzufügen | Ajouter un dépôt | Añadir repositorio |
| Publication | Review history publication | Publicatie van historie bekijken | Veröffentlichung der Historie prüfen | Examiner la publication de l’historique | Revisar publicación del historial |
| Denied | Access unavailable | Toegang ontbreekt | Zugriff fehlt | Accès indisponible | Acceso no disponible |
| Partial | Partially assessed | Partieel beoordeeld | Teilweise bewertet | Évaluation partielle | Evaluación parcial |
| Uncertain | Checking original operation | Oorspronkelijke operatie teruglezen | Ursprünglichen Vorgang prüfen | Vérification de l’opération initiale | Comprobando operación original |

Human labels are proposed copy; identifiers/contracts stay unchanged. Allow ≥40% expansion, wrapped
buttons and 200% text. The narrow drawing is a 640px composition; smaller windows stack further.
Light/dark drawings illustrate contrast and system appearance; materials/glass are proposed native
chrome only. Color never carries status alone. Screen reading order is in SVG title/description and
manifest; focus rules and VoiceOver announcements are normative design requirements, not tested UI claims.

## Navigation and states

Overview→new/link/adopt; each journey uses Sources and optional Chat. Basic link returns to project
without analysis/setup. Adopt→analysis→findings→exact preview→owning progress. Add child starts from
the current project and reuses scoped Sources/Preview, never New project. The diagrams in the main
design define uncertainty/recovery transitions. Gallery links only navigate drawings; depicted actions
are not connected to any service. No JavaScript, provider calls, grants or application toolchain.

## Complete rendered static previews

SVG/PNG hashes and actual preview dimensions are bound in the manifest. Initial square-thumbnail
cropping was rejected privately; temporary padding now preserves the full original design canvas.
These are document drawings, never product screenshots or delivered onboarding.

### Project toevoegen

![Project toevoegen — static design only](01-overview.png)

### Nieuw project

![Nieuw project — static design only](02-new.png)

### Project koppelen

![Project koppelen — static design only](03-link.png)

### Code adopteren

![Code adopteren — static design only](04-adopt.png)

### Bronnen bevestigen

![Bronnen bevestigen — static design only](05-repositories.png)

### Analysevoortgang

![Analysevoortgang — static design only](06-analysis.png)

### Analyseplan

![Analyseplan — static design only](06a-analysis-plan.png)

### Bevinding bespreken

![Bevinding bespreken — static design only](07-finding.png)

### Inrichtingsvoorstel

![Inrichtingsvoorstel — static design only](08-approval.png)

### Repository toevoegen

![Repository toevoegen — static design only](09-add-repository.png)

### Bronnen en gesprek

![Bronnen en gesprek — static design only](10-narrow.png)
