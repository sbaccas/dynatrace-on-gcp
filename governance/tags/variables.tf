variable "org_id" {
  type        = string
  description = "The numeric GCP Organization ID (e.g. 123456789012)"
}

variable "scoping_shards" {
  type        = list(string)
  description = "List of scoping project shard identifiers (e.g. dynatrace-scope-01, dynatrace-scope-02)"
  default     = ["dynatrace-scope-01", "dynatrace-scope-02", "dynatrace-scope-03"]
}

variable "project_to_shard_map" {
  type        = map(string)
  description = "Map of GCP Project Numbers to their designated scoping shard key"
  default     = {}
}
