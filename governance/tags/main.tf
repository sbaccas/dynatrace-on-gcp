# ==============================================================================
# GCP Resource Manager Secure Tags for Dynatrace Scoping Project Sharding
# ==============================================================================
# Secure Tags provide organization-level, cryptographically signed, immutable
# bindings that cannot be altered or removed by project-level administrators.
# ==============================================================================

# 1. Organization-level Tag Key
resource "google_tags_tag_key" "scoping_project" {
  parent      = "organizations/${var.org_id}"
  short_name  = "observability_scoping_project"
  description = "Centralized Observability Scoping Project Pool Tag Key"
}

# 2. Tag Values representing each 375-project shard
resource "google_tags_tag_value" "scope_shards" {
  for_each    = toset(var.scoping_shards)
  parent      = google_tags_tag_key.scoping_project.id
  short_name  = each.key
  description = "Assigned to projects monitored by scoping pool ${each.key}"
}

# 3. Tag Binding Module / Dynamic Association
# Attaches the designated shard tag to a target project
resource "google_tags_tag_binding" "project_shard_binding" {
  for_each  = var.project_to_shard_map
  parent    = "//cloudresourcemanager.googleapis.com/projects/${each.key}"
  tag_value = google_tags_tag_value.scope_shards[each.value].id
}
