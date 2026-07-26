use anyhow::Result;
use clap::{Parser, Subcommand};

mod bucket;
mod extractor;
mod index;
mod planner;
mod seal;
mod schema;

#[derive(Parser)]
#[command(name = "gitbucket")]
#[command(about = "Deterministic Memory Layer — Git as WORM, JSON as Query, Prolog as Truth")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Extract memory buckets from git history
    Extract {
        /// Git repo path
        #[arg(short, long, default_value = ".")]
        repo: String,
        /// Start commit (ref or hash)
        #[arg(short, long)]
        from: Option<String>,
        /// End commit (ref or hash, default: HEAD)
        #[arg(short, long)]
        to: Option<String>,
        /// Output directory for buckets
        #[arg(short, long, default_value = ".gitbucket/buckets")]
        output: String,
    },
    /// Verify WORM seals on all buckets
    Verify {
        /// Bucket directory
        #[arg(short, long, default_value = ".gitbucket/buckets")]
        buckets: String,
    },
    /// Query the memory index
    Query {
        /// Query type: topic, file, entity, agent, type
        #[arg(short, long)]
        field: String,
        /// Query value
        #[arg(short, long)]
        value: String,
        /// Token budget
        #[arg(short, long, default_value = "8000")]
        budget: usize,
    },
    /// Generate Ed25519 keypair
    Keygen,
    /// Backfill history from existing git repo
    Backfill {
        /// Git repo path
        #[arg(short, long, default_value = ".")]
        repo: String,
        /// Start commit
        #[arg(short, long)]
        from: Option<String>,
        /// End commit
        #[arg(short, long, default_value = "HEAD")]
        to: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Extract { repo, from, to, output } => {
            println!("Extracting memory buckets from {}...", repo);
            let buckets = extractor::extract_range(&repo, from.as_deref(), to.as_deref())?;
            for bucket in &buckets {
                let path = format!("{}/{}.json", output, bucket.id);
                std::fs::write(&path, serde_json::to_string_pretty(bucket)?)?;
                println!("  Wrote {}", path);
            }
            println!("Extracted {} buckets.", buckets.len());
        }
        Commands::Verify { buckets } => {
            println!("Verifying WORM seals in {}...", buckets);
            let results = seal::verify_all(&buckets)?;
            let passed = results.iter().filter(|r| r.is_ok()).count();
            let failed = results.len() - passed;
            println!("  {} passed, {} failed", passed, failed);
            for (i, result) in results.iter().enumerate() {
                if let Err(e) = result {
                    println!("  FAILED bucket {}: {}", i, e);
                }
            }
        }
        Commands::Query { field, value, budget } => {
            println!("Querying: {} = {} (budget: {})", field, value, budget);
            let context = planner::query(&field, &value, budget)?;
            println!("{}", serde_json::to_string_pretty(&context)?);
        }
        Commands::Keygen => {
            let (pubkey, privkey) = seal::keygen()?;
            println!("Public key:  {}", pubkey);
            println!("Private key: {}", privkey);
        }
        Commands::Backfill { repo, from, to } => {
            println!("Backfilling from {} to {} in {}...", 
                from.as_deref().unwrap_or("first commit"), to, repo);
            let buckets = extractor::extract_range(&repo, from.as_deref(), Some(&to))?;
            let output = ".gitbucket/buckets";
            std::fs::create_dir_all(output)?;
            for bucket in &buckets {
                let path = format!("{}/{}.json", output, bucket.id);
                std::fs::write(&path, serde_json::to_string_pretty(bucket)?)?;
            }
            println!("Backfilled {} buckets.", buckets.len());
        }
    }

    Ok(())
}
