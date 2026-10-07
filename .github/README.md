# 🤖 Pipeline CI/CD de Terraform (GitHub Actions)

Este directorio contiene el **pipeline que valida y despliega la plataforma de contenedores en AWS** ([`Serverless/ECS-Fargate/Terraform`](../Serverless/ECS-Fargate/Terraform/README.md)) desde GitHub.

Con el pipeline, **nadie ejecuta `terraform apply` desde su PC**. Los cambios entran por un **Pull Request**, el pipeline muestra qué va a cambiar en AWS (`plan`), una persona lo revisa y lo aprueba, y el pipeline lo aplica **en el orden correcto**.

Este documento sirve para **usarlo** (puesta en marcha, flujo diario, workflow manual) y para **mantenerlo** (cómo funciona cada job, el script de detección, los permisos y cómo probar cambios).

| 🧭 Ficha rápida | |
|---|---|
| **Qué despliega** | Los proyectos Terraform de la plataforma: VPC, ALB, cluster ECS, ECR y servicios (el Bastion, solo con el workflow manual) |
| **Cuándo se ejecuta** | En cada Pull Request a `main`, en cada merge a `main` y a mano (*Run workflow*) |
| **Credenciales de AWS** | **OIDC**, sin claves guardadas: rol de **plan** (solo lectura) y rol de **apply** (solo con aprobación). Los crea [`GitHub-OIDC-module`](../Serverless/ECS-Fargate/Terraform/GitHub-OIDC-module/README.md) |
| **Aprobación** | Environment de GitHub **`production`**, con revisores obligatorios |
| **Archivos** | [`workflows/terraform.yml`](workflows/terraform.yml) y [`scripts/terraform-changed-projects.sh`](scripts/terraform-changed-projects.sh) |
| **Nunca aplica** | El bucket del state (`S3-tfstate-backend-module`) ni sus propios permisos (`GitHub-OIDC-module`) |

> 🗺️ Vista general de la plataforma: [README de Terraform](../Serverless/ECS-Fargate/Terraform/README.md).

---

## Índice

1. 💡 [¿Qué es y para qué sirve?](#qué-es-y-para-qué-sirve)
2. 📚 [Conceptos básicos](#conceptos-básicos)
3. 🗺️ [Diagrama](#diagrama)
4. 📁 [Archivos del pipeline](#archivos-del-pipeline)
5. 🎯 [Disparadores](#disparadores)
6. 🔍 [Los jobs en detalle](#los-jobs-en-detalle)
7. 🧮 [Detección de proyectos](#detección-de-proyectos)
8. 🔒 [Seguridad y permisos](#seguridad-y-permisos)
9. ⚙️ [Configuración](#configuración)
10. 🚀 [Puesta en marcha (una sola vez)](#puesta-en-marcha-una-sola-vez)
11. 📲 [Flujo diario](#flujo-diario)
12. 🖐️ [Workflow manual](#workflow-manual)
13. 🛠️ [Mantenimiento](#mantenimiento)
14. 🧪 [Cómo probar cambios del pipeline](#cómo-probar-cambios-del-pipeline)
15. ⚠️ [Limitaciones conocidas](#limitaciones-conocidas)
16. 🧰 [Problemas frecuentes](#problemas-frecuentes)

---

## ¿Qué es y para qué sirve?

El pipeline aplica el modelo **GitOps**: **git es la única fuente de verdad**. Lo que está en la rama `main` es lo que debe existir en AWS.

| Paso | Qué ocurre | Por qué |
|---|---|---|
| 1. **Rama + Pull Request** | Haces el cambio en una rama y abres un PR a `main` | `main` siempre refleja lo desplegado |
| 2. **Validación y `plan`** | El pipeline comprueba el formato, valida el código y comenta en el PR el `plan` de cada proyecto cambiado | Ver qué va a pasar en AWS **antes** de tocar nada |
| 3. **Revisión y merge** | Alguien revisa el código y el plan (por ejemplo, "`17 to add, 0 to destroy`") | Cuatro ojos: nadie despliega solo |
| 4. **Aprobación** | Tras el merge, el pipeline **espera** a que una persona autorizada pulse *Approve* | Último control humano antes de cambiar AWS |
| 5. **Apply en orden** | Aplica los proyectos cambiados: VPC → ALB → cluster → ECR → servicios | Respeta las dependencias entre proyectos |
| 6. **Smoke test** | Comprueba con `curl` que cada servicio aplicado responde | Confirmar que el despliegue funciona de verdad |

> 💡 **Analogía:** es como una obra con permisos.
> - El PR es la **solicitud con los planos**.
> - El `plan` es el **informe del revisor técnico**: qué se construye y qué se derriba.
> - La aprobación es la **firma del responsable**.
> - El pipeline es la **constructora**: solo trabaja con la firma, y en el orden correcto (primero los cimientos, luego las paredes).

---

## Conceptos básicos

| Término | Qué significa en palabras simples |
|---|---|
| **Workflow** | Un archivo YAML en `.github/workflows/` que describe una automatización. Aquí: `terraform.yml`. |
| **Job** | Un bloque de trabajo del workflow que corre en su propia máquina. Aquí: `detect`, `checks`, `plan` y `apply`. |
| **Step** | Un paso dentro de un job: un comando o una *action* reutilizable. |
| **Runner** | La máquina temporal (Ubuntu) que GitHub crea para cada job y destruye al terminar. |
| **Action** | Un paso reutilizable publicado por terceros, por ejemplo `hashicorp/setup-terraform` (instala Terraform). |
| **`needs` / `outputs`** | `needs` hace que un job espere a otro; `outputs` le pasa datos, por ejemplo la lista de proyectos cambiados. |
| **Matrix** | Repite un job una vez por cada elemento de una lista: un `plan` por proyecto, en paralelo. |
| **Environment** | Una etapa de GitHub (`production`) que puede exigir **revisores**: el job que la usa espera la aprobación. |
| **OIDC** | GitHub firma un token por cada job. AWS lo cambia por credenciales temporales de un rol, sin claves guardadas. El campo **`sub`** del token dice de dónde viene: PR, rama o environment. |
| **`plan` / `apply`** | `plan` muestra qué cambiaría en AWS sin tocar nada; `apply` lo ejecuta. |
| **`concurrency`** | Regla que impide que dos ejecuciones del mismo grupo corran a la vez. |
| **Variables del repositorio** | Valores de configuración (no secretos) que usa el workflow: `vars.AWS_REGION`, etc. |

---

## Diagrama

**Los tres caminos del workflow:**

```mermaid
flowchart TB
    subgraph PR["Pull Request a main"]
        d1["detect"] --> c1["checks<br/>fmt + validate"] --> p1["plan × proyecto<br/>(rol plan)"] --> com["Comentario<br/>en el PR"]
    end
    subgraph MERGE["Merge (push) a main"]
        d2["detect"] --> c2["checks"] --> p2["plan × proyecto<br/>(resumen del job)"] --> ok{"⏸ Aprobación<br/>production"} --> a2["apply en orden<br/>(rol apply)"] --> s2["Smoke test"]
    end
    subgraph MANUAL["Run workflow (manual)"]
        d3["detect<br/>(1 proyecto)"] --> c3["checks"] --> p3["plan<br/>(-destroy si aplica)"] --> ok3{"⏸ Aprobación<br/>(si apply/destroy)"} --> a3["apply o destroy"]
    end
```

**Cómo se conectan los jobs:**

```mermaid
flowchart LR
    detect["detect<br/>qué proyectos cambiaron"] -- "plan / apply (JSON)" --> checks["checks<br/>sin AWS"]
    checks --> plan["plan<br/>matrix: 1 job por proyecto"]
    detect --> plan
    plan --> apply["apply<br/>environment: production<br/>1 job, proyectos en orden"]
    detect --> apply
```

---

## Archivos del pipeline

```text
Sr-Labs/
├── .github/
│   ├── README.md                               # este documento
│   ├── workflows/
│   │   └── terraform.yml                       # el workflow: detect → checks → plan → apply
│   └── scripts/
│       └── terraform-changed-projects.sh       # qué proyectos cambiaron y en qué orden
└── Serverless/ECS-Fargate/Terraform/
    ├── S3-tfstate-backend-module/              # bucket del state (a mano, antes que todo)
    ├── GitHub-OIDC-module/                     # proveedor OIDC + roles plan/apply (a mano)
    └── <módulos>/manifests/                    # lo que el pipeline valida, planifica y aplica
```

| Archivo | Qué hace |
|---|---|
| [`workflows/terraform.yml`](workflows/terraform.yml) | Define cuándo se ejecuta, los 4 jobs, sus permisos y el orden de despliegue |
| [`scripts/terraform-changed-projects.sh`](scripts/terraform-changed-projects.sh) | Recibe los archivos cambiados (`git diff`) y devuelve los proyectos a planificar y aplicar, ordenados. Ver [Detección de proyectos](#detección-de-proyectos) |
| [`GitHub-OIDC-module`](../Serverless/ECS-Fargate/Terraform/GitHub-OIDC-module/README.md) | Crea los roles IAM que asume el pipeline. **No** lo aplica el pipeline |

---

## Disparadores

```yaml
on:
  pull_request:  { branches: [main], paths: [...] }
  push:          { branches: [main], paths: [...] }
  workflow_dispatch: { inputs: { project, service_name, action } }
```

**Filtro de rutas (`paths`):** el workflow solo se dispara si el PR o el push cambia algo en:
- `Serverless/ECS-Fargate/Terraform/**`;
- `.github/workflows/terraform.yml`;
- `.github/scripts/terraform-changed-projects.sh`.

Los cambios en otros laboratorios del repositorio no lo activan.

| Evento | `detect` | `checks` | `plan` | `apply` |
|---|---|---|---|---|
| **Pull Request** a `main` | ✅ | ✅ si hay proyectos | ✅ por proyecto + comentario en el PR | — |
| **Push / merge** a `main` | ✅ | ✅ si hay proyectos | ✅ por proyecto (resumen) | ✅ tras la aprobación, si hay proyectos aplicables |
| **Manual** `action = plan` | ✅ (1 proyecto) | ✅ | ✅ | — |
| **Manual** `action = apply` / `destroy` | ✅ (1 proyecto) | ✅ | ✅ (`-destroy` si aplica) | ✅ tras la aprobación |

> ℹ️ Si un PR solo cambia documentación (`README.md`) o scripts que no son de Terraform, el workflow se dispara (la ruta coincide), pero `detect` no encuentra proyectos y los demás jobs se saltan.

---

## Los jobs en detalle

### `detect` – Detectar proyectos

| | |
|---|---|
| **Corre** | Siempre |
| **Permisos** | `contents: read` (sin AWS) |
| **Outputs** | `plan`, `apply` (listas JSON de `{name, dir}`), `has_plan`, `has_apply` |

1. `actions/checkout` con `fetch-depth: 0` (historia completa, necesaria para el `git diff`).
2. **Proyectos afectados:**
   - **PR:** `git diff --name-only <base del PR> <commit>` → script de detección.
   - **Push:** `git diff` entre el commit anterior de `main` (`github.event.before`) y el nuevo. En el primer push de una rama compara con el árbol vacío.
   - **Manual:** construye la lista con el proyecto elegido (valida `service_name` con `^[a-z0-9-]{1,20}$` y que exista su `manifests/`).
   - Escribe la lista en el resumen del job.
3. **Avisos** (anotaciones `::warning::`):
   - faltan las variables del repositorio, así que se omiten `plan` y `apply`;
   - se borró el directorio de un servicio (sus recursos pueden seguir en AWS);
   - en un merge cambió el Bastion, que no se aplica automáticamente.

### `checks` – fmt + validate

| | |
|---|---|
| **Corre** | Si `has_plan == 'true'` |
| **Permisos** | `contents: read` (sin AWS) |

1. Instala Terraform `1.16.5` (`hashicorp/setup-terraform`, sin *wrapper*).
2. `terraform fmt -check -recursive -diff` en todo `Serverless/ECS-Fargate/Terraform`.
3. Para cada proyecto de la lista `plan`: `terraform init -backend=false` + `terraform validate` (no necesita AWS ni el bucket).

### `plan` – plan por proyecto

| | |
|---|---|
| **Corre** | Si `has_plan == 'true'` **y** existe la variable `AWS_PLAN_ROLE_ARN` |
| **Necesita** | `detect` y `checks` |
| **Matrix** | Un job por proyecto de la lista `plan`, en paralelo (`fail-fast: false`: si uno falla, los demás siguen) |
| **Permisos** | `contents: read`, `id-token: write` (OIDC), `pull-requests: write` (comentar) |
| **Rol de AWS** | `AWS_PLAN_ROLE_ARN` (solo lectura) |

1. Credenciales temporales con `aws-actions/configure-aws-credentials` (sesión `gha-plan-<run_id>`).
2. `terraform init` (backend S3) y `terraform plan -lock-timeout=5m -detailed-exitcode -out=tfplan`. En el workflow manual con `destroy` añade `-destroy`.
   - Código **0**: sin cambios. Código **2**: hay cambios. Código **1**: error; el job falla.
3. Resumen del job: la línea `Plan: …` y el plan completo plegado (hasta 60 000 caracteres).
4. **Solo en PR:** comenta el plan en el PR con `actions/github-script`.
   - Cada proyecto tiene un comentario identificado con el marcador oculto `<!-- tf-plan:<proyecto> -->`. En cada push nuevo se **actualiza** ese comentario en lugar de crear otro.
   - Icono: ✅ sin cambios, 📝 con cambios, ❌ error.

### `apply` – apply con aprobación

| | |
|---|---|
| **Corre** | Si `has_apply == 'true'`, existe `AWS_APPLY_ROLE_ARN` y: es un **push a `main`**, o es el **workflow manual** con `action` `apply` o `destroy` |
| **Necesita** | `detect` y `plan` (todos los `plan` de la matrix deben terminar bien) |
| **Environment** | `production`: el job **espera la aprobación** de un revisor antes de empezar |
| **Permisos** | `contents: read`, `id-token: write` |
| **Rol de AWS** | `AWS_APPLY_ROLE_ARN` (solo se puede asumir desde este environment) |

1. Recorre la lista `apply` **en orden**, en un solo job. Para cada proyecto:
   1. `terraform init`;
   2. `terraform plan -detailed-exitcode -out=tfplan` (con `-destroy` si corresponde);
   3. si hay cambios (código 2), `terraform apply tfplan`;
   4. si el `plan` falla (código 1), **se detiene** y no aplica los siguientes.
   
   Cada proyecto se **vuelve a planificar justo antes de aplicarlo**, para que vea los outputs que el proyecto anterior acaba de aplicar.
2. El resumen del job lista cada proyecto como "aplicado" o "sin cambios".
3. **Smoke test:** para cada servicio aplicado (no en `destroy`) lee `terraform output -raw url` y hace `curl` cada 10 s, hasta 30 intentos (5 min), esperando **HTTP 200**. Si no llega, el job falla.

### `concurrency`

```yaml
group: terraform-${{ pull_request ? 'pr-<número>' : 'deploy' }}
cancel-in-progress: ${{ es un pull_request }}
```

- **PR:** un push nuevo **cancela** la ejecución anterior del mismo PR (solo hacen `plan`).
- **Merge y manual:** comparten el grupo `deploy`. Se ejecutan **de uno en uno** y **nunca se cancela** un `apply` en curso; el siguiente espera.

---

## Detección de proyectos

[`scripts/terraform-changed-projects.sh`](scripts/terraform-changed-projects.sh) decide **qué proyectos** tocar y **en qué orden**.

**Entrada:** lista de archivos cambiados, por stdin o como argumentos.

**Salida:** JSON por stdout. Dentro de GitHub Actions escribe además en `$GITHUB_OUTPUT`: `plan`, `apply`, `removed`, `has_plan`, `has_apply`, `has_removed` y `bastion_changed`.

**Reglas:**

| Regla | Detalle |
|---|---|
| Qué archivos cuentan | Solo `.tf`, `.tfvars` y `.terraform.lock.hcl` dentro de `Serverless/ECS-Fargate/Terraform/<proyecto>/manifests/` |
| Módulo común de servicios | Un cambio en `ECS-services-module/modules/**` marca **todos** los servicios existentes |
| Proyectos ignorados | `S3-tfstate-backend-module` y `GitHub-OIDC-module`: siempre a mano |
| Bastion | `EC2-bastion-host-module` va en `plan` pero **no** en `apply` |
| Servicios borrados | Si cambió un archivo de `services/<x>/manifests/` y ese directorio ya no existe, va a `removed` (aviso) |
| Orden | `VPC-module` → `ALB-module` → `ECS-cluster-module` → `EC2-bastion-host-module` → `ECR-module` → servicios (alfabético) |

**Ejemplo:**

```bash
cd ~/Sr-Labs
printf '%s\n' \
  Serverless/ECS-Fargate/Terraform/ECR-module/manifests/ecr.auto.tfvars \
  Serverless/ECS-Fargate/Terraform/VPC-module/manifests/vpc.auto.tfvars \
  | .github/scripts/terraform-changed-projects.sh
```

```json
{"plan":[{"name":"VPC-module","dir":"Serverless/ECS-Fargate/Terraform/VPC-module/manifests"},
         {"name":"ECR-module","dir":"Serverless/ECS-Fargate/Terraform/ECR-module/manifests"}],
 "apply":[ "...los mismos..." ],
 "removed":[]}
```

**Ver qué tocaría tu rama:** `git diff --name-only main | .github/scripts/terraform-changed-projects.sh`.

Variables opcionales: `TF_ROOT` (por defecto `Serverless/ECS-Fargate/Terraform`) y `REPO_ROOT` (por defecto `.`).

---

## Seguridad y permisos

| Control | Cómo se implementa |
|---|---|
| **Sin claves de AWS en GitHub** | OIDC: cada job pide credenciales **temporales** (1 h) de un rol. No hay secretos que robar ni rotar |
| **Dos roles** | **plan:** `ReadOnlyAccess` + leer el state + crear y borrar el bloqueo `*.tflock`. **apply:** `PowerUserAccess` + IAM acotado a `*-stag-*` + escribir el state. Detalle en [`GitHub-OIDC-module`](../Serverless/ECS-Fargate/Terraform/GitHub-OIDC-module/README.md#cómo-funciona) |
| **Quién puede asumir cada rol** (`sub` del token) | **plan:** `repo:adrianjsosag/Sr-Labs:pull_request` y `…:ref:refs/heads/main`. **apply:** **solo** `…:environment:production` |
| **El apply exige aprobación** | El job `apply` usa `environment: production`, con revisores obligatorios. Sin aprobación, ni siquiera obtiene el token con `environment:production` |
| **El pipeline no cambia sus permisos** | Nunca aplica `GitHub-OIDC-module`, y el rol de apply tiene un `Deny` explícito sobre sus propios roles |
| **Token de GitHub mínimo** | `permissions: contents: read` por defecto. `id-token: write` solo en `plan` y `apply`; `pull-requests: write` solo en `plan` |
| **Actions fijadas por SHA** | `actions/checkout`, `hashicorp/setup-terraform`, `aws-actions/configure-aws-credentials` y `actions/github-script` usan el SHA del commit, con la versión en un comentario. Un tag se puede mover; un SHA no |
| **Sin credenciales en el checkout** | `persist-credentials: false`: el token de GitHub no queda en `.git` del runner |
| **Sin inyección de comandos** | Las entradas del usuario (`project`, `service_name`) y los datos del evento se pasan a los scripts por `env:`, nunca interpolados con `${{ }}` dentro de `run:` |
| **Un despliegue a la vez** | `concurrency` del grupo `deploy` |

---

## Configuración

**Variables del repositorio** (*Settings → Secrets and variables → Actions → Variables*):

| Variable | Valor | La usa |
|---|---|---|
| `AWS_REGION` | `us-east-1` | `plan` y `apply` |
| `AWS_PLAN_ROLE_ARN` | Output `plan_role_arn` de `GitHub-OIDC-module` | `plan`. Si está vacía, `plan` y `apply` se saltan con un aviso |
| `AWS_APPLY_ROLE_ARN` | Output `apply_role_arn` de `GitHub-OIDC-module` | `apply`. Si está vacía, `apply` se salta |

**Environment `production`:** revisores obligatorios y, como rama permitida, solo `main`. Su nombre **debe coincidir** con `github_environment` de `GitHub-OIDC-module`.

**Variables del workflow** (bloque `env:` de `terraform.yml`):

| Variable | Valor | Para qué |
|---|---|---|
| `TF_VERSION` | `1.16.5` | Versión de Terraform que se instala |
| `TF_ROOT` | `Serverless/ECS-Fargate/Terraform` | Raíz de los proyectos (también la usa el script) |
| `TF_IN_AUTOMATION` | `true` | Salida de Terraform más compacta, sin sugerencias interactivas |
| `TF_INPUT` | `false` | Terraform nunca pregunta nada (fallaría en vez de quedarse esperando) |

---

## Puesta en marcha (una sola vez)

1. **Bucket del state:** aplica [`S3-tfstate-backend-module`](../Serverless/ECS-Fargate/Terraform/S3-tfstate-backend-module/README.md), si aún no existe.
2. **Accesos del pipeline:** aplica [`GitHub-OIDC-module`](../Serverless/ECS-Fargate/Terraform/GitHub-OIDC-module/README.md) y anota sus outputs:
   ```bash
   cd ~/Sr-Labs/Serverless/ECS-Fargate/Terraform/GitHub-OIDC-module/manifests
   terraform init && terraform apply           # 8 to add
   terraform output
   ```
3. **Environment con aprobación.** En GitHub: *Settings → Environments → New environment* → `production`.
   - Activa *Required reviewers* (tú o tu equipo).
   - En *Deployment branches and tags*, permite solo `main`.
   > ⚠️ Sin revisores, el apply se ejecuta sin esperar a nadie.
4. **Variables del repositorio:** crea `AWS_REGION`, `AWS_PLAN_ROLE_ARN` y `AWS_APPLY_ROLE_ARN` (ver [Configuración](#configuración)). Mientras no existan, el workflow solo ejecuta `fmt` y `validate`.
5. **Proteger `main`.** *Settings → Rules → Rulesets → New branch ruleset* sobre `main`:
   - *Require a pull request before merging*, con al menos 1 aprobación.
   - *Block force pushes*.
   - *(Opcional)* *Require status checks to pass*: `fmt + validate`.
     > ⚠️ Si lo marcas como obligatorio, los PR que **no** tocan Terraform quedan bloqueados: el workflow no se dispara para ellos y el check nunca aparece. Márcalo solo si todos los PR del repo pasan por Terraform, o restringe el ruleset.

✅ **Comprobación:** abre un PR que cambie, por ejemplo, `desired_count` en `Serverless/ECS-Fargate/Terraform/ECS-services-module/services/nginx-2/manifests/service.auto.tfvars`.
1. El PR debe recibir el comentario del plan (`1 to change`).
2. Tras el merge, el job `apply` pide aprobación, aplica y el smoke test pasa.

---

## Flujo diario

```bash
cd ~/Sr-Labs
git switch main && git pull
git switch -c cambio-nginx-2                  # 1. rama nueva
# 2. edita los .tf / .tfvars
git add . && git commit -m "nginx-2: 3 tareas"
git push -u origin cambio-nginx-2             # 3. sube la rama
```

4. **Abre el Pull Request** a `main` y espera el comentario del plan de cada proyecto.
5. **Revisa el plan:**

   | Icono | Significado | Qué hacer |
   |---|---|---|
   | ✅ | `No changes`: el proyecto ya coincide con AWS | Nada |
   | 📝 | Hay cambios | Abre *Ver el plan completo*: `+` crea, `~` modifica, **`-` destruye**, `-/+` reemplaza |
   | ❌ | El plan falló | Lee el error en el comentario o en el log del job |

   > ⚠️ **Fíjate en `to destroy` y en `must be replaced`.** Si aparecen sin esperarlo, no hagas merge hasta entender por qué.
6. **Haz merge.**
7. **Aprueba:** *Actions → el run del merge → Review deployments → production → Approve and deploy*.
8. Revisa el resumen del job `apply` y el smoke test.

**Publicar una versión nueva de una aplicación:**
1. Sube la imagen **desde tu PC** con `ECR-module/push-image.sh <repo> <tag-nuevo> ...`.
2. PR cambiando `image_tag` en el `service.auto.tfvars` del servicio.

El pipeline no sube imágenes: si el tag no existe, el `plan` del servicio falla con `couldn't find resource`.

**Añadir un servicio nuevo:** sigue la [guía de la plataforma](../Serverless/ECS-Fargate/Terraform/README.md#guía-desplegar-mi-aplicación). No olvides cambiar la `key` de su `backend.tf`. El pipeline lo detecta solo, sin cambiar nada del workflow.

🧹 **Eliminar un servicio:**
1. **Primero** `destroy` con el [workflow manual](#workflow-manual).
2. **Después**, un PR que borre su directorio.

Si borras el directorio primero, el pipeline solo avisa y los recursos se quedan en AWS.

---

## Workflow manual

*Actions → Terraform → Run workflow*, desde la rama `main` (el rol de plan solo confía en `main` y en los PR):

| Entrada | Valores |
|---|---|
| `project` | `VPC-module`, `ALB-module`, `ECS-cluster-module`, `EC2-bastion-host-module`, `ECR-module` o `service` |
| `service_name` | Solo si `project = service`: el nombre del directorio, por ejemplo `nginx-1` |
| `action` | `plan` (solo mirar), `apply` o `destroy` |

Siempre muestra primero el plan (con `-destroy` si la acción es `destroy`). Para `apply` y `destroy` espera la aprobación del environment `production`.

**Cuándo usarlo:**
- **Bastion:** es la única forma de aplicarlo desde GitHub. Ten en cuenta que su `.pem` se escribe en el runner y se pierde (la llave sigue en el state), y que el provisioner SSH necesita que el runner pueda llegar al puerto 22.
- **Destruir** un servicio o un módulo.
- **Volver a aplicar** un proyecto sin cambios de código, por ejemplo para corregir un cambio hecho a mano en la consola (*drift*).

---

## Mantenimiento

### Añadir un proyecto Terraform nuevo a la plataforma
Por ejemplo, un `RDS-module`:
1. **Script:** añádelo al array `ORDER` de `terraform-changed-projects.sh`, en la posición que le corresponda según sus dependencias.
2. **Workflow:** añádelo a las `options` de la entrada `project` de `workflow_dispatch`.
3. **Permisos:** si crea recursos IAM con otro patrón de nombre, o servicios que `PowerUserAccess` no cubre, amplía `GitHub-OIDC-module` (a mano).

Los **servicios nuevos** (`ECS-services-module/services/<x>`) no requieren cambios: el script los detecta por su ruta.

### Actualizar las actions
Las actions están fijadas por SHA. Para obtener el SHA de la última versión de una action:

```bash
r=actions/checkout
tag=$(curl -s https://api.github.com/repos/$r/releases/latest | jq -r .tag_name)
curl -s https://api.github.com/repos/$r/git/ref/tags/$tag | jq -r '.object | "\(.type) \(.sha)"'
# si el tipo es "tag" (anotado), el SHA del commit es:
#   curl -s https://api.github.com/repos/$r/git/tags/<sha> | jq -r .object.sha
```

Sustituye `uses: <action>@<sha> # <versión>` en todos los jobs.

> 💡 **Recomendado:** activa Dependabot para que abra PRs con las versiones nuevas. Crea `.github/dependabot.yml` con `package-ecosystem: github-actions`.

### Cambiar la versión de Terraform
1. Cambia `TF_VERSION` en `terraform.yml`.
2. Si cambia la versión mínima, actualiza también `required_version` en los `versions.tf`.
3. Prueba primero en un PR: los `plan` deben seguir diciendo `No changes` donde no hubo cambios.

### Añadir escáneres de seguridad
Es una [mejora pendiente](../Serverless/ECS-Fargate/Terraform/README.md#oportunidades-de-mejora-devsecops). Se añaden como steps del job `checks`, que no necesita AWS:
- **tflint:** action `terraform-linters/setup-tflint` + `tflint --recursive`.
- **checkov:** action `bridgecrewio/checkov-action` con `directory: Serverless/ECS-Fargate/Terraform`. Empieza con `soft_fail: true`, porque el laboratorio tiene hallazgos conocidos.
- **gitleaks:** busca secretos en los commits del PR.

---

## Cómo probar cambios del pipeline

Antes de subir cambios a `terraform.yml` o al script:

```bash
cd ~/Sr-Labs
actionlint                                             # sintaxis y expresiones del workflow
shellcheck .github/scripts/terraform-changed-projects.sh

# Casos del script con listas de archivos ficticias (no tocan nada)
X=Serverless/ECS-Fargate/Terraform
printf '%s\n' "$X/ECS-services-module/modules/ecs-service/main.tf" | .github/scripts/terraform-changed-projects.sh   # → todos los servicios
printf '%s\n' "$X/EC2-bastion-host-module/manifests/x.tf"          | .github/scripts/terraform-changed-projects.sh   # → plan sí, apply no
printf '%s\n' "$X/README.md"                                       | .github/scripts/terraform-changed-projects.sh   # → nada
```

> ℹ️ `actionlint` y `shellcheck` no vienen con Ubuntu: descárgalos de sus páginas de *Releases* en GitHub o instálalos con `apt`/`snap`.

**Prueba real sin riesgo:**
1. Abre un PR desde una rama: solo hace `plan`, con el rol de solo lectura.
2. Antes de hacer merge, comprueba en el run que `detect` eligió los proyectos esperados y que los `plan` son correctos.
3. Si no quieres que el merge aplique nada, el `apply` sigue esperando tu aprobación: puedes rechazarla.

---

## Limitaciones conocidas

| Limitación | Detalle | Alternativa |
|---|---|---|
| **No sube imágenes Docker** | `push-image.sh` necesita Docker y se ejecuta desde tu PC | Subir la imagen antes del merge. A futuro: un pipeline de *build* por aplicación |
| **El Bastion no se aplica en el merge** | Sus provisioners se conectan por SSH desde quien aplica y el `.pem` se escribe en ese equipo | Aplicarlo desde tu PC o con el workflow manual. Mejor aún: SSM Session Manager en lugar de SSH |
| **Se vuelve a planificar antes del apply** | El `apply` no usa el plan del job `plan` (el que viste), sino uno nuevo calculado justo antes. Así cada proyecto ve los outputs del anterior, pero si alguien cambia AWS entre medias, el apply incluirá esos cambios | Revisar el resumen del job `apply`. A futuro: aplicar el plan guardado cuando solo cambia un proyecto |
| **Un solo entorno** | Todo despliega en `stag`, en una cuenta | Al crear más entornos: un environment de GitHub y un par de roles por entorno |
| **Sin escáneres de seguridad** | Solo `fmt` y `validate` | Ver [Añadir escáneres](#añadir-escáneres-de-seguridad) |

---

## Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| Aviso "se omiten plan y apply" | Faltan las variables del repositorio `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN` o `AWS_REGION` | Ver [Configuración](#configuración) |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | El `sub` del token no coincide con la *trust policy*: otro repositorio u owner, workflow lanzado desde otra rama, o environment con otro nombre | Compara `terraform output github_oidc_subjects` (en `GitHub-OIDC-module`) con el repositorio, la rama y el environment reales |
| El job `apply` se queda en *Waiting* | Espera la aprobación del environment `production` | *Review deployments → Approve and deploy* |
| El `apply` no espera aprobación | El environment `production` no tiene revisores | *Settings → Environments → production → Required reviewers* |
| `Error acquiring the state lock` | Otro `plan`/`apply` usa ese state, o uno anterior se interrumpió | Espera (el workflow espera hasta 5 min). Si nadie lo usa: `terraform force-unlock <LOCK_ID>` desde tu PC |
| `AccessDenied` al crear un rol IAM | El nombre del rol no contiene `-stag-` | Usa la convención `<división>-<entorno>-…` o amplía los permisos en `GitHub-OIDC-module` |
| `plan` de un servicio: `couldn't find resource` | El `image_tag` no está subido al ECR | Súbelo con `push-image.sh` y relanza el job (*Re-run failed jobs*) |
| `NoSuchBucket` en `terraform init` | No existe el bucket del state | Aplica `S3-tfstate-backend-module` |
| El smoke test falla por timeout | Las tareas no pasan el health check: imagen, puerto o ruta de salud incorrectos | Eventos del servicio en ECS y logs en CloudWatch (ver [servicios](../Serverless/ECS-Fargate/Terraform/ECS-services-module/README.md#problemas-frecuentes)) |
| Un PR no dispara el workflow | No toca `Serverless/ECS-Fargate/Terraform/**` ni los archivos del pipeline, o no va contra `main` | Es lo esperado |
| `detect` no encuentra el proyecto que cambié | Cambiaste un archivo que no cuenta (README, script) o un proyecto ignorado (bucket, OIDC) | Ver las [reglas de detección](#detección-de-proyectos) |
| En Windows, `git status` muestra el script como modificado (`old mode 100755 / new mode 100644`) | Git para Windows no ve el permiso de ejecución en esa unidad | **No hagas commit** de ese cambio. Para ocultarlo: `git config core.fileMode false` en el repositorio |
