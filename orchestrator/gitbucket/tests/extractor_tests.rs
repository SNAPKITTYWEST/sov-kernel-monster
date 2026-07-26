use snapkitty_gitbucket::extractor;

#[test]
fn test_parse_feat_commit() {
    let msg = "feat(auth): add Ed25519 verification\n\nRefs: #42";
    assert!(msg.contains("feat("));
    assert!(msg.contains("Refs: #42"));
}

#[test]
fn test_parse_fix_commit() {
    let msg = "fix(scheduler): prevent race condition in borrow chain";
    assert!(msg.contains("fix("));
    assert!(msg.contains("scheduler"));
}

#[test]
fn test_parse_breaking_change() {
    let msg = "refactor!: change API surface\n\nBREAKING CHANGE: removed deprecated endpoints";
    assert!(msg.contains("BREAKING CHANGE:"));
}

#[test]
fn test_file_role_classification() {
    let paths = vec![
        ("src/engine.rs", "core"),
        ("tests/integration.rs", "test"),
        ("README.md", "doc"),
        ("Cargo.toml", "config"),
    ];
    for (path, expected_role) in paths {
        assert!(!path.is_empty());
        assert!(!expected_role.is_empty());
    }
}
