ci:
    ruby tests/runner_workflow_contract.rb
    cargo fmt --check
    cargo clippy --all-targets --all-features -- -D warnings
    cargo test --all-features
    cargo doc --no-deps
    cargo package
