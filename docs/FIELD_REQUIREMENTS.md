# Field requirements configuration

Each assignment may publish a `field_requirements.txt` sidecar. Lines use
`field.key = required|optional`; blank lines and `#` comments are ignored.
Unknown keys are retained. Unknown values (including typos) mean required.
Missing or malformed files fall back to the legacy defaults.

Existing keys default to required when omitted. These two keys default to
optional, preserving completion of existing assignments and saved surveys:

| Key | Omitted | Required answer |
| --- | --- | --- |
| `building.cbmsId` | optional | Nonblank text; no additional format restriction |
| `building.fireFightingFacilities` | optional | At least one selection; explicit `None` is an answer |

For an assignment that requires both answers:

```text
building.cbmsId = required
building.fireFightingFacilities = required
```

To retain optional collection explicitly:

```text
building.cbmsId = optional
building.fireFightingFacilities = optional
```

The same policy drives required markers, remaining required questions, Done
validation and review blockers for these fields. Fields hidden by either a
variant or a form-definition section and a building marked “does not exist” do not require answers. The current form
definition still controls editability and its own validation constraints;
requirement configuration does not override those contracts. At least one photo
remains mandatory regardless of `building.photo` configuration.

Requirement snapshots stay scoped to their assignment and reload from local
storage offline. Switching assignments selects that assignment's snapshot.
Configuration changes do not rewrite saved answers, drafts, or photo evidence.
Review keeps upload unavailable while requirements or the form definition load,
and surfaces configuration errors without applying optional defaults.
