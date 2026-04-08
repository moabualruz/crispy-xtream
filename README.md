# crispy-xtream

Async Xtream Codes API client for IPTV services.

## What This Crate Is

`crispy-xtream` provides a typed async client for Xtream Codes compatible IPTV providers. It wraps the common Xtream API surface used by IPTV apps and sync pipelines without dragging in any app-specific persistence or UI code.

## What It Provides

- credentials and client configuration types
- authentication
- live, VOD, and series category fetches
- live stream, VOD stream, and series listing fetches
- short/full EPG fetches
- typed Xtream response models
- helper URL generation

## Installation

```toml
[dependencies]
crispy-xtream = "0.1.1"
```

MSRV: Rust `1.85`

## Quick Start

```rust
use crispy_xtream::{XtreamClient, XtreamCredentials};

# async fn demo() -> Result<(), crispy_xtream::XtreamError> {
let client = XtreamClient::new(XtreamCredentials::new(
    "http://example.com:8080",
    "username",
    "password",
))?;

let profile = client.authenticate().await?;
let _live = client.get_live_streams(None).await?;
let _xmltv = client.xmltv_url();

assert!(!profile.user_info.username.is_empty());
# Ok(())
# }
```

## Main Public Types

- `XtreamClient`
- `XtreamCredentials`
- `XtreamClientConfig`
- `XtreamError`
- protocol models re-exported from `types`

## Typical Uses

- syncing IPTV provider content into an app/backend
- validating account credentials
- building provider-specific import tools

## Current Limitations

- this crate only covers Xtream-compatible providers; it does not try to normalize every broken vendor variation
- it does not persist results
- it does not handle playback probing or stream health

## License

See `LICENSE.md` and `NOTICE.md`.
