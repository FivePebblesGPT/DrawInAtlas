class_name AtlasCampaignSaveRoot
extends Node

## Data-only scene root. The map registry is reconstructed from owned children.
const NATIVE_VERSION: int = 1

## Native scene schema version, distinct from the campaign's data version.
@export_storage var native_version: int = NATIVE_VERSION
## Recomputed whole-campaign integrity digest; derived guard, not editable data.
@export_storage var semantic_digest: String = ""
## Canonical campaign metadata/links; map Resources are reconstructed from
## child AtlasMapSaveNode nodes, not from the runtime maps dictionary.
@export_storage var campaign: AtlasCampaign
