---
title: "Zocam.Point.ComposeError"
description: "Raised (or returned) when two points do not compose."
---

[AI SLOP]{.ai-slop} An AI agent wrote the docstrings; `mix docs` generated this page. [yuri4n](https://github.com/yuri4n), a senior engineer, gave the direction and did the review. The review is human, thus errors can stay.

[Source on GitHub ↗](https://github.com/yuri4n/zocam/blob/main/lib/zocam/point.ex#L154){.source-link}

Raised (or returned) when two points do not compose.

## Types

### `reason`

```elixir
@type reason() :: :grain_gap | :cross_cycle | :invalid | :anchored
```

### `t`

```elixir
@type t() :: %Zocam.Point.ComposeError{
  __exception__: term(),
  hint: String.t(),
  left: Zocam.Point.t(),
  message: String.t(),
  reason: reason(),
  right: Zocam.Point.t()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
