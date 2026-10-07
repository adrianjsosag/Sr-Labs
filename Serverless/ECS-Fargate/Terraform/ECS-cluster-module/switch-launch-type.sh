#!/usr/bin/env bash
# =============================================================================
# switch-launch-type.sh
# Cambia el tipo de despliegue del cluster ECS entre AWS Fargate y EC2,
# comentando / descomentando los bloques marcados en manifests/:
#
#   # >>> [FARGATE] enabled|disabled        # >>> [EC2] enabled|disabled
#   ...código...                            ...código...
#   # <<< [FARGATE]                         # <<< [EC2]
#
# Reglas:
#   - Desactivar un bloque: se antepone "# " a cada línea ("" -> "#").
#   - Activar un bloque:    se quita "<espacios>#" y un espacio opcional.
#   - El estado de cada bloque se guarda en su línea de apertura.
#
# Nunca ejecuta "terraform apply".
# =============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${SCRIPT_DIR}/manifests"
BACKUP_ROOT="${MANIFESTS_DIR}/.launch-type-backup"
BACKUPS_TO_KEEP=5

# --- Colores (solo si la salida es una terminal) -----------------------------
if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BLUE=$'\e[34m'; C_BOLD=$'\e[1m'; C_RESET=$'\e[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

info()  { printf '%s\n' "${C_BLUE}==>${C_RESET} $*"; }
ok()    { printf '%s\n' "${C_GREEN}OK${C_RESET}  $*"; }
warn()  { printf '%s\n' "${C_YELLOW}AVISO${C_RESET} $*" >&2; }
die()   { printf '%s\n' "${C_RED}ERROR${C_RESET} $*" >&2; exit 1; }

usage() {
  cat <<EOF
Uso:
  ${SCRIPT_NAME} fargate [--dry-run] [--validate]   Activa Fargate y desactiva EC2
  ${SCRIPT_NAME} ec2     [--dry-run] [--validate]   Activa EC2 y desactiva Fargate
  ${SCRIPT_NAME} status                             Muestra el modo actual y cada bloque
  ${SCRIPT_NAME} restore                            Restaura la última copia de seguridad
  ${SCRIPT_NAME} -h | --help                        Muestra esta ayuda

Opciones:
  --dry-run    Muestra qué bloques cambiarían, sin modificar archivos.
  --validate   Después del cambio ejecuta "terraform init -backend=false" y "terraform validate".

Este script nunca ejecuta "terraform apply".
EOF
}

# --- Procesador de bloques (awk) ----------------------------------------------
# Variables: action = check | status | apply ; target = FARGATE | EC2
# - check : solo valida los marcadores
# - status: imprime "archivo<TAB>línea<TAB>MODO<TAB>estado" por cada bloque
# - apply : imprime el archivo con los bloques activados/desactivados según target
#           (los bloques cambiados se escriben en el archivo indicado por "changes")
read -r -d '' AWK_PROGRAM <<'AWK' || true
function fail(msg) { printf "%s:%d: %s\n", FILENAME, FNR, msg > "/dev/stderr"; err = 1 }
BEGIN { inb = 0; err = 0 }
{
  line = $0

  # Apertura de bloque: "# >>> [MODO] enabled|disabled"
  if (line ~ /^[ \t]*# >>> \[[A-Za-z0-9_]+\] (enabled|disabled)[ \t]*$/) {
    if (inb) fail("se abre un bloque dentro de [" bmode "] (falta '# <<< [" bmode "]')")
    m = line; sub(/^[ \t]*# >>> \[/, "", m); sub(/\].*$/, "", m)
    st = (line ~ /enabled[ \t]*$/) ? "enabled" : "disabled"
    if (m != "FARGATE" && m != "EC2") fail("tipo de bloque desconocido: [" m "] (se esperaba FARGATE o EC2)")
    inb = 1; bmode = m; bstate = st; bstart = FNR
    want = (m == target) ? "enabled" : "disabled"
    change = (action == "apply" && st != want)
    if (action == "status") print FILENAME "\t" FNR "\t" m "\t" st
    if (change) {
      sub(/(enabled|disabled)[ \t]*$/, want, line)
      print FILENAME "\t" FNR "\t" m "\t" st "\t" want >> changes
    }
    if (action == "apply") print line
    next
  }

  # Cierre de bloque: "# <<< [MODO]"
  if (line ~ /^[ \t]*# <<< \[[A-Za-z0-9_]+\][ \t]*$/) {
    m = line; sub(/^[ \t]*# <<< \[/, "", m); sub(/\].*$/, "", m)
    if (!inb) fail("cierre '# <<< [" m "]' sin apertura")
    else if (m != bmode) fail("cierre '# <<< [" m "]' no coincide con la apertura [" bmode "] de la línea " bstart)
    inb = 0; change = 0
    if (action == "apply") print line
    next
  }

  # Marcador mal escrito
  if (line ~ /^[ \t]*# (>>>|<<<)/) fail("marcador mal formado: " line)

  if (inb) {
    if (bstate == "disabled" && line !~ /^[ \t]*#/)
      fail("línea sin comentar dentro de un bloque [" bmode "] marcado como disabled")
    if (change) {
      if (want == "disabled") line = (line == "") ? "#" : "# " line
      else sub(/^[ \t]*# ?/, "", line)
    }
  }
  if (action == "apply") print line
}
END {
  if (inb) { printf "%s: el bloque [%s] abierto en la línea %d no tiene cierre\n", FILENAME, bmode, bstart > "/dev/stderr"; err = 1 }
  exit err ? 2 : 0
}
AWK

run_awk() { # $1=action $2=target $3=file [$4=changes_file]
  awk -v action="$1" -v target="$2" -v changes="${4:-/dev/null}" "$AWK_PROGRAM" "$3"
}

# --- Utilidades -----------------------------------------------------------------
manifest_files() {
  find "$MANIFESTS_DIR" -maxdepth 1 -type f \( -name '*.tf' -o -name '*.tfvars' \) | sort
}

files_with_blocks() {
  local f
  while IFS= read -r f; do
    grep -qE '^[[:space:]]*# >>> \[' "$f" && printf '%s\n' "$f"
  done < <(manifest_files)
}

check_markers() {
  local f failed=0
  while IFS= read -r f; do
    run_awk check NONE "$f" || failed=1
  done < <(files_with_blocks)
  [[ $failed -eq 0 ]] || die "Hay marcadores con errores (ver arriba). No se modificó ningún archivo."
}

current_mode() { # imprime fargate | ec2 | inconsistente | sin-bloques
  local all f
  all="$(while IFS= read -r f; do run_awk status NONE "$f"; done < <(files_with_blocks))"
  [[ -n "$all" ]] || { echo "sin-bloques"; return; }
  local fe fd ee ed
  fe=$(grep -c $'\tFARGATE\tenabled$'  <<<"$all" || true)
  fd=$(grep -c $'\tFARGATE\tdisabled$' <<<"$all" || true)
  ee=$(grep -c $'\tEC2\tenabled$'      <<<"$all" || true)
  ed=$(grep -c $'\tEC2\tdisabled$'     <<<"$all" || true)
  if   [[ $fd -eq 0 && $ee -eq 0 && $fe -gt 0 ]]; then echo "fargate"
  elif [[ $fe -eq 0 && $ed -eq 0 && $ee -gt 0 ]]; then echo "ec2"
  else echo "inconsistente"; fi
}

cmd_status() {
  check_markers
  local f
  printf '%s\n' "${C_BOLD}Bloques en ${MANIFESTS_DIR#"$SCRIPT_DIR"/}/${C_RESET}"
  printf '  %-28s %-6s %-8s %s\n' "ARCHIVO" "LINEA" "MODO" "ESTADO"
  while IFS= read -r f; do
    run_awk status NONE "$f" | while IFS=$'\t' read -r file ln mode st; do
      local color=$C_YELLOW; [[ $st == enabled ]] && color=$C_GREEN
      printf '  %-28s %-6s %-8s %s\n' "$(basename "$file")" "$ln" "$mode" "${color}${st}${C_RESET}"
    done
  done < <(files_with_blocks)
  local mode; mode="$(current_mode)"
  echo
  case "$mode" in
    fargate|ec2)   printf 'Modo actual: %s\n' "${C_BOLD}${mode}${C_RESET}" ;;
    inconsistente) printf 'Modo actual: %s\n' "${C_RED}inconsistente${C_RESET} (hay bloques de ambos modos activos/inactivos). Ejecuta '${SCRIPT_NAME} fargate' o '${SCRIPT_NAME} ec2'." ;;
    *)             warn "No se encontraron bloques '# >>> [FARGATE|EC2]' en manifests/." ;;
  esac
}

prune_backups() {
  local old
  mapfile -t old < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | head -n -"$BACKUPS_TO_KEEP")
  ((${#old[@]})) && rm -rf -- "${old[@]}"
  return 0
}

cmd_restore() {
  [[ -d "$BACKUP_ROOT" ]] || die "No hay copias de seguridad en ${BACKUP_ROOT}"
  local last
  last="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
  [[ -n "$last" ]] || die "No hay copias de seguridad en ${BACKUP_ROOT}"
  info "Restaurando la copia $(basename "$last")"
  cp -p -- "$last"/* "$MANIFESTS_DIR"/
  ok "Archivos restaurados. Modo actual: $(current_mode)"
}

run_validate() {
  command -v terraform >/dev/null 2>&1 || { warn "terraform no está instalado; se omite --validate."; return 0; }
  info "terraform init -backend=false"
  terraform -chdir="$MANIFESTS_DIR" init -backend=false -input=false -no-color >/dev/null
  info "terraform validate"
  terraform -chdir="$MANIFESTS_DIR" validate -no-color
}

cmd_switch() { # $1 = fargate | ec2
  local mode="$1" target
  target="$(tr '[:lower:]' '[:upper:]' <<<"$mode")"

  check_markers
  [[ "$(current_mode)" != "sin-bloques" ]] || die "No se encontraron bloques '# >>> [FARGATE|EC2]' en manifests/."

  # Calcula los cambios sin escribir nada
  CHANGES_FILE="$(mktemp)"
  trap 'rm -f "$CHANGES_FILE"' EXIT
  local changes="$CHANGES_FILE" f
  while IFS= read -r f; do
    run_awk apply "$target" "$f" "$changes" >/dev/null
  done < <(files_with_blocks)

  if [[ ! -s "$changes" ]]; then
    ok "El cluster ya está en modo ${C_BOLD}${mode}${C_RESET}. Sin cambios."
    [[ $VALIDATE -eq 1 && $DRY_RUN -eq 0 ]] && run_validate
    return 0
  fi

  info "Cambios para pasar a modo ${C_BOLD}${mode}${C_RESET}:"
  while IFS=$'\t' read -r file ln m from to; do
    local color=$C_YELLOW; [[ $to == enabled ]] && color=$C_GREEN
    printf '  %-28s línea %-4s [%s] %s -> %s\n' "$(basename "$file")" "$ln" "$m" "$from" "${color}${to}${C_RESET}"
  done < "$changes"

  if [[ $DRY_RUN -eq 1 ]]; then
    ok "--dry-run: no se modificó ningún archivo."
    return 0
  fi

  # Copia de seguridad
  local backup_dir; backup_dir="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  while IFS= read -r f; do cp -p -- "$f" "$backup_dir"/; done < <(manifest_files)
  prune_backups
  info "Copia de seguridad: ${backup_dir#"$SCRIPT_DIR"/}"

  # Aplica el cambio archivo por archivo (escritura en temporal + mv)
  while IFS= read -r f; do
    local tmp; tmp="$(mktemp "${f}.XXXXXX")"
    if run_awk apply "$target" "$f" /dev/null > "$tmp"; then
      if cmp -s "$tmp" "$f"; then rm -f "$tmp"; else chmod --reference="$f" "$tmp" 2>/dev/null || true; mv -f "$tmp" "$f"; fi
    else
      rm -f "$tmp"; die "Falló el procesamiento de $(basename "$f"). Restaura con '${SCRIPT_NAME} restore'."
    fi
  done < <(files_with_blocks)

  # Formato
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="$MANIFESTS_DIR" fmt -no-color >/dev/null \
      || warn "terraform fmt falló; revisa la sintaxis o restaura con '${SCRIPT_NAME} restore'."
  else
    warn "terraform no está instalado; se omite 'terraform fmt'."
  fi

  ok "Modo actual: ${C_BOLD}$(current_mode)${C_RESET}"
  [[ $VALIDATE -eq 1 ]] && run_validate

  echo
  info "Siguiente paso: revisa los cambios con 'terraform plan' en manifests/ (este script nunca hace apply)."
  [[ "$mode" == "ec2" ]] && info "Modo ec2: el plan necesita el state de la VPC (con el output public_subnets_cidr_blocks) y el NAT Gateway."
  return 0
}

# --- Argumentos -----------------------------------------------------------------
COMMAND=""; DRY_RUN=0; VALIDATE=0
for arg in "$@"; do
  case "$arg" in
    fargate|ec2|status|restore) [[ -z "$COMMAND" ]] || die "Solo se admite un comando."; COMMAND="$arg" ;;
    --dry-run)  DRY_RUN=1 ;;
    --validate) VALIDATE=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) usage >&2; die "Argumento no reconocido: $arg" ;;
  esac
done
[[ -n "$COMMAND" ]] || { usage >&2; exit 1; }
[[ -d "$MANIFESTS_DIR" ]] || die "No existe el directorio ${MANIFESTS_DIR}"
command -v awk >/dev/null 2>&1 || die "Se necesita 'awk'."

case "$COMMAND" in
  status)      cmd_status ;;
  restore)     cmd_restore ;;
  fargate|ec2) cmd_switch "$COMMAND" ;;
esac
