output "tag_key_id" {
  value       = google_tags_tag_key.scoping_project.id
  description = "The fully qualified TagKey resource name"
}

output "tag_key_namespaced" {
  value       = google_tags_tag_key.scoping_project.namespaced_name
  description = "Namespaced TagKey name (e.g. 1234567890/observability_scoping_project)"
}

output "tag_values_map" {
  value       = { for k, v in google_tags_tag_value.scope_shards : k => v.id }
  description = "Map of shard names to their fully qualified TagValue resource names"
}
