# crispy-xtream

Async Xtream Codes API client for IPTV services.

## Status

Extracted from CrispyTivi. Intended as a reusable Rust client crate for Xtream Codes compatible providers.

## What This Crate Provides

- authentication against Xtream-compatible endpoints
- typed access to:
  - profile/account info
  - live categories
  - VOD categories
  - series categories
  - live streams
  - VOD streams
  - series listings
  - short/full EPG data
- typed protocol models and URL helpers

## Installation

```toml
[dependencies]
crispy-xtream = "0.1"
```

## Quick Start

```rust
use crispy_xtream::{XtreamClient, XtreamCredentials};

# async fn demo() -> Result<(), crispy_xtream::XtreamError> {
let client = XtreamClient::new(XtreamCredentials::new(
    "http://example.com:8080",
    "username",
    "password",
))?;

let _profile = client.authenticate().await?;
# Ok(())
# }
```

## Primary Use Cases

- IPTV applications
- provider sync services
- metadata ingestion pipelines
- account validation tools

## Relationship To Other Crates

- uses `crispy-iptv-types`
- typically paired with app-side mapping code

## Non-Goals

- playback probing
- app persistence
- Flutter/FFI integration

## Caveats

- public release should document auth failure modes, rate limiting behavior, and compatibility assumptions for non-standard Xtream providers
