# 🤖 GitHub Actions de la plataforma Terraform

Este directorio contiene los **workflows de GitHub Actions** de la plataforma de contenedores en AWS ([`Serverless/ECS-Fargate/Terraform`](../Serverless/ECS-Fargate/Terraform/README.md)). Cada workflow tiene su propio documento, junto al archivo del workflow.

## Workflows

| Workflow | Qué hace | Cuándo se ejecuta | Documentación |
|---|---|---|---|
| [`terraform.yml`](workflows/terraform.yml) | **Pipeline CI/CD**: valida, planifica y despliega en orden los proyectos que cambian, con aprobación antes del `apply` | En cada Pull Request a `main`, en cada merge a `main` y a mano | [README-terraform.md](workflows/README-terraform.md) |
| [`check-terraform-drift.yml`](workflows/check-terraform-drift.yml) | **Detección de drift**: compara AWS con el código de `main` sin cambiar nada y abre un issue si hay diferencias | Solo a mano, desde `main` | [README-check-terraform-drift.md](workflows/README-check-terraform-drift.md) |

## Archivos

```text
.github/
├── README.md                                   # este índice
├── workflows/
│   ├── terraform.yml                           # pipeline: detect → checks → plan → apply
│   ├── README-terraform.md                     # su documentación
│   ├── check-terraform-drift.yml               # detección de drift (manual): list → drift → report
│   └── README-check-terraform-drift.md         # su documentación
└── scripts/
    └── terraform-changed-projects.sh           # qué proyectos procesar y en qué orden (lo usan los dos)
```

El script [`terraform-changed-projects.sh`](scripts/terraform-changed-projects.sh) es compartido: el pipeline le pasa los archivos cambiados y el workflow de drift le pasa todos. Está explicado en [Detección de proyectos](workflows/README-terraform.md#detección-de-proyectos).

## Configuración común

Los dos workflows usan las mismas credenciales y variables:

- **OIDC, sin claves guardadas:** los roles de **plan** (solo lectura) y **apply** los crea [`GitHub-OIDC-module`](../Serverless/ECS-Fargate/Terraform/GitHub-OIDC-module/README.md). El workflow de drift solo usa el de plan.
- **Variables del repositorio:** `AWS_REGION`, `AWS_PLAN_ROLE_ARN` y `AWS_APPLY_ROLE_ARN`. Ver [Configuración](workflows/README-terraform.md#configuración).
- **Primera vez:** bucket del state, OIDC, environment `production` y protección de `main`. Ver [Puesta en marcha](workflows/README-terraform.md#puesta-en-marcha-una-sola-vez).

> 🔒 Ninguno de los dos gestiona el bucket del state, `GitHub-OIDC-module` ni el Bastion: se gestionan desde tu PC.
