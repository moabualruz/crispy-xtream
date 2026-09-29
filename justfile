ci:
    ruby tests/runner_workflow_contract.rb
    cargo fmt --check
    cargo clippy --locked --all-targets --all-features -- -D warnings
    cargo test --locked --all-features
    cargo doc --locked --no-deps
    cargo package --locked
