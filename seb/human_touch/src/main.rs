mod review_queue;
mod commit_gateway;
mod audit_log;

use anyhow::Result;
use clap::Parser;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::info;
use tracing_subscriber;

#[derive(Parser, Debug)]
#[command(
    name = "SEB Human-Touch Gateway",
    about = "Human-centered async review gate for code changes",
    long_about = "Ensures all code changes receive explicit human approval before landing. \
                  Manages async review queue, approval workflow, and cryptographically-sealed commits."
)]
struct Args {
    /// Path to git repository
    #[arg(short, long, default_value = ".")]
    repo_path: PathBuf,

    /// Path to audit log file
    #[arg(short, long, default_value = "HUMAN_REVIEW_LOG.json")]
    audit_log: PathBuf,

    /// Maximum pending changes before blocking
    #[arg(short, long, default_value = "100")]
    max_pending: usize,

    /// Approval timeout in seconds
    #[arg(short, long, default_value = "3600")]
    approval_timeout_secs: u64,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// Human reviewer name (for commits)
    #[arg(long)]
    reviewer: Option<String>,

    /// Run in daemon mode (background service)
    #[arg(long)]
    daemon: bool,

    /// Port for webhook listener (if daemon mode)
    #[arg(long, default_value = "8080")]
    webhook_port: u16,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Initialize tracing
    if args.verbose {
        tracing_subscriber::fmt()
            .with_max_level(tracing::Level::DEBUG)
            .pretty()
            .init();
    } else {
        tracing_subscriber::fmt()
            .with_max_level(tracing::Level::INFO)
            .init();
    }

    info!(
        "🔐 Human-Touch Gateway starting (repo: {:?}, audit: {:?})",
        args.repo_path, args.audit_log
    );

    // Initialize components
    let (tx, rx) = mpsc::channel::<review_queue::PendingChange>(args.max_pending);

    let review_queue = review_queue::ReviewQueue::new(
        rx,
        args.repo_path.clone(),
        args.audit_log.clone(),
        args.max_pending,
    )?;

    let commit_gateway = commit_gateway::CommitGateway::new(
        args.repo_path.clone(),
        args.approval_timeout_secs,
    )?;

    let audit_log = audit_log::AuditLog::new(args.audit_log)?;

    // Arc the queue for sharing between tasks
    let review_queue = Arc::new(tokio::sync::Mutex::new(review_queue));
    let audit_log_clone = audit_log.clone();

    // Spawn the review queue processor
    let queue_handle = {
        let gateway = commit_gateway.clone();
        let queue = Arc::clone(&review_queue);
        tokio::spawn(async move {
            let mut queue_mut = queue.lock().await;
            if let Err(e) = queue_mut.process_queue(gateway, audit_log_clone).await {
                tracing::error!("Review queue processor failed: {}", e);
            }
        })
    };

    if args.daemon {
        // Run as daemon with webhook listener
        info!("🌙 Running in daemon mode (webhook: 0.0.0.0:{})", args.webhook_port);

        let _tx_clone = tx.clone();
        // Placeholder: would start webhook server here
        // For now just keep running
        tokio::signal::ctrl_c().await?;
        info!("Received shutdown signal");
    } else {
        // Interactive mode: read from stdin
        info!("📋 Running in interactive mode");

        // Run interactive loop
        if let Err(e) = interactive_loop_blocking(
            tx.clone(),
            review_queue.clone(),
            audit_log.clone(),
            &args.reviewer.clone().unwrap_or_else(|| "human".to_string()),
        )
        .await
        {
            tracing::error!("Interactive loop error: {}", e);
        }

        // Wait for queue processor
        let _ = queue_handle.await;
    }

    info!("✅ Human-Touch Gateway shutting down gracefully");
    Ok(())
}

/// Interactive loop for human approval/rejection of changes
async fn interactive_loop_blocking(
    _tx: mpsc::Sender<review_queue::PendingChange>,
    review_queue: Arc<tokio::sync::Mutex<review_queue::ReviewQueue>>,
    audit_log: audit_log::AuditLog,
    reviewer_name: &str,
) -> Result<()> {
    let stdin = io::stdin();
    let mut reader = stdin.lock();

    println!("\n✨ Human-Touch Gateway Interactive Mode ✨");
    println!("   Commands: 'approve <id>', 'reject <id> <reason>', 'status', 'help', 'exit'");
    println!();

    loop {
        print!("🤔 > ");
        io::stdout().flush()?;

        let mut line = String::new();
        reader.read_line(&mut line)?;
        let cmd = line.trim();

        if cmd.is_empty() {
            continue;
        }

        let parts: Vec<&str> = cmd.split_whitespace().collect();

        match parts.get(0).copied() {
            Some("approve") => {
                if let Some(change_id) = parts.get(1) {
                    match review_queue
                        .lock().await
                        .approve_change(change_id, reviewer_name, &audit_log)
                        .await
                    {
                        Ok(_) => println!("✅ Change {} approved and ready for commit", change_id),
                        Err(e) => println!("❌ Failed to approve: {}", e),
                    }
                } else {
                    println!("❌ Usage: approve <change-id>");
                }
            }
            Some("reject") => {
                if let (Some(change_id), Some(reason)) = (parts.get(1), parts.get(2..)) {
                    let reason_str = reason.join(" ");
                    match review_queue
                        .lock().await
                        .reject_change(change_id, reviewer_name, &reason_str, &audit_log)
                        .await
                    {
                        Ok(_) => println!("❌ Change {} rejected", change_id),
                        Err(e) => println!("❌ Failed to reject: {}", e),
                    }
                } else {
                    println!("❌ Usage: reject <change-id> <reason>");
                }
            }
            Some("status") => {
                let status = review_queue.lock().await.status();
                println!(
                    "\n📊 Queue Status:\n   Total: {}\n   Pending: {}\n   Approved: {}\n   Rejected: {}\n   Committed: {}\n   Capacity: {}\n",
                    status.total, status.pending, status.approved, status.rejected, status.committed, status.capacity
                );
            }
            Some("help") => {
                println!("\n📖 Available Commands:");
                println!("   approve <id>         - Approve a change for commit");
                println!("   reject <id> <reason> - Reject a change with reason");
                println!("   status               - Show queue status");
                println!("   help                 - Show this message");
                println!("   exit                 - Exit gateway\n");
            }
            Some("exit") => {
                println!("👋 Exiting Human-Touch Gateway...");
                break;
            }
            _ => println!("❓ Unknown command. Type 'help' for available commands."),
        }
    }

    Ok(())
}
