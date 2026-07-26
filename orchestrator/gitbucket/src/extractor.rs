use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use std::process::Command;

use crate::bucket::{Author, FileEntry, MemoryBucket, WormSeal};

/// Extract memory buckets from a git commit range.
pub fn extract_range(repo: &str, from: Option<&str>, to: Option<&str>) -> Result<Vec<MemoryBucket>> {
    let to_hash = to.unwrap_or("HEAD");
    let range = match from {
        Some(f) => format!("{}..{}", f, to_hash),
        None => to_hash.to_string(),
    };

    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("log")
        .arg("--format=%H|%P|%an|%ae|%ai|%s")
        .arg(&range)
        .output()
        .context("Failed to run git log")?;

    if !output.status.success() {
        anyhow::bail!("git log failed: {}", String::from_utf8_lossy(&output.stderr));
    }

    let stdout = String::from_utf8(output.stdout)?;
    let mut buckets = Vec::new();

    for (i, line) in stdout.lines().enumerate() {
        let parts: Vec<&str> = line.splitn(6, '|').collect();
        if parts.len() < 6 {
            continue;
        }

        let hash = parts[0];
        let parent = if parts[1].is_empty() { "" } else { parts[1].split_whitespace().next().unwrap_or("") };
        let author_name = parts[2];
        let _author_email = parts[3];
        let timestamp = parts[4];
        let message = parts[5];

        // Get diff stat
        let diff_stat = get_diff_stat(repo, hash)?;

        // Parse conventional commit message
        let parsed = parse_conventional_commit(message);

        // Get branch
        let branch = get_branch(repo, hash)?;

        // Generate bucket ID
        let id = format!("mem_{:06}", i);

        // Compute file entries
        let files = compute_file_entries(&diff_stat);

        // Create the bucket
        let bucket = MemoryBucket {
            id: id.clone(),
            git_hash: hash.to_string(),
            parent_hash: parent.to_string(),
            timestamp: timestamp.to_string(),
            author: Author {
                id: author_name.to_string(),
                pubkey: format!("ed25519:{}", author_name),
            },
            branch,
            bucket_type: parsed.bucket_type,
            summary: parsed.summary,
            keywords: parsed.keywords,
            entities: extract_entities_from_files(&files),
            files,
            related: parsed.related,
            trust: "pending".to_string(),
            immutable: true,
            worm_seal: WormSeal {
                algorithm: "Ed25519".to_string(),
                signature: String::new(),
                signer: "Plasma_Gate".to_string(),
                audit_ref: uuid::Uuid::new_v4().to_string(),
            },
        };

        buckets.push(bucket);
    }

    Ok(buckets)
}

fn get_diff_stat(repo: &str, hash: &str) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("diff")
        .arg("--stat")
        .arg(format!("{}~1", hash))
        .arg(hash)
        .output()
        .context("Failed to get diff stat")?;

    Ok(String::from_utf8(output.stdout)?)
}

fn get_branch(repo: &str, hash: &str) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("branch")
        .arg("--contains")
        .arg(hash)
        .output()
        .context("Failed to get branch")?;

    let stdout = String::from_utf8(output.stdout)?;
    for line in stdout.lines() {
        let line = line.trim().trim_start_matches('*');
        if !line.is_empty() {
            return Ok(line.to_string());
        }
    }
    Ok("main".to_string())
}

struct ParsedCommit {
    bucket_type: String,
    summary: String,
    keywords: Vec<String>,
    related: Vec<String>,
    breaking: bool,
}

fn parse_conventional_commit(message: &str) -> ParsedCommit {
    let lines: Vec<&str> = message.lines().collect();
    let first_line = lines.first().unwrap_or(&"");

    let (bucket_type, summary) = if let Some(colon_pos) = first_line.find(':') {
        let before_colon = &first_line[..colon_pos];
        let after_colon = first_line[colon_pos + 1..].trim();

        let (type_part, scope) = if let Some(paren_start) = before_colon.find('(') {
            if let Some(paren_end) = before_colon.find(')') {
                (&before_colon[..paren_start], Some(&before_colon[paren_start + 1..paren_end]))
            } else {
                (before_colon, None)
            }
        } else {
            (before_colon, None)
        };

        let bucket_type = match type_part {
            "feat" => "implementation",
            "fix" => "repair",
            "docs" => "architecture",
            "style" => "architecture",
            "refactor" => "implementation",
            "perf" => "implementation",
            "test" => "audit",
            "build" => "architecture",
            "ci" => "audit",
            "chore" => "audit",
            "revert" => "repair",
            "security" => "audit",
            "decision" => "decision",
            "audit" => "audit",
            "fiscal" => "fiscal_decision",
            _ => "audit",
        };

        let summary = match scope {
            Some(s) => format!("{}: {}", s, after_colon),
            None => after_colon.to_string(),
        };

        (bucket_type.to_string(), summary)
    } else {
        ("audit".to_string(), first_line.to_string())
    };

    let breaking = message.contains("BREAKING CHANGE:") || message.contains("BREAKING:");

    let keywords: Vec<String> = summary
        .split_whitespace()
        .map(|w| w.to_lowercase())
        .filter(|w| !STOP_WORDS.contains(&w.as_str()))
        .collect();

    let related: Vec<String> = message
        .lines()
        .filter(|l| l.starts_with("Refs:") || l.starts_with("Ref:"))
        .flat_map(|l| {
            l.split_whitespace()
                .filter(|w| w.starts_with('#'))
                .map(|w| format!("issue_{}", &w[1..]))
                .collect::<Vec<_>>()
        })
        .collect();

    ParsedCommit {
        bucket_type,
        summary,
        keywords,
        related,
        breaking,
    }
}

fn compute_file_entries(diff_stat: &str) -> Vec<FileEntry> {
    diff_stat
        .lines()
        .filter(|l| l.contains('|'))
        .filter_map(|l| {
            let parts: Vec<&str> = l.splitn(2, '|').collect();
            if parts.len() == 2 {
                let path = parts[0].trim().to_string();
                let role = classify_file_role(&path);
                let diff_hash = format!("{:x}", Sha256::digest(parts[1].as_bytes()));
                Some(FileEntry { path, role, diff_hash })
            } else {
                None
            }
        })
        .collect()
}

fn classify_file_role(path: &str) -> String {
    if path.ends_with(".rs") || path.ends_with(".cpp") || path.ends_with(".hs") || path.ends_with(".lean") {
        if path.contains("test") || path.contains("_test.") {
            "test".to_string()
        } else {
            "core".to_string()
        }
    } else if path.ends_with(".md") || path.ends_with(".txt") {
        "doc".to_string()
    } else if path.ends_with(".toml")
        || path.ends_with(".json")
        || path.ends_with(".yml")
        || path.ends_with(".yaml")
        || path.ends_with(".pl")
    {
        "config".to_string()
    } else if path.ends_with(".new") {
        "new".to_string()
    } else {
        "modified".to_string()
    }
}

fn extract_entities_from_files(files: &[FileEntry]) -> Vec<String> {
    let mut entities = Vec::new();
    for file in files {
        if let Some(name) = file.path.rsplit('/').next() {
            if let Some(stem) = name.split('.').next() {
                let entity = stem.to_lowercase();
                if !entities.contains(&entity) {
                    entities.push(entity);
                }
            }
        }
    }
    entities
}

const STOP_WORDS: &[&str] = &[
    "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "shall", "can", "to", "of", "in", "for",
    "on", "with", "at", "by", "from", "as", "and", "but", "or", "not",
    "so", "if", "when", "while", "this", "that", "it", "its",
];
