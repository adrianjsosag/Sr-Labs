#!/usr/bin/env bash
# =============================================================================
# terraform-changed-projects.sh
# Which Terraform projects of Serverless/ECS-Fargate/Terraform changed, in deployment order.
#
#   git diff --name-only <base> <head> | .github/scripts/terraform-changed-projects.sh
#   .github/scripts/terraform-changed-projects.sh <file> [<file> ...]
#
# Output (stdout, JSON) and, inside GitHub Actions, the same values in $GITHUB_OUTPUT:
#   plan     projects to validate/plan            [{"name":"ALB-module","dir":"Serverless/.../manifests"}, ...]
#   apply    projects the pipeline may apply      (plan without EC2-bastion-host-module)
#   removed  service directories that no longer exist (their resources may still be in AWS)
#   has_plan / has_apply / has_removed / bastion_changed   true|false
#
# Rules:
#   - Only .tf, .tfvars and .terraform.lock.hcl files inside <project>/manifests/ count.
#   - A change in ECS-services-module/modules/** affects every service.
#   - S3-tfstate-backend-module and GitHub-OIDC-module are ignored: they are always applied by hand.
#   - EC2-bastion-host-module is planned but never applied by the pipeline (its provisioners SSH from
#     whoever applies and write the .pem locally): apply it from your PC or with the manual workflow.
#   - Order: VPC -> ALB -> ECS-cluster -> EC2-bastion-host -> ECR -> services (alphabetical).
# =============================================================================
set -euo pipefail

TF_ROOT="${TF_ROOT:-Serverless/ECS-Fargate/Terraform}"
REPO_ROOT="${REPO_ROOT:-.}"
ORDER=(VPC-module ALB-module ECS-cluster-module EC2-bastion-host-module ECR-module)
MANUAL_ONLY=EC2-bastion-host-module

if [[ $# -gt 0 ]]; then files=("$@"); else mapfile -t files; fi

declare -A changed=() removed=()
all_services=false
for f in "${files[@]}"; do
  [[ "$f" == "$TF_ROOT/"* ]] || continue
  rel="${f#"$TF_ROOT"/}"
  case "$rel" in
    *.tf | *.tfvars | *.terraform.lock.hcl) ;;
    *) continue ;;
  esac
  case "$rel" in
    ECS-services-module/modules/*)
      all_services=true ;;
    ECS-services-module/services/*/manifests/*)
      svc="${rel#ECS-services-module/services/}"; svc="${svc%%/*}"
      if [[ -d "$REPO_ROOT/$TF_ROOT/ECS-services-module/services/$svc/manifests" ]]; then
        changed["ECS-services-module/services/$svc"]=1
      else
        removed["ECS-services-module/services/$svc"]=1
      fi ;;
    */manifests/*)
      project="${rel%%/*}"
      for p in "${ORDER[@]}"; do [[ "$p" == "$project" ]] && changed["$project"]=1; done ;;
  esac
done

if $all_services; then
  for d in "$REPO_ROOT/$TF_ROOT"/ECS-services-module/services/*/manifests; do
    [[ -d "$d" ]] || continue
    svc="${d%/manifests}"; svc="${svc##*/}"
    changed["ECS-services-module/services/$svc"]=1
  done
fi

# Ordered list: fixed order for the base projects, then the services alphabetically
ordered=()
for p in "${ORDER[@]}"; do [[ -n "${changed[$p]:-}" ]] && ordered+=("$p"); done
mapfile -t services < <(printf '%s\n' "${!changed[@]}" | grep '^ECS-services-module/services/' | sort || true)
ordered+=("${services[@]}")

to_json() { # name list -> [{"name":..,"dir":..}]
  local out="" item name
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    name="${item##*/}"
    out+="${out:+,}{\"name\":\"$name\",\"dir\":\"$TF_ROOT/$item/manifests\"}"
  done
  printf '[%s]' "$out"
}

apply_list=()
for p in "${ordered[@]}"; do [[ -z "$p" || "$p" == "$MANUAL_ONLY" ]] || apply_list+=("$p"); done
mapfile -t removed_list < <(printf '%s\n' "${!removed[@]}" | sort | sed '/^$/d' || true)

plan_json=$(to_json "${ordered[@]}")
apply_json=$(to_json "${apply_list[@]}")
removed_json=$(to_json "${removed_list[@]}")
bool() { [[ "$1" != "[]" ]] && echo true || echo false; }
bastion_changed=false; [[ -n "${changed[$MANUAL_ONLY]:-}" ]] && bastion_changed=true

printf '{"plan":%s,"apply":%s,"removed":%s}\n' "$plan_json" "$apply_json" "$removed_json"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "plan=$plan_json"
    echo "apply=$apply_json"
    echo "removed=$removed_json"
    echo "has_plan=$(bool "$plan_json")"
    echo "has_apply=$(bool "$apply_json")"
    echo "has_removed=$(bool "$removed_json")"
    echo "bastion_changed=$bastion_changed"
  } >> "$GITHUB_OUTPUT"
fi
