# Quant AI with Terraform

Provider setup, versions, Pulumi names and import IDs are in `quant-iac`. This file shows the AI
resources together. Checked against `quantcdn/quant` v5.14.1 resource docs.

## Resources

| Resource | Manages |
|---|---|
| `quant_ai_agent` | A custom agent (`name`, `description`, `model_id`, `system_prompt` required) |
| `quant_ai_agent_overlay` | An organisation overlay on a platform agent |
| `quant_ai_custom_tool` | A custom tool (`name`, `description`, `edge_function_code`, `input_schema` as `jsonencode(...)`) |
| `quant_ai_skill` | A skill (`name`, `content`, `trigger_condition`) |
| `quant_ai_vector_collection` | A collection (`name`, `embedding_model`) |
| `quant_ai_vector_document` | Documents in a collection (`documents` list) |
| `quant_ai_governance` | The organisation's governance and spend limits (one per organisation) |

## Example

```hcl
provider "quant" {
  bearer       = var.quant_api_token
  organization = "example-org"
  base_url     = "https://dash.quantgov.cloud"   # QuantGov only; bare host, no /api/v2
}

resource "quant_ai_vector_collection" "faq" {
  name            = "support-faq"
  description     = "Support FAQ"
  embedding_model = var.embedding_model_id   # from GET /models?feature=embeddings; cannot change later
}

resource "quant_ai_vector_document" "faq" {
  collection_id = quant_ai_vector_collection.faq.collection_id
  documents = [
    {
      key      = "faq-returns"
      content  = "You can return items within 30 days of delivery."
      metadata = { title = "Returns FAQ", tags = ["faq"] }
    }
  ]
}

resource "quant_ai_skill" "returns" {
  name              = "returns-policy"
  description       = "Explains the returns policy."
  trigger_condition = "The user asks about returns or refunds."
  content           = file("${path.module}/skills/returns.md")
}

resource "quant_ai_custom_tool" "lookup_order" {
  name        = "lookup_order"          # lowercase letters, digits, underscores only
  description = "Look up an order by its number."
  input_schema = jsonencode({
    type       = "object"
    properties = { order_number = { type = "string" } }
    required   = ["order_number"]
  })
  edge_function_code = file("${path.module}/tools/lookup_order.js")
  timeout_seconds    = 10                # 5 to 300
}

resource "quant_ai_agent" "support" {
  name                = "Support agent"
  description         = "Answers customer questions."
  model_id            = var.chat_model_id   # from GET /models?feature=chat; must support tool use
  system_prompt       = "You are a helpful support agent. Use lookup_order for order questions."
  assigned_skills     = [quant_ai_skill.returns.skill_id]
  allowed_tools       = [quant_ai_custom_tool.lookup_order.name]
  allowed_collections = [quant_ai_vector_collection.faq.collection_id]
  guardrail_preset    = "official"
}

resource "quant_ai_governance" "org" {
  ai_enabled   = true
  model_policy = "unrestricted"
  spend_limits = {
    monthly_budget_cents      = 65000   # US cents (USD 650); budgets are not in AUD
    warning_threshold_percent = 80
  }
}
```

Notes:

- One `quant_ai_governance` exists per organisation. It replaces the whole configuration, so
  include every setting you want to keep.
- Changing `embedding_model` means a new collection. Plan the replacement and upload the
  documents again.
- `quant_ai_agent_overlay` changes a platform agent for your organisation (`agent_id`,
  `system_prompt_append`, `additional_tools`, `disabled_tools`, `model_id`, and so on).
- Workflows, triggers, sessions, filter policies and MCP servers stay in the dashboard or API.
