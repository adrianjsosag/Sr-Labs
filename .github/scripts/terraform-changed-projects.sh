#!/usr/bin/env bash
# =============================================================================
# terraform-changed-projects.sh
# Decide QUÉ proyectos Terraform de Serverless/ECS-Fargate/Terraform cambiaron y en QUÉ ORDEN
# hay que desplegarlos. Lo usa el job "detect" del workflow .github/workflows/terraform.yml.
#
# USO
#   git diff --name-only <base> <head> | .github/scripts/terraform-changed-projects.sh
#   .github/scripts/terraform-changed-projects.sh <archivo> [<archivo> ...]
#
#   Recibe la lista de archivos cambiados (por stdin o como argumentos). No toca nada:
#   solo lee rutas y comprueba si existen directorios. Se puede probar en local con
#   listas de archivos inventadas.
#
# SALIDA
#   Por stdout, un JSON:
#     {"plan":[...], "apply":[...], "removed":[...]}
#   Cada lista contiene objetos {"name": "<proyecto>", "dir": "<ruta a su manifests/>"}:
#     plan     proyectos a validar y planificar
#     apply    proyectos que el pipeline puede aplicar (hoy es la misma lista que plan)
#     removed  directorios de servicios que ya no existen (sus recursos pueden seguir en AWS)
#   Dentro de GitHub Actions escribe además en $GITHUB_OUTPUT (outputs del step):
#     plan, apply, removed (los JSON) y has_plan / has_apply / has_removed / bastion_changed (true|false)
#
# REGLAS
#   - Solo cuentan archivos .tf, .tfvars y .terraform.lock.hcl dentro de <proyecto>/manifests/
#     (un README o un script no disparan ningún plan).
#   - Un cambio en ECS-services-module/modules/** (módulo común) afecta a TODOS los servicios.
#   - Se ignoran por completo (no entran en ninguna lista) y siempre se gestionan a mano desde tu PC:
#       S3-tfstate-backend-module  (bucket del state)
#       GitHub-OIDC-module         (permisos del propio pipeline)
#       EC2-bastion-host-module    (sus provisioners se conectan por SSH desde quien aplica y escriben
#                                   el .pem en local: no encaja en un runner de GitHub)
#     Si cambia el Bastion, se devuelve bastion_changed=true para que el workflow avise.
#   - Orden: VPC -> ALB -> ECS-cluster -> ECR -> servicios (alfabético).
#
# VARIABLES OPCIONALES
#   TF_ROOT    raíz de los proyectos (por defecto Serverless/ECS-Fargate/Terraform)
#   REPO_ROOT  raíz del repositorio desde donde se comprueban los directorios (por defecto ".")
# =============================================================================

# -e: termina ante cualquier error · -u: error si se usa una variable sin definir
# -o pipefail: un fallo en cualquier comando de una tubería (|) hace fallar toda la tubería
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
TF_ROOT="${TF_ROOT:-Serverless/ECS-Fargate/Terraform}"   # ${VAR:-defecto}: usa el valor por defecto si no viene definida
REPO_ROOT="${REPO_ROOT:-.}"
# Orden de despliegue de los proyectos base (los servicios van siempre al final).
# Para añadir un proyecto nuevo a la plataforma, ponlo aquí en la posición que le toque
# según sus dependencias (y en las opciones de "project" del workflow manual).
# Los proyectos que NO están aquí (bucket del state, OIDC y Bastion) se ignoran.
ORDER=(VPC-module ALB-module ECS-cluster-module ECR-module)
# Proyecto excluido del pipeline del que, aun así, se avisa si cambia
BASTION=EC2-bastion-host-module

# ---------------------------------------------------------------------------
# 1. Leer la lista de archivos cambiados
# ---------------------------------------------------------------------------
# Si hay argumentos, los archivos son los argumentos; si no, se leen de stdin, una ruta por
# línea (mapfile -t carga cada línea en un elemento del array "files", sin el salto de línea)
if [[ $# -gt 0 ]]; then files=("$@"); else mapfile -t files; fi

# ---------------------------------------------------------------------------
# 2. Clasificar cada archivo
# ---------------------------------------------------------------------------
# Arrays asociativos usados como "conjuntos": la clave es el proyecto y el valor siempre es 1.
# Así un proyecto con varios archivos cambiados solo aparece una vez.
#   changed[<proyecto>]  proyectos que cambiaron
#   removed[<servicio>]  servicios cuyo directorio ya no existe
declare -A changed=() removed=()
all_services=false        # pasa a true si cambió el módulo común de servicios
bastion_changed=false     # pasa a true si cambió el Bastion (solo para avisar)
for f in "${files[@]}"; do
  # Ignora todo lo que no esté dentro de la plataforma (otros laboratorios del repositorio)
  [[ "$f" == "$TF_ROOT/"* ]] || continue
  # Ruta relativa a TF_ROOT: "ALB-module/manifests/alb.tf"
  rel="${f#"$TF_ROOT"/}"

  # Solo cuentan los archivos de Terraform; el resto (README.md, *.sh, ...) se ignora
  case "$rel" in
    *.tf | *.tfvars | *.terraform.lock.hcl) ;;   # archivo de Terraform: se sigue procesando
    *) continue ;;                               # cualquier otro: siguiente archivo
  esac

  # ¿A qué proyecto pertenece? El orden de los patrones importa: el primero que coincide gana
  case "$rel" in
    ECS-services-module/modules/*)
      # Módulo común de servicios: afecta a todos (se resuelve después del bucle)
      all_services=true ;;
    ECS-services-module/services/*/manifests/*)
      # Un servicio concreto: se extrae su nombre de la ruta
      #   "ECS-services-module/services/nginx-1/manifests/service.tf" -> "nginx-1"
      svc="${rel#ECS-services-module/services/}"; svc="${svc%%/*}"
      if [[ -d "$REPO_ROOT/$TF_ROOT/ECS-services-module/services/$svc/manifests" ]]; then
        changed["ECS-services-module/services/$svc"]=1      # existe: hay que planificarlo/aplicarlo
      else
        removed["ECS-services-module/services/$svc"]=1      # se borró su directorio: solo se avisa
      fi ;;
    */manifests/*)
      # Un proyecto base: el primer componente de la ruta ("ALB-module/manifests/x.tf" -> "ALB-module").
      # Solo se acepta si está en ORDER: así quedan fuera el bucket, OIDC y el Bastion
      project="${rel%%/*}"
      [[ "$project" == "$BASTION" ]] && bastion_changed=true    # excluido, pero se avisa
      for p in "${ORDER[@]}"; do [[ "$p" == "$project" ]] && changed["$project"]=1; done ;;
  esac
done

# Si cambió el módulo común, se marcan TODOS los servicios que existen en el repositorio
if $all_services; then
  for d in "$REPO_ROOT/$TF_ROOT"/ECS-services-module/services/*/manifests; do
    [[ -d "$d" ]] || continue     # si el glob no encuentra nada, devuelve el patrón literal: se descarta
    # ".../services/nginx-2/manifests" -> "nginx-2"
    svc="${d%/manifests}"; svc="${svc##*/}"
    changed["ECS-services-module/services/$svc"]=1
  done
fi

# ---------------------------------------------------------------------------
# 3. Ordenar
# ---------------------------------------------------------------------------
# Primero los proyectos base en el orden fijo de ORDER (solo los que cambiaron)...
ordered=()
for p in "${ORDER[@]}"; do [[ -n "${changed[$p]:-}" ]] && ordered+=("$p"); done
# ...y después los servicios, en orden alfabético. "${!changed[@]}" son las claves del array.
# "|| true": si no hay servicios, grep devuelve error y con pipefail cortaría el script
mapfile -t services < <(printf '%s\n' "${!changed[@]}" | grep '^ECS-services-module/services/' | sort || true)
ordered+=("${services[@]}")

# Convierte una lista de proyectos en JSON: [{"name":"ALB-module","dir":"<TF_ROOT>/ALB-module/manifests"}, ...]
# (se construye a mano para no depender de jq en local)
to_json() { # lista de proyectos -> [{"name":..,"dir":..}]
  local out="" item name
  for item in "$@"; do
    [[ -n "$item" ]] || continue       # ignora elementos vacíos
    name="${item##*/}"                 # el nombre es el último componente: ".../services/nginx-1" -> "nginx-1"
    # ${out:+,} añade una coma solo si "out" ya tiene contenido (separador entre objetos)
    out+="${out:+,}{\"name\":\"$name\",\"dir\":\"$TF_ROOT/$item/manifests\"}"
  done
  printf '[%s]' "$out"
}

# ---------------------------------------------------------------------------
# 4. Construir las tres listas
# ---------------------------------------------------------------------------
# Servicios borrados, ordenados (sed quita la línea vacía que aparece si no hay ninguno)
mapfile -t removed_list < <(printf '%s\n' "${!removed[@]}" | sort | sed '/^$/d' || true)

plan_json=$(to_json "${ordered[@]}")
# Todo lo que se planifica se puede aplicar (los proyectos que no se aplican ya quedaron fuera).
# Se mantiene como output separado por si en el futuro algún proyecto fuera "solo plan".
apply_json="$plan_json"
removed_json=$(to_json "${removed_list[@]}")
# true si la lista JSON tiene algún elemento ("[]" = vacía)
bool() { [[ "$1" != "[]" ]] && echo true || echo false; }

# ---------------------------------------------------------------------------
# 5. Salida
# ---------------------------------------------------------------------------
# JSON por stdout: el workflow lo guarda en changes.json y lo muestra en el resumen del job
printf '{"plan":%s,"apply":%s,"removed":%s}\n' "$plan_json" "$apply_json" "$removed_json"

# Dentro de GitHub Actions, GITHUB_OUTPUT apunta a un archivo: cada línea "clave=valor" que se
# añade se convierte en un output del step (steps.changes.outputs.<clave>). Fuera de Actions no existe
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "plan=$plan_json"                         # proyectos a planificar (matrix del job plan)
    echo "apply=$apply_json"                       # proyectos a aplicar (job apply)
    echo "removed=$removed_json"                   # servicios borrados (aviso)
    echo "has_plan=$(bool "$plan_json")"           # ¿se ejecutan checks y plan?
    echo "has_apply=$(bool "$apply_json")"         # ¿se ejecuta apply?
    echo "has_removed=$(bool "$removed_json")"     # ¿hay que avisar de servicios borrados?
    echo "bastion_changed=$bastion_changed"        # ¿hay que avisar de que cambió el Bastion (excluido)?
  } >> "$GITHUB_OUTPUT"
fi
